#!/usr/bin/env python3
"""Символы CPC для ассемблера логики i8080 (src/i8080): метки (адреса CPC) — с приставкой C_ (C_player_x),
константы (equ) — как есть. Из build/cpcsrc/rasmoutput.sym -> build/l80/cpcsym.inc."""
import os, re
ROOT = os.path.join(os.path.dirname(__file__), '..')
out = ['; сгенерировано tools/mk80sym.py из build/cpcsrc/rasmoutput.sym']
seen = set()
for l in open(os.path.join(ROOT, 'build/cpcsrc/rasmoutput.sym')):
    m = re.match(r'(\w+) #([0-9A-F]+) \S+ (\w)', l)
    if not m: continue
    name, val, kind = m.group(1).lower(), int(m.group(2), 16), m.group(3)
    n = ('C_' + name) if kind == 'L' else name
    if n in seen: continue
    seen.add(n)
    out.append('%s\tequ 0x%04X' % (n, val))
os.makedirs(os.path.join(ROOT, 'build/l80'), exist_ok=True)
open(os.path.join(ROOT, 'build/l80/cpcsym.inc'), 'w').write('\n'.join(out) + '\n')
print(len(seen), 'символов')
