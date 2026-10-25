// sprite.asm: враги (sprite1..3) и босс — состояния, движение, рождение/смерть. Вывод не моделируется.
'use strict';
const { S } = require('./core');
const { random, neg, animate } = require('./util');
const snd = require('./sound');
const lazy = (m) => () => require(m);
const score = lazy('./score'), boss = lazy('./boss');

function update_sprite(M, ix) {
  const st = M.rd(ix + S.spr_state);
  if (st === S.state_dead) return is_dead(M, ix);
  if (st === S.state_arriving) return is_arriving(M, ix);
  if (st === S.state_dying) return is_dying(M, ix);
  if (M.rd(ix + S.spr_boss)) return boss().update_boss(M, ix);
  const cnt = (M.rd(ix + S.spr_counter) - 1) & 0xff;
  M.wr(ix + S.spr_counter, cnt);
  if (!cnt) return E.random_sprite_action(M, ix);
  if (!(M.rd(S.heartbeat) & 1)) return;
  bounce(M, ix + S.spr_x, ix + S.spr_xinc, S.min_x, S.max_x);
  bounce(M, ix + S.spr_y, ix + S.spr_yinc, S.min_y, S.max_y);
  animate(M, ix);
}

// pos += inc; вне [min, max] (min >= pos или max < pos) — inc = -inc, pos = граница
function bounce(M, pa, ia, mina, maxa) {
  const p = (M.rd(pa) + M.rd(ia)) & 0xff;
  M.wr(pa, p);
  let d = M.rd(mina);
  if (d < p) { d = M.rd(maxa); if (d >= p) return; }
  M.wr(ia, neg(M.rd(ia)));
  M.wr(pa, d);
}

function is_dead(M, ix) {
  if (M.rd(ix + S.spr_boss)) return;
  if (M.rd(S.player_growing)) return;
  const cnt = (M.rd(ix + S.spr_counter) - 1) & 0xff;
  M.wr(ix + S.spr_counter, cnt);
  if (cnt) return;
  M.wr(ix + S.spr_state, S.state_arriving);
  M.wr(ix + S.spr_counter, S.arrival_time);
  let e = M.rd(S.min_x);
  let c = (M.rd(S.max_x) - 6 - e) & 0xff;
  let a = random(M);
  for (let i = 0; i < 4 && a >= c; i++) a >>= 1;
  M.wr(ix + S.spr_x, (a + e) & 0xff);
  e = M.rd(S.min_y);
  c = (M.rd(S.max_y) - 24 - e) & 0xff;
  a = random(M);
  for (let i = 0; i < 3 && a >= c; i++) a >>= 1;
  M.wr(ix + S.spr_y, (a + e) & 0xff);
  init_sprite(M, ix, S.sprite_birth);
}

function init_sprite(M, ix, iy) {
  M.wr(ix + S.spr_frame, 0);
  M.wr(ix + S.spr_w, M.rd(iy));
  M.wr(ix + S.spr_h, M.rd(iy + 1));
  M.wr(ix + S.spr_fdom, M.rd(iy + 4));
  M.wr(ix + S.spr_alt, M.rd(iy + 2)); M.wr(ix + S.spr_alt + 1, M.rd(iy + 3));
  const g = (iy + 5) & 0xffff;
  M.wr(ix + S.spr_gfx, g & 0xff); M.wr(ix + S.spr_gfx + 1, g >> 8);
}

function is_arriving(M, ix) {
  const cnt = (M.rd(ix + S.spr_counter) - 1) & 0xff;
  M.wr(ix + S.spr_counter, cnt);
  if (cnt) return animate(M, ix);
  M.wr(ix + S.spr_state, S.state_active);
  const a = random(M) & 0x0f;
  const iy = M.rd16(S.sprite_info + 2 * a);
  E.random_sprite_action(M, ix);
  init_sprite(M, ix, iy);
}

function random_sprite_action(M, ix) {
  M.wr(ix + S.spr_counter, (M.ldar() & 0x3f) + 20);
  const a = random(M) & 7;
  M.wr(ix + S.spr_xinc, M.rd(S.sprite_direction_table + 2 * a));
  M.wr(ix + S.spr_yinc, M.rd(S.sprite_direction_table + 2 * a + 1));
}

function kill_sprite(M, ix) {
  M.wr(ix + S.spr_state, S.state_dying);
  M.wr(ix + S.spr_counter, S.dying_time);
  init_sprite(M, ix, S.sprite_death);
  let a = (M.rd(S.enemy_kill_sfx) + 1) & 0xff;
  if (a === S.sound_clock) a = S.sound_thunder_1;
  M.wr(S.enemy_kill_sfx, a);
  snd.play_sfx(M, a);
  score().add_to_score(M, 0x155);
}

function is_dying(M, ix) {
  const cnt = (M.rd(ix + S.spr_counter) - 1) & 0xff;
  M.wr(ix + S.spr_counter, cnt);
  if (cnt) return animate(M, ix);
  M.wr(ix + S.spr_state, S.state_dead);
  M.wr(ix + S.spr_counter, (random(M) & 0x0f) + 10);
}

function reset_sprites(M) {
  for (const s of [S.boss, S.sprite1, S.sprite2, S.sprite3]) M.wr(s + S.spr_state, S.state_dead);
  for (const s of [S.sprite1, S.sprite2, S.sprite3]) M.wr(s + S.spr_counter, (random(M) & 0x3f) + 5);
}

// поля вывода (адреса экрана и кадров для стирания) — не моделируются и не сверяются
const DRAW_FIELDS = [11, 12, 13, 14, 15, 16, 17, 18, 22, 23, 24, 25];

const E = module.exports = { update_sprite, init_sprite, kill_sprite, random_sprite_action, reset_sprites, DRAW_FIELDS };
