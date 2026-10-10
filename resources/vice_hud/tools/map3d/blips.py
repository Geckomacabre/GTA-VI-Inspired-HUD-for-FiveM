"""Builds the sheet of blip pictures the drawn minimap puts on the map.

    git clone --depth 1 https://github.com/citizenfx/fivem-docs
    python tools/map3d/blips.py --docs path/to/fivem-docs

The engine's radar draws its own blips; the drawn minimap replaces the radar,
so it has to draw them itself and needs the pictures. FiveM's documentation
carries every one of them at the size the game stores them (32 pixels) beside
the page that says which sprite number each is, which is all this reads:

    content/docs/game-references/blips.md     number -> name
    static/blips/<name>.png                   the picture

Writes html/map3d/blips.png and html/map3d/blips.json. They are the game's
pictures, so they are not in this repository; without them every blip is a
round dot in its own colour, and nothing else changes.
"""
import argparse
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image

CELL = 36      # the largest picture in the set; most are 32 and sit centred
COLS = 32


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--docs', required=True, help='a clone of citizenfx/fivem-docs')
    ap.add_argument('--out', default=os.path.join(here, '..', '..', 'html', 'map3d'))
    args = ap.parse_args()

    page = os.path.join(args.docs, 'content', 'docs', 'game-references', 'blips.md')
    pictures = os.path.join(args.docs, 'static', 'blips')
    if not os.path.isfile(page) or not os.path.isdir(pictures):
        raise SystemExit('that does not look like fivem-docs: no blips page or no static/blips')

    text = open(page, encoding='utf-8').read()
    found = re.findall(r'<img src="/blips/([^"]+)"[^>]*>.*?<strong>(\d+)</strong>', text)
    if not found:
        raise SystemExit('the blips page has changed shape: no sprite numbers found in it')

    cells, images = {}, []
    for file, number in found:
        path = os.path.join(pictures, file)
        if not os.path.isfile(path):
            continue
        try:
            im = Image.open(path)
            im.seek(0)
            im = im.convert('RGBA')
        except OSError:
            continue
        box = im.getbbox()
        if box is None:
            continue
        px = np.asarray(im).astype(np.int32)
        solid = px[..., 3] > 128
        if not solid.any():
            continue
        # The documentation stands a plain red square in for a sprite it has
        # no picture of. That is not a blip; leave it to be drawn as a dot.
        red = solid & (px[..., 0] > 240) & (px[..., 1] < 16) & (px[..., 2] < 16)
        if red.sum() > 0.9 * solid.sum():
            continue
        # Some pictures there are drawn black with a white edge. On the radar
        # a blip is a white shape with a dark edge, which is also the only
        # kind a blip's colour can tint, so those are turned inside out.
        grey = np.abs(px[..., 0] - px[..., 1]) + np.abs(px[..., 1] - px[..., 2]) < 24
        light = px[..., :3].mean(axis=-1) > 128
        if grey[solid].mean() > 0.95 and light[solid].mean() < 0.45:
            px[..., :3] = 255 - px[..., :3]
            im = Image.fromarray(px.astype(np.uint8), 'RGBA')
        # The animated ones are stored large; everything is brought to the
        # size the still ones already are.
        if max(im.size) > CELL:
            im = im.crop(box)
            scale = 32.0 / max(im.size)
            im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)
        cells[int(number)] = len(images)
        images.append(im)

    rows = math.ceil(len(images) / COLS)
    sheet = Image.new('RGBA', (COLS * CELL, rows * CELL), (0, 0, 0, 0))
    for i, im in enumerate(images):
        x = (i % COLS) * CELL + (CELL - im.width) // 2
        y = (i // COLS) * CELL + (CELL - im.height) // 2
        sheet.paste(im, (x, y))

    os.makedirs(args.out, exist_ok=True)
    sheet.save(os.path.join(args.out, 'blips.png'), optimize=True)
    with open(os.path.join(args.out, 'blips.json'), 'w', encoding='utf-8') as f:
        json.dump({'file': 'blips.png', 'cell': CELL, 'cols': COLS, 'rows': rows,
                   'cells': {str(k): v for k, v in sorted(cells.items())}}, f, separators=(',', ':'))
    print('wrote %d blips to %s (%dx%d)' % (len(images), os.path.join(args.out, 'blips.png'), sheet.width, sheet.height))


if __name__ == '__main__':
    sys.exit(main())
