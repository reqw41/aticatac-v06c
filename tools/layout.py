#!/usr/bin/env python3
"""Раскладка игры по памяти Вектора: куски (модули .asm и блоки данных .inc) — по свободным участкам.

Свободно: «дыры» страницы 0 CPC (tools/holes.js -> build/l80/holes.json: исполнявшийся код Z80, к которому
логика не обращается как к данным), 0x0004..0x00FF, 0x3B18..0x3EFF (после еды, до стека), хвост банка
комнат 0x7C78..0x7FFF, скрытая 4-я плоскость 0xE000..0xFFFF.
Данные .inc режутся на блоки по меткам (описатель фазы 1 предмета iv_*_1 идёт сразу за фазой 0).
Проход 1 (измерение): куски подряд с 0x0000 -> размеры; раскладка — крупные первыми в первый подходящий
участок; проход 2 — build/game/layout.inc (ORG + INCLUDE + ASSERT).
  python3 tools/layout.py
"""
import json, os, re, subprocess, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
B = os.path.join(ROOT, 'build/game')
SJ = os.path.join(ROOT, 'tools/sjasmplus')
CODE = ['src/vec/main.asm', 'src/vec/spr.asm', 'src/vec/roomdraw.asm', 'src/vec/sound_game.asm'] + \
    ['src/i8080/%s.asm' % m for m in ('playermove', 'util', 'weapon', 'sprite', 'boss', 'doors', 'items', 'room',
                                       'food', 'chicken', 'player', 'collectables', 'clock', 'state', 'game')]
DATA = ['build/room/items.inc', 'build/game/sprites.inc', 'build/room/pal.inc', 'build/l80/item_wh.inc']

def split_inc(path, tag):
    """блоки по меткам в первой колонке; *_1 приклеивается к предыдущему; строки equ/DEFINE — в отдельный кусок"""
    head, blocks, cur = [], [], None
    for l in open(os.path.join(ROOT, path)):
        if re.match(r'^\s*(\w+\s+equ\b|DEFINE\b)', l, re.I) or (re.match(r'^\w+\s+equ', l)):
            head.append(l); continue
        m = re.match(r'^(\w+):', l)
        if m and not m.group(1).endswith('_1'):
            cur = [l]; blocks.append(cur)
        elif cur is not None: cur.append(l)
        else: head.append(l)
    files = []
    os.makedirs(os.path.join(B, 'chunks'), exist_ok=True)
    if head:
        hp = os.path.join(B, 'chunks', tag + '_head.inc'); open(hp, 'w').write(''.join(head))
    else: hp = None
    # блоки сливаются в куски до ~400 Б по оценке (строк), чтобы кусков было не слишком много
    group, n = [], 0
    def flush():
        nonlocal group
        if group:
            p = os.path.join(B, 'chunks', '%s_%d.inc' % (tag, len(files)))
            open(p, 'w').write(''.join(''.join(b) for b in group)); files.append(p); group = []
    for b in blocks:
        group.append(b)
        if sum(len(x) for x in group) > 40: flush()
    flush()
    return hp, files

heads, chunks = [], []
for p in CODE: chunks.append(os.path.join(ROOT, p))
for i, p in enumerate(DATA):
    h, fs = split_inc(p, 'd%d' % i)
    if h: heads.append(h)
    chunks += fs

PRE = ['\t\t\t\tDEVICE\tNOSLOT64K',
       '\t\t\t\tINCLUDE\t"%s"' % os.path.join(ROOT, 'build/l80/cpcsym.inc'),
       '\t\t\t\tINCLUDE\t"%s"' % os.path.join(ROOT, 'src/i8080/defs.asm'),
       '\t\t\t\tINCLUDE\t"%s"' % os.path.join(ROOT, 'build/room/room.inc')] + ['\t\t\t\tINCLUDE\t"%s"' % h for h in heads]

# проход 1: измерение
m = PRE + ['\t\t\t\tORG\t0x0000']
for i, c in enumerate(chunks):
    m += ['ck%d_s:' % i, '\t\t\t\tINCLUDE\t"%s"' % c, 'ck%d_e:' % i]
open(os.path.join(B, 'measure.asm'), 'w').write('\n'.join(m) + '\n')
r = subprocess.run([SJ, '--nologo', '--i8080', 'measure.asm', '--sym=measure.sym'], cwd=B, capture_output=True, text=True)
if 'Errors: 0' not in r.stdout + r.stderr:
    print(r.stdout[-3000:], r.stderr[-3000:]); sys.exit(1)
sym = {}
for l in open(os.path.join(B, 'measure.sym')):
    mm = re.match(r'^(\w+):\s+EQU\s+0x([0-9A-F]+)', l, re.I)
    if mm: sym[mm.group(1)] = int(mm.group(2), 16)
sizes = [sym['ck%d_e' % i] - sym['ck%d_s' % i] for i in range(len(chunks))]

holes = json.load(open(os.path.join(ROOT, 'build/l80/holes.json')))['holes']
regions = [[a, b] for a, b in holes] + [[0x0004, 0x0100], [0x3B18, 0x3F00], [0x7C78, 0x8000], [0xE000, 0x10000]]
place = {}
for i in sorted(range(len(chunks)), key=lambda i: -sizes[i]):
    for r in sorted(regions, key=lambda r: r[1] - r[0]):        # самый тесный подходящий
        if r[1] - r[0] >= sizes[i]:
            place[i] = (r[0], r[1]); r[0] += sizes[i]; break
    else:
        sys.exit('не помещается кусок %s (%d Б)' % (chunks[i], sizes[i]))
out = []
for i in sorted(place, key=lambda i: place[i][0]):
    a, end = place[i]
    out += ['\t\t\t\tORG\t0x%04X' % a, '\t\t\t\tINCLUDE\t"%s"' % chunks[i], '\t\t\t\tASSERT\t$ <= 0x%04X' % end]
json.dump([[place[i][0], place[i][0] + sizes[i], os.path.basename(chunks[i])] for i in place],
          open(os.path.join(B, 'ranges.json'), 'w'))
open(os.path.join(B, 'layout.inc'), 'w').write('\n'.join(['; сгенерировано tools/layout.py'] + ['\t\t\t\tINCLUDE\t"%s"' % h for h in heads] + out) + '\n')
free = sum(r[1] - r[0] for r in regions)
print('кусков %d, код+данные %d Б, свободно осталось %d Б (крупнейший участок %d)' % (
    len(chunks), sum(sizes), free, max(r[1] - r[0] for r in regions)))
