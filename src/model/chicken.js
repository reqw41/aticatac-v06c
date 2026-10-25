// chicken.asm: здоровье (курица на панели), убывание и смерть. Вывод курицы не моделируется.
'use strict';
const { S } = require('./core');
const lazy = (m) => () => require(m);
const player = lazy('./player');

function init_health(M) { M.wr(S.health, S.max_health); M.wr(S.drawn_health, S.max_health >> 2); }
function health_decay(M) { const a = M.rd(S.health); if (a) M.wr(S.health, a - 1); }
function health_down(M) { const a = M.rd(S.health); if (!a) return; M.wr(S.health, a >= 8 ? a - 8 : 0); }
function health_up(M) { const a = M.rd(S.health) + 16; M.wr(S.health, a < S.max_health ? a & 0xff : S.max_health); }

function update_chicken(M) {
  const b = M.rd(S.health) >> 2;
  let a = M.rd(S.drawn_health);
  if (a === b) return;
  if (a < b) { M.wr(S.drawn_health, a + 1); return; }   // рисование строки курицы
  a = (a - 1) & 0xff;
  M.wr(S.drawn_health, a);
  if (((30 - a) & 0xff) !== 30) return;
  player().decrease_lives(M);
  if (!M.rd(S.game_over)) player().make_player_disappear(M);
}

module.exports = { init_health, health_decay, health_down, health_up, update_chicken };
