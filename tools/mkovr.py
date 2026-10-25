#!/usr/bin/env python3
"""Данные прототипа «запись без XOR» (proto.asm -DOVR): 8 цветов, 3 плоскости, пиксель CPC = 2 точки.

Спрайт пишется поверх экрана рамкой (столбцы x высота), без XOR. В столбце рамки плоскость с данными —
блок POP из квазидиска + запись; плоскость без данных — нули (PUSH прямо в экран), но только там, где под
рамкой непустой фон: на чёрном полу она и так нулевая. Часть видов сведена к 1 или 2 плоскостям (PLANES):
форма лежит только в них. Стирание: на чёрном полу — нули в плоскостях с данными; где фон непустой — копия
фона из квазидиска (те же адреса, что у экрана, 0x8000..0xDFFF). Непустые места — bgf.bin [группа 8 строк][столбец].
Дескриптор: DW данные, вход рисования, вход нулей, вход восстановления; DB сдвиг строки, высота, столбцов;
смещения блоков данных (столбец + 0x20*плоскость).., 0xFF; смещения блоков без данных.., 0xFF.

Палитра: 8 цветов те же, что у mkproto COLORS=8; перестановка цветов по индексам подбирается перебором
так, чтобы одно- и двухплоскостные спрайты получили ближайшие цвета.

  python3 tools/mkovr.py <ref/cpc> <bg8000.bin> <build/ovr>
"""
import os, re, sys, itertools
sys.path.insert(0, os.path.dirname(__file__))
from cpcpal import vecbyte, mode0, cpc_pixels, HW, PENS

REF, BG, OUT = sys.argv[1:4]
ROW0 = 223
KVAZ0 = 0x2000
MAXPAIRS = 16
NPL = 3
PAL8 = (0, 1, 4, 7, 8, 10, 13, 15)          # перья CPC восьмёрки (подбор mkproto COLORS=8)
PMAP = [0, 1, 1, 2, 2, 2, 2, 3, 4, 3, 5, 5, 5, 6, 4, 7]   # перо CPC -> номер в PAL8

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

KINDS = {
    'knight_r': (['sprite_bank_player_kr_%d_0' % i for i in range(3)], [0, 1, 2, 1, 0, 1, 2, 1]),
    'knight_l': (['sprite_bank_player_kl_%d_0' % i for i in range(3)], [0, 1, 2, 1, 0, 1, 2, 1]),
    'ghost':    (['ghost1_%d_0' % i for i in range(4)], [0, 1, 2, 3, 0, 1, 2, 3]),
    'bat':      (['bat_large_%d_0' % i for i in range(4)], [0, 1, 2, 3, 0, 1, 2, 3]),
    'witch':    (['witch_%d_0' % i for i in range(4)], [0, 1, 2, 3, 0, 1, 2, 3]),
    'pumpkin':  (['pumpkin_%d_0' % i for i in range(2)], [0, 1, 0, 1, 0, 1, 0, 1]),
    'axe':      (['weapon_axe_%d' % i for i in range(8)], list(range(8))),
}
PLANES = dict(knight_r=3, knight_l=3, ghost=1, bat=1, axe=1, witch=2, pumpkin=2)
for k, v in os.environ.items():                        # PL_ghost=2 и т.п. — переопределить
    if k.startswith('PL_'): PLANES[k[3:]] = int(v)

rgb = lambda pen: HW[PENS[pen]]
d2 = lambda a, b: sum((x - y) ** 2 for x, y in zip(a, b))

# гистограмма перьев по видам
hist = {}
for kind, (labels, _) in KINDS.items():
    h = [0] * 16
    for lab in labels:
        for r in G[lab]:
            for b in r:
                for q in mode0(b): h[q] += 1
    hist[kind] = h

def subsets(n):                                        # наборы плоскостей (маски битов индекса)
    return [sum(1 << (NPL - 1 - k) for k in c) for c in itertools.combinations(range(NPL), n)]

def kind_cost(h, perm, n):
    """perm[slot] = номер в PAL8. Лучший набор плоскостей для вида: (ошибка, маска)."""
    best = None
    for m in subsets(n):
        slots = [s for s in range(1, 8) if s & ~m == 0]
        e = sum(h[q] * min(d2(rgb(q), rgb(PAL8[perm[s]])) for s in slots) for q in range(1, 16) if h[q])
        if best is None or e < best[0]: best = (e, m)
    return best

best = None
for p in itertools.permutations(range(1, 8)):
    perm = (0,) + p
    e = sum(kind_cost(hist[k], perm, PLANES[k])[0] for k in KINDS if PLANES[k] < 3)
    if best is None or e < best[0]: best = (e, perm)
PERM = best[1]
INV = [PERM.index(j) for j in range(8)]               # номер в PAL8 -> слот (индекс палитры)
MASK = {k: (kind_cost(hist[k], PERM, PLANES[k])[1] if PLANES[k] < 3 else 7) for k in KINDS}

def pen_slot(q, mask):
    if q == 0: return 0
    if mask == 7: return INV[PMAP[q]]
    return min((s for s in range(1, 8) if s & ~mask == 0), key=lambda s: d2(rgb(q), rgb(PAL8[PERM[s]])))

print('перестановка слотов', PERM, '; цвета слотов (перья CPC)', [PAL8[PERM[s]] for s in range(8)])
for k in KINDS:
    print('  %-9s плоскостей %d, маска %s, цвета %s' % (k, PLANES[k], format(MASK[k], '03b'),
          sorted({pen_slot(q, MASK[k]) for q in range(1, 16) if hist[k][q]})))

def frame(rows, phase, mask):
    """-> yoff, H, ncol, {(c,k): байты}, [(c,k) нулевые]"""
    pens = [[pen_slot(p, mask) for b in r for p in mode0(b)] for r in rows]
    y0 = next((i for i, r in enumerate(pens) if any(r)), 0)
    y1 = max((i for i, r in enumerate(pens) if any(r)), default=0) + 1
    pens = pens[y0:y1]
    if len(pens) % 2: pens.append([0] * len(pens[0]))
    w = max(len(r) for r in pens)
    ncol = (2 * (w + phase) + 7) // 8
    data = {}; zero = []
    for c in range(ncol):
        for k in range(NPL):
            col = []
            for r in pens:
                v = 0
                for j in range(8):
                    x = (c * 8 + j) // 2 - phase
                    if 0 <= x < len(r) and (r[x] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
                col.append(v)
            if any(col): data[(c, k)] = col
            else: zero.append((c, k))
    return y0, len(pens), ncol, data, zero

kvaz = bytearray(); inc = []; st = dict(data=0, zero=0, box=0, n=0)
for kind, (labels, seq) in KINDS.items():
    for fi, lab in enumerate(labels):
        for ph in range(4):
            yoff, h, ncol, data, zero = frame(G[lab], ph, MASK[kind])
            assert h // 2 <= MAXPAIRS
            ptr = KVAZ0 + len(kvaz)
            doffs = []
            for (c, k), col in sorted(data.items()):
                kvaz += bytes(col); doffs.append(c + 0x20 * k)
            zoffs = [c + 0x20 * k for c, k in sorted(zero)]
            st['data'] += h * len(data); st['zero'] += h * len(zero); st['box'] += h * ncol; st['n'] += 1
            sk = MAXPAIRS - h // 2
            inc.append('d_%s_%d_%d:\tDW 0x%04X, dr_body + %d*DR_PAIR, zr_body + %d, rs_body + %d*RS_PAIR\n'
                       '\tDB %d, %d, %d%s, 0xFF%s, 0xFF' % (
                kind, fi, ph, ptr, sk, sk, sk, yoff, h, ncol, ''.join(', 0x%02X' % o for o in doffs),
                ''.join(', 0x%02X' % o for o in zoffs)))
    inc.append('t_%s:' % kind)
    for s in seq:
        inc.append('\tDW ' + ', '.join('d_%s_%d_%d' % (kind, s, ph) for ph in range(4)))

if len(kvaz) % 2: kvaz.append(0)
assert KVAZ0 + len(kvaz) <= 0x8000
os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'spr.bin'), 'wb').write(kvaz)
open(os.path.join(OUT, 'spr.inc'), 'w').write(
    '; сгенерировано tools/mkovr.py\nKVAZ0\tequ 0x%04X\nKVAZ_END\tequ 0x%04X\nMAXPAIRS\tequ %d\nROW0\tequ %d\n'
    '\tDEFINE OVR\n' % (KVAZ0, KVAZ0 + len(kvaz), MAXPAIRS, ROW0))
open(os.path.join(OUT, 'spr_desc.inc'), 'w').write('; сгенерировано tools/mkovr.py\n' + '\n'.join(inc) + '\n')

# фон
px = cpc_pixels(open(BG, 'rb').read(), 0x8000)
scr = bytearray(0x8000)
for y in range(192):
    row = ROW0 - y
    for c in range(32):
        for k in range(NPL):
            v = 0
            for j in range(8):
                if (INV[PMAP[px[y][c * 4 + j // 2]]] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
            scr[k * 0x2000 + c * 256 + row] = v
open(os.path.join(OUT, 'bg.bin'), 'wb').write(scr)
# bgf[g*32 + c] = 1, если в столбце c в строках памяти 8g..8g+31 фон не чёрный (рамка до 22 строк от низа)
nb = [[any(scr[k * 0x2000 + c * 256 + r] for k in range(NPL)) for r in range(256)] for c in range(32)]
bgf = bytearray(1024)
for g in range(32):
    for c in range(32):
        bgf[g * 32 + c] = int(any(nb[c][r] for r in range(8 * g, min(256, 8 * g + 32))))
open(os.path.join(OUT, 'bgf.bin'), 'wb').write(bgf)
pal = [vecbyte(PAL8[PERM[i >> 1]]) for i in range(16)]
open(os.path.join(OUT, 'pal.inc'), 'w').write('pal_data:\tDB ' + ', '.join('0x%02X' % v for v in pal) + '\n')
n = st['n']
print('квазидиск %d Б; на кадр-фазу в среднем: данных %.0f Б, нулей %.0f Б, рамка %.0f Б/плоскость'
      % (len(kvaz), st['data'] / n, st['zero'] / n, st['box'] / n))
