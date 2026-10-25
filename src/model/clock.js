// clock.asm: часы игры (обновляет прерывание), вывод — show_clock (не моделируется, кроме переменных).
'use strict';
const { S } = require('./core');

function show_clock(M) {
  M.wr(S.tell_time, 0);
  if (!M.rd(S.second_only)) return;
  M.wr(S.seconds_time, M.rd(S.game_time + 5));
}

function reset_clock(M) {
  for (const i of [0, 1, 2, 4, 5]) M.wr(S.game_time + i, 0x30);
  M.wr(S.tell_time, 1);
}

module.exports = { show_clock, reset_clock };
