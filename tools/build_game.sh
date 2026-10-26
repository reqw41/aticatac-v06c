#!/bin/bash
# Сборка игры для Вектора: build/game/aticatac.rom (64 КБ с 0x0000) + build/game/aticatac.edd (квазидиск).
#   tools/build_game.sh            (holes.json берётся готовый; пересчёт — node tools/holes.js build/golden/*.json.gz)
set -e
cd "$(dirname "$0")/.."
python3 -I tools/mk80sym.py >/dev/null
python3 -I tools/mk80data.py >/dev/null
python3 -I tools/mkroom.py build/room >/dev/null
node tools/cpcpanel.js >/dev/null
node tools/cpcmenu.js >/dev/null
python3 -I tools/mkgame.py build/game
[ -f build/l80/holes.json ] || node tools/holes.js build/golden/*.json.gz
python3 - <<'PY'
import json
p = json.load(open('build/game/patch.json'))
out = ['; сгенерировано tools/build_game.sh из build/game/patch.json']
for a, lab in p['patch']: out.append('\t\t\t\tORG\t0x%04X\n\t\t\t\tDW\t%s' % (a, lab))
open('build/game/patch.inc', 'w').write('\n'.join(out) + '\n')
PY
python3 -I tools/layout.py
(cd src/vec && ../../tools/sjasmplus --nologo --i8080 $SJFLAGS game.asm --sym=../../build/game/aticatac.sym > ../../build/game/sjasm.log 2>&1) || true
if grep -qE "Errors: [1-9]|error:" build/game/sjasm.log || ! grep -q "Errors: 0" build/game/sjasm.log; then grep -iE "error|warning" build/game/sjasm.log | head -20; echo "СБОРКА НЕ УДАЛАСЬ"; exit 1; fi
python3 - <<'PY'
# квазидиск: стр. 1 — предметы комнат, стр. 2 — контуры + ключи/еда (0xA300), стр. 3 — спрайты
edd = bytearray(0x40000)
def put(page, off, f):
    d = open(f, 'rb').read(); edd[page * 0x10000 + off: page * 0x10000 + off + len(d)] = d
put(1, 0, 'build/room/items1.bin')
put(2, 0, 'build/room/items2.bin')
put(2, 0xA300, 'build/game/kv2_items.bin')
put(3, 0, 'build/game/kv3_spr.bin')
put(2, 0xC000, 'build/game/bgf_rooms.bin')
import re
pa = int(re.search(r'PANEL_ADDR\tequ 0x([0-9A-F]+)', open('build/game/sprites.inc').read()).group(1), 16)
put(2, pa, 'build/game/panel_kv.bin')
put(0, 0x8000, 'build/game/menu_kv.bin')
assert len(open('build/room/items2.bin', 'rb').read()) <= 0xA300
open('build/game/aticatac.edd', 'wb').write(edd)
print('aticatac.edd: 256 КБ')
PY
cp build/game/aticatac.rom build/game/aticatac.r0m
ls -la build/game/aticatac.r0m build/game/aticatac.edd
