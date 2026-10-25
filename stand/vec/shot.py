#!/usr/bin/env python3
"""Снимок Вектора (32К плоскостей + 16 Б палитры %BBGGGRRR) -> PNG 512x512 (точка 2x2), верх = строка памяти 255."""
import sys
from PIL import Image
d = open(sys.argv[1], 'rb').read(); pal = d[0x8000:0x8010]
def rgb(b): return ((b & 7) * 255 // 7, ((b >> 3) & 7) * 255 // 7, ((b >> 6) & 3) * 255 // 3)
im = Image.new('RGB', (256, 256))
for c in range(32):
    for r in range(256):
        p = [d[k * 0x2000 + c * 256 + r] for k in range(4)]
        for j in range(8):
            i = sum(((p[k] >> (7 - j)) & 1) << (3 - k) for k in range(4))
            im.putpixel((c * 8 + j, 255 - r), rgb(pal[i]))
im.resize((512, 512), Image.NEAREST).save(sys.argv[2])
