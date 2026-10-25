#!/usr/bin/env python3
"""Кадры «как видит луч» (fr.raw из frames.js) -> GIF 50 к/с, игровое поле. gif.py fr.raw out.gif [с] [сколько]"""
import sys, numpy as np
from PIL import Image
W, H = 576, 288
fr = np.frombuffer(open(sys.argv[1], 'rb').read(), np.uint32).reshape(-1, H, W)
a = int(sys.argv[3]) if len(sys.argv) > 3 else 5; n = int(sys.argv[4]) if len(sys.argv) > 4 else 100
ims = []
for f in fr[a:a + n]:
    rgb = np.stack([(f >> s) & 255 for s in (0, 8, 16)], -1).astype(np.uint8)[16 + 32:16 + 224, 32:32 + 512]
    ims.append(Image.fromarray(rgb).resize((512, 384), Image.NEAREST))
ims[0].save(sys.argv[2], save_all=True, append_images=ims[1:], duration=20, loop=0)
