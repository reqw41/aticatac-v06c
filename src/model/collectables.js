// collectables.asm: ключи и предметы (карманы), подбор/сброс по огню 2. Вывод не моделируется.
'use strict';
const { S } = require('./core');
const { random, neg } = require('./util');
const snd = require('./sound');
const lazy = (m) => () => require(m);
const doors = lazy('./doors');

function init_collectables(M) {
  M.bank(S.item_bank_config);
  M.wr(S.pocket1, 0xff); M.wr(S.pocket2, 0xff); M.wr(S.pocket3, 0xff);
  for (let ix = S.col_key_yellow; M.rd(ix) !== 0xff; ix += 8) {
    M.wr(ix, M.rd(ix + 5)); M.wr(ix + 3, M.rd(ix + 6)); M.wr(ix + 4, M.rd(ix + 7));
  }
  M.wr(S.random_seed, M.ldar());
  let hl = M.rd16(S.random_place_table + 2 * (random(M) & 7));
  for (let i = 0, ix = S.collectable_items; i < 6; i++, ix += 8) {
    M.wr(ix, M.rd(hl++)); M.wr(ix + 3, M.rd(hl++)); M.wr(ix + 4, M.rd(hl++));
  }
  M.wr(S.mummy_room, M.rd(S.col_key_red));
  M.wr(S.dracula_room, S.room_dracula);
}

function collect_this_collectable(M, ix) {
  let e = ((M.rd(S.player_x) >> 1) + 2) & 0xff;
  let a = (M.rd(ix + 3) + 2 - e) & 0xff;
  if (a & 0x80) a = neg(a);
  if (a >= 4) return 0;
  e = (M.rd(S.player_y) + (S.average_player_height >> 1)) & 0xff;
  a = (M.rd(ix + 4) + 8 - e) & 0xff;
  if (a & 0x80) a = neg(a);
  if (a >= 8) return 0;
  return 1;
}

function pickup_tapped(M) {
  snd.play_sfx(M, S.sound_c_food);
  const c = M.rd(S.room_number);
  let ix = S.collectable_items, b = 0, got = false;
  for (;; b = (b + 1) & 0xff, ix += 8) {
    const a = M.rd(ix);
    if (a === 0xff) break;
    if (a === c && collect_this_collectable(M, ix)) { got = true; break; }
  }
  const e = M.rd(S.pocket3);
  M.wr(S.pocket3, M.rd(S.pocket2));
  M.wr(S.pocket2, M.rd(S.pocket1));
  M.wr(S.pocket1, 0xff);
  if (got) {
    M.wr(S.pocket1, b);
    M.wr(ix, 0xfe);
    if (b === S.the_red_key && M.rd(S.mummy_room) === M.rd(S.room_number)) M.wr(S.mummy_angry, 1);
    M.bank(S.room_bank_config);
  }
  if (e !== 0xff) {
    const it = S.collectable_items + ((e << 3) & 0x7ff);
    M.wr(it, M.rd(S.room_number));
    M.wr(it + 3, M.rd(S.player_x) >> 1);
    M.wr(it + 4, (M.rd(S.player_y) + 4) & 0xff);
    M.bank(S.room_bank_config);
  }
  M.wr(S.do_pockets, 2);
  doors().update_collision_grid_for_items(M);
}

module.exports = { init_collectables, pickup_tapped };
