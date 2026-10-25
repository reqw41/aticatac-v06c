#!/usr/bin/env python3
"""Самостоятельный образ демо комнат (proto/room.asm -DDEMO): графика квазидиска и банк комнат сжаты ZX0
(классический формат, tools/zx0 -c; распаковщик proto/dzx0.asm) и лежат в образе. При старте куски по 8 КБ
распаковываются в буфер 0x8000..0x9FFF (палитра чёрная) и PUSH-ем переносятся в квазидиск; банк комнат —
последним, на своё место 0x4000 (его сжатая копия лежит выше 0xA000).

Области под сжатое: B = DATA_LO..0x7FFF, A = 0xA000..0xFFFF. Куски квазидиска — сначала в B, потом в A;
банк комнат — только в A.
  python3 tools/mkroomdemo.py build/room        (после mkroom.py)
"""
import os, subprocess, sys
OUT = sys.argv[1]
ZX0 = os.path.join(os.path.dirname(__file__), 'zx0')
DATA_LO = 0x1000
CH = 0x2000

def pack(raw, name):
    src = os.path.join(OUT, name + '.raw'); dst = os.path.join(OUT, name + '.zx0')
    open(src, 'wb').write(raw)
    subprocess.run([ZX0, '-f', '-c', src, dst], check=True, stdout=subprocess.DEVNULL)
    return open(dst, 'rb').read()

regions = [[DATA_LO, 0x8000], [0xA000, 0x10000]]   # [следующий свободный, конец]
def place(blob, only_a=False):
    for r in (regions[1:] if only_a else regions):
        if r[0] + len(blob) <= r[1]:
            a = r[0]; r[0] += len(blob); return a
    raise SystemExit('не влезло: %d Б' % len(blob))

entries = []; blobs = []; raw_tot = z_tot = 0
rooms = open(os.path.join(OUT, 'rooms.bin'), 'rb').read()
rz = pack(rooms, 'z_rooms')
ra = place(rz, only_a=True)                        # банк комнат — первым в A (распакуется последним)
blobs.append((ra, 'z_rooms.zx0'))
for p in (1, 2, 3):
    f = os.path.join(OUT, 'items%d.bin' % p)
    if not os.path.exists(f): continue
    d = open(f, 'rb').read()
    if len(d) % 2: d += b'\0'
    for o in range(0, len(d), CH):
        raw = d[o:o + CH]
        z = pack(raw, 'z_p%d_%d' % (p, o // CH))
        a = place(z)
        blobs.append((a, 'z_p%d_%d.zx0' % (p, o // CH)))
        entries.append((a, 0x10 | (p << 2), (o + len(raw)) & 0xFFFF, len(raw)))
        raw_tot += len(raw); z_tot += len(z)
open(os.path.join(OUT, 'demo_const.inc'), 'w').write(
    '; сгенерировано tools/mkroomdemo.py\nDATA_LO\tequ 0x%04X\nROOMS_Z\tequ 0x%04X\n' % (DATA_LO, ra))
lines = ['; сгенерировано tools/mkroomdemo.py', 'kv_chunks:']
for a, pg, end, n in entries:
    lines.append('\tDW 0x%04X\n\tDB 0x%02X\n\tDW 0x%04X, %d' % (a, pg, end, n))
lines.append('\tDW 0')
open(os.path.join(OUT, 'demo.inc'), 'w').write('\n'.join(lines) + '\n')
open(os.path.join(OUT, 'demo_blobs.inc'), 'w').write(
    '\n'.join('\t\t\t\tORG\t0x%04X\n\t\t\t\tINCBIN\t"../build/room/%s"' % (a, n) for a, n in blobs) + '\n')
print('квазидиск %d Б -> %d Б (%d кусков), банк комнат %d -> %d Б; свободно B %d Б, A %d Б'
      % (raw_tot, z_tot, len(entries), len(rooms), len(rz), regions[0][1] - regions[0][0], regions[1][1] - regions[1][0]))
