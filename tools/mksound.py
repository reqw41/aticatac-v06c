#!/usr/bin/env python3
"""Звук для Вектора из записей регистров AY с модели CPC (tools/cpcsound.js -> build/sound/sound.json).

Частота AY: CPC — 1 МГц, Вектор — 1,75 МГц: периоды тона (R0..R5), шума (R6) и огибающей (R11, R12) x 1,75.
Поток на кадр: маска m0 (биты 0..6 — регистры 0..6, бит 7 — есть m1), m1 (биты 0..6 — регистры 7..13),
значения по порядку. R7 — без битов портов (& 0x3F). R13 — при смене или записи, когда огибающая
слышна (бит 4 громкости). Конец потока: m0 = 0x80, m1 = 0x80, слово — адрес кадра повтора (0 — тишина).
Кадр повтора мелодии записан полным состоянием. Всё — квазидиск стр. 0 с SND_ADDR (0x0010; адрес 0 — признак тишины).
  python3 tools/mksound.py build/game   -> snd_kv.bin, snd.inc (snd_tab: адреса потоков)
"""
import json, os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT = sys.argv[1]
d = json.load(open(os.path.join(ROOT, 'build/sound/sound.json')))
SND_ADDR = 0x0010                                   # 0 — признак тишины в проигрывателе
K = 1.75

def scale_state(st):
    s = list(st)
    for lo in (0, 2, 4):
        p = min(4095, round((s[lo] | (s[lo + 1] & 15) << 8) * K))
        s[lo], s[lo + 1] = p & 255, p >> 8
    s[6] = min(31, round((s[6] & 31) * K))
    e = min(65535, round((s[11] | s[12] << 8) * K))
    s[11], s[12] = e & 255, e >> 8
    s[7] &= 0x3F
    return s

def encode(frames, loop):
    """кадры (изменения CPC) -> байты потока; loop — номер кадра повтора или -1"""
    cpc = [0] * 14
    prev = [None] * 14
    out = bytearray(); loop_off = None
    for i, fr in enumerate(frames):
        r13w = False
        for r, v in fr:
            cpc[r] = v
            if r == 13: r13w = True
        st = scale_state(cpc)
        env = any(st[r] & 16 for r in (8, 9, 10))
        full = i == 0 or i == loop
        regs = [r for r in range(14) if full or (st[r] != prev[r] if r != 13 else (st[13] != prev[13] or (r13w and env)))]
        if i == loop: loop_off = len(out)
        m0 = sum(1 << r for r in regs if r < 7); m1 = sum(1 << (r - 7) for r in regs if r >= 7)
        if m1: out += bytes((m0 | 0x80, m1))
        else: out += bytes((m0,))
        out += bytes(st[r] for r in regs)
        for r in regs: prev[r] = st[r]
    return out, loop_off

blob = bytearray(); tab = []
names = ['menu', 'start', 'over', 'done'] + ['sfx%d' % (i + 1) for i in range(len(d['sfx']))]
streams = [(d['tunes'][n]['frames'], d['tunes'][n]['loop']) for n in names[:4]] + [(s['frames'], -1) for s in d['sfx']]
for name, (frames, loop) in zip(names, streams):
    base = SND_ADDR + len(blob)
    data, loop_off = encode(frames, loop)
    blob += data
    la = base + loop_off if loop_off is not None else 0
    blob += bytes((0x80, 0x80, la & 255, la >> 8))
    tab.append((name, base))
    print('%-6s кадров %5d, байт %5d%s' % (name, len(frames), len(data) + 4, ', повтор с %d' % loop if loop >= 0 else ''))
blob += bytes(18)                                    # запас: чтение кадра словами за концом
assert SND_ADDR + len(blob) <= 0x8000, len(blob)
assert SND_ADDR > 0
open(os.path.join(OUT, 'snd_kv.bin'), 'wb').write(bytes(blob))
with open(os.path.join(OUT, 'snd.inc'), 'w') as f:
    f.write('; сгенерировано tools/mksound.py: потоки звука в квазидиске стр. 0\n')
    f.write('snd_tab:\tDW %s\n' % ', '.join('0x%04X' % a for _, a in tab))
    for i, (n, _) in enumerate(tab): f.write('SND_%s\tequ %d\n' % (n.upper(), i))
print('звук: %d Б' % len(blob))
