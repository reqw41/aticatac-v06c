// doors.asm: двери — начальная раскладка, проход (check_doors), автоматические двери, сетка столкновений.
// Байт состояния двери (ix+2): б7 закрыта, б6 автоматическая, б5..3 время, б2..0 счётчик.
'use strict';
const { S } = require('./core');
const { random } = require('./util');
const snd = require('./sound');
const lazy = (m) => () => require(m);
const state = lazy('./state');

const loops = (n) => n || 256;                 // djnz/dec с нулём — 256 оборотов

function init_doors(M) {
  M.bank(S.room_bank_config);
  let n = (S.end_room_bank_item_list - S.room_bank_item_list) >> 4;
  let ix = S.room_bank_item_list, iyl = 0;
  M.wr(S.random_seed, M.ldar());
  const set = (a, m) => M.wr(a, M.rd(a) | m), res = (a, m) => M.wr(a, M.rd(a) & ~m);
  for (; n > 0; n--, ix += 16) {
    if (!M.rd(ix + 7)) continue;
    set(ix + 2, 0x80); set(ix + 10, 0x80);
    const c = M.rd(ix);
    let auto = false;
    if (c === S.active_door_trapdoor) auto = true;
    else if (c >= S.active_door_big + 1) {
      if (c !== M.rd(S.magic_door)) { res(ix + 2, 0x40); res(ix + 10, 0x40); continue; }
    } else if (c === M.rd(ix + 8) && random(M) < 179) auto = true;
    if (!auto) {
      res(ix + 2, 0x80); res(ix + 10, 0x80); res(ix + 2, 0x40); res(ix + 10, 0x40);
      continue;
    }
    set(ix + 2, 0x40); set(ix + 10, 0x40);
    const a = (((random(M) & 7) << 3) | iyl | M.rd(ix + 2)) & 0xff;
    M.wr(ix + 2, a); M.wr(ix + 10, a);
    iyl = (iyl + 1) & 7;
  }
}

function check_doors(M) {
  const a = M.rd(S.collision_info);
  if (!a) return;
  if (a !== M.rd(S.collision_info + 1)) return;
  if (a !== M.rd(S.collision_info + 2) || a !== M.rd(S.collision_info + 3)) return;
  const ix = S.this_rooms_door_list + 8 * ((a - 1) & 0xff);
  if (M.rd(ix) === S.active_door_trapdoor) return trapdoor_collision(M, ix);
  const c = M.rd(S.keys_pressed) & 0x0f;
  if (!c) return;
  const hl = (M.rd16(ix + 3) + 5) & 0xffff;
  M.bank(S.room_bank_config);
  const v = (M.rd(hl) & 0xc0) | c;
  if (v === 0x42 || v === 0xc1 || v === 0x88 || v === 0x04) do_collision(M, ix, c);
}

function twinOffset(M, ix) { return M.rd(ix + 7) ? -8 : 8; }

function trapdoor_collision(M, ix) {
  const de = (M.rd16(ix + 3) + 2) & 0xffff;
  M.bank(S.room_bank_config);
  if (M.rd(de) & 0x80) return;
  const hl = (M.rd16(ix + 3) + twinOffset(M, ix) + 1) & 0xffff;
  M.wr(S.room_number, M.rd(hl));
  state().switch_game_state(M, S.state_falling);
}

function do_collision(M, ix, c) {
  M.wr(S.transition_keypress, c);
  let hl = (M.rd16(ix + 3) + 2) & 0xffff;
  M.wr(hl, M.rd(hl) & 0x7f);
  hl = (hl + twinOffset(M, ix)) & 0xffff;
  M.wr(hl, M.rd(hl) & 0x7f);
  hl = (hl - 2) & 0xffff;
  get_new_door_dimensions(M, hl);
  M.wr(S.last_room_number, M.rd(S.room_number));
  hl++;
  M.wr(S.room_number, M.rd(hl));
  M.wr(S.room_changed, 1);
  snd.play_sfx(M, S.sound_door);
  M.wr(S.screen_transition_in_progress, S.transition_time);
  hl += 2;
  const b = M.rd(hl) >> 1;
  const c2 = M.rd(hl + 1);
  const rot = M.rd(hl + 2) & 0xfe;
  M.wr(S.collision_info, 0);
  M.wr(S.collision_info + 2, 0);
  const w = M.rd(S.this_item_width), h = M.rd(S.this_item_height);
  if (rot === S.rotation_top) {
    M.wr(S.player_y, (c2 - 12) & 0xff);
    M.wr(S.player_x, (w + b - S.player_width + 1) & 0xff);
  } else if (rot === S.rotation_bottom) {
    M.wr(S.player_y, (c2 - h - S.average_player_height + 12) & 0xff);
    M.wr(S.player_x, (w + b - S.player_width + 1) & 0xff);
  } else if (rot === S.rotation_left) {
    M.wr(S.player_x, ((h >> 2) + b) & 0xff);
    M.wr(S.player_y, (c2 - ((w << 1) & 0xff) - (S.average_player_height >> 1)) & 0xff);
  } else {
    M.wr(S.player_x, (b - (S.player_width - 1) + 2) & 0xff);
    M.wr(S.player_y, (c2 - ((w << 1) & 0xff) - (S.average_player_height >> 1)) & 0xff);
  }
}

function get_new_door_dimensions(M, hl) {
  const t = M.rd(hl);
  M.bank(S.item_bank_config);
  const meta = M.rd16(S.item_bank_items + 2 * t);
  M.wr(S.this_item_width, M.rd(meta));
  M.wr(S.this_item_height, M.rd(meta + 1));
  M.bank(S.room_bank_config);
}

function update_doors(M) {
  const px = M.rd(S.player_x);
  if (M.rd(S.min_x) >= ((px + 1) & 0xff)) return;
  if (M.rd(S.max_x) < px) return;
  const py = M.rd(S.player_y);
  if (M.rd(S.min_y) >= py) return;
  if (M.rd(S.max_y) < py) return;
  let n = loops(M.rd(S.this_rooms_door_count));
  for (let ix = S.this_rooms_door_list, b = n; b > 0; b--, ix += 8) {
    const hl = (M.rd16(ix + 3) + 2) & 0xffff;
    const a = M.rd(hl);
    if (!(a & 0x40)) continue;
    const d = (a + 1) & 7;
    if (((a & 0x38) >> 3) !== d) { M.wr(hl, (a & 0xf8) | d); continue; }
    const c = (a & 0xf8) ^ 0x80;
    M.wr(hl, c);
    M.wr((hl + (M.rd(ix + 7) === 8 ? -8 : 8)) & 0xffff, c);
    const g = M.rd(ix) === S.active_door_trapdoor ? M.rd(ix) & 0x7f : c;
    update_collision_grid_for_door(M, ix, g, b);
    const item = M.rd16(ix + 3);
    if (M.rd(item) === S.active_door_trapdoor) return;   // решётка люка — только вывод
    M.wr16(S.door_to_toggle, item);
    return;                                               // jp draw_item
  }
}

function update_collision_grid_for_items(M) {
  let n = loops(M.rd(S.this_rooms_door_count));
  for (let ix = S.this_rooms_door_list, b = n; b > 0; b--, ix += 8) {
    let a = M.rd(ix);
    if (a === S.door_acg) {
      let closed = 0x80;
      if (M.rd(S.pocket3) === 2 && M.rd(S.pocket1 + 1) === 1 && M.rd(S.pocket1) === 0) closed = 0;
      update_collision_grid_for_door(M, ix, closed, b);
      for (let i = 0, p = S.collision_grid + 24 * 8 + 19; i < 8; i++, p += 24) M.wr(p, 0);
      continue;
    }
    const st = M.rd((M.rd16(ix + 3) + 2) & 0xffff);
    if (st & 0x40) continue;
    if (!(st & 0x80)) continue;
    if (a >= 16 || a < 7) continue;
    a &= ~4;
    const c = a === S.door_blue ? 3 : a === S.door_green ? 4 : a === S.door_red ? 5 : a === S.door_yellow ? 6 : 0;
    if (!c) continue;
    const key = M.rd(S.pocket1) === c || M.rd(S.pocket2) === c || M.rd(S.pocket3) === c;
    update_collision_grid_for_door(M, ix, key ? 0 : 0x80, b);
  }
}

// a: бит 7 — закрыта (0xFF в сетке), иначе номер двери (count - b + 1); b — счётчик цикла вызывающего
function update_collision_grid_for_door(M, ix, a, b) {
  const v = a & 0x80 ? 0xff : (M.rd(S.this_rooms_door_count) - b + 1) & 0xff;
  let hl = S.collision_grid + (M.rd(ix + 2) >> 3) * 24 + (M.rd(ix + 1) >> 2);
  let c = loops(M.rd(ix + 6) >> 3);
  for (; c > 0; c--, hl += 24) {
    const w = loops(M.rd(ix + 5) >> 1);
    for (let i = 0; i < w; i++) M.wr((hl + i) & 0xffff, v);
  }
}

module.exports = { init_doors, check_doors, update_doors, update_collision_grid_for_items,
  update_collision_grid_for_door, get_new_door_dimensions };
