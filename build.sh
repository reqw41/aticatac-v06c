#!/bin/bash
# Полная сборка: CPC-эталон из ref/cpc (tools/build_cpc.sh) -> игра для Вектора (tools/build_game.sh) ->
# rom/aticatac.fdd. Нужны ref/cpc (клон shaymanjohn/aticatac-cpc), tools/rasm, tools/sjasmplus — см. README.
set -e
cd "$(dirname "$0")"
[ -f ref/cpc/atic.asm ] || { echo "нет ref/cpc: git clone https://github.com/shaymanjohn/aticatac-cpc ref/cpc"; exit 1; }
for t in rasm sjasmplus; do [ -x tools/$t ] || { echo "нет tools/$t (см. README, «Сборка»)"; exit 1; }; done
tools/build_cpc.sh
tools/build_game.sh
mkdir -p rom
cp build/game/aticatac.fdd rom/aticatac.fdd
echo "готово: rom/aticatac.fdd ($(md5 -q rom/aticatac.fdd 2>/dev/null || md5sum rom/aticatac.fdd | cut -d' ' -f1))"
