#!/usr/bin/env python3
"""Профиль трассы MAME (CPC) по процедурам: приблизительные мкс (NOP-циклы CPC) по мнемонике.
  python3 tools/cpcprof.py trace.txt rasmoutput.sym <кадров>"""
import re, sys, bisect, collections
tr, symf, nfr = sys.argv[1], sys.argv[2], int(sys.argv[3])
syms = []
for l in open(symf):
    m = re.match(r'(\S+)\s+#([0-9A-F]+)\s+B(\d+)', l)
    if m and not m.group(1).startswith(('@', '.')): syms.append((int(m.group(2), 16), m.group(1)))
syms.sort(); addrs = [a for a, _ in syms]
def us(ins):
    op = ins.split()[0]; a = ins[len(op):].strip().lower()
    ix = '(ix' in a or '(iy' in a or a.startswith(('ix', 'iy')) or ',ix' in a or ',iy' in a
    if op in ('ldir', 'lddr'): return 6
    if op == 'call': return 5
    if op == 'ret': return 3 if not a else 3
    if op in ('push',): return 5 if ix else 4
    if op == 'pop': return 4 if ix else 3
    if op in ('jp',): return 1 if a == '(hl)' else 3
    if op == 'jr': return 3
    if op == 'djnz': return 4
    if op in ('out', 'in'): return 4
    if op == 'ex': return 6 if '(sp)' in a else 1
    if op in ('rst',): return 4
    if ix: return 6 if re.search(r'\),\$', a) or op in ('inc', 'dec', 'set', 'res', 'rl', 'rr', 'sla', 'srl') else 5
    if op == 'ld':
        if re.match(r'(a|hl|bc|de|sp),\(\$', a): return 5 if a[0] != 'a' else 4
        if re.match(r'\(\$[0-9a-f]+\),', a): return 5 if not a.endswith(',a') else 4
        if re.match(r'(bc|de|hl|sp),\$', a): return 3
        if a.startswith('sp,'): return 2
        if '(hl)' in a or '(de)' in a or '(bc)' in a: return 3 if re.search(r'\(hl\),\$', a) else 2
        if ',$' in a: return 2
        return 1
    if op in ('inc', 'dec'):
        if a in ('bc', 'de', 'hl', 'sp'): return 2
        return 3 if a == '(hl)' else 1
    if op == 'add' and a.startswith(('hl', 'ix', 'iy')): return 3 if a.startswith('hl') else 4
    if op in ('adc', 'sbc') and a.startswith('hl'): return 4
    if op in ('srl', 'sla', 'sra', 'rl', 'rr', 'rlc', 'rrc', 'bit', 'set', 'res'):
        return (4 if op in ('set', 'res', 'srl', 'sla', 'rl', 'rr') else 3) if '(hl)' in a else 2
    if '(hl)' in a or ',$' in a or re.match(r'^\$', a): return 2
    if op in ('neg', 'im', 'ei', 'di', 'halt', 'nop', 'cpl', 'scf', 'ccf', 'rlca', 'rrca', 'rla', 'rra', 'exx'):
        return 2 if op in ('neg', 'im') else 1
    return 1
cnt = collections.Counter(); tot = 0
for l in open(tr):
    m = re.match(r'([0-9A-F]{4}): (.*)', l)
    if not m: continue
    pc = int(m.group(1), 16); i = bisect.bisect_right(addrs, pc) - 1
    name = syms[i][1] if i >= 0 else '?'
    c = us(m.group(2)); cnt[name] += c; tot += c
print('всего %.0f мкс за %d кадров = %.0f мкс/кадр (из 20000)' % (tot, nfr, tot / nfr))
for n, c in cnt.most_common(30): print('%7.0f мкс/кадр %5.1f%%  %s' % (c / nfr, 100 * c / tot, n))
