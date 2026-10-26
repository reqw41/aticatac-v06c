#!/usr/bin/env python3
"""PlayerAkg (Arkos Tracker 2, ref/cpc/sound) в плоский исходник: условная сборка по конфигурации банка звука
CPC (ref/cpc/include_banks.asm), макросы с параметром развёрнуты, служебные метки Disark убраны; перед каждой
командой — метка ZL_<номер строки исходника>. Собирается rasm в банк звука (Music_Empty, atic_tunes, эффекты,
плеер с 0x4000) — байты должны совпасть с build/cpcnew/sounds.bin; по меткам ZL_ — адрес каждой строки.
  python3 tools/akgflat.py      -> build/sound/akg/{flat.asm, bank.asm, flat_lines.json}, проверка байт
"""
import json, os, re, subprocess, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SRC = os.path.join(ROOT, 'build/cpcsrc/sound')          # копия ref/cpc после tools/build_cpc.sh (без «МЕТКА: equ»)
OUT = os.path.join(ROOT, 'build/sound/akg')
CONFIG = """PLY_AKG_HARDWARE_CPC = 1
PLY_AKG_MANAGE_SOUND_EFFECTS = 1
PLY_CFG_ConfigurationIsPresent = 1
PLY_CFG_UseSpeedTracks = 1
PLY_CFG_UseEffects = 1
PLY_CFG_UseInstrumentLoopTo = 1
PLY_CFG_NoSoftNoHard = 1
PLY_CFG_SoftOnly = 1
PLY_CFG_SoftOnly_SoftwareArpeggio = 1
PLY_CFG_SoftOnly_SoftwarePitch = 1
PLY_CFG_UseEffect_Legato = 1
PLY_CFG_UseEffect_Arpeggio3Notes = 1
PLY_CFG_UseEffect_ArpeggioTable = 1
PLY_CFG_SFX_ConfigurationIsPresent = 1
PLY_CFG_SFX_SoftOnly = 1
PLY_CFG_SFX_SoftOnly_Noise = 1
"""

sym = {}                                            # переменные условной сборки
def defs_from(text):
    for l in text.splitlines():
        m = re.match(r'^\s*([A-Za-z_]\w*)\s*(?::\s*equ|=|\s+equ)\s*([^;]+)', l, re.I)
        if m: sym[m.group(1)] = m.group(2).strip()
defs_from(CONFIG)

def ev(expr, params):
    e = expr.split(';')[0].strip()
    for k, v in params.items(): e = e.replace('{%s}' % k, str(v))
    e = re.sub(r'#([0-9A-Fa-f]+)', r'0x\1', e)
    def val(m):
        n = m.group(0)
        if n in params: return str(params[n])
        if n in sym:
            try: return str(ev(sym[n], params))
            except Exception: return '1'
        raise KeyError(n)
    e = re.sub(r'[A-Za-z_]\w*', val, e)
    e = e.replace('&&', ' and ').replace('||', ' or ')
    return int(eval(e))

def flatten(path, params=None, out=None, macros=None, depth=0):
    params = params or {}
    macros = macros if macros is not None else {}
    out = out if out is not None else []
    lines = open(path, encoding='latin-1').read().splitlines()
    stack = []                                       # [активна ли ветка, была ли выбрана]
    active = lambda: all(s[0] for s in stack)
    i = 0
    while i < len(lines):
        raw = lines[i]; ln = i + 1; i += 1
        code = raw.split(';')[0]
        t = code.strip()
        w = t.split()[0].upper().rstrip(':') if t else ''
        if w in ('IFDEF', 'IFNDEF'):
            name = t.split()[1].replace('{', '').replace('}', '')
            for k, v in params.items(): name = name.replace(k, str(v))
            c = (name in sym or name.upper() in macros)
            if w == 'IFNDEF': c = not c
            stack.append([c and active(), c]); continue
        if w == 'IF':
            c = bool(ev(t[2:], params)) if active() else False
            stack.append([c and active(), c]); continue
        if w == 'ELSEIF':
            s_ = stack[-1]; outer = all(x[0] for x in stack[:-1])
            c = (not s_[1]) and outer and bool(ev(t.split(None, 1)[1], params))
            s_[0] = c; s_[1] = s_[1] or c; continue
        if w == 'ELSE':
            s = stack[-1]; outer = all(x[0] for x in stack[:-1])
            s[0] = outer and not s[1]; s[1] = True; continue
        if w == 'ENDIF':
            stack.pop(); continue
        if not active(): continue
        if w == 'MACRO':
            parts = t.split(None, 1)[1].replace(',', ' ').split()
            name, mparams = parts[0], parts[1:]
            body = []
            while not lines[i].strip().upper().startswith('ENDM'):
                body.append((lines[i], i + 1)); i += 1
            i += 1
            macros[name.upper()] = (mparams, body, path); continue
        if w == 'REPEAT':                            # REPEAT n, переменная ... REND (счёт с 1)
            arg = t.split(None, 1)[1].split(',')
            n = ev(arg[0], params); var = arg[1].strip() if len(arg) > 1 else None
            body = []; depth_r = 0
            while True:
                tt = lines[i].split(';')[0].strip().upper()
                if tt.startswith('REPEAT'): depth_r += 1
                if tt.startswith('REND'):
                    if depth_r == 0: break
                    depth_r -= 1
                body.append((lines[i], i + 1)); i += 1
            i += 1
            for k in range(1, n + 1):
                p = dict(params)
                if var: p[var] = k
                tmp = os.path.join(OUT, '_rep_%d_%d.asm' % (ln, k))
                open(tmp, 'w', encoding='latin-1').write('\n'.join(b for b, _ in body))
                for (txt, kk) in flatten(tmp, p, [], macros, depth + 1): out.append((txt, body[kk - 1][1] if isinstance(kk, int) and kk <= len(body) else kk))
            continue
        if w == 'INCLUDE':
            inc = re.search(r'"([^"]+)"', t).group(1)
            flatten(os.path.join(SRC, inc), params, out, macros, depth + 1); continue
        if w in ('DKWS', 'DKWE', 'DKPS', 'DKPE', 'DKBS', 'DKBE', 'DKNR3'):
            rest = re.sub(r'^\s*\w+:?', '', raw)          # «dknr3:  ld de,4» — команда остаётся
            if not rest.split(';')[0].strip(): continue
            raw = '        ' + rest.lstrip(); code = raw.split(';')[0]; t = code.strip(); w = t.split()[0].upper()
        if w in macros:
            mparams, body, mpath = macros[w]
            args = t.split(None, 1)[1].replace(',', ' ').split() if len(t.split()) > 1 else []
            p = dict(params); p.update(zip(mparams, [int(a) if a.isdigit() else a for a in args]))
            tmp = os.path.join(OUT, '_macro_%s_%s.asm' % (w, '_'.join(map(str, args)) or '0'))
            open(tmp, 'w', encoding='latin-1').write('\n'.join(b for b, _ in body))
            sub = flatten(tmp, p, [], macros, depth + 1)
            base = {}                                # номера строк — исходные строки тела макроса
            for (txt, k) in sub: out.append((txt, body[k - 1][1] if isinstance(k, int) and k <= len(body) else k))
            continue
        if w in ('DKWS', 'DKWE', 'DKPS', 'DKPE', 'DKBS', 'DKBE', 'DKNR3'): continue
        # подстановка параметров макроса
        txt = raw
        for k, v in params.items(): txt = txt.replace('{%s}' % k, str(v))
        m = re.match(r'^\s*([A-Za-z_]\w*)\s*(?::\s*equ|=|\s+equ)\s*([^;]+)', txt, re.I)
        if m:
            try: sym[m.group(1)] = str(ev(m.group(2), params))      # значение сразу (счётчики вида X = X + 1)
            except Exception: sym[m.group(1)] = m.group(2).strip()
        out.append((txt, ln if depth == 0 or 'PlayerAkg' in path else ln))
    return out

def main():
    os.makedirs(OUT, exist_ok=True)
    # переменные из начала плеера (агрегаты флагов) берутся по ходу разворота
    flat = flatten(os.path.join(SRC, 'PlayerAkg.asm'))
    res, nl = [], 0
    for txt, ln in flat:
        code = txt.split(';')[0]
        m = re.match(r'^(\s*)([A-Za-z_][\w.]*:?)?(\s+)(\S.*)?$', code)
        is_instr = bool(code.strip()) and not re.match(r'^\s*[A-Za-z_]\w*\s*(:\s*equ|=|\s+equ)', code, re.I) \
            and (code[:1].isspace() or ':' in code.split()[0] and len(code.split()) > 1)
        if is_instr:
            nl += 1
            res.append('ZL_%05d' % nl)
            res.append(txt if code[:1].isspace() else txt)
        else:
            res.append(txt)
    open(os.path.join(OUT, 'flat.asm'), 'w', encoding='latin-1').write('\n'.join(res) + '\n')
    bank = 'BANK\norg 0x4000\nsound_bank_start\ninclude "%s/Music_Empty.asm"\ninclude "%s/atic_tunes.asm"\n%s\nSoundEffects\ninclude "%s/Atic-Atac-CPC-SFX.asm"\ninclude "flat.asm"\nsound_bank_end\nsave "bank.bin", 0x4000, sound_bank_end-sound_bank_start\n' % (SRC, SRC, CONFIG, SRC)
    open(os.path.join(OUT, 'bank.asm'), 'w').write(bank)
    r = subprocess.run([os.path.join(ROOT, 'tools/rasm'), 'bank.asm', '-s', '-sl', '-sq'], cwd=OUT, capture_output=True, text=True)
    if r.returncode: print(r.stdout[-3000:], r.stderr[-2000:]); sys.exit(1)
    a = open(os.path.join(OUT, 'bank.bin'), 'rb').read(); b = open(os.path.join(ROOT, 'build/cpcnew/sounds.bin'), 'rb').read()
    print('банк звука: %d Б, эталон %d Б, %s' % (len(a), len(b), 'байт в байт' if a == b else 'РАСХОЖДЕНИЕ'))
    if a != b:
        d = next(k for k in range(min(len(a), len(b))) if a[k] != b[k]) if any(a[k] != b[k] for k in range(min(len(a), len(b)))) else min(len(a), len(b))
        print('первое отличие 0x%04X' % (0x4000 + d)); sys.exit(1)

if __name__ == '__main__':
    main()
