// room.asm: смена комнаты (draw_room без вывода) — посещение, размеры, сетка столкновений, враги
// старой/новой комнаты, босс, оружие, еда. Вывод (контур, предметы, копия экрана) не моделируется.
'use strict';
const { S } = require('./core');
const lazy = (m) => () => require(m);
const items = lazy('./items'), food = lazy('./food'), doors = lazy('./doors'), boss = lazy('./boss'),
  sprite = lazy('./sprite'), weapon = lazy('./weapon');

const SPR_LEN = S.sprite_end - S.sprite1;
const loops = (n) => n || 256;

function copy(M, from, to, n) { for (let i = 0; i < n; i++) M.wr(to + i, M.rd(from + i)); }

function draw_room(M) {
  M.bank(S.room_bank_config);
  draw_outline(M);
  items().draw_items(M);
  M.bank(S.room_bank_config);
  food().draw_food(M);
  M.bank(S.item_bank_config);
  calc_room_dimensions(M);
  M.bank(S.room_bank_config);
  calculate_collision_grid(M);
  doors().update_collision_grid_for_items(M);
  boss().try_teleport_dracula(M);
  food().replen_food(M);
  M.wr(S.room_changed, 0);
  copy(M, S.sprite1, S.temp_sprite_data, SPR_LEN);
  if (M.rd(S.room_number) === M.rd(S.saved_room_number)) copy(M, S.old_room_sprites, S.sprite1, SPR_LEN);
  else sprite().reset_sprites(M);
  copy(M, S.temp_sprite_data, S.old_room_sprites, SPR_LEN);
  M.wr(S.saved_room_number, M.rd(S.last_room_number));
  M.wr(S.random_seed, M.ldar());
  M.wr16(S.door_to_toggle, 0);
  boss().init_boss(M);
  weapon().reset_weapon(M);
  food().reset_food_collected(M);
  if (M.rd(S.room_number) === S.end_room) M.wr(S.game_over, S.game_completed);
}

// логика draw_outline: отметка «посещена», тип и размер комнаты, указатель вершин
function draw_outline(M) {
  const ri = S.room_bank_roominfo + 2 * M.rd(S.room_number);
  M.wr(ri, M.rd(ri) | 0x80);
  const typ = M.rd(ri + 1);
  M.wr(S.room_type, typ);
  const t = S.room_bank_roomtypes + 6 * typ;
  M.wr(S.room_size, M.rd(t + 1)); M.wr(S.room_size + 1, M.rd(t));
  M.wr(S.point_address, M.rd(t + 2)); M.wr(S.point_address + 1, M.rd(t + 3));
}

function calc_room_dimensions(M) {
  const h = M.rd(S.room_size + 1) >> 1, l = M.rd(S.room_size);
  M.wr(S.min_x, (0x30 - h - 4) & 0xff);
  M.wr(S.max_x, (0x30 + h - 4) & 0xff);
  M.wr(S.min_y, (0x60 - l - 9) & 0xff);
  M.wr(S.max_y, (0x60 + l - 12) & 0xff);
}

function calculate_collision_grid(M) {
  const N = S.collision_grid_size;
  for (let i = 0; i < N * N; i++) M.wr(S.collision_grid + i, 0xff);
  block_items(M);
  block_room(M);
}

function block_items(M) {
  const n = M.rd(S.this_rooms_door_count);
  for (let b = loops(n), ix = S.this_rooms_door_list; b > 0; b--, ix += 8) {
    const hl = S.collision_grid + (M.rd(ix + 2) >> 3) * 24 + (M.rd(ix + 1) >> 2);
    M.wr(S.this_doors_index, (n - b + 1) & 0xff);
    block_out_item(M, ix, hl);
  }
}

function block_out_item(M, ix, hl) {
  const de = M.rd16(ix + 3);
  if (M.rd(de) !== S.item_table && (M.rd((de + 2) & 0xffff) & 0x80)) M.wr(S.this_doors_index, 0xff);
  for (let c = loops(M.rd(ix + 6) >> 3); c > 0; c--, hl += 24) {
    let b = M.rd(ix + 5) >> 1;
    if (M.rd(ix) === S.item_clock) b = (b - 1) & 0xff;
    const v = M.rd(S.this_doors_index);
    for (let i = 0; i < loops(b); i++) M.wr((hl + i) & 0xffff, v);
  }
}

function get_type_for_collision_index(M, a) {
  return M.rd((S.this_rooms_door_list + ((a - 1) & 0xff) * 8) & 0xffff);
}

function block_room(M) {
  const N = S.collision_grid_size;
  let hl = S.collision_grid;
  for (let b = 0; b < N; b++) for (let c = 0; c < N; c++, hl++) {
    if ((M.rd(S.min_y) >> 3) >= b) continue;
    if (((M.rd(S.max_y) >> 3) + 2) < b) continue;
    if ((((M.rd(S.min_x) >> 2) - 1) & 0xff) >= c) continue;
    if (((M.rd(S.max_x) >> 2) + 1) < c) continue;
    const t = get_type_for_collision_index(M, M.rd(hl));
    if (t === S.active_door_trapdoor) continue;
    M.wr(hl, t === S.item_table ? 0xff : 0);
  }
}

module.exports = { draw_room, calc_room_dimensions, calculate_collision_grid };
