// score.asm: счёт в BCD и строка score_text (вывод show_text не моделируется).
'use strict';
const { S } = require('./core');
const { addBcd } = require('./util');

function init_score(M) { M.wr(S.score, 0); M.wr(S.score + 1, 0); M.wr(S.score + 2, 0); }

function add_to_score(M, bc) {
  let [r, c] = addBcd(M.rd(S.score + 2), bc & 0xff, 0); M.wr(S.score + 2, r);
  [r, c] = addBcd(M.rd(S.score + 1), bc >> 8, c); M.wr(S.score + 1, r);
  [r, c] = addBcd(M.rd(S.score), 0, c); M.wr(S.score, r);
  let t = S.score_text + 3;
  for (let i = 0; i < 3; i++) {
    const v = M.rd(S.score + i);
    M.wr(t++, (v >> 4) + 0x30);
    M.wr(t++, (v & 0x0f) + 0x30);
  }
  M.bank(S.item_bank_config);
}

module.exports = { init_score, add_to_score };
