#!/usr/bin/env python3
"""Спрайты ZX-оригинала (ref/zx/atic-atac/original/aticatac.asm, sprite_table: байт высоты, строки по 2 байта)
в разрешении Вектора с цветами CPC — автораскраска для сборки GFX_ZX=1 (tools/mkgame.py).
Форма — ZX (обрезана по рамке), место — внутри рамки кадра CPC (сдвиг без ухода влево/вверх: позиция кадра
та же, что у CPC), цвет точки — перо CPC под ней, нет — частое перо в окрестности, нет и там — частое перо кадра.
Соответствие кадров — по меткам CPC (MAP); для семейств — лучший из кандидатов по совпадению силуэтов."""
import os, re, collections
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')

def load():
    zx, cur = {}, None
    num = lambda t: int(t[1:], 16) if t.startswith('&') else int(t)
    for l in open(os.path.join(ROOT, 'ref/zx/atic-atac/original/aticatac.asm')):
        m = re.match(r'^(g_\w+):\s*db\s+(.*)', l)
        if m: cur = m.group(1); zx[cur] = []; rest = m.group(2)
        else:
            m2 = re.match(r'^\s+db\s+(.*)', l)
            if m2 and cur: rest = m2.group(1)
            else:
                if re.match(r'^\w', l): cur = None
                continue
        for t in rest.split(';')[0].split(','):
            if t.strip(): zx[cur].append(num(t.strip()))
    return zx
ZX = load()

def bits(name):
    d = ZX[name]; h = d[0]; wb = (len(d) - 1) // h
    b = [[(d[1 + y * wb + x // 8] >> (7 - x % 8)) & 1 for x in range(wb * 8)] for y in range(h)][::-1]   # ZX хранит снизу вверх
    ys = [y for y in range(h) if any(b[y])]; xs = [x for x in range(wb * 8) if any(b[y][x] for y in range(h))]
    return [r[xs[0]:xs[-1] + 1] for r in b[ys[0]:ys[-1] + 1]]

SEQ = lambda base, n: [['%s%d' % (base, i + 1)] for i in range(n)]
FIX = {}
for hero in ('knight', 'wizard', 'serf'):
    for d, zd in (('d', 'down'), ('u', 'up'), ('l', 'left'), ('r', 'right')):
        for f in range(3): FIX['%s_%s%d' % (hero, d, f)] = ['g_%s_%s%d' % (hero, zd, f + 1)]
def fam(labels, cands):
    for l in labels: FIX[l] = cands
for i, l in enumerate(('boss_devil_0_0', 'boss_devil_1_0', 'acg_shield_landscape')): FIX[l] = ['g_devil%d' % (i + 1)]
for z, c in (('dracula', 'dracula'), ('franken', 'frankie'), ('hunchback', 'hunchback'), ('mummy', 'mummy')):
    for i in range(3): FIX['boss_%s_%d_0' % (c, i)] = ['g_%s%d' % (z, i + 1)]
for i in range(4): FIX['birth_%d' % i] = ['g_sparkle%d' % (i + 1)]
for i, l in enumerate(('death_0', 'bookcase_portrait', 'death_2', 'death_3')): FIX[l] = ['g_pop%d' % (i + 1)]
fam(('item_bank_start', 'bat_large_1_0', 'bat_large_2_0', 'bat_large_3_0'), ['g_bat_l1', 'g_bat_l2', 'g_bat_r1', 'g_bat_r2'])
fam(('barrels', 'bat_small_1_0'), ['g_bat1', 'g_bat2'])
fam(('bouncy_0_0', 'bouncy_1_0'), ['g_blob1', 'g_blob2'])
fam(('ghost1_0_0', 'ghost1_1_0', 'ghost1_2_0', 'ghost1_3_0'), ['g_ghost1', 'g_ghost2'])
fam(('cavedoor_blue_portrait', 'ghost2_1_0'), ['g_ghoul1', 'g_ghoul2'])
fam(('monk_0_0', 'monk_1_0', 'monk_2_0', 'monk_3_0'), ['g_monk_l1', 'g_monk_l2', 'g_monk_r1', 'g_monk_r2'])
fam(('octopus_0_0', 'octopus_1_0'), ['g_spider1', 'g_spider2'])
fam(('pumpkin_0_0', 'pumpkin_1_0'), ['g_pumpkin1', 'g_pumpkin2'])
fam(('slime_0_0', 'slime_1_0'), ['g_ghostlet1', 'g_ghostlet2'])
fam(('spark_0_0', 'spark_1_0'), ['g_spikey1', 'g_spikey2'])
fam(('witch_0_0', 'witch_1_0', 'witch_2_0', 'witch_3_0'), ['g_witch_l1', 'g_witch_l2', 'g_witch_r1', 'g_witch_r2'])
fam(['weapon_sword_%d' % i for i in range(8)], ['g_sword%d' % (i + 1) for i in range(8)])
fam(['weapon_axe_%d' % i for i in range(8)] + ['door_closed_landscape'], ['g_axe%d' % (i + 1) for i in range(8)])
fam(['weapon_spell_%d' % i for i in range(4)], ['g_fireball1', 'g_fireball3'])

def colorize(rows, cands):
    """rows — перья CPC (точка CPC = 2 точки Вектора) -> (строки перьев в точках Вектора, имя ZX)"""
    hc, wc = len(rows), 2 * len(rows[0])
    cp = lambda X, Y: rows[Y][X // 2] if 0 <= Y < hc and 0 <= X < wc else 0
    best = None
    for name in cands:
        zb = bits(name); h, w = len(zb), len(zb[0])
        for dy in range(0, max(0, hc - h) + 1):
            for dx in range(0, max(0, wc - w) + 1):
                on = sum(1 for y in range(h) for x in range(w) if zb[y][x] and cp(x + dx, y + dy))
                off = sum(1 for y in range(h) for x in range(w) if zb[y][x] and not cp(x + dx, y + dy))
                cpc_n = sum(1 for y in range(hc) for x in range(wc) if cp(x, y))
                sc = on - 0.5 * off - 0.3 * (cpc_n - on)
                if best is None or sc > best[0]: best = (sc, name, dx, dy, zb)
    _, name, dx, dy, zb = best
    h, w = len(zb), len(zb[0])
    W, H = max(wc, dx + w), max(hc, dy + h)
    allp = [p for r in rows for p in r if p]
    common = collections.Counter(allp).most_common(1)[0][0] if allp else 13
    out = [[0] * W for _ in range(H)]
    for y in range(h):
        for x in range(w):
            if not zb[y][x]: continue
            X, Y = x + dx, y + dy
            p = cp(X, Y)
            if not p:
                for r in (1, 2, 3):
                    c = [cp(X + i, Y + j) for i in range(-r, r + 1) for j in range(-r, r + 1) if cp(X + i, Y + j)]
                    if c: p = collections.Counter(c).most_common(1)[0][0]; break
            out[Y][X] = p or common
    if FILL:                                          # дыры внутри формы ZX — цветом CPC под ними (чёрное CPC остаётся)
        zm = [[0] * W for _ in range(H)]
        for y in range(h):
            for x in range(w):
                if zb[y][x]: zm[y + dy][x + dx] = 1
        for Y, X in holes(zm):
            p = cp(X, Y)
            if p: out[Y][X] = p
    return out, name

FILL = os.environ.get('ZXFILL', '1') != '0'
def holes(m, r=3):
    """пустые точки внутри маски m: замкнутые (заливка от рамки по 4 соседям не доходит) или с точками маски не
    дальше r и слева, и справа, и сверху, и снизу"""
    H, W = len(m), len(m[0])
    out = set(); st = [(x, y) for x in range(W) for y in (0, H - 1)] + [(x, y) for y in range(H) for x in (0, W - 1)]
    while st:
        x, y = st.pop()
        if not (0 <= x < W and 0 <= y < H) or (x, y) in out or m[y][x]: continue
        out.add((x, y)); st += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    on = lambda x, y: 0 <= x < W and 0 <= y < H and m[y][x]
    res = []
    for y in range(H):
        for x in range(W):
            if m[y][x]: continue
            if (x, y) not in out or (any(on(x - i, y) for i in range(1, r + 1)) and any(on(x + i, y) for i in range(1, r + 1))
                                     and any(on(x, y - i) for i in range(1, r + 1)) and any(on(x, y + i) for i in range(1, r + 1))):
                res.append((y, x))
    return res
