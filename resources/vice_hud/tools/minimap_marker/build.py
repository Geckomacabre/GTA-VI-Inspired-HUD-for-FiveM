"""Put the GTA VI player marker into a copy of the game's minimap.gfx.

    python build.py --ffdec <path to ffdec-cli.jar> --in <minimap.gfx> --out <new minimap.gfx>

The minimap is a scaleform, and the arrow that marks the player on it is a
vector shape inside that file (the blip called radar_centre). This swaps that
shape, and the two outline shapes that go with it, for the reference's marker:
a black ring, dark grey inside, a pale arrowhead. Nothing else in the file is
touched, and the script checks that before it writes anything: every other tag
has to come out byte for byte what went in.

The game still places the marker and turns it with the player; all that
changes is what it looks like. Its size is the minimap's "blipScale" setting.

It also takes out the game's own sat-nav strip -- the turn arrow and distance
("-> 0.12mi") the minimap draws along its bottom edge while a route is set.
The reference has one distance on the map, top left, and the HUD draws that
one; the strip was a second. It is removed by renaming the strip's symbol, so
the minimap's script finds nothing to attach and its sat-nav calls do nothing.
--keep-satnav leaves it in.

What you need:
  * minimap.gfx from the game build your server runs. It is in
        update\\update.rpf\\x64\\patch\\data\\cdimages\\scaleform_minimap.rpf
    (OpenIV or CodeWalker will get it out). The file differs between builds --
    newer ones carry more blips -- so use your own build's, and rebuild after
    changing sv_enforceGameBuild.
  * JPEXS Free Flash Decompiler (https://github.com/jindrapetrik/jpexs-decompiler),
    which needs Java. Its ffdec-cli.jar is what --ffdec points at.

Put the result in this resource's stream/ folder as minimap.gfx. Delete it
from there to get the stock arrow back. Only one resource on a server can
stream a minimap.gfx; if another already does (a custom blip pack), run this
on that one's file instead.

The measurements, from the reference at 1080p: the marker is 18.2px across;
the ring runs from 0.818 of the radius to the edge; the arrowhead's tip is
0.51 of the radius above the middle, its corners 0.425 out and 0.365 down, and
the notch in its base 0.245 down.
"""
import argparse, math, os, re, shutil, struct, subprocess, sys, tempfile

RING, INSIDE, ARROW = '#000000', '#322b2c', '#ebd9dd'
RADIUS = 8.75   # units; the footprint of the stock arrow and its outline


def circle(r):
    c = r / math.cos(math.radians(22.5))
    arcs = []
    for i in range(8):
        mid, end = math.radians(45 * i + 22.5), math.radians(45 * (i + 1))
        arcs.append('Q %.3f %.3f %.3f %.3f' % (c * math.cos(mid), c * math.sin(mid), r * math.cos(end), r * math.sin(end)))
    return 'M %.3f 0 ' % r + ' '.join(arcs) + ' Z'


def svg(paths):
    body = ''.join('  <path d="%s" fill="%s"%s fill-rule="nonzero" stroke="none"/>\n'
                   % (d, fill, ' fill-opacity="%s"' % alpha if alpha else '') for d, fill, alpha in paths)
    return ('<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
            '<svg xmlns="http://www.w3.org/2000/svg" width="40px" height="40px">\n' + body + '</svg>\n')


def shapes():
    r = RADIUS
    arrow = 'M 0 %.3f L %.3f %.3f L 0 %.3f L %.3f %.3f Z' % (-0.51 * r, 0.425 * r, 0.365 * r, 0.245 * r, -0.425 * r, 0.365 * r)
    return {
        'radar_centre': svg([(circle(r), RING, None), (circle(0.818 * r), INSIDE, None), (arrow, ARROW, None)]),
        # The outlines the stock arrow has: the same disc, so nothing of them shows round the marker.
        'radar_centre_stroke': svg([(circle(r), '#ffffff', None)]),
        'radar_centre_red_stroke': svg([(circle(r), '#ff0000', '0.6')]),
    }


def tags(path):
    """The file's header and its top-level tags as (code, bytes)."""
    d = open(path, 'rb').read()
    if d[:3] != b'GFX':
        sys.exit('%s is not an uncompressed GFX file' % path)
    nbits = d[8] >> 3
    pos = 8 + (5 + 4 * nbits + 7) // 8 + 4
    head, out = d[8:pos], []
    while pos < len(d):
        word = struct.unpack('<H', d[pos:pos + 2])[0]
        code, size, hdr = word >> 6, word & 0x3F, 2
        if size == 0x3F:
            size, hdr = struct.unpack('<I', d[pos + 2:pos + 6])[0], 6
        out.append((code, d[pos + hdr:pos + hdr + size]))
        pos += hdr + size
    return head, out


def character(tag):
    return struct.unpack('<H', tag[1][:2])[0]


def find_shapes(all_tags):
    """export name -> the id of the shape its sprite places."""
    exported, placed = {}, {}
    for code, body in all_tags:
        if code == 56:                                   # ExportAssets
            n = struct.unpack('<H', body[:2])[0]
            p = 2
            for _ in range(n):
                cid = struct.unpack('<H', body[p:p + 2])[0]
                end = body.index(b'\0', p + 2)
                exported[body[p + 2:end].decode('latin-1')] = cid
                p = end + 1
        elif code == 39:                                 # DefineSprite: its first PlaceObject2
            sid = struct.unpack('<H', body[:2])[0]
            p = 4
            while p < len(body):
                word = struct.unpack('<H', body[p:p + 2])[0]
                c, size, hdr = word >> 6, word & 0x3F, 2
                if size == 0x3F:
                    size, hdr = struct.unpack('<I', body[p + 2:p + 6])[0], 6
                if c == 26 and body[p + hdr] & 0x02:     # PlaceObject2 with a character
                    placed.setdefault(sid, struct.unpack('<H', body[p + hdr + 3:p + hdr + 5])[0])
                p += hdr + size
    out = {}
    for name in shapes():
        if name not in exported:
            sys.exit('this minimap.gfx has no blip called %s' % name)
        out[name] = placed[exported[name]]
    return out


def drop_satnav(path):
    """Rename the exported symbol "satnav" so the minimap can no longer attach it.
    One tag, same length; returns False if the file has no such symbol."""
    d = bytearray(open(path, 'rb').read())
    nbits = d[8] >> 3
    pos = 8 + (5 + 4 * nbits + 7) // 8 + 4
    while pos < len(d):
        word = struct.unpack('<H', d[pos:pos + 2])[0]
        code, size, hdr = word >> 6, word & 0x3F, 2
        if size == 0x3F:
            size, hdr = struct.unpack('<I', d[pos + 2:pos + 6])[0], 6
        body = pos + hdr
        if code == 56 and bytes(d[body:body + 2]) == b'\x01\x00' and bytes(d[body + 4:body + size]) == b'satnav\x00':
            d[body + 4:body + 10] = b'satna_'
            open(path, 'wb').write(bytes(d))
            return True
        pos += hdr + size
    return False


def main():
    ap = argparse.ArgumentParser(description='Put the GTA VI player marker into a copy of minimap.gfx.')
    ap.add_argument('--ffdec', required=True, help='path to JPEXS ffdec-cli.jar')
    ap.add_argument('--in', dest='src', required=True, help="the game's minimap.gfx")
    ap.add_argument('--out', required=True, help='where to write the new one')
    ap.add_argument('--java', default='java')
    ap.add_argument('--keep-satnav', action='store_true', help="leave the game's own turn-and-distance strip on the map")
    a = ap.parse_args()

    head, before = tags(a.src)
    ids = find_shapes(before)
    work = tempfile.mkdtemp(prefix='marker_')
    try:
        folder = os.path.join(work, 'shapes')
        os.makedirs(folder)
        for name, text in shapes().items():
            with open(os.path.join(folder, '%d.svg' % ids[name]), 'w', newline='\n') as fh:
                fh.write(text)
        built = os.path.join(work, 'minimap.gfx')
        run = subprocess.run([a.java, '-jar', a.ffdec, '-importShapes', a.src, built, 'nofill', folder],
                             capture_output=True, text=True)
        if not os.path.exists(built):
            sys.exit('JPEXS did not write a file:\n' + run.stdout + run.stderr)

        head2, after = tags(built)
        wanted = set(ids.values())
        if head2 != head or len(after) != len(before):
            sys.exit('the rebuilt file is not the same shape as the original; not writing it')
        changed = [character(n) for o, n in zip(before, after) if o != n]
        if set(changed) != wanted or len(changed) != len(wanted):
            sys.exit('expected only shapes %s to change, got %s; not writing it' % (sorted(wanted), sorted(changed)))
        strip = 'kept'
        if not a.keep_satnav:
            strip = 'removed' if drop_satnav(built) else 'not found in this file'
            _, patched = tags(built)
            off = [i for i, (o, n) in enumerate(zip(after, patched)) if o != n]
            if len(patched) != len(after) or len(off) > 1 or (off and patched[off[0]][0] != 56):
                sys.exit('taking out the sat-nav strip changed more than its one tag; not writing it')
        shutil.copyfile(built, a.out)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print('player marker written to %s' % a.out)
    print('  shapes replaced: ' + ', '.join('%s = %d' % (n, i) for n, i in ids.items()))
    print('  sat-nav strip: ' + strip)
    print('  %d other tags unchanged' % (len(before) - len(ids) - (1 if strip == 'removed' else 0)))


if __name__ == '__main__':
    main()
