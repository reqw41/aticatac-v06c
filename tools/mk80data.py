#!/usr/bin/env python3
"""Данные логики i8080 из сборки CPC: item_wh — (ширина, высота) метаданных предмета по типу
(item_bank_items в банке предметов). -> build/l80/item_wh.inc"""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
import roomref as rr
n = 40
out = ['; сгенерировано tools/mk80data.py', 'item_wh:']
for t in range(n):
    meta = rr.w16(rr.I, rr.SYM['item_bank_items'] + 2 * t)
    w, h = (rr.I(meta), rr.I(meta + 1)) if 0x4000 <= meta < 0x8000 else (0, 0)
    out.append('\tDB %d, %d\t; %d' % (w, h, t))
open(os.path.join(rr.ROOT, 'build/l80/item_wh.inc'), 'w').write('\n'.join(out) + '\n')
print('item_wh: %d типов' % n)
