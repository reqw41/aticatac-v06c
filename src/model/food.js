// food.asm: еда в комнатах (банк героев, стр. 4), могилы, подбор еды. Вывод не моделируется,
// но смена банков в процедурах вывода повторена (draw_food_item2 оставляет банк комнат).
'use strict';
const { S } = require('./core');
const { neg } = require('./util');
const snd = require('./sound');
const lazy = (m) => () => require(m);
const chicken = lazy('./chicken');

const NFOOD = (S.food_items_end - S.food_items) >> 3;
const draw_food_item2 = (M) => M.bank(S.room_bank_config);

function init_food(M) {
  M.bank(S.sprite_bank_config);
  for (let i = 0, ix = S.food_items; i < NFOOD; i++, ix += 8) M.wr(ix + 2, 0);
  M.wr(S.tombstones + 1, 0xff); M.wr(S.tombstones + 9, 0xff); M.wr(S.tombstones + 17, 0xff);
}

function replen_food(M) {
  M.bank(S.sprite_bank_config);
  for (let i = 0, ix = S.food_items; i < NFOOD; i++, ix += 8) {
    const a = M.rd(ix + 2);
    if (a) M.wr(ix + 2, a - 1);
  }
}

function add_tombstone(M) {
  const ix = S.tombstones + ((M.rd(S.num_lives) << 3) & 0xff);
  M.wr(ix + 1, M.rd(S.room_number));
  M.wr(ix + 3, M.rd(S.player_x) >> 1);
  M.wr(ix + 4, (M.rd(S.player_y) + M.rd(S.actual_player_height)) & 0xff);
  M.wr16(S.draw_tombstone_with_index, ix);
  draw_food_item2(M);
}

function check_food_collision(M, count) {
  M.bank(S.sprite_bank_config);
  let hl = S.this_rooms_food_list;
  for (let b = count || 256; b > 0; b--, hl += 2) {
    const ix = M.rd16(hl);
    if (!M.rd(ix + 2) && check_food(M, ix)) return;
  }
}

function check_food(M, ix) {
  const e = ((M.rd(S.player_x) >> 1) + 2) & 0xff;
  let a = (M.rd(ix + 3) + 1 - e) & 0xff;
  if (a & 0x80) a = neg(a);
  if (a >= 4) return 0;
  const e2 = (M.rd(S.player_y) + (S.average_player_height >> 1)) & 0xff;
  a = (M.rd(ix + 4) - (M.rd(ix + 7) >> 1) - e2) & 0xff;
  if (a & 0x80) a = neg(a);
  if (a >= 12) return 0;
  const t = M.rd(ix);
  if (t === S.type_tombstone) return 0;
  if (t === S.type_mushroom) { snd.play_sfx(M, S.sound_clock); chicken().health_decay(M); return 0; }
  draw_food_item2(M);
  M.bank(S.sprite_bank_config);
  M.wr(ix + 2, S.food_respawn);
  M.wr16(S.erase_food_with_index, ix);
  snd.play_sfx(M, S.sound_c_food);
  chicken().health_up(M);
  return 1;
}

function reset_food_collected(M) { M.wr16(S.erase_food_with_index, 0); M.wr16(S.draw_tombstone_with_index, 0); }

function draw_food(M) {
  M.wr(S.this_rooms_food_count, 0);
  create_food_list(M);
  M.bank(S.room_bank_config);
  const n = M.rd(S.this_rooms_food_count);
  for (let i = 0; i < n; i++) { M.bank(S.sprite_bank_config); draw_food_item2(M); }
}

function create_food_list(M) {
  M.bank(S.sprite_bank_config);
  const c = M.rd(S.room_number);
  for (let i = 0, ix = S.food_items; i < NFOOD; i++, ix += 8) {
    if (M.rd(ix + 1) !== c || M.rd(ix + 2)) continue;
    const n = M.rd(S.this_rooms_food_count);
    M.wr16(S.this_rooms_food_list + ((n << 1) & 0xff), ix);
    M.wr(S.this_rooms_food_count, n + 1);
    if (n + 1 >= S.max_food) return;
  }
}

module.exports = { init_food, replen_food, add_tombstone, check_food_collision, reset_food_collected, draw_food };
