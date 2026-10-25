// state_manager.asm: смена состояния игры (задача главного цикла — самомодифицируемый call).
'use strict';
const { S } = require('./core');
const { notModeled } = require('./util');
const lazy = (m) => () => require(m);
const sprite = lazy('./sprite'), weapon = lazy('./weapon'), snd = lazy('./sound'), player = lazy('./player'),
  chicken = lazy('./chicken'), food = lazy('./food'), doors = lazy('./doors'), coll = lazy('./collectables'),
  score = lazy('./score'), clock = lazy('./clock');

function setTask(M, a) { M.wr(S.current_game_state + 1, a & 0xff); M.wr(S.current_game_state + 2, a >> 8); }

function switch_game_state(M, b) {
  if (b === S.state_falling) return select_falling(M);
  if (b === S.state_game) return select_game(M);
  if (b === S.state_end) return select_end(M);
  notModeled('switch_game_state ' + b);
}

// новая игра (state_manager.asm select_game, без вывода)
function select_game(M) {
  setTask(M, S.game_tasks);
  M.wr16(S.current_interrupts, S.game_interrupts);
  for (const n of ['room_number', 'player_orientation', 'game_over', 'heartbeat', 'frank_dead', 'mummy_angry', 'game_paused'])
    M.wr(S[n], 0);
  M.wr(S.room_changed, 1);
  M.wr(S.saved_room_number, 1);
  player().init_player(M);
  chicken().init_health(M);
  food().init_food(M);
  doors().init_doors(M);
  coll().init_collectables(M);
  score().init_score(M);
  M.bank(S.sprite_bank_config); M.bank(S.item_bank_config);      // draw_panel
  M.wr16(S.font_type, (S.font_0 - 256) & 0xffff);
  clock().reset_clock(M);
  M.bank(S.room_bank_config);
  const n = ((S.end_room_bank - S.room_bank_roominfo) >> 1) & 0xff;
  for (let i = 0, hl = S.room_bank_roominfo; i < (n || 256); i++, hl += 2) M.wr(hl, M.rd(hl) & 0x7f);
  M.bank(S.item_bank_config);
  score().add_to_score(M, 0);
  M.wr(S.boss_hunchback + 14, 44);
  M.wr(S.boss_hunchback + 15, 32);
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

module.exports = { switch_game_state, setTask, end_tasks, select_game };
