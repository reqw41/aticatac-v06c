#!/usr/bin/env python3
"""Данные прототипа вывода (proto/): фон комнаты 0 и спрайты CPC -> плоскости Вектора.

Пиксель CPC Mode 0 = 2 точки Вектора. Перо p -> плоскость k (0x8000 + k*0x2000) хранит бит (3-k) пера,
то есть индекс палитры Вектора p0<<3|p1<<2|p2<<1|p3 равен номеру пера CPC и XOR плоскостей = XOR перьев.
Экран Вектора: байт = 0x8000 + плоскость*0x2000 + столбец*256 + строка_памяти, строка 255 — верх кадра.
Строка CPC y (0..191) -> строка памяти ROW0 - y.

Спрайт: 4 фазы (сдвиг 0/2/4/6 точек = 0..3 пикселя CPC). Для каждой фазы — непустые блоки
(столбец, плоскость) высотой H (чётная, данные по парам для POP), данные идут в квазидиск подряд.
Дескриптор (ОЗУ): DW указатель_в_квазидиске, DW вход_в_развёрнутый_цикл, DB сдвиг_строки, DB блоков, DB смещения_h...

  python3 tools/mkproto.py <ref/cpc> <bg8000.bin> <build/proto>
  COLORS=8 — 8 цветов: 3 плоскости (0x8000, 0xA000, 0xC000), плоскость 0xE000 не видна (палитра
  дублирует записи), перья CPC сведены к 8 цветам перебором (минимум ошибки, взвешенной по частоте).
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from cpcpal import vecbyte, mode0, cpc_pixels, HW, PENS
import itertools

REF, BG, OUT = sys.argv[1:4]
ROW0 = 223                     # строка памяти для y = 0 (картинка 192 строки по центру 256)
KVAZ0 = 0x1000                 # данные спрайтов в образе и в квазидиске (стр. 0) с этого адреса
KVAZ_END = 0x8000
MAXPAIRS = 16                  # длина развёрнутого цикла blit (пар строк)

def parse(fn):
    cur = None; d = {}
    for line in open(fn):
        s = line.split(';')[0]
        m = re.match(r"^\s*([A-Za-z_]\w*)\s*$", s)
        if m: cur = m.group(1); d[cur] = []; continue
        m = re.match(r'\s*(defb|db)\s+(.*)', s, re.I)
        if m and cur:
            d[cur].append([int(t.strip(), 0) & 255 for t in m.group(2).split(',') if t.strip()])
    return d

G = {}
for f in ('baddies_gfx', 'player_sprites_gfx', 'weapon_gfx'):
    G.update(parse(os.path.join(REF, 'graphics', f + '.asm')))

COLORS = int(os.environ.get('COLORS', '16'))
PIX = int(os.environ.get('PIX', '2'))       # точек Вектора на пиксель CPC: 2 (как на экране CPC) или 1 (картинка 128 точек)
NPH = 4 if PIX == 2 else 8                  # фаз сдвига: пиксель CPC внутри байта Вектора
COL0 = 0 if PIX == 2 else 8                 # столбец левого края картинки
if PIX == 1: KVAZ0 = 0x2000                 # дескрипторов вдвое больше (8 фаз)
NPL = 4 if COLORS == 16 else 3
if COLORS == 16:
    PMAP = list(range(16)); PAL8 = None
else:
    # частоты перьев: спрайты, предметы, снимок экрана
    w = [0] * 16
    for src in (G, parse(os.path.join(REF, 'graphics', 'item_gfx.asm'))):
        for k, v in src.items():
            if re.search(r'_\d_1$', k): continue
            for r in v:
                for b in r:
                    for q in mode0(b): w[q] += 1
    for r in cpc_pixels(open(BG, 'rb').read(), 0x8000):
        for q in r: w[q] += 1
    rgb = [HW[PENS[q]] for q in range(16)]
    d2 = lambda a, b: sum((x - y) ** 2 for x, y in zip(rgb[a], rgb[b]))
    best = None
    for sel in itertools.combinations(range(1, 16), 7):
        cand = (0,) + sel
        e = sum(w[q] * min(d2(q, c) for c in cand[1:]) for q in range(1, 16))   # цвет в чёрный не сводим
        if best is None or e < best[0]: best = (e, cand)
    PAL8 = best[1]
    PMAP = [0] + [min(range(1, 8), key=lambda i: d2(q, PAL8[i])) for q in range(1, 16)]
    print('8 цветов: перья CPC', PAL8, '; сведение', PMAP)

# виды: имя -> (метки кадров, последовательность анимации из 8 шагов)
KINDS = {
    'knight_r': (['sprite_bank_player_kr_%d_0' % i for i in range(3)], [0, 1, 2, 1, 0, 1, 2, 1]),
    'knight_l': (['sprite_bank_player_kl_%d_0' % i for i in range(3)], [0, 1, 2, 1, 0, 1, 2, 1]),
    'ghost':    (['ghost1_%d_0' % i for i in range(4)], [0, 1, 2, 3, 0, 1, 2, 3]),
    'bat':      (['bat_large_%d_0' % i for i in range(4)], [0, 1, 2, 3, 0, 1, 2, 3]),
    'witch':    (['witch_%d_0' % i for i in range(4)], [0, 1, 2, 3, 0, 1, 2, 3]),
    'pumpkin':  (['pumpkin_%d_0' % i for i in range(2)], [0, 1, 0, 1, 0, 1, 0, 1]),
    'axe':      (['weapon_axe_%d' % i for i in range(8)], list(range(8))),
}

def frame_planes(rows, phase):
    """rows: строки байт CPC -> (yoff, H, {(col, plane): [байты]}) для сдвига phase пикселей CPC."""
    pens = [[PMAP[p] for b in r for p in mode0(b)] for r in rows]
    y0 = next((i for i, r in enumerate(pens) if any(r)), 0)
    y1 = max((i for i, r in enumerate(pens) if any(r)), default=0) + 1
    pens = pens[y0:y1]
    if len(pens) % 2: pens.append([0] * len(pens[0]))
    w = max(len(r) for r in pens)
    ncol = (PIX * (w + phase) + 7) // 8
    blocks = {}
    for c in range(ncol):
        for k in range(NPL):
            col = []
            for r in pens:
                v = 0
                for j in range(8):
                    x = (c * 8 + j) // PIX - phase        # пиксель CPC под точкой j
                    if 0 <= x < len(r) and (r[x] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
                col.append(v)
            if any(col): blocks[(c, k)] = col
    return y0, len(pens), blocks

kvaz = bytearray(); descs = []; inc = []
stat_blocks = 0; stat_bytes = 0
for kind, (labels, seq) in KINDS.items():
    names = []
    for fi, lab in enumerate(labels):
        for ph in range(NPH):
            yoff, h, blocks = frame_planes(G[lab], ph)
            assert h // 2 <= MAXPAIRS, (lab, h)
            name = 'd_%s_%d_%d' % (kind, fi, ph)
            ptr = KVAZ0 + len(kvaz); offs = []
            for (c, k), col in sorted(blocks.items()):
                kvaz += bytes(col); offs.append(c + 0x20 * k)
            stat_blocks += len(offs); stat_bytes += h * len(offs)
            inc.append('%s:\tDW 0x%04X, bl_body + %d*BL_PAIR\n\tDB %d, %d%s' % (
                name, ptr, MAXPAIRS - h // 2, yoff, len(offs), ''.join(', 0x%02X' % o for o in offs)))
            names.append(name)
    # таблица вида: 8 шагов анимации x NPH фаз
    inc.append('t_%s:' % kind)
    for s in seq:
        inc.append('\tDW ' + ', '.join('d_%s_%d_%d' % (kind, s, ph) for ph in range(NPH)))

assert KVAZ0 + len(kvaz) <= KVAZ_END, hex(KVAZ0 + len(kvaz))
if len(kvaz) % 2: kvaz.append(0)
os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'spr.bin'), 'wb').write(kvaz)
open(os.path.join(OUT, 'spr.inc'), 'w').write(
    '; сгенерировано tools/mkproto.py\nKVAZ0\tequ 0x%04X\nKVAZ_END\tequ 0x%04X\nMAXPAIRS\tequ %d\nROW0\tequ %d\n'
    % (KVAZ0, KVAZ0 + len(kvaz), MAXPAIRS, ROW0) + ('\tDEFINE PIX1\n' if PIX == 1 else ''))
open(os.path.join(OUT, 'spr_desc.inc'), 'w').write('; сгенерировано tools/mkproto.py\n' + '\n'.join(inc) + '\n')

# фон: экран CPC -> 4 плоскости по 8К; строки вне картинки — ноль
mem = open(BG, 'rb').read()
px = cpc_pixels(mem, 0x8000)
scr = bytearray(0x8000)
for y in range(192):
    row = ROW0 - y
    for c in range(16 * PIX):
        for k in range(NPL):
            v = 0
            for j in range(8):
                if (PMAP[px[y][(c * 8 + j) // PIX]] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
            scr[k * 0x2000 + (COL0 + c) * 256 + row] = v
open(os.path.join(OUT, 'bg.bin'), 'wb').write(scr)
# палитра Вектора: индекс = p0<<3|p1<<2|p2<<1|p3; при 8 цветах p3 не важен
pal = [vecbyte(p) for p in range(16)] if COLORS == 16 else [vecbyte(PAL8[i >> 1]) for i in range(16)]
open(os.path.join(OUT, 'pal.inc'), 'w').write(
    'pal_data:\tDB ' + ', '.join('0x%02X' % v for v in pal) + '\n')
print('спрайты: %d Б в квазидиске (0x%04X..0x%04X), блоков %d, байт-плоскостей %d'
      % (len(kvaz), KVAZ0, KVAZ0 + len(kvaz), stat_blocks, stat_bytes))
