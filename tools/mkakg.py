#!/usr/bin/env python3
"""Проигрыватель Arkos (src/vec/akg80.tpl -> i8080) и данные звука CPC для Вектора.
Плеер — с AKG_ORG, данные (Music_Empty, atic_tunes, таблица и эффекты Atic-Atac-CPC-SFX; rasm из исходников
CPC) — с AKG_DATA; всё вместе — один блок для окна квазидиска 0xA000..0xDFFF.
  python3 tools/mkakg.py   -> build/sound/akg/{akg80.asm, akg80.bin, akg80.sym, data.bin, data.inc, akg_kv.bin}
"""
import os, re, subprocess, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT = os.path.join(ROOT, 'build/sound/akg')
SRC = os.path.join(ROOT, 'build/cpcsrc/sound')
AKG_ORG, AKG_DATA = 0xA000, 0xC000

def expand(tpl):
    out, i, lines = [], 0, tpl.split('\n')
    while i < len(lines):
        if lines[i].strip() == '{{CH}}':
            j = i + 1
            while lines[j].strip() != '{{END}}': j += 1
            body = lines[i + 1:j]
            for n in (1, 2, 3):
                out += [l.replace('{N}', str(n)).replace('{I}', str(n - 1)) for l in body]
            i = j + 1
        else:
            out.append(lines[i]); i += 1
    return '\n'.join(out)

def main():
    os.makedirs(OUT, exist_ok=True)
    # данные — rasm, исходники CPC
    open(os.path.join(OUT, 'data.asm'), 'w').write(
        'org 0x%04X\nakg_data_start\ninclude "%s/Music_Empty.asm"\ninclude "%s/atic_tunes.asm"\nSoundEffects\ninclude "%s/Atic-Atac-CPC-SFX.asm"\nakg_data_end\nsave "data.bin", 0x%04X, akg_data_end-akg_data_start\n' % (AKG_DATA, SRC, SRC, SRC, AKG_DATA))
    r = subprocess.run([os.path.join(ROOT, 'tools/rasm'), 'data.asm', '-s', '-os', 'data.sym'], cwd=OUT, capture_output=True, text=True)
    if r.returncode: print(r.stdout[-2000:]); sys.exit(1)
    syms = {}
    for l in open(os.path.join(OUT, 'data.sym')):
        m = re.match(r'^(\S+) #([0-9A-F]+)', l)
        if m: syms[m.group(1).upper()] = int(m.group(2), 16)
    with open(os.path.join(OUT, 'data.inc'), 'w') as f:
        for n in ('NOMUSIC_START', 'ATIC_START', 'SOUNDEFFECTS'): f.write('AKG_%s\tequ 0x%04X\n' % (n, syms[n]))
    data = open(os.path.join(OUT, 'data.bin'), 'rb').read()
    # плеер
    src = '; сгенерировано tools/mkakg.py из src/vec/akg80.tpl\n\t\t\t\tORG\t0x%04X\n' % AKG_ORG + expand(open(os.path.join(ROOT, 'src/vec/akg80.tpl')).read()) + \
          '\nakg_end:\n\t\t\t\tASSERT\takg_end <= 0x%04X\n' % AKG_DATA
    open(os.path.join(OUT, 'akg80.asm'), 'w').write(src)
    r = subprocess.run([os.path.join(ROOT, 'tools/sjasmplus'), '--nologo', '--i8080', 'akg80.asm', '--raw=akg80.bin', '--sym=akg80.sym'], cwd=OUT, capture_output=True, text=True)
    if r.returncode or re.search(r'Errors: [1-9]|error:', r.stdout + r.stderr): print(r.stdout[-3000:], r.stderr[-2000:]); sys.exit(1)
    code = open(os.path.join(OUT, 'akg80.bin'), 'rb').read()
    blob = bytearray(AKG_DATA - AKG_ORG + len(data))
    blob[:len(code)] = code; blob[AKG_DATA - AKG_ORG:] = data
    open(os.path.join(OUT, 'akg_kv.bin'), 'wb').write(bytes(blob))
    sym = {}
    for l in open(os.path.join(OUT, 'akg80.sym')):
        m = re.match(r'^(\w+):\s+EQU\s+0x([0-9A-Fa-f]+)', l)
        if m: sym[m.group(1)] = int(m.group(2), 16)
    with open(os.path.join(OUT, 'akg.inc'), 'w') as f:            # для игры: входы плеера и данные
        f.write('; сгенерировано tools/mkakg.py: плеер akg80 и данные звука в квазидиске стр. 0 (окно 0xA000..0xDFFF)\n')
        for n in ('akg_init', 'akg_initsfx', 'akg_playsfx', 'akg_play', 'akg_quiet', 'akg_regs'): f.write('%s\tequ 0x%04X\n' % (n, sym[n]))
        f.write(open(os.path.join(OUT, 'data.inc')).read())
    print('akg80: плеер %d Б, данные %d Б' % (len(code), len(data)))

if __name__ == '__main__':
    main()
