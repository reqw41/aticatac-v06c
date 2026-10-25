// playermove.asm: движение героя по клавишам, столкновения с сеткой комнаты, кадр анимации.
'use strict';
const { S } = require('./core');
const snd = require('./sound');
const lazy = (m) => () => require(m);
const weapon = lazy('./weapon');

function move_player(M) {
  let c = M.rd(S.keys_pressed);
  const t = M.rd(S.screen_transition_in_progress);
  if (t) {
    M.wr(S.screen_transition_in_progress, t - 1);
    c = M.rd(S.transition_keypress);
    M.wr(S.keys_pressed, c);
  }
  M.wr(S.updated_x, M.rd(S.player_x));
  if (c & (1 << S.player_up_bit)) move_vert(M, S.player_is_going_up, -S.player_vert_speed);
  if (c & (1 << S.player_down_bit)) move_vert(M, S.player_is_going_down, S.player_vert_speed);
  M.wr(S.updated_y, M.rd(S.player_y));
  if (c & (1 << S.player_left_bit)) move_horiz(M, S.player_is_going_left, -S.player_horiz_speed);
  if (c & (1 << S.player_right_bit)) move_horiz(M, S.player_is_going_right, S.player_horiz_speed);
  if (c & (1 << S.player_fire1_bit)) weapon().fire_weapon(M);
  E.check_collision_squares(M);
  if (!M.rd(S.screen_transition_in_progress) && !(M.rd(S.keys_pressed) & 0x0f)) {
    M.wr(S.player_frame, S.default_frame);
    return;
  }
  const f = (M.rd(S.player_frame) + 1) & 0x0f;
  M.wr(S.player_frame, f);
  if (f === S.player_step_frame1 || f === S.player_step_frame2) snd.play_lowpriority_sfx(M, S.sound_steps);
}

function move_vert(M, orient, dy) {
  M.wr(S.player_orientation, orient);
  const y = (M.rd(S.player_y) + dy) & 0xff;
  M.wr(S.updated_y, y);
  if (E.check_collision(M)) return;
  M.wr(S.player_y, M.rd(S.updated_y));
}

function move_horiz(M, orient, dx) {
  M.wr(S.player_orientation, orient);
  const x = (M.rd(S.player_x) + dx) & 0xff;
  M.wr(S.updated_x, x);
  if (E.check_collision(M)) return;
  M.wr(S.player_x, M.rd(S.updated_x));
}

// -> 0 / 1 (A на выходе)
function check_collision(M) {
  const ux = () => M.rd(S.updated_x), uy = () => M.rd(S.updated_y);
  const h = () => M.rd(S.actual_player_height);
  const pts = [
    () => [ux(), uy()], () => [(ux() + 3) & 0xff, uy()], () => [(ux() + S.player_width + 2) & 0xff, uy()],
    () => [ux(), (uy() + h()) & 0xff], () => [(ux() + 3) & 0xff, (uy() + h()) & 0xff],
    () => [(ux() + S.player_width + 2) & 0xff, (uy() + h()) & 0xff],
  ];
  for (const p of pts) { const [x, y] = p(); if (E.check_corner_collision(M, y, x).b) return 1; }
  return 0;
}

function check_collision_squares(M) {
  const px = () => M.rd(S.player_x), py = () => M.rd(S.player_y), h = () => M.rd(S.actual_player_height);
  M.wr(S.collision_info + 0, E.check_corner_collision(M, py(), px()).a);
  M.wr(S.collision_info + 1, E.check_corner_collision(M, py(), (px() + S.player_width + 2) & 0xff).a);
  M.wr(S.collision_info + 2, E.check_corner_collision(M, (py() + h()) & 0xff, px()).a);
  M.wr(S.collision_info + 3, E.check_corner_collision(M, (py() + h()) & 0xff, (px() + S.player_width + 2) & 0xff).a);
}

// a = y, b = x -> { a: клетка, b: 1 если 0xFF }
function check_corner_collision(M, y, x) {
  const row = M.rd16(S.collision_rows + 2 * (y >> 3));
  const v = M.rd((row + (x >> 2)) & 0xffff);
  return { a: v, b: v === 0xff ? 1 : 0 };
}

const E = module.exports = { move_player, check_collision, check_collision_squares, check_corner_collision };
// внутренние вызовы — через E, чтобы сверка (tools/lock80.js) могла их перехватить
