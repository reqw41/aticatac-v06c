// boss.asm: боссы (Франкенштейн, Дракула, мумия, горбун, дьявол) — выбор по комнате и движение.
'use strict';
const { S } = require('./core');
const { random, neg, animate, notModeled } = require('./util');
const lazy = (m) => () => require(m);
const sprite = lazy('./sprite');

function init_boss(M) {
  const a = M.rd(S.room_number);
  if (a === S.room_frankenstein) return init_frank(M);
  if (a === M.rd(S.mummy_room)) return init_mummy(M);
  if (a === S.room_hunchback) return init_hunchback(M);
  if (a === S.room_devil) return init_devil(M);
  if (a === M.rd(S.dracula_room)) return init_dracula(M);
  M.wr(S.boss + S.spr_state, S.state_dead);
}

function common_boss_init(M, iy) {
  const ix = S.boss;
  M.wr(ix + S.spr_state, S.state_active);
  M.wr(ix + S.spr_x, M.rd(iy + 14));
  M.wr(ix + S.spr_y, M.rd(iy + 15));
  sprite().init_sprite(M, ix, iy);
}
const setMover = (M, a) => { M.wr(S.boss_mover, a & 0xff); M.wr(S.boss_mover + 1, a >> 8); };

function init_frank(M) {
  if (M.rd(S.frank_dead)) return;
  setMover(M, S.move_devil_and_frank);
  common_boss_init(M, S.boss_frankie);
}
function init_dracula(M) { setMover(M, S.move_dracula); common_boss_init(M, S.boss_dracula); }
function init_mummy(M) {
  setMover(M, S.move_mummy);
  common_boss_init(M, S.boss_mummy);
  if (M.rd(S.mummy_angry)) return;
  M.wr(S.mummy_inc, 1);
  M.wr(S.mummy_count, S.mummy_count_max >> 1);
}
function init_hunchback(M) { setMover(M, S.move_hunchback); common_boss_init(M, S.boss_hunchback); }
function init_devil(M) { setMover(M, S.move_devil_and_frank); M.wr(S.boss_timer, 0); common_boss_init(M, S.boss_devil); }

function get_room_type(M, a) { return M.rd(S.room_bank_roominfo + a + 1); }

function update_boss(M, ix) {
  const m = M.rd16(S.boss_mover);
  if (m === S.move_dracula) return move_dracula(M, ix);
  if (m === S.move_mummy) return move_mummy(M, ix);
  if (m === S.move_hunchback) return move_hunchback(M, ix);
  if (m === S.move_devil_and_frank) return move_devil_and_frank(M, ix);
  if (m === S.move_frankie) return animate(M, ix);
  notModeled('boss_mover ' + m.toString(16));
}

// направление к цели: 0 — совпало, -1 — цель меньше, 1 — больше
const toward = (target, pos) => (target === pos ? 0 : target < pos ? 0xff : 1);

function move_dracula(M, ix) {
  const t = (M.rd(S.dracula_timer) + 1) & 0xff;
  M.wr(S.dracula_timer, t);
  if (t !== 2) return;
  M.wr(S.dracula_timer, 0);
  if (M.rd(S.player_growing)) return within_bounds(M, ix, 0xff, 1);
  const cr = S.crucifix;
  if (cr === M.rd(S.pocket1 + 1) || cr === M.rd(S.pocket1) || M.rd(S.pocket3) === cr) {
    const d = M.rd(S.player_x) < M.rd(ix + S.spr_x) ? 1 : 0xff;
    const e = M.rd(S.player_y) < M.rd(ix + S.spr_y) ? 1 : 0xff;
    return within_bounds(M, ix, d, e);
  }
  normal_move_towards(M, ix);
}

function move_mummy(M, ix) {
  if (!(M.rd(S.heartbeat) & 1)) return;
  if (M.rd(S.mummy_angry)) return mummy_is_mad(M, ix);
  if (M.rd(S.col_leaf) === M.rd(S.room_number)) { M.wr(S.mummy_angry, 1); return; }
  const b = M.rd(S.mummy_inc);
  M.wr(ix + S.spr_x, (M.rd(ix + S.spr_x) + b) & 0xff);
  M.wr(ix + S.spr_y, (M.rd(ix + S.spr_y) + b) & 0xff);
  const c = (M.rd(S.mummy_count) + 1) & 0xff;
  M.wr(S.mummy_count, c);
  if (c === S.mummy_count_max) { M.wr(S.mummy_inc, neg(b)); M.wr(S.mummy_count, 0); }
  animate(M, ix);
}

function mummy_is_mad(M, ix) {
  if (M.rd(S.col_leaf) !== M.rd(S.room_number)) return devil_frank_mummy(M, ix);
  const d = toward((M.rd(S.col_leaf + 3) << 1) & 0xff, M.rd(ix + S.spr_x));
  const e = toward(M.rd(S.col_leaf + 4), M.rd(ix + S.spr_y));
  M.wr(ix + S.spr_x, (M.rd(ix + S.spr_x) + d) & 0xff);
  M.wr(ix + S.spr_y, (M.rd(ix + S.spr_y) + e) & 0xff);
  animate(M, ix);
  if (d | e) return;
  M.bank(S.room_bank_config);
  M.wr(S.col_leaf, 0x6b);                  // лист съеден — в другую комнату
  M.bank(S.baddie_bank_config);
}

function move_hunchback(M, ix) {
  const t = (M.rd(S.boss_timer) + 1) & 3;
  M.wr(S.boss_timer, t);
  if (t) return;
  let iy = 0, b = 0x2c, c = 0x20;
  if (!M.rd(S.player_growing)) {
    const room = M.rd(S.room_number);
    iy = S.col_money;
    let found = false;
    for (let n = 10; n > 0; n--, iy += 8) {
      if (n === 5 || n === 8) continue;
      if (M.rd(iy) === room) { found = true; break; }
    }
    if (!found) return;
    b = (M.rd(iy + 3) << 1) & 0xff;
    c = M.rd(iy + 4);
  }
  const d = toward(b, M.rd(ix + S.spr_x));
  const e = toward(c, M.rd(ix + S.spr_y));
  const x = (M.rd(ix + S.spr_x) + d) & 0xff;
  M.wr(ix + S.spr_x, x);
  const y = (M.rd(ix + S.spr_y) + e) & 0xff;
  M.wr(ix + S.spr_y, y);
  M.wr(S.boss_hunchback + 14, x);
  M.wr(S.boss_hunchback + 15, y);
  if (d | e) return animate(M, ix);
  if (!iy) return;
  M.bank(S.room_bank_config);
  M.wr(iy, 0xfe);                          // предмет унесён
  M.bank(S.baddie_bank_config);
}

function move_devil_and_frank(M, ix) {
  const t = (M.rd(S.boss_timer) + 1) & 3;
  M.wr(S.boss_timer, t);
  if (t) return;
  devil_frank_mummy(M, ix);
}

function devil_frank_mummy(M, ix) {
  if (M.rd(S.player_growing)) return within_bounds(M, ix, 0xff, 1);
  normal_move_towards(M, ix);
}

function normal_move_towards(M, ix) {
  const d = toward(M.rd(S.player_x), M.rd(ix + S.spr_x));
  const e = toward(M.rd(S.player_y), M.rd(ix + S.spr_y));
  within_bounds(M, ix, d, e);
}

function within_bounds(M, ix, d, e) {
  let c = M.rd(S.min_x), b = M.rd(S.min_x + 1);
  let a = (M.rd(ix + S.spr_x) + d) & 0xff;
  if (!(a < c) && a < b) M.wr(ix + S.spr_x, a);
  c = M.rd(S.min_y); b = M.rd(S.min_y + 1);
  a = (M.rd(ix + S.spr_y) + e) & 0xff;
  if (!(a < c) && a < b) M.wr(ix + S.spr_y, a);
  animate(M, ix);
}

function try_teleport_dracula(M) {
  const a = random(M) & 0x7f;
  if (!a) return;
  if (get_room_type(M, a) === 3) return;
  M.wr(S.dracula_room, a);
}

module.exports = { init_boss, update_boss, try_teleport_dracula, get_room_type };
