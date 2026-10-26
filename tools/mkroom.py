#!/usr/bin/env python3
"""Данные отрисовки комнат на Векторе (proto/room.asm): банк комнат CPC как есть (с 0x4000 — указатели
внутри верны), графика предметов в 3 плоскостях (8 цветов, перестановка слотов как у mkovr) в квазидиске.

Предмет на CPC стоит с точностью до байта (2 пикселя = 4 точки Вектора): 2 фазы. Вариант = поворот
(бит 6 — «лёжа», бит 7 — переворот на 180°: данные с конца, пиксели в байте переставлены). Берутся все
варианты, что встречаются в списках предметов, для дверей — в обоих состояниях.

Описатель варианта-фазы: DB страница (значение порта 0x10), DW адрес в квазидиске, DB строк, столбцов,
маски столбцов (точки предмета; запись (экран & ~маска) | данные). Данные: столбец за столбцом,
в столбце плоскости 0..2, в плоскости строки сверху вниз, число строк дополнено до чётного (POP).
Таблица item_var: DW описатель фазы 0 для (тип*4 + (rot>>6)); описатель фазы 1 — следом за фазой 0.
Контуры комнат — заранее по типам (outline_tab: DB страница, DW адрес, DW число байт).

  python3 tools/mkroom.py <build/room>
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
import pixsmooth
import roomref as rr
from cpcpal import mode0, vecbyte

OUT = sys.argv[1]
from mkroom_slots import ROW0, PAL8, PMAP, PERM, SLOT
NPL = 3

# все используемые (тип, rot&0xC0)
used = set()
item_list, end = rr.SYM['room_bank_item_list'], rr.SYM['room_bank_items_per_room']
for ix in range(item_list, end, 8):
    t, st, rot = rr.R(ix), rr.R(ix + 2), rr.R(ix + 5) & 0xC0
    for s in (0, 0x80):
        used.add((rr.convert_door_type(t, s), rot))

def variant(t, rot):
    """-> строки пикселей CPC (перья) предмета в варианте rot"""
    meta = rr.w16(rr.I, rr.SYM['item_bank_items'] + 2 * t)
    size = rr.w16(rr.I, meta + 2)
    if rot & 0x40: rows, nb, data = rr.I(meta) * 4, rr.I(meta + 1) >> 2, rr.w16(rr.I, meta + 6)
    else: rows, nb, data = rr.I(meta + 1), rr.I(meta), rr.w16(rr.I, meta + 4)
    flip = bool(rot & 0x80)
    k = data + size - 1 if flip else data
    px = []
    for r in range(rows):
        row = []
        for i in range(nb):
            p0, p1 = mode0(rr.I(k)); k += -1 if flip else 1
            row += [p1, p0] if flip else [p0, p1]
        px.append(row)
    return px

PAGE0 = 1                                          # страницы квазидиска (стековый режим): 1, 2, ...
kv = {}                                            # страница -> bytearray
inc = []; table = {}
cur_page, cur = PAGE0, bytearray()
def put(data):
    global cur_page, cur
    if len(cur) + len(data) > 0x10000:
        kv[cur_page] = cur; cur_page += 1; cur = bytearray()
    a = len(cur); cur += data
    return cur_page, a
tot = 0
for (t, rot) in sorted(used):
    px = variant(t, rot)
    rows = len(px); w = len(px[0])                 # w пикселей CPC (чётно)
    hi = pixsmooth.smooth2x(px)                    # точки Вектора, сглаженный силуэт (tools/pixsmooth.py)
    names = []
    for ph in range(2):                            # сдвиг 0 или 4 точки (байт CPC в столбце Вектора)
        off = 4 * ph
        ncol = (off + 2 * w + 7) // 8
        masks = []; data = bytearray()
        for c in range(ncol):
            m = 0
            for j in range(8):
                x = (c * 8 + j - off)
                if 0 <= x < 2 * w: m |= 0x80 >> j
            masks.append(m)
            for k in range(NPL):
                col = []
                for r in range(rows):
                    v = 0
                    for j in range(8):
                        x = (c * 8 + j - off)
                        if 0 <= x < 2 * w and (SLOT[hi[r][x]] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
                    col.append(v)
                if rows % 2: col.append(0)
                data += bytes(col)
        page, a = put(data)
        tot += len(data)
        name = 'iv_%d_%d_%d' % (t, rot >> 6, ph)
        inc.append('%s:\tDB 0x%02X\n\tDW 0x%04X\n\tDB %d, %d%s' % (
            name, 0x10 | (page << 2), a, rows, ncol, ''.join(', 0x%02X' % m for m in masks)))
        names.append(name)
    table[(t, rot >> 6)] = names[0]
kv[cur_page] = cur

# контуры по типам комнат: те же отрезки, что draw_outline (Брезенхем roomref.plot_line), заранее —
# список ненулевых байт одной плоскости (столбец, строка, байт); на Векторе пишется в плоскости цвета
# комнаты. Элемент: DW 0x8000 + столбец*256 + строка, DB байт, DB 0. Страница квазидиска отдельная.
cur_page += 1; cur = bytearray()
ntypes = max(rr.R(rr.SYM['room_bank_roominfo'] + 2 * n + 1) for n in range(143)) + 1
out_desc = []; obytes = 0
for typ in range(ntypes):
    px = [[0] * 128 for _ in range(192)]
    t = rr.SYM['room_bank_roomtypes'] + 6 * typ
    pts, lines = rr.w16(rr.R, t + 2), rr.w16(rr.R, t + 4)
    pt = lambda a: (rr.R(pts + 2 * a), rr.R(pts + 2 * a + 1))
    q = lines
    while True:
        a = rr.R(q); q += 1
        if a == 0xFF: break
        b, c = pt(a)
        while True:
            a = rr.R(q); q += 1
            if a == 0xFF: break
            d, e = pt(a)
            rr.plot_line(px, b, c, d, e, 1)
    ent = bytearray()
    for col in range(24):
        for y in range(192):
            v = 0
            for j in range(8):
                if px[y][(col * 8 + j) // 2]: v |= 0x80 >> j
            if v:
                a = 0x8000 + col * 256 + ROW0 - y
                ent += bytes((a & 255, a >> 8, v, 0))
    page, a = put(bytes(ent))
    out_desc.append((0x10 | (page << 2), a, len(ent) // 4)); obytes += len(ent)
kv[cur_page] = cur
assert max(kv) <= 3, 'не влезло в страницы 1..3'

os.makedirs(OUT, exist_ok=True)
for p, d in kv.items():
    open(os.path.join(OUT, 'items%d.bin' % p), 'wb').write(d)
ntype = max(t for t, _ in used) + 1
lines = ['; сгенерировано tools/mkroom.py', 'ROW0\tequ %d' % ROW0, 'NITEMT\tequ %d' % ntype]
for p in sorted(kv): lines.append('KV_PAGE%d_LEN\tequ %d' % (p, (len(kv[p]) + 1) & ~1))
lines.append('\tDEFINE KV_PAGES %d' % len(kv))
open(os.path.join(OUT, 'room.inc'), 'w').write('\n'.join(lines) + '\n')
t_lines = ['item_var:']
for t in range(ntype):
    t_lines.append('\tDW ' + ', '.join(table.get((t, v), '0') for v in range(4)))
# слот линии комнаты для 4 цветов room_colour_palette (байт Mode 0 -> перо)
lslots = [SLOT[mode0(rr.G(rr.SYM['room_colour_palette'] + i))[0]] for i in range(4)]
t_lines.append('line_slot:\tDB ' + ', '.join(str(s) for s in lslots))
t_lines.append('outline_tab:')
for pg, a, n in out_desc: t_lines.append('\tDB 0x%02X\n\tDW 0x%04X, %d' % (pg, a, n))
t_lines.append('SKEL1\tequ 0x%02X\nSKEL2\tequ 0x%02X\nSKEL3\tequ 0x%02X\nSKEL4\tequ 0x%02X' % rr.SKELETON)
for nm in ('room_bank_roominfo', 'room_bank_roomtypes', 'room_bank_items_per_room'):
    t_lines.append('%s\tequ 0x%04X' % (nm.upper(), rr.SYM[nm]))
open(os.path.join(OUT, 'items.inc'), 'w').write('\n'.join(t_lines + inc) + '\n')
pal = [vecbyte(PAL8[PERM[i >> 1]]) for i in range(16)]
open(os.path.join(OUT, 'pal.inc'), 'w').write('pal_data:\tDB ' + ', '.join('0x%02X' % v for v in pal) + '\n')
import shutil
shutil.copy(os.path.join(rr.ROOT, 'build/cpcnew/rooms.bin'), os.path.join(OUT, 'rooms.bin'))
print('вариантов %d, графика предметов %d Б, контуры %d типов %d Б; страницы квазидиска %s, слоты линий %s'
      % (len(used), tot, ntypes, obytes, sorted(kv), lslots))
