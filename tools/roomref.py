#!/usr/bin/env python3
"""Эталонная отрисовка комнаты CPC по данным игры (контур + предметы, как draw_room до draw_collectables).

Повторяет room.asm (draw_outline, get_point), lines.asm (plot_line — Брезенхем fgbrain, с его округлениями)
и items.asm (draw_items, convert_door_type, draw_item, переворот на 180°). Данные — собранные банки CPC
build/cpcnew/{rooms,items,gamecode}.bin (банки с 0x4000, код с 0x100), адреса — build/cpcsrc/rasmoutput.sym.
Результат — перья 128x192 (поле CPC); сверка со снимками MAME stand/cpc/rooms (allrooms.lua):

  python3 tools/roomref.py [номер комнаты]     — без номера сверяет все снятые комнаты
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from cpcpal import mode0, cpc_pixels

ROOT = os.path.join(os.path.dirname(__file__), '..')
SYM = {}
for l in open(os.path.join(ROOT, 'build/cpcsrc/rasmoutput.sym')):
    m = re.match(r'(\w+) #([0-9A-F]+)', l)
    if m: SYM[m.group(1).lower()] = int(m.group(2), 16)

def blob(name, base):
    d = open(os.path.join(ROOT, 'build/cpcnew', name), 'rb').read()
    return lambda a: d[a - base]
R = blob('rooms.bin', 0x4000)          # банк комнат (для сверки — снимок банка из MAME: состояния дверей)
def use_rooms_bank(data):
    global R
    R = lambda a: data[a - 0x4000]
I = blob('items.bin', 0x4000)          # банк предметов
G = blob('gamecode.bin', 0x100)        # основной код
w16 = lambda f, a: f(a) | f(a + 1) << 8
cst = open(os.path.join(ROOT, 'ref/cpc/utils/constants.asm')).read()
SKELETON = tuple(int(re.search(r'skeleton_room%d\s+equ\s+(0x[0-9a-fA-F]+|\d+)' % i, cst).group(1), 0) for i in range(1, 5))
NUM_ROWS = int(re.search(r'num_rows\s+equ\s+(\w+)', cst).group(1), 0)

def s16(v): v &= 0xFFFF; return v - 0x10000 if v & 0x8000 else v

def plot_line(px, b, c, d, e, pen):
    """bc = (x, y) начала, de = (x, y) конца; x вершин в полупикселях (делится на 2)."""
    x1, y1, x2, y2 = b >> 1, c, d >> 1, e
    dy = abs(y2 - y1)
    er = 0x8000 | (((-dy) & 0xFFFF) >> 1)
    sy = 1 if y1 < y2 else -1
    dx = abs(x2 - x1)
    sx = 1 if x1 < x2 else -1
    if dx >= dy: er = dx >> 1
    while True:
        px[y1][x1] = pen
        if x1 == x2 and y1 == y2: return
        e2 = er
        if s16(e2 + dx) >= 0:
            er = (er - dy) & 0xFFFF; x1 += sx
        if s16(e2 - dy) < 0:
            er = (er + dx) & 0xFFFF; y1 += sy

def draw_outline(px, room):
    ri = SYM['room_bank_roominfo'] + 2 * room
    col, typ = R(ri), R(ri + 1)
    if room in SKELETON: col = 0
    pen = mode0(G(SYM['room_colour_palette'] + (col & 3)))[0]   # там байт Mode 0 с пером в обоих пикселях
    t = SYM['room_bank_roomtypes'] + 6 * typ
    pts, lines = w16(R, t + 2), w16(R, t + 4)
    pt = lambda a: (R(pts + 2 * a), R(pts + 2 * a + 1))
    p = lines
    while True:
        a = R(p); p += 1
        if a == 0xFF: return pen
        b, c = pt(a)
        while True:
            a = R(p); p += 1
            if a == 0xFF: break
            d, e = pt(a)
            plot_line(px, b, c, d, e, pen)

def convert_door_type(t, state):
    closed = state & 0x80
    if t == 1: return 34 if closed else t
    if t == 2: return 32 if closed else t
    if t == 25: return t if closed else 24
    if t in (8, 9, 10, 11): return t if closed else 2
    if t in (12, 13, 14, 15): return t if closed else 1
    return t

def item_rects(room):
    """[(тип после convert, x байт, верх, строк, байт в строке, адрес данных, обратный порядок)]"""
    out = []
    p = w16(R, SYM['room_bank_items_per_room'] + 2 * room)
    while True:
        ix = w16(R, p); p += 2
        if ix == 0: return out
        if R(ix + 1) != room: ix += 8
        t = convert_door_type(R(ix), R(ix + 2))
        meta = w16(I, SYM['item_bank_items'] + 2 * t)
        bx, y = R(ix + 3) >> 2, R(ix + 4)
        rot = R(ix + 5) & 0xFE
        size = w16(I, meta + 2)
        if rot & 0x40:
            rows, nb, data = I(meta) * 4, I(meta + 1) >> 2, w16(I, meta + 6)
        else:
            rows, nb, data = I(meta + 1), I(meta), w16(I, meta + 4)
        out.append((t, bx, y - rows + 1, rows, nb, data, size, bool(rot & 0x80)))

def draw_items(px, room):
    for t, bx, top, rows, nb, data, size, flip in item_rects(room):
        k = data + size - 1 if flip else data
        for r in range(rows):
            for i in range(nb):
                v = I(k); k += -1 if flip else 1
                p0, p1 = mode0(v)
                if flip: p0, p1 = p1, p0
                px[top + r][2 * (bx + i)] = p0
                px[top + r][2 * (bx + i) + 1] = p1

def render(room):
    px = [[0] * 128 for _ in range(192)]
    pen = draw_outline(px, room)
    draw_items(px, room)
    return px

if __name__ == '__main__':
    rooms = [int(sys.argv[1])] if len(sys.argv) > 1 else range(143)
    bad = 0
    for n in rooms:
        f = os.path.join(ROOT, 'stand/cpc/rooms/r%03d' % n)
        mem = open(f + '.bin', 'rb').read(); v = open(f + '.vars', 'rb').read()
        ref = cpc_pixels(mem, v[1] << 8)
        use_rooms_bank(open(f + '.bank', 'rb').read())
        px = render(n)
        diff = [(x, y) for y in range(NUM_ROWS) for x in range(96) if px[y][x] != ref[y][x]]
        if diff:
            bad += 1
            ys = [y for _, y in diff]; xs = [x for x, _ in diff]
            print('комната %d: %d отличий, x %d..%d y %d..%d' % (n, len(diff), min(xs), max(xs), min(ys), max(ys)))
    print('совпало %d из %d' % (len(rooms) - bad, len(rooms)))
