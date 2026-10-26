#!/usr/bin/env python3
"""Дискета МикроДОС с игрой (по образцу порта Ianna: ~/projects/ianna-v06c/tools/disk_layout.py, build_fdd.py).

82 дорожки по 2 стороны x 5 секторов x 1024 Б (839 680 Б), LBA = дорожка * 10 + сторона * 5 + (сектор - 1).
    дорожки 0..3   загрузочная область: дескриптор (32 Б) и загрузчик src/vec/fddload.asm со смещения 0x80 —
                   штатное ПЗУ грузит с начала дорожки 0 по 0x0080 (байт 4 дескриптора — сколько КБ), вход 0x0100
    LBA 40..43     каталог МикроДОС (128 записей)
    LBA 44..47     ATICATAC.COM — тот же загрузчик (запуск из CP/M)
    LBA 48..       ATICATAC.DAT: квазидиск стр. 0..3 (занятая часть), блок 0xE000..0xFFFF, основная память
                   0x0400..0x7FFF и последним 0x0000..0x03FF (вектор прерывания — после всего, см. fddload.asm)
Данные — без сжатия (~280 КБ). Константы для загрузчика — build/game/fddload.inc.
  python3 tools/build_fdd.py      (после tools/build_game.sh)  -> build/game/aticatac.fdd
"""
import os, re, subprocess, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
B = os.path.join(ROOT, 'build/game')
SEC, TRACK, TRACKS = 1024, 10 * 1024, 82
DIR_LBA, COM_LBA, DAT_LBA, DSM = 40, 44, 48, 379
STAGE = 0xE000                                      # стр. 3: временное место блока 0xE000..0xFFFF
# блок параметров диска МикроДОС (байты 5..30 дескриптора): 1 КБ сектор, 5 секторов, 80 дорожек, блок 2 КБ, DSM 379
DPB = bytes.fromhex('00000101010301050050002800040f007b017f00c00020000800')

def msdos_dir(files):
    """каталог МикроДОС (CP/M 2.2) на 4 сектора — как disk_layout.msdos_dir порта Ianna"""
    d = bytearray(b'\xe5' * 4 * SEC)
    e = 0
    for (name, ext), lba, size in files:
        assert (lba - DIR_LBA) % 2 == 0
        b0, nblk = (lba - DIR_LBA) // 2, (size + 2047) // 2048
        blocks = list(range(b0, b0 + nblk))
        assert blocks[-1] <= DSM
        recs = (size + 127) // 128
        for x in range(0, len(blocks), 8):
            ent = bytearray(32)
            ent[1:9] = name.ljust(8).encode(); ent[9:12] = ext.ljust(3).encode()
            ent[12] = (x // 8) & 31; ent[14] = (x // 8) >> 5
            ent[15] = min(128, recs - x * 16)
            for i, blk in enumerate(blocks[x:x + 8]): ent[16 + 2 * i:18 + 2 * i] = blk.to_bytes(2, 'little')
            d[e * 32:e * 32 + 32] = ent; e += 1
        if recs % 128 == 0:
            ent = bytearray(32)
            ent[1:9] = name.ljust(8).encode(); ent[9:12] = ext.ljust(3).encode()
            ent[12] = (recs // 128) & 31; ent[14] = (recs // 128) >> 5
            d[e * 32:e * 32 + 32] = ent; e += 1
    assert e <= 128
    return d

def used(page):
    n = len(page)
    while n and page[n - 1] == 0: n -= 1
    return (n + SEC - 1) // SEC

def main():
    ram = open(os.path.join(B, 'aticatac.rom'), 'rb').read()
    edd = open(os.path.join(B, 'aticatac.edd'), 'rb').read()
    assert len(ram) == 0x10000 and len(edd) == 0x40000
    pages = [edd[p * 0x10000:(p + 1) * 0x10000] for p in range(4)]
    np = [used(p) for p in pages]
    assert np[3] * SEC <= STAGE, 'спрайты стр. 3 заходят на временное место блока 0xE000'
    dat = bytearray()
    for p in range(4): dat += pages[p][:np[p] * SEC]
    dat += ram[0xE000:0x10000] + ram[0x0400:0x8000] + ram[0x0000:0x0400]
    nsec = len(dat) // SEC
    track, rem = divmod(DAT_LBA, 10)
    per = (nsec - np[0] + 23) // 24                   # полоска — 24 столбца, после заставки (стр. 0 — до неё)
    open(os.path.join(B, 'fddload.inc'), 'w').write(
        '; сгенерировано tools/build_fdd.py\nFL_TRACK\tequ %d\nFL_SIDE\tequ %d\nFL_SEC\tequ %d\n'
        'FL_P0\tequ %d\nFL_P1\tequ %d\nFL_P2\tequ %d\nFL_P3\tequ %d\nFL_STAGE\tequ 0x%04X\nFL_PER\tequ %d\n' % (
            track, rem // 5, rem % 5 + 1, np[0], np[1], np[2], np[3], STAGE, per))
    r = subprocess.run([os.path.join(ROOT, 'tools/sjasmplus'), '--nologo', '--i8080', 'fddload.asm',
                        '--raw=../../build/game/fddload.bin', '--sym=../../build/game/fddload.sym'],
                       cwd=os.path.join(ROOT, 'src/vec'), capture_output=True, text=True)
    if r.returncode or re.search(r'Errors: [1-9]|error:', r.stdout + r.stderr):
        print(r.stdout[-3000:], r.stderr[-2000:]); sys.exit(1)
    ld = open(os.path.join(B, 'fddload.bin'), 'rb').read()
    assert len(ld) <= (DAT_LBA - COM_LBA) * SEC and 0x80 + len(ld) <= 40 * SEC
    img = bytearray(TRACKS * TRACK)
    desc = bytearray(32)
    desc[4] = (0x80 + len(ld) + SEC - 1) // SEC        # КБ с начала дорожки 0 -> 0x0080..
    desc[5:31] = DPB
    s = 0x66
    for i in range(31): s = (s + desc[i]) & 0xFF
    desc[31] = s
    img[0:32] = desc
    img[0x80:0x80 + len(ld)] = ld
    img[DIR_LBA * SEC:(DIR_LBA + 4) * SEC] = msdos_dir([(('ATICATAC', 'COM'), COM_LBA, len(ld)), (('ATICATAC', 'DAT'), DAT_LBA, len(dat))])
    img[COM_LBA * SEC:COM_LBA * SEC + len(ld)] = ld
    assert DAT_LBA * SEC + len(dat) <= (DIR_LBA + 2 * (DSM + 1)) * SEC, 'ATICATAC.DAT не влез в диск CP/M'
    img[DAT_LBA * SEC:DAT_LBA * SEC + len(dat)] = dat
    open(os.path.join(B, 'aticatac.fdd'), 'wb').write(img)
    print('aticatac.fdd: загрузчик %d Б, данные %d КБ (квазидиск %s КБ по страницам), дорожки %d..%d' % (
        len(ld), len(dat) // SEC, '/'.join(str(n) for n in np), DAT_LBA // 10, (DAT_LBA + nsec - 1) // 10))

if __name__ == '__main__':
    main()
