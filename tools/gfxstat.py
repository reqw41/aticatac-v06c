#!/usr/bin/env python3
"""Статистика CPC-графики Atic Atac: байты и число цветов (Mode 0, 2 px/байт) по меткам."""
import re, sys, collections
def px(b):  # Mode 0: пиксель 0 — биты 7,3,5,1 ; пиксель 1 — биты 6,2,4,0
    p0 = ((b>>7)&1) | ((b>>3)&1)<<1 | ((b>>5)&1)<<2 | ((b>>1)&1)<<3
    p1 = ((b>>6)&1) | ((b>>2)&1)<<1 | ((b>>4)&1)<<2 | ((b>>0)&1)<<3
    return p0, p1
for fn in sys.argv[1:]:
    cur = None; spr = collections.OrderedDict()
    for line in open(fn):
        s = line.split(';')[0]
        m = re.match(r"^\s*([A-Za-z_]\w*)\s*$", s)
        if m: cur = m.group(1); spr[cur] = []; continue
        m = re.match(r'\s*(defb|db)\s+(.*)', s, re.I)
        if m and cur:
            for t in m.group(2).split(','):
                t = t.strip()
                if not t: continue
                v = int(t[2:], 16) if t.lower().startswith('0x') else int(t[1:], 16) if t.startswith(('#','&','$')) else int(t, 0) if t[0].isdigit() else None
                if v is not None: spr[cur].append(v & 255)
    tot = sum(len(v) for v in spr.values()); allc = collections.Counter(); hist = collections.Counter()
    for k, v in spr.items():
        c = set()
        for b in v: c.update(px(b))
        c.discard(0); allc.update(c); hist[len(c)] += 1
    print(f'{fn}: меток {len(spr)}, байт {tot}, цвета {dict(sorted(allc.items()))}, гист. «цветов на метку» {dict(sorted(hist.items()))}')
