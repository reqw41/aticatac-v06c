// game.asm: шаг игры (game_tasks) и переход героя (появление/исчезновение); falling.asm: падение.
// Вывод не моделируется; смена банков в процедурах вывода повторена там, где она влияет на логику.
'use strict';
const { S } = require('./core');
const snd = require('./sound');
const pm = require('./playermove'), weapon = require('./weapon'), sprite = require('./sprite'),
  player = require('./player'), chicken = require('./chicken'), food = require('./food'),
  doors = require('./doors'), coll = require('./collectables'), clock = require('./clock'),
  room = require('./room'), state = require('./state');

const draw_item = (M) => M.bank(S.item_bank_config);       // вывод предмета: оставляет банк предметов
const draw_food_item2 = (M) => M.bank(S.room_bank_config);

function game_tasks(M) {
  if (M.rd(S.game_paused)) return game_is_paused(M);
  M.bank(S.item_bank_config);
  if (M.rd(S.room_changed)) { room.draw_room(M); return; }
  if (M.rd(S.tell_time)) clock.show_clock(M);
  chicken.update_chicken(M);
  const dp = M.rd(S.do_pockets);
  if (dp) { M.wr(S.do_pockets, dp - 1); M.bank(S.room_bank_config); }   // draw_pockets
  if (M.rd(S.erase_food_with_index + 1)) {
    M.bank(S.sprite_bank_config); draw_food_item2(M); M.wr16(S.erase_food_with_index, 0);
  }
  if (M.rd(S.draw_tombstone_with_index + 1)) {
    M.bank(S.sprite_bank_config); draw_food_item2(M); M.wr16(S.draw_tombstone_with_index, 0);
  }
  M.bank(S.sprite_bank_config);
  if (M.rd(S.player_growing)) { continue_player_transition(M); }
  else {
    if (M.rd(S.heartbeat) === 31) chicken.health_decay(M);
    M.bank(S.sprite_bank_config);
    M.bank(S.room_bank_config);
    pm.move_player(M);
    doors.check_doors(M);
  }
  // skip_some_others
  M.bank(S.sprite_bank_config);
  weapon.move_weapon(M);
  weapon.draw_weapon(M);
  M.bank(S.baddie_bank_config);
  for (const s of [S.boss, S.sprite1, S.sprite2, S.sprite3]) sprite.update_sprite(M, s);
  weapon.check_weapon_hit(M);
  player.check_player_hit_baddie(M);
  const fc = M.rd(S.this_rooms_food_count);
  if (fc) food.check_food_collision(M, fc);
  M.bank(S.room_bank_config);
  const dt = M.rd16(S.door_to_toggle);
  if (dt) { M.wr16(S.door_to_toggle, 0); draw_item(M); }
  if (M.rd(S.heartbeat) === 25) doors.update_doors(M);
  if (M.rd(S.keys_pressed) & (1 << S.player_fire2_bit)) coll.pickup_tapped(M);
  M.bank(S.item_bank_config);
  if (!M.rd(S.game_over)) {
    if (!(M.rd(S.keyboard_state + 5) & 0x10)) M.wr(S.game_paused, 1);
    if (M.rd(S.keyboard_state + 4) & 0x40) return;
  }
  state.switch_game_state(M, S.state_end);
}

function game_is_paused(M) {
  M.bank(S.sprite_bank_config);
  M.bank(S.baddie_bank_config);
  if (M.rd(S.keys_pressed)) M.wr(S.game_paused, 0);
}

function continue_player_transition(M) {
  const hb = () => M.rd(S.heartbeat);
  if (M.rd(S.player_growing) === S.player_disappearing) {
    if (M.rd(S.current_player_height) === 1) {
      food.add_tombstone(M);
      player.make_player_appear(M);
    } else if ((hb() & 3) === 3) {
      const a = (M.rd(S.current_player_height) - 1) & 0xff;
      M.wr(S.current_player_height, a);
      if (a === 16) snd.play_sfx(M, S.sound_p_death);
      M.wr16(S.current_height_gfx_offset, (M.rd16(S.current_height_gfx_offset) + 5) & 0xffff);
    }
  } else if ((hb() & 3) === 3) {
    const b = M.rd(S.current_player_height);
    if (M.rd(S.actual_player_height) === b) M.wr(S.player_growing, 0);
    else {
      const a = (b + 1) & 0xff;
      M.wr(S.current_player_height, a);
      if (a === 4) snd.play_sfx(M, S.sound_p_appear);
      M.wr16(S.current_height_gfx_offset, (M.rd16(S.current_height_gfx_offset) - 5) & 0xffff);
    }
  }
  M.bank(S.room_bank_config);
}

// falling.asm: туннели (вывод) по fall_index; конец падения — новая комната и снова game_tasks
function falling_tasks(M) {
  // erase_previous_tunnels / draw_new_tunnels: логика — fall_index, still_falling, this_index, save_fall_data
  M.wr(S.tunnel_pen, 0);
  let hl = S.save_fall_data;
  if (M.rd(S.hidden_screen_base_address) === 0xc0) hl++;
  M.wr16(S.this_index, hl);
  M.wr(S.tunnel_pen, 0xf3);
  const fi = (M.rd(S.fall_index) + 1) & 0xff;
  if (fi === ((S.end_falling_sequence - S.falling_sequence) * 2 & 0xff)) M.wr(S.still_falling, 0);
  else {
    M.wr(S.fall_index, fi);
    M.wr(M.rd16(S.this_index), M.rd(S.falling_sequence + (fi >> 1)));
  }
  if (M.rd(S.tell_time)) clock.show_clock(M);
  if (M.rd(S.still_falling)) return;
  room.draw_room(M);
  state.setTask(M, S.game_tasks);
  M.wr16(S.current_interrupts, S.game_interrupts);
}

module.exports = { game_tasks, falling_tasks, continue_player_transition };
