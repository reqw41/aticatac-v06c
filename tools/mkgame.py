#!/usr/bin/env python3
"""Графика игры для Вектора (этап 3, docs/LOGIC_PLAN.md): спрайты героев, врагов, боссов, оружия — поток для
квазидиска; ключи, еда, могила — описатели предметов (как в tools/mkroom.py); правки образа страницы 0 CPC.

Спрайт (XOR, 3 плоскости, 4 фазы = x & 3 пикселя CPC): в ОЗУ — запись кадра
    DB высота (чётная), сдвиг сверху, порт квазидиска (0x10 | стр << 2); DW адреса фаз 0..3
в квазидиске на фазу — поток слов для POP: блок = (смещение, 0) и высота байт (строки сверху вниз);
конец = (0xFF, 2). Смещение = столбец + 0x20 * плоскость; пустые блоки не хранятся.

Указатели на графику, которые читает только вывод, переписываются в образе страницы 0 указателями на записи:
списки кадров врагов и боссов (struct + 5.., alt-списки), кадры оружия (+4), таблица еды, ключи (+1).
Таблицы кадров героев — свои (hero_frames: 3 героя x 4 направления x 4 шага).

  python3 tools/mkgame.py build/game        -> sprites.inc (записи, таблицы), patch.json, kv*.bin
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
import roomref as rr
from cpcpal import mode0
from mkroom_slots import SLOT, ROW0

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

def sprite_streams(rows):
    """перья -> (yoff, h, [поток фазы 0..3])"""
    pens = [[SLOT[p] for p in r] for r in rows]
    y0 = next((i for i, r in enumerate(pens) if any(r)), 0)
    y1 = max((i for i, r in enumerate(pens) if any(r)), default=0) + 1
    pens = pens[y0:y1]
    if len(pens) % 2: pens.append([0] * len(pens[0]))
    w = len(pens[0])
    out = []
    for ph in range(4):
        ncol = (2 * (w + ph) + 7) // 8
        data, zero = [], []
        for c in range(ncol):
            for k in range(NPL):
                col = []
                for r in pens:
                    v = 0
                    for j in range(8):
                        x = (c * 8 + j) // 2 - ph
                        if 0 <= x < w and (r[x] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
                    col.append(v)
                if any(col): data.append((c + 0x20 * k, col))
                else: zero.append(c + 0x20 * k)
        s = bytearray()
        for off, col in data: s += bytes((off, 0)) + bytes(col)
        s += bytes((0xff, 2))
        out.append(bytes(s))
    return y0, len(pens), out

kv = KV([(3, 0x0000, 0x10000), (0, 0x0000, 0x8000)])
frames = {}                                        # ключ -> метка записи
inc = ['; сгенерировано tools/mkgame.py']
stat = dict(frames=0, bytes=0)

def frame(key, rows):
    if key in frames: return frames[key]
    y0, h, streams = sprite_streams(rows)
    addrs = []; page = None
    for s in streams:
        p, a = kv.put(s)
        if page is None: page = p
        elif p != page:                            # фазы кадра — в одной странице
            p, a = kv.put(s); page = p
        addrs.append(a); stat['bytes'] += len(s)
    lab = 'fr_%d' % len(frames)
    inc.append('%s:\tDB %d, %d, 0x%02X\n\tDW %s\t; %s' % (lab, h, y0, 0x10 | (page << 2), ', '.join('0x%04X' % a for a in addrs), key))
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
for name, p, hk in HEROES:
    h = const[hk]
    for d in 'dulr':
        labs = []
        for f in (0, 1, 2, 1):
            a = S['sprite_bank_player_%s%s_%d_0' % (p, d, f)]
            labs.append(frame('%s_%s%d' % (name, d, f), gfx('heroes', a, 5, h)))
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
for lst, w, h in sorted(lists):
    for i in range(4):
        a = G16(lst + 2 * i)
        patch.append((lst + 2 * i, frame('bad_%04x' % a, gfx('baddies', a, w, h))))

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
                for r in rows:
                    v = 0
                    for j in range(8):
                        x = c * 8 + j - off
                        if 0 <= x < 2 * w and (SLOT[r[x // 2]] >> (NPL - 1 - k)) & 1: v |= 0x80 >> j
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

os.makedirs(OUT, exist_ok=True)
for p, d in list(kv.data.items()) + [(2, kv2.data[2])]:
    if d: open(os.path.join(OUT, 'kv%d_%s.bin' % (p, 'spr' if (p, d) in kv.data.items() else 'items')), 'wb').write(d)
open(os.path.join(OUT, 'sprites.inc'), 'w').write('\n'.join(inc) + '\n')
json.dump({'patch': patch, 'kv_sprites': {str(p): [lo, len(kv.data[p])] for p, lo, hi in kv.pages},
           'kv_items': [0xA300, len(kv2.data[2])]}, open(os.path.join(OUT, 'patch.json'), 'w'))
print('кадров %d, поток %d Б (стр. 3: %d, стр. 0: %d), предметов %d (%d Б, стр. 2), правок %d'
      % (stat['frames'], stat['bytes'], len(kv.data[3]), len(kv.data[0]), len(ITEMS), len(kv2.data[2]), len(patch)))
