#!/bin/bash
# Замер прототипа: скорость (run.js), разрывы по лучу (tearcheck.js — главный) и артефакты кадров (frames.js +
# tear.py — с ложными срабатываниями, когда объект перерисовывается в момент снимка памяти). Ключи sjasmplus — аргументами.
#   stand/vec/flicker.sh -DBEAM -DOFS_U=8
set -e
cd "$(dirname "$0")/../.."
T=${TMPDIR:-/tmp}/aticatac_flicker; mkdir -p "$T"
(cd proto && ../tools/sjasmplus --nologo --i8080 "$@" proto.asm --sym=../build/proto/flk.sym >/dev/null)
cp build/proto/proto.r0m build/proto/flk.r0m
echo "== $*"
node stand/vec/run.js build/proto/flk.r0m build/proto/flk.sym 500 | sed -n 2p
node stand/vec/tearcheck.js build/proto/flk.r0m build/proto/flk.sym 300
node stand/vec/frames.js build/proto/flk.r0m 170 20 "$T/fr.raw"
[ -f "$T/bg.raw" ] || { (cd proto && ../tools/sjasmplus --nologo --i8080 -DERASECHK proto.asm >/dev/null); \
  node stand/vec/frames.js build/proto/proto.r0m 520 519 "$T/bg.raw"; rm -f "$T/bg.raw.mem"; }
python3 stand/vec/tear.py "$T" build/proto/bg.bin
(cd proto && ../tools/sjasmplus --nologo --i8080 proto.asm --sym=../build/proto/proto.sym >/dev/null)
