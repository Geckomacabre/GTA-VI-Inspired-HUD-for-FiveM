"""Builds the drawn minimap's world out of the "GTA-VI MiniMap (3D Buildings)"
mod by @moddims: its roads, building outlines, building heights and its sea
and sand survey of the whole map.

    python tools/map3d/build.py --mod "path/to/MiniMap.dll"

Writes html/map3d/world.bin and html/map3d/ground.png, which html/map3d.js
loads. Neither is in this repository: the survey is moddims' work, not ours to
hand out, so each server builds its own copy from the mod it downloaded.

Nothing in the mod is run. Its map is one gzip stream inside the DLL, found by
its "MMV1" header; --mod also takes that stream already cut out and unpacked.

What is in the mod's map, as read from it:

  header   "MMV1", min x, min y, max x, max y (world metres), layer count
  layer    id, vertex count, triangle count, x/y pairs, index triples
             0  building footprints      3  yards, lots and paths
             1  railway                  4  roads above the ground: bridges
             2  roads                    5  lane lines
  "BLD1"   a height per building, the building each layer-0 triangle belongs
           to, and each building's outline as rings of points
  "WAT1"   a 4 m grid in 128 m tiles: land, water or sand in every cell the
           author's survey reached

What comes out:

  world.bin   "VHM1", a JSON header, then the arrays it names. Every mesh's
              triangles are sorted into 256 m squares so the page draws the
              few squares around the player and not the whole island.
  ground.png  red = how much of each 4 m cell is water, green = sand, both
              blurred a little so the shoreline is a curve and not stairs.
"""
import argparse
import gzip
import json
import math
import os
import struct
import sys
import zlib

import numpy as np
from PIL import Image
from scipy import ndimage

CHUNK = 256.0          # metres to a side; map3d.js reads it from the header
WATER_CELL = 4.0       # metres, the mod's survey grid
TILE = 32              # survey cells to a tile side

# Survey cell states. 3 is "no ground found yet"; 5 and 6 are land and water
# seen from far away, which the mod draws the same as 1 and 2.
WATER_STATES = (2, 6)
SAND_STATE = 4

# The mod's "buildings" are whatever its survey found standing: houses and
# towers, but also electricity pylons, kiosks, sheds and tanks. Each is only an
# outline and a height, so each is drawn as a flat-topped block -- which is a
# fair picture of an office and a poor one of a pylon. Anything with a footprint
# under this many square metres is left off the map rather than drawn as a box.
MIN_BUILDING_AREA = 60.0

# The mod keeps a body of water only when it is this many cells or more, and
# a patch of sand only when it is this big and within reach of the water.
WATER_MIN_CELLS = 150
SAND_MIN_CELLS = 40
BEACH_REACH = 10


def find_map(blob):
    """The unpacked map, from a DLL that has it inside or from the map itself."""
    if blob[:4] == b'MMV1':
        return blob
    if blob[:2] == b'\x1f\x8b':
        return gzip.decompress(blob)
    at = 0
    while True:
        at = blob.find(b'\x1f\x8b\x08', at)
        if at < 0:
            raise SystemExit('no map found in that file: is it the mod\'s MiniMap.dll?')
        try:
            data = zlib.decompressobj(31).decompress(blob[at:])
        except zlib.error:
            data = b''
        if data[:4] == b'MMV1':
            return data
        at += 1


def read_map(raw):
    p = 4
    bounds = struct.unpack_from('<4f', raw, p); p += 16
    count = struct.unpack_from('<i', raw, p)[0]; p += 4
    layers = {}
    for _ in range(count):
        lid = raw[p]; p += 1
        nv, nt = struct.unpack_from('<2i', raw, p); p += 8
        xy = np.frombuffer(raw, '<f4', nv * 2, p).reshape(nv, 2); p += nv * 8
        tri = np.frombuffer(raw, '<i4', nt * 3, p).reshape(nt, 3); p += nt * 12
        layers[lid] = (xy, tri)

    buildings = None
    if raw[p:p + 4] == b'BLD1':
        p += 4
        n = struct.unpack_from('<I', raw, p)[0]; p += 4
        height = np.frombuffer(raw, '<f4', n, p); p += n * 4
        nt = struct.unpack_from('<I', raw, p)[0]; p += 4
        owner = np.frombuffer(raw, '<u4', nt, p); p += nt * 4
        npts = struct.unpack_from('<I', raw, p)[0]; p += 4
        pts = np.frombuffer(raw, '<f4', npts * 2, p).reshape(npts, 2); p += npts * 8
        nr = struct.unpack_from('<I', raw, p)[0]; p += 4
        rings = np.frombuffer(raw, '<u4', nr * 3, p).reshape(nr, 3); p += nr * 12
        buildings = dict(height=height, owner=owner, pts=pts, rings=rings)

    water = None
    if raw[-4:] == b'WEND':
        at = struct.unpack_from('<i', raw, len(raw) - 8)[0]
        if raw[at:at + 4] == b'WAT1':
            size = struct.unpack_from('<i', raw, at + 4)[0]
            water = raw[at + 8:at + 8 + size]
            if water[:2] == b'\x1f\x8b':
                water = gzip.decompress(water)
    return bounds, layers, buildings, water


def drop_small(layer, b, min_area):
    """The footprint layer and the buildings, without the ones too small to be
    buildings. Returns (layer, buildings, how many went)."""
    xy, tri = layer
    owner = b['owner']
    n = len(b['height'])
    p = xy[tri]
    area = 0.5 * np.abs((p[:, 1, 0] - p[:, 0, 0]) * (p[:, 2, 1] - p[:, 0, 1])
                        - (p[:, 2, 0] - p[:, 0, 0]) * (p[:, 1, 1] - p[:, 0, 1]))
    keep = np.bincount(owner, area, n) >= min_area
    if keep.all():
        return layer, b, 0
    renumber = np.cumsum(keep) - 1
    tris = keep[owner]
    rings = b['rings']
    rings = rings[(rings[:, 0] < n) & keep[np.minimum(rings[:, 0], n - 1)]].copy()
    rings[:, 0] = renumber[rings[:, 0]]
    return ((xy, tri[tris]),
            dict(height=b['height'][keep], owner=renumber[owner[tris]].astype('<u4'), pts=b['pts'], rings=rings),
            int((~keep).sum()))


def survey_grid(water, bounds):
    """The survey as one array, row 0 at the map's south edge."""
    min_x, min_y, max_x, max_y = bounds
    gw = math.ceil((max_x - min_x) / (TILE * WATER_CELL)) + 1
    gh = math.ceil((max_y - min_y) / (TILE * WATER_CELL)) + 1
    grid = np.zeros((gh * TILE, gw * TILE), np.uint8)
    if water is None:
        return grid
    count = struct.unpack_from('<i', water, 8)[0]
    p = 12
    for _ in range(count):
        idx = struct.unpack_from('<i', water, p)[0]; p += 4
        tile = np.frombuffer(water, np.uint8, TILE * TILE, p).reshape(TILE, TILE); p += TILE * TILE
        if 0 <= idx < gw * gh:
            cy, cx = divmod(idx, gw)
            grid[cy * TILE:(cy + 1) * TILE, cx * TILE:(cx + 1) * TILE] = tile
    return grid


def ground_image(grid):
    water = np.isin(grid, WATER_STATES)
    sand = grid == SAND_STATE

    # A cell the survey never found ground under takes its neighbours' answer.
    unknown = grid == 3
    if unknown.any():
        near_water = ndimage.uniform_filter(water.astype(np.float32), 3) > 0.34
        water |= unknown & near_water

    labels, n = ndimage.label(water)
    if n:
        sizes = ndimage.sum(water, labels, np.arange(1, n + 1))
        water = np.isin(labels, 1 + np.flatnonzero(sizes >= WATER_MIN_CELLS))

    labels, n = ndimage.label(sand)
    if n:
        ids = np.arange(1, n + 1)
        sizes = ndimage.sum(sand, labels, ids)
        reach = ndimage.binary_dilation(water, iterations=BEACH_REACH)
        touches = ndimage.maximum(reach, labels, ids) > 0
        sand = np.isin(labels, ids[(sizes >= SAND_MIN_CELLS) & touches])

    def soft(mask):
        return np.clip(ndimage.gaussian_filter(mask.astype(np.float32), 0.9) * 255.0 + 0.5, 0, 255).astype(np.uint8)

    out = np.zeros(grid.shape + (3,), np.uint8)
    out[..., 0] = soft(water)
    out[..., 1] = soft(sand)
    return Image.fromarray(out, 'RGB')


class Chunks:
    def __init__(self, bounds):
        self.x0, self.y0 = bounds[0], bounds[1]
        self.gw = max(1, math.ceil((bounds[2] - bounds[0]) / CHUNK))
        self.gh = max(1, math.ceil((bounds[3] - bounds[1]) / CHUNK))

    def of(self, x, y):
        cx = np.clip(((x - self.x0) / CHUNK).astype(np.int64), 0, self.gw - 1)
        cy = np.clip(((y - self.y0) / CHUNK).astype(np.int64), 0, self.gh - 1)
        return cy * self.gw + cx

    def sort(self, tri, cell):
        """Triangles in square order, and where each square's run starts."""
        order = np.argsort(cell, kind='stable')
        starts = np.searchsorted(cell[order], np.arange(self.gw * self.gh + 1)) * 3
        return tri[order], starts.astype('<u4')


def weld(xy, tri):
    """The mod stores some layers as loose triangles. Share their corners."""
    uniq, inverse = np.unique(np.round(xy, 3), axis=0, return_inverse=True)
    return uniq.astype('<f4'), inverse.reshape(-1)[tri].astype('<u4')


def flat_layer(chunks, xy, tri):
    xy, tri = weld(xy, tri)
    c = xy[tri].mean(axis=1)
    tri, starts = chunks.sort(tri, chunks.of(c[:, 0], c[:, 1]))
    return xy, tri.astype('<u4'), starts


def building_mesh(chunks, layer, b):
    """Roofs at their height, and a wall under every outline edge.

    A vertex is x, y, height above the ground, the compass angle its wall
    faces -- or 9 for a roof, which faces the sky -- and which building it is
    part of, so the page can see through the one the player is standing in."""
    xy, tri = layer
    height = b['height']
    owner = b['owner']
    n = len(height)

    roof_v = np.empty((len(tri) * 3, 5), '<f4')
    flat = tri.reshape(-1)
    roof_v[:, 0:2] = xy[flat]
    roof_v[:, 2] = np.repeat(height[owner], 3)
    roof_v[:, 3] = 9.0
    roof_v[:, 4] = np.repeat(owner, 3)
    roof_i = np.arange(len(tri) * 3, dtype='<u4').reshape(-1, 3)

    # Where each building stands: the middle of its footprint, by area.
    p = xy[tri]
    area = 0.5 * np.abs((p[:, 1, 0] - p[:, 0, 0]) * (p[:, 2, 1] - p[:, 0, 1])
                        - (p[:, 2, 0] - p[:, 0, 0]) * (p[:, 1, 1] - p[:, 0, 1]))
    mid = p.mean(axis=1)
    wsum = np.maximum(np.bincount(owner, area, n), 1e-3)
    cx = np.bincount(owner, area * mid[:, 0], n) / wsum
    cy = np.bincount(owner, area * mid[:, 1], n) / wsum
    home = chunks.of(cx, cy)

    wall_v, wall_i, wall_owner = [], [], []
    base = len(roof_v)
    pts = b['pts']
    for owner_id, start, length in b['rings']:
        if owner_id >= n or length < 3:
            continue
        ring = pts[start:start + length]
        nxt = np.roll(ring, -1, axis=0)
        d = nxt - ring
        keep = np.hypot(d[:, 0], d[:, 1]) >= 0.05
        a, c, d = ring[keep], nxt[keep], d[keep]
        if not len(a):
            continue
        # Outlines run anticlockwise, so the outside is on the right of travel.
        facing = np.arctan2(-d[:, 0], d[:, 1])
        h = height[owner_id]
        quad = np.empty((len(a), 4, 5), '<f4')
        quad[:, 0, 0:2] = a; quad[:, 0, 2] = 0.0
        quad[:, 1, 0:2] = c; quad[:, 1, 2] = 0.0
        quad[:, 2, 0:2] = c; quad[:, 2, 2] = h
        quad[:, 3, 0:2] = a; quad[:, 3, 2] = h
        quad[:, :, 3] = facing[:, None]
        quad[:, :, 4] = owner_id
        first = base + 4 * np.arange(len(a), dtype=np.int64)
        idx = np.stack([first, first + 1, first + 2, first, first + 2, first + 3], axis=1).reshape(-1, 3)
        wall_v.append(quad.reshape(-1, 5))
        wall_i.append(idx)
        wall_owner.append(np.full(len(idx), owner_id, np.int64))
        base += 4 * len(a)

    verts = np.concatenate([roof_v] + wall_v)
    wall_i = np.concatenate(wall_i).astype('<u4')
    wall_owner = np.concatenate(wall_owner)

    roof_i, roof_starts = chunks.sort(roof_i, home[owner])
    wall_i, wall_starts = chunks.sort(wall_i, home[wall_owner])
    return verts, roof_i.astype('<u4'), roof_starts, wall_i, wall_starts


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--mod', required=True, help="the mod's MiniMap.dll (or its map, cut out)")
    ap.add_argument('--out', default=os.path.join(here, '..', '..', 'html', 'map3d'))
    ap.add_argument('--min-area', type=float, default=MIN_BUILDING_AREA,
                    help='leave out "buildings" with a footprint under this many square metres (0 keeps all)')
    args = ap.parse_args()

    raw = find_map(open(args.mod, 'rb').read())
    bounds, layers, buildings, water = read_map(raw)
    dropped = 0
    if buildings is not None and 0 in layers and args.min_area > 0:
        layers[0], buildings, dropped = drop_small(layers[0], buildings, args.min_area)
    chunks = Chunks(bounds)
    os.makedirs(args.out, exist_ok=True)

    blobs = []
    offset = 0

    def put(arr):
        nonlocal offset
        data = np.ascontiguousarray(arr).tobytes()
        ref = {'at': offset, 'n': int(arr.size)}
        blobs.append(data)
        offset += len(data)
        pad = -offset % 4
        if pad:
            blobs.append(b'\0' * pad)
            offset += pad
        return ref

    header = {
        'bounds': [float(v) for v in bounds],
        'chunk': CHUNK, 'gw': chunks.gw, 'gh': chunks.gh,
        'layers': {},
    }
    names = {0: 'footprint', 1: 'rail', 2: 'road', 3: 'lot', 4: 'bridge', 5: 'lane'}
    for lid, name in names.items():
        if lid not in layers or not len(layers[lid][1]):
            continue
        xy, tri, starts = flat_layer(chunks, *layers[lid])
        header['layers'][name] = {'xy': put(xy), 'tri': put(tri), 'starts': put(starts)}
        print('  %-9s %7d triangles' % (name, len(tri)))

    if buildings is not None and 0 in layers:
        verts, roof, roof_starts, wall, wall_starts = building_mesh(chunks, layers[0], buildings)
        header['buildings'] = {
            'count': int(len(buildings['height'])),
            'verts': put(verts),
            'roof': put(roof), 'roofStarts': put(roof_starts),
            'wall': put(wall), 'wallStarts': put(wall_starts),
        }
        print('  buildings %7d, tallest %.0f m%s' % (len(buildings['height']), buildings['height'].max(),
              ('  (%d under %.0f m2 left out)' % (dropped, args.min_area)) if dropped else ''))

    grid = survey_grid(water, bounds)
    image = ground_image(grid)
    image.save(os.path.join(args.out, 'ground.png'), optimize=True)
    header['ground'] = {
        'file': 'ground.png', 'cell': WATER_CELL,
        'x0': float(bounds[0]), 'y0': float(bounds[1]),
        'w': image.width, 'h': image.height,
    }

    head = json.dumps(header, separators=(',', ':')).encode()
    head += b' ' * (-len(head) % 4)
    with open(os.path.join(args.out, 'world.bin'), 'wb') as f:
        f.write(b'VHM1')
        f.write(struct.pack('<I', len(head)))
        f.write(head)
        for blob in blobs:
            f.write(blob)
    size = 8 + len(head) + offset
    print('wrote %s  (%.1f MB) and ground.png (%dx%d)'
          % (os.path.join(args.out, 'world.bin'), size / 1e6, image.width, image.height))


if __name__ == '__main__':
    sys.exit(main())
