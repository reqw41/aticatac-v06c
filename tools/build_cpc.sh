#!/bin/bash
# Эталонная сборка CPC-версии (ref/cpc) свежим rasm 3.3.2 в build/cpcsrc и сверка с ref/cpc/aticatac.dsk.
# Новый rasm не принимает "МЕТКА: equ" — в копии двоеточие убирается (на код не влияет: сборка байт в байт).
# rasm: tools/rasm (собран из tools/src/rasm: make -f makefile.MacOS CC=/usr/bin/clang ARCH="-arch arm64").
set -e
cd "$(dirname "$0")/.."
mkdir -p build
RASM=${RASM:-$PWD/tools/rasm}
rm -rf build/cpcsrc build/cpcnew && cp -R ref/cpc build/cpcsrc
find build/cpcsrc -name '*.asm' -print0 | xargs -0 sed -i.bak -E \
  's/^([[:space:]]*[A-Za-z_][A-Za-z0-9_.{}]*):([[:space:]]+[Ee][Qq][Uu])/\1\2/'
find build/cpcsrc -name '*.asm.bak' -delete
(cd build/cpcsrc && rm -f aticatac.dsk && "$RASM" atic.asm -s -sl -sq >/dev/null && "$RASM" loader.asm >/dev/null)
python3 -I tools/dskextract.py build/cpcsrc/aticatac.dsk build/cpcnew >/dev/null
python3 -I tools/dskextract.py ref/cpc/aticatac.dsk build/cpc >/dev/null
ok=1
for f in build/cpc/*.bin; do b=$(basename "$f")
  if cmp -s "$f" "build/cpcnew/$b"; then echo "$b = эталон"; else echo "$b ОТЛИЧАЕТСЯ"; ok=0; fi
done
[ $ok = 1 ] && echo "CPC: сборка байт в байт" || { echo "CPC: расхождение"; exit 1; }
