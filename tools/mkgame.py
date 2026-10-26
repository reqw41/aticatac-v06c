#!/usr/bin/env python3
"""Графика игры для Вектора (этап 3, docs/LOGIC_PLAN.md): спрайты героев, врагов, боссов, оружия — поток для
квазидиска; ключи, еда, могила — описатели предметов (как в tools/mkroom.py); правки образа страницы 0 CPC.

Спрайт (3 плоскости, 4 фазы = x & 3 пикселя CPC): в ОЗУ — запись кадра
    DB высота (чётная), сдвиг сверху, порт квазидиска (0x10 | стр << 2); DW адреса фаз 0..3;
    DB столбцов фазы 0..3
в квазидиске на фазу — поток слов для POP: блок данных = (смещение, 0) и высота байт (строки сверху вниз);
блок рамки без данных = (смещение, 1); конец = (0xFF, 2). Смещение = столбец + 0x20 * плоскость.
XOR-вывод пропускает блоки без данных, замещение пишет в них нули.
Карта фона комнат (bgf): на комнату 72 байта — по столбцу поля (24) 3 байта бит групп по 8 строк
(24 группы, бит 0 первого байта — строки 0..7); «есть фон» = контур, предметы в обоих состояниях дверей.
Квазидиск стр. 2 с BGF_ADDR.

Указатели на графику, которые читает только вывод, переписываются в образе страницы 0 указателями на записи:
списки кадров врагов и боссов (struct + 5.., alt-списки), кадры оружия (+4), таблица еды, ключи (+1).
Таблицы кадров героев — свои (hero_frames: 3 героя x 4 направления x 4 шага).

  python3 tools/mkgame.py build/game        -> sprites.inc (записи, таблицы), patch.json, kv*.bin
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
import roomref as rr
from cpcpal import mode0
from mkroom_slots import SLOT, ROW0, PAL8, PERM
import pixsmooth
from cpcpal import rgb

OUT = sys.argv[1]
NPL = 3
S = rr.SYM
B = os.path.join(rr.ROOT, 'build/cpcnew')
code = open(os.path.join(B, 'gamecode.bin'), 'rb').read()
heroes = open(os.path.join(B, 'heroes.bin'), 'rb').read()
baddies = open(os.path.join(B, 'baddies.bin'), 'rb').read()
rooms = open(os.path.join(B, 'rooms.bin'), 'rb').read()
G = lambda a: code[a - 0x100]
G16 = lambda a: G(a) | G(a + 1) << 8
bank = {'heroes': heroes, 'baddies': baddies, 'rooms': rooms}

def gfx(bk, addr, wbytes, h):
    d = bank[bk]
    rows = []
    for r in range(h):
        row = []
        for i in range(wbytes):
            row += list(mode0(d[addr - 0x4000 + r * wbytes + i]))
        rows.append(row)
    return rows

# --- квазидиск
class KV:
    def __init__(self, pages):                     # [(страница, начало, конец)]
        self.pages = pages; self.i = 0; self.pos = pages[0][1]; self.data = {p: bytearray() for p, _, _ in pages}
    def put(self, b):
        p, lo, hi = self.pages[self.i]
        if self.pos + len(b) > hi:
            self.i += 1; p, lo, hi = self.pages[self.i]; self.pos = lo
        a = self.pos; self.pos += len(b)
        d = self.data[p]; need = a - lo + len(b)
        if len(d) < need: d.extend(b'\0' * (need - len(d)))
        d[a - lo:a - lo + len(b)] = b
        return p, a

# сокращение до 4 цветов (чёрный + 3 в двух плоскостях): лучшая пара плоскостей для группы кадров,
# цвета вне пары — ближайшие по RGB (разбор 25.10: build/game/sprites4_review.png)
VRGB = [rgb(PAL8[PERM[i]]) for i in range(8)]
def reduce_map(frames_rows):
    hist = [0] * 8
    for rows in frames_rows:
        for r in rows:
            for p in r: hist[SLOT[p]] += 1
    d2 = lambda a, b: sum((x - y) ** 2 for x, y in zip(VRGB[a], VRGB[b]))
    best = None
    for m in (0b011, 0b101, 0b110):
        allowed = [i for i in range(1, 8) if i & ~m == 0]
        mp = [0] + [i if i in allowed else min(allowed, key=lambda a: d2(a, i)) for i in range(1, 8)]
        ch = sum(hist[i] for i in range(1, 8) if mp[i] != i)
        if best is None or ch < best[0]: best = (ch, mp)
    return best[1]

GFX_ZX = os.environ.get('GFX_ZX') == '1'            # спрайты — формы ZX в разрешении Вектора с цветами CPC (tools/zxgfx.py)
if GFX_ZX:
    import zxgfx
    _inv = {}
    for _k, _v in S.items():
        if isinstance(_v, int): _inv.setdefault(_v, _k)
    def zx_cands(key):
        if key.startswith(('bad_', 'wpn_')): return zxgfx.FIX.get(_inv.get(int(key[4:], 16), ''))
        return zxgfx.FIX.get(key)

def sprite_streams(rows, mp=None, hires=False):
    """перья -> (yoff, h, [поток фазы 0..3], [столбцов фазы 0..3]); hires — строки в точках Вектора"""
    pens = [[SLOT[p] for p in r] for r in rows]
    if mp: pens = [[mp[v] for v in r] for r in pens]
    y0 = next((i for i, r in enumerate(pens) if any(r)), 0)
    y1 = max((i for i, r in enumerate(pens) if any(r)), default=0) + 1
    pens = pens[y0:y1]
    if len(pens) % 2: pens.append([0] * len(pens[0]))
    w = len(pens[0])
    out = []; ncols = []; costs = []
    for ph in range(4):
        ncol = ((w + 2 * ph if hires else 2 * (w + ph)) + 7) // 8
        ncols.append(ncol)
        data, zero = [], []
        for c in range(ncol):
            for k in range(NPL):
                col = []
                for r in pens:
                    v = 0
                    for j in range(8):
                        x = (c * 8 + j - 2 * ph) if hires else (c * 8 + j) // 2 - ph
                        if 0 <= x < w and (r[x] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
                    col.append(v)
                if any(col): data.append((c + 0x20 * k, col))
                else: zero.append(c + 0x20 * k)
        # стоимость вывода XOR одного изображения (единицы по 64 такта): блок — h * 29 + 80, вход — 700
        h2 = len(pens)
        costs.append(min(255, (len(data) * (h2 * 29 + 80) + 700 + 63) // 64))
        s = bytearray()
        for off, col in data: s += bytes((off, 0)) + bytes(col)
        for off in zero: s += bytes((off, 1))
        s += bytes((0xff, 2))
        out.append(bytes(s))
    return y0, len(pens), out, ncols, costs

kv = KV([(3, 0x0000, 0x10000), (0, 0x0000, 0x8000)])
frames = {}                                        # ключ -> метка записи
inc = ['; сгенерировано tools/mkgame.py']
stat = dict(frames=0, bytes=0)

def frame(key, rows, mp=None):
    if key in frames: return frames[key]
    hires = False
    if GFX_ZX and zx_cands(key):
        rows, _zn = zxgfx.colorize(rows, zx_cands(key)); hires = True
    else:
        rows = pixsmooth.smooth2x(rows); hires = True        # точки Вектора, сглаженный силуэт
    y0, h, streams, ncols, costs = sprite_streams(rows, mp, hires)
    assert h <= 24, (key, h)
    addrs = []; page = None
    for s in streams:
        p, a = kv.put(s)
        if page is None: page = p
        elif p != page:                            # фазы кадра — в одной странице
            p, a = kv.put(s); page = p
        addrs.append(a); stat['bytes'] += len(s)
    lab = 'fr_%d' % len(frames)
    inc.append('%s:\tDB %d, %d, 0x%02X\n\tDW %s\n\tDB %s\n\tDB %s\t; %s' % (lab, h, y0, 0x10 | (page << 2), ', '.join('0x%04X' % a for a in addrs), ', '.join(str(n) for n in ncols), ', '.join(str(c) for c in costs), key))
    frames[key] = lab; stat['frames'] += 1
    return lab

patch = []                                         # (адрес CPC в странице 0, метка) — слово

# герои: 3 x 4 направления x шаги 0,1,2,1
HEROES = [('knight', 'k', 'knight_height'), ('wizard', 'w', 'wizard_height'), ('serf', 's', 'serf_height')]
const = {}
for l in open(os.path.join(rr.ROOT, 'ref/cpc/utils/constants.asm')):
    m = re.match(r'(\w+)\s+equ\s+(\w+)', l)
    if m:
        try: const[m.group(1)] = int(m.group(2), 0)
        except ValueError: pass
hero_tab = ['hero_frames:']
REDUCE_HEROES = {'serf'}
for name, p, hk in HEROES:
    h = const[hk]
    hg = lambda d, f: gfx('heroes', S['sprite_bank_player_%s%s_%d_0' % (p, d, f)], 5, h)
    mp = reduce_map([hg(d, f) for d in 'dulr' for f in (0, 1, 2)]) if name in REDUCE_HEROES else None
    for d in 'dulr':
        labs = []
        for f in (0, 1, 2, 1):
            labs.append(frame('%s_%s%d' % (name, d, f), hg(d, f), mp))
        hero_tab.append('\tDW ' + ', '.join(labs))
inc += hero_tab

# враги, боссы, рождение/смерть: структура (w, h, alt, fdom, 4 кадра), alt-список (4 кадра)
structs = []
for i in range(16): structs.append(G16(S['sprite_info'] + 2 * i))
structs += [S[n] for n in ('boss_devil', 'boss_dracula', 'boss_frankie', 'boss_hunchback', 'boss_mummy', 'sprite_birth', 'sprite_death')]
lists = set()
for st in sorted(set(structs)):
    w, h = G(st), G(st + 1)
    lists.add((st + 5, w, h))
    alt = G16(st + 2)
    if alt: lists.add((alt, w, h))
# 4 цвета: тыква, летучая мышь, призрак 2, прыгун, боссы (кроме мумии — она и так в 2 плоскостях, и Дракулы)
REDUCE = {S[n] + 5 for n in ('spr_pumpkin', 'spr_large_bat', 'spr_ghost2', 'spr_bouncy',
                             'boss_devil', 'boss_frankie', 'boss_hunchback')} | {S['spr_large_bat_alt']}   # Дракула — полный цвет (26.10)
for lst, w, h in sorted(lists):
    mp = reduce_map([gfx('baddies', G16(lst + 2 * i), w, h) for i in range(4)]) if lst in REDUCE else None
    for i in range(4):
        a = G16(lst + 2 * i)
        patch.append((lst + 2 * i, frame('bad_%04x' % a, gfx('baddies', a, w, h), mp)))
assert len(REDUCE & {l for l, _, _ in lists}) == len(REDUCE), 'не все списки для 4 цветов найдены' 

# оружие: кадр (w, h, offx, offy, gfx, процедура)
for tab in ('sword_data', 'spell_data', 'axe_data'):
    for i in range(8):
        fr = G16(S[tab] + 2 * i)
        w, h, a = G(fr), G(fr + 1), G16(fr + 4)
        patch.append((fr + 4, frame('wpn_%04x' % a, gfx('heroes', a, w, h))))

# --- предметы (ключи, еда, могила): описатели как у mkroom (2 фазы, маска), квазидиск стр. 2
ITEMS = []
def item_desc(key, rows):
    for k, lab in ITEMS:
        if k == key: return lab
    lab = 'it_%d' % len(ITEMS)
    rows_n = len(rows); w = len(rows[0])
    hi = pixsmooth.smooth2x(rows)                       # точки Вектора
    descs = []
    for ph in range(2):
        off = 4 * ph
        ncol = (off + 2 * w + 7) // 8
        masks = []; data = bytearray()
        for c in range(ncol):
            m = 0
            for j in range(8):
                if 0 <= c * 8 + j - off < 2 * w: m |= 0x80 >> j
            masks.append(m)
            for k in range(NPL):
                col = []
                for r in hi:
                    v = 0
                    for j in range(8):
                        x = c * 8 + j - off
                        if 0 <= x < 2 * w and (SLOT[r[x]] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
                    col.append(v)
                if rows_n % 2: col.append(0)
                data += bytes(col)
        p, a = kv2.put(bytes(data))
        descs.append('\tDB 0x%02X\n\tDW 0x%04X\n\tDB %d, %d%s' % (0x10 | (p << 2), a, rows_n, ncol, ''.join(', 0x%02X' % m for m in masks)))
    inc.append('%s:\t; %s\n%s' % (lab, key, '\n'.join(descs)))
    ITEMS.append((key, lab))
    return lab
kv2 = KV([(2, 0xA300, 0x10000)])                  # стр. 2 после контуров комнат (mkroom: 41500 Б)
# ключи и предметы: (ix+1) — графика 4 x 16 в банке комнат
ix = S['collectable_items']
while G(ix) != 0xff and ix < S['collectable_items'] + 8 * 40:
    a = G16(ix + 1)
    patch.append((ix + 1, item_desc('col_%04x' % a, gfx('rooms', a, 4, 16))))
    ix += 8
# еда: food_table -> графика 4 байта; высота — из food_items (ix+7) по типу
food_h = {}
fi = S['food_items']
for i in range((S['food_items_end'] - fi) // 8):
    t, hgt = heroes[fi - 0x4000 + 8 * i], heroes[fi - 0x4000 + 8 * i + 7]
    food_h[t] = hgt
for t in range(10):
    a = G16(S['food_table'] + 2 * t)
    hgt = food_h.get(0x50 + t)
    if not hgt: continue
    patch.append((S['food_table'] + 2 * t, item_desc('food_%d' % t, gfx('rooms', a, 4, hgt))))

# --- карта фона комнат: оба состояния дверей
BGF_ADDR = 0xC000
bgf = bytearray()
rooms_bank = bytearray(rooms)
for n in range(143):
    grid = [[0] * 24 for _ in range(24)]
    for force in (0x00, 0x80):
        b = bytearray(rooms_bank)
        for ix in range(S['room_bank_item_list'], S['room_bank_items_per_room'], 8):
            b[ix - 0x4000 + 2] = (b[ix - 0x4000 + 2] & 0x7f) | force
        rr.use_rooms_bank(bytes(b))
        px = rr.render(n)
        for c in range(24):
            for y in range(192):
                if any(px[y][c * 4 + j] for j in range(4)): grid[c][y >> 3] = 1
    for c in range(24):
        v = sum(grid[c][g] << g for g in range(24))
        bgf += bytes((v & 255, (v >> 8) & 255, v >> 16))
rr.use_rooms_bank(bytes(rooms_bank))
assert BGF_ADDR + len(bgf) <= 0x10000 and 0xA300 + len(kv2.data[2]) <= BGF_ADDR
inc.append('BGF_ADDR\tequ 0x%04X' % BGF_ADDR)

# --- панель: неподвижная часть (снимок CPC в начале игры, tools/cpcpanel.js), шрифт, курица
pan = open(os.path.join(rr.ROOT, 'build/game/panel_cpc.bin'), 'rb').read()[:0x4000]
cbyte = lambda x, y: pan[(y >> 3) * 64 + (y & 7) * 0x800 + x]
items = open(os.path.join(B, 'items.bin'), 'rb').read()
def vec_cols(pixrow_fn, ncols, rows):
    """(столбец, плоскость) -> байты строк сверху вниз; pixrow_fn(y) -> перья (2 * 4 * ncols точек / 2)"""
    out = {}
    for c in range(ncols):
        for k in range(NPL):
            col = bytearray()
            for y in range(rows):
                pens = pixrow_fn(y)
                v = 0
                for j in range(8):
                    if (SLOT[pens[(c * 8 + j) // 2]] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
                col.append(v)
            out[(c, k)] = col
    return out
def cpc_row_pens(src, x0, nbytes):
    return lambda y: [p for i in range(nbytes) for p in mode0(src(x0 + i, y))]
PANEL_ADDR = (BGF_ADDR + len(bgf) + 15) & ~15
pc = vec_cols(cpc_row_pens(cbyte, 48, 16), 8, 192)
panel_blob = bytearray()
for k in range(NPL):
    for c in range(8): panel_blob += pc[(c, k)]
CHICK_ADDR = PANEL_ADDR + len(panel_blob)
chick = bytearray()
for base in (S['chicken_full'], S['chicken_empty']):
    for a in range(30):
        row = [p for i in range(12) for p in mode0(items[base - 0x4000 + a * 12 + i])]
        cc = vec_cols(lambda y: row, 6, 1)
        for k in range(NPL):
            for c in range(6): chick += cc[(c, k)]
assert CHICK_ADDR + len(chick) <= 0x10000
glyph = ['glyphs:\t; цифры 0..9 и «:» (шрифт CPC банка предметов 0x647C), на символ 3 плоскости x 8 строк']
for ch in range(11):
    g = S['font_0'] - 0x4000 + 16 * ch
    rows = [[p for i in range(2) for p in mode0(items[g + 2 * y + i])] for y in range(8)]
    gc = vec_cols(lambda y: rows[y], 1, 8)
    glyph.append('\tDB ' + ', '.join('0x%02X' % b for k in range(NPL) for b in gc[(0, k)]))
inc += glyph
inc.append('PANEL_ADDR\tequ 0x%04X\nCHICK_ADDR\tequ 0x%04X' % (PANEL_ADDR, CHICK_ADDR))
# шрифт экрана итогов (font_data_mode0 CPC, банк комнат): символы ' '..'Z', для масок цвета 0x03 и 0xF3
# (show_text: AND с маской) — 3 плоскости x 8 строк на символ, стр. 0 после жизней (раздел меню)
fnt = bytearray()
for mask in (0x03, 0xF3):
    for ch in range((S['font_data_mode1'] - S['font_data_mode0']) // 16):
        g = S['font_data_mode0'] - 0x4000 + 16 * ch
        rows = [[p for i in range(2) for p in mode0(rooms[g + 2 * y + i] & mask)] for y in range(8)]
        gc = vec_cols(lambda y: rows[y], 1, 8)
        for k in range(NPL): fnt += gc[(0, k)]
open(os.path.join(OUT, 'panel_kv.bin'), 'wb').write(bytes(panel_blob) + bytes(chick))

# --- меню: снимок CPC (tools/cpcmenu.js), экран 256 x 192 в трёх полосах: строки 0..MENU_B0-1 — режим 1
# (чёрный, ярко-красный, розовый, белый), MENU_B0..MENU_B1-1 — режим 0 с палитрой игры (герои — спрайтами,
# на снимке стираются; указатель остаётся), дальше — режим 1 (чёрный, ярко-красный, ярко-зелёный, белый).
# Палитра меню — как в игре, но слот тёмно-красного — ярко-красный; розовый -> оранжевый, зелёный -> голубой.
MENU_B0, MENU_B1 = 116, 164
HERO_Y0, HERO_Y1 = 0x7a, 0x7a + 21                  # character_select_y, max_player_height
men = open(os.path.join(rr.ROOT, 'build/game/menu_cpc.bin'), 'rb').read()[:0x4000]
mbyte = lambda x, y: men[(y >> 3) * 64 + (y & 7) * 0x800 + x]
LOGO1 = [0, 9, 10, 13]                              # перья игры для 4 цветов режима 1 (розовый -> оранжевый)
LOGO2 = [0, 9, 4, 13]                               # зелёный -> голубой (перо 4)
def menu_pens(y):
    if MENU_B0 <= y < MENU_B1:
        if HERO_Y0 <= y < HERO_Y1: return [0] * 128 * 2
        return [p for x in range(64) for p in mode0(mbyte(x, y)) for _ in (0, 1)]
    lp = LOGO1 if y < MENU_B0 else LOGO2
    out = []
    for x in range(64):
        b = mbyte(x, y)
        for i in range(4): out.append(lp[((b >> (7 - i)) & 1) | ((b >> (3 - i)) & 1) << 1])
    return out
menu_blob = bytearray()
mrows = [menu_pens(y) for y in range(192)]
for k in range(NPL):
    for c in range(32):
        for y in range(192):
            v = 0
            for j in range(8):
                if (SLOT[mrows[y][c * 8 + j]] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
            menu_blob.append(v)
MENU_ADDR = 0x0000                                  # квазидиск стр. 0 (с 0xA000 — плеер звука akg80, tools/mkakg.py)
assert not kv.data[0], 'спрайты вышли в стр. 0 — там звук (0x0000..) и меню (0x8000..)'
# жизни на панели — фигурки выбранного героя: строки LIVES_Y0..+LIVES_N столбцов 24..31 для рыцаря, мага,
# серва (снимки tools/cpcpanel.js), после фона меню; panel_init накладывает по hero
LIVES_Y0, LIVES_N = 120, 28
LIVES_ADDR = MENU_ADDR + len(menu_blob)
for name in ('', '_1', '_2'):
    ph = open(os.path.join(rr.ROOT, 'build/game/panel_cpc%s.bin' % name), 'rb').read()[:0x4000]
    hb = lambda x, y, ph=ph: ph[(y >> 3) * 64 + (y & 7) * 0x800 + x]
    lc = vec_cols(lambda y: [p for i in range(16) for p in mode0(hb(48 + i, LIVES_Y0 + y))], 8, LIVES_N)
    for k in range(NPL):
        for c in range(8): menu_blob += lc[(c, k)]
FONT_ADDR = MENU_ADDR + len(menu_blob)
menu_blob += fnt
assert FONT_ADDR + len(fnt) <= 0xA000
inc.append('FONT_ADDR\tequ 0x%04X\nFONT_N\tequ %d' % (FONT_ADDR, (S['font_data_mode1'] - S['font_data_mode0']) // 16))
inc.append('LIVES_ADDR\tequ 0x%04X\nLIVES_Y0\tequ %d\nLIVES_N\tequ %d' % (LIVES_ADDR, LIVES_Y0, LIVES_N))
open(os.path.join(OUT, 'menu_kv.bin'), 'wb').write(bytes(menu_blob))
from cpcpal import vecbyte
from mkroom_slots import PERM
mpal = [vecbyte(9 if PAL8[PERM[i >> 1]] == 7 else PAL8[PERM[i >> 1]]) for i in range(16)]
inc.append('MENU_ADDR\tequ 0x%04X\npal_menu:\tDB %s' % (MENU_ADDR, ', '.join('0x%02X' % v for v in mpal)))
os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, 'bgf_rooms.bin'), 'wb').write(bgf)
for p, d in list(kv.data.items()) + [(2, kv2.data[2])]:
    if d: open(os.path.join(OUT, 'kv%d_%s.bin' % (p, 'spr' if (p, d) in kv.data.items() else 'items')), 'wb').write(d)
open(os.path.join(OUT, 'sprites.inc'), 'w').write('\n'.join(inc) + '\n')
json.dump({'patch': patch, 'kv_sprites': {str(p): [lo, len(kv.data[p])] for p, lo, hi in kv.pages},
           'kv_items': [0xA300, len(kv2.data[2])]}, open(os.path.join(OUT, 'patch.json'), 'w'))
print('кадров %d, поток %d Б (стр. 3: %d, стр. 0: %d), предметов %d (%d Б, стр. 2), правок %d'
      % (stat['frames'], stat['bytes'], len(kv.data[3]), len(kv.data[0]), len(ITEMS), len(kv2.data[2]), len(patch)))
