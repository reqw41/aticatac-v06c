// weapon.asm: выстрел, полёт и отскоки оружия, попадание по врагам. Вывод не моделируется,
// кроме last_drawn_weapon_frame (его читает check_weapon_hit).
'use strict';
const { S } = require('./core');
const { neg } = require('./util');
const snd = require('./sound');
const lazy = (m) => () => require(m);
const sprite = lazy('./sprite');

function draw_weapon(M) {
  if (!M.rd(S.weapon_active)) return;
  const f = (M.rd(S.weapon_frame) >> 2) * 2;
  const p = M.rd16((M.rd16(S.weapon_type) + f) & 0xffff);
  M.wr(S.last_drawn_weapon_frame, p & 0xff); M.wr(S.last_drawn_weapon_frame + 1, p >> 8);
}

function reset_weapon(M) { M.wr(S.weapon_active, 0); }

function fire_weapon(M) {
  if (M.rd(S.weapon_active)) return;
  const fd = M.rd(S.fire_delay);
  if (fd) { M.wr(S.fire_delay, fd - 1); return; }
  snd.play_sfx(M, S.sound_spell);
  M.wr(S.weapon_active, S.fire_decay);
  M.wr(S.weapon_x, M.rd(S.player_x));
  M.wr(S.weapon_y, M.rd(S.player_y));
  const a = M.rd(S.fire_direction);
  let d = 0, e = 0;
  if (a & (1 << S.player_left_bit)) d = neg(S.fire_horizontal_speed);
  if (a & (1 << S.player_right_bit)) d = S.fire_horizontal_speed;
  if (a & (1 << S.player_down_bit)) e = S.fire_vertical_speed;
  if (a & (1 << S.player_up_bit)) e = neg(S.fire_vertical_speed);
  if (!(d | e)) d = S.fire_horizontal_speed;
  M.wr(S.weapon_x_inc, d);
  M.wr(S.weapon_y_inc, e);
}

function move_weapon(M) {
  let a = M.rd(S.weapon_active);
  if (!a) return;
  a = (a - 1) & 0xff;
  M.wr(S.weapon_active, a);
  if (!a) M.wr(S.fire_delay, 2);
  let fr;
  if (M.rd(S.weapon_rotates)) {
    const xi = M.rd(S.weapon_x_inc), yi = M.rd(S.weapon_y_inc);
    if (!xi) fr = yi === S.fire_vertical_speed ? 3 * 4 : 7 * 4;
    else if (xi === S.fire_horizontal_speed) fr = !yi ? 5 * 4 : yi === S.fire_vertical_speed ? 4 * 4 : 6 * 4;
    else fr = !yi ? 1 * 4 : yi === S.fire_vertical_speed ? 2 * 4 : 0;
  } else fr = (M.rd(S.weapon_frame) + 1) & 0x1f;
  M.wr(S.weapon_frame, fr);
  const b = (M.rd(S.weapon_x) + M.rd(S.weapon_x_inc)) & 0xff;
  M.wr(S.weapon_x, b);
  const c = (M.rd(S.weapon_y) + M.rd(S.weapon_y_inc)) & 0xff;
  M.wr(S.weapon_y, c);
  let d = M.rd(S.min_x);
  let bx = d >= b;
  if (!bx) { d = M.rd(S.max_x); bx = d < b; }
  if (bx) {
    const xi = neg(M.rd(S.weapon_x_inc));
    M.wr(S.weapon_x_inc, xi);
    M.wr(S.weapon_x, d);
    if (xi) snd.play_sfx(M, S.sound_spell_bounce);
  }
  d = M.rd(S.min_y);
  if (d < c) { d = M.rd(S.max_y); if (d >= c) return; }
  M.wr(S.weapon_y_inc, neg(M.rd(S.weapon_y_inc)));
  M.wr(S.weapon_y, d);
  snd.play_sfx(M, S.sound_spell_bounce);
}

function check_weapon_hit(M) {
  const ix = M.rd16(S.last_drawn_weapon_frame);
  const h = (M.rd(S.weapon_x) + M.rd(ix + 2)) & 0xff;
  const l = (M.rd(S.weapon_y) + M.rd(ix + 3)) & 0xff;
  const d = M.rd(ix), e = M.rd(ix + 1);
  for (const s of [S.sprite1, S.sprite2, S.sprite3]) check_weapon_hitting_sprite(M, s, h, l, d, e);
}

function axisMiss(M, pos, size, objPos, objSize) {
  const c = (pos + (size >> 1)) & 0xff;
  let b = M.rd(objSize) >> 1;
  let a = (M.rd(objPos) + b - c) & 0xff;
  if (a & 0x80) a = neg(a);
  b = ((b << 1) - 1) & 0xff;
  return a >= b;
}

function check_weapon_hitting_sprite(M, ix, h, l, d, e) {
  if (!M.rd(S.weapon_active)) return;
  if (M.rd(ix + S.spr_state) !== S.state_active) return;
  if (axisMiss(M, h, d, ix + 0, ix + 5)) return;
  if (axisMiss(M, l, e, ix + 1, ix + 6)) return;
  sprite().kill_sprite(M, ix);
  M.wr(S.weapon_active, 1);
}

module.exports = { draw_weapon, reset_weapon, fire_weapon, move_weapon, check_weapon_hit };
