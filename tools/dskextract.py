#!/usr/bin/env python3
"""Извлечение файлов из образа CPC (EXTENDED/MV - CPC DSK, формат DATA, сектора C1..C9)."""
import sys, struct, os
img = open(sys.argv[1], 'rb').read(); out = sys.argv[2]
ext = img.startswith(b'EXTENDED')
ntr, nsd = img[0x30], img[0x31]
tsizes = [img[0x34+i]*256 for i in range(ntr*nsd)] if ext else [struct.unpack_from('<H', img, 0x32)[0]]*(ntr*nsd)
sec = {}
off = 0x100
for t in range(ntr*nsd):
    if tsizes[t] == 0: continue
    ti = img[off:off+tsizes[t]]; assert ti.startswith(b'Track-Info'), (t, ti[:12])
    n = ti[0x15]; p = 0x100
    for s in range(n):
        tr, sd, sid, sz, st1, st2, alen = struct.unpack_from('<BBBBBBH', ti, 0x18+8*s)
        ln = alen if ext else 128 << sz
        sec[(tr, sid)] = ti[p:p+ln]; p += ln
    off += tsizes[t]
def block(b):  # блок 1 КБ = 2 сектора, данные с дорожки 0
    r = b''
    for k in range(2):
        ls = b*2+k; tr, s = divmod(ls, 9); r += sec[(tr, 0xC1+s)]
    return r
d = b''.join(sec[(0, 0xC1+i)] for i in range(4))
files = {}
for i in range(64):
    e = d[i*32:(i+1)*32]
    if e[0] == 0xE5: continue
    name = (e[1:9].decode('latin1').rstrip() + '.' + bytes(c & 0x7f for c in e[9:12]).decode().rstrip()).lower()
    files.setdefault(name, []).append((e[12], e[15], [x for x in e[16:32] if x]))
os.makedirs(out, exist_ok=True)
for name, exts in files.items():
    data = b''
    for ex, rc, bl in sorted(exts):
        data += b''.join(block(x) for x in bl)[:rc*128]
    h = data[:128]
    if sum(h[:67]) & 0xffff == struct.unpack_from('<H', h, 67)[0]:
        load, ln, ent = struct.unpack_from('<H', h, 21)[0], struct.unpack_from('<H', h, 64)[0] | (h[66] << 16), struct.unpack_from('<H', h, 26)[0]
        data = data[128:128+ln]; info = f'load={load:04x} len={ln} entry={ent:04x}'
    else: info = f'raw len={len(data)}'
    open(os.path.join(out, name), 'wb').write(data); print(f'{name:14s} {info}')
