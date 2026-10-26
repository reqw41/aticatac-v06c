#!/bin/sh
# Запуск игры в Emu80 (Вектор-06Ц): build/game/aticatac.r0m + квазидиск build/game/aticatac.edd.
# Квазидиск — через --post-conf (ramDisk.fileName): штатный --edd на Векторе не работает (свойство
# ставится объекту vector.edd, а в конфиге он ramDisk) — урок Ianna (tools/emu80_run.sh там же).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${EMU80_APP:-$HOME/Applications/Emu80/Emu80qt_40559_macos/Emu80qt.app/Contents/MacOS}"
TMP="${TMPDIR:-/tmp}/aticatac_emu80"; mkdir -p "$TMP"
pkill -f "aticatac.r0m" 2>/dev/null || true
cp "$ROOT/build/game/aticatac.r0m" "$ROOT/build/game/aticatac.edd" "$TMP/"
printf 'ramDisk.fileName = "%s"\n' "$TMP/aticatac.edd" > "$TMP/post.conf"
cd "$APP"
nohup ./Emu80qt --platform vector --post-conf "$TMP/post.conf" --run "$TMP/aticatac.r0m" >"$TMP/emu80.log" 2>&1 &
echo "Emu80 запущен: стрелки, пробел — огонь, Z или Я — взять/бросить, в меню F1+F3 — god mode"
