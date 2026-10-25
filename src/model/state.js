// state_manager.asm: смена состояния игры (задача главного цикла — самомодифицируемый call).
'use strict';
const { S } = require('./core');
const { notModeled } = require('./util');
const lazy = (m) => () => require(m);
const sprite = lazy('./sprite'), weapon = lazy('./weapon'), snd = lazy('./sound');

function setTask(M, a) { M.wr(S.current_game_state + 1, a & 0xff); M.wr(S.current_game_state + 2, a >> 8); }

function switch_game_state(M, b) {
  if (b === S.state_falling) return select_falling(M);
  if (b === S.state_end) return select_end(M);
  notModeled('switch_game_state ' + b);
}

// конец игры: экран итогов (endgame.asm init_endgame — без вывода и звука)
function select_end(M) {
  setTask(M, S.end_tasks);
  M.wr16(S.current_interrupts, S.end_game_interrupts);
  if (M.rd(S.game_over) === S.game_completed) M.bank(S.sprite_bank_config);   // erase_player
  M.wr(S.end_key_delay, 100);
  M.bank(S.room_bank_config);
  M.wr16(S.font_type, S.font_data_mode0);
  let a = 0;
  const n = ((S.end_room_bank - S.room_bank_roominfo) >> 1) & 0xff;
  for (let i = 0, hl = S.room_bank_roominfo; i < (n || 256); i++, hl += 2) if (M.rd(hl) & 0x80) a = (a + 1) & 0xff;
  const ix = S.game_over_percentage_text;
  if (a >= S.end_room) { M.wr(ix + 11, 0x31); M.wr(ix + 12, 0x30); M.wr(ix + 13, 0x30); }
  else {
    M.wr(ix + 13, 0x20);
    const v = M.rd(S.percentage_lookup - 1 + a);
    M.wr(ix + 11, (v >> 4) + 0x30);
    M.wr(ix + 12, (v & 0x0f) + 0x30);
  }
  M.bank(S.sound_bank_config);                     // init_sound_system
  M.bank(S.room_bank_config);
  for (let i = 0; i < 6; i++) M.wr(S.game_over_time_text + 11 + i, M.rd(S.game_time + i));
  for (let i = 0; i < 6; i++) M.wr(S.game_over_score_text + 11 + i, M.rd(S.score_text + 3 + i));
}

function end_tasks(M) {
  const d = M.rd(S.end_key_delay);
  if (d) { M.wr(S.end_key_delay, d - 1); return; }
  if (!M.rd(S.keys_pressed)) return;
  notModeled('переход в меню');
}

function select_falling(M) {
  setTask(M, S.falling_tasks);
  M.wr16(S.current_interrupts, S.falling_interrupts);
  sprite().reset_sprites(M);
  weapon().reset_weapon(M);
  M.wr(S.save_fall_data, 0); M.wr(S.save_fall_data + 1, 0);
  M.wr(S.still_falling, 1);
  M.wr(S.fall_index, 0xff);
  snd().play_sfx(M, S.sound_p_fall);
}

module.exports = { switch_game_state, setTask, end_tasks };
