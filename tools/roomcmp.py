#!/usr/bin/env python3
"""Сверка комнат Вектора (stand/vec/roomrun.js) с эталоном tools/roomref.py (начальное состояние дверей).
Поле CPC 96x192 -> столбцы 0..23, строки памяти ROW0-191..ROW0, индекс палитры = слот пера (mkroom).
  python3 tools/roomcmp.py build/room/vec_rooms.bin [png-каталог для расхождений]"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import roomref as rr
from mkroom_slots import SLOT, ROW0
data = open(sys.argv[1], 'rb').read()
CH = 1 + 0x6000
bad = 0; n = len(data) // CH
for i in range(n):
    c = data[i * CH:(i + 1) * CH]; room = c[0]; pl = c[1:]
    px = rr.render(room)
    nd = 0; where = []
    for y in range(192):
        row = ROW0 - y
        for x in range(192):                    # точки поля
            col, bit = x >> 3, 0x80 >> (x & 7)
            v = 0
            for k in range(3):
                if pl[k * 0x2000 + col * 256 + row] & bit: v |= 4 >> k
            if v != SLOT[px[y][x >> 1]]:
                nd += 1; where.append((x, y))
    if nd:
        bad += 1
        xs = [p[0] for p in where]; ys = [p[1] for p in where]
        print('комната %d: %d точек, x %d..%d y %d..%d' % (room, nd, min(xs), max(xs), min(ys), max(ys)))
print('совпало %d из %d' % (n - bad, n))
