#!/usr/bin/env python3
"""Снимок экрана модели CPC (tools/cpc6128.js): файл = 16К экрана + 17 цветов gate array + режим + CRTC R1,R6,R9.
  python3 tools/cpcshot.py in.scr out.png"""
import sys
from PIL import Image
sys.path.insert(0, __import__('os').path.dirname(__file__))
from cpcpal import HW
d = open(sys.argv[1], 'rb').read(); scr, pens, mode = d[:0x4000], d[0x4000:0x4011], d[0x4011]
R1, R6, R9 = d[0x4012], d[0x4013], d[0x4014]
BPL, H = 2 * R1, R6 * (R9 + 1)
GA = {i: HW.get(0x40 | i, (0, 0, 0)) for i in range(32)}
rgb = lambda pen: tuple((0, 128, 255)[c] for c in GA[pens[pen]])
W = BPL * (2 if mode == 0 else 4 if mode == 1 else 8)
img = Image.new('RGB', (W, H))
for y in range(H):
    a = (y // (R9 + 1)) * BPL + (y % (R9 + 1)) * 0x800
    for xb in range(BPL):
        b = scr[a + xb]
        if mode == 0:
            p = [((b >> 7) & 1) | ((b >> 3) & 1) << 1 | ((b >> 5) & 1) << 2 | ((b >> 1) & 1) << 3,
                 ((b >> 6) & 1) | ((b >> 2) & 1) << 1 | ((b >> 4) & 1) << 2 | (b & 1) << 3]
        elif mode == 1:
            p = [((b >> (7 - i)) & 1) | ((b >> (3 - i)) & 1) << 1 for i in range(4)]
        else:
            p = [(b >> (7 - i)) & 1 for i in range(8)]
        for i, q in enumerate(p): img.putpixel((xb * len(p) + i, y), rgb(q))
img.resize((W * (4 if mode == 0 else 2 if mode == 1 else 1), H * 2), Image.NEAREST).save(sys.argv[2])
