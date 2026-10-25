// sound.asm: запросы звуков (сам плеер — в обработчике прерывания, не моделируется).
'use strict';
const { S } = require('./core');

function play_sfx(M, e) {
  M.sfx.push(e);
  M.wr(S.sound_guard, S.sound_persist_time);
}

function play_lowpriority_sfx(M, e) {
  if (M.rd(S.sound_guard)) return;
  M.sfx.push(e);
}

module.exports = { play_sfx, play_lowpriority_sfx };
