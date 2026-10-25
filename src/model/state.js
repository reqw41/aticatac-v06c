// state_manager.asm: смена состояния игры (задача главного цикла — самомодифицируемый call).
'use strict';
const { S } = require('./core');
const { notModeled } = require('./util');
const lazy = (m) => () => require(m);
const sprite = lazy('./sprite'), weapon = lazy('./weapon'), snd = lazy('./sound');

function setTask(M, a) { M.wr(S.current_game_state + 1, a & 0xff); M.wr(S.current_game_state + 2, a >> 8); }

function switch_game_state(M, b) {
  if (b === S.state_falling) return select_falling(M);
  notModeled('switch_game_state ' + b);
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

module.exports = { switch_game_state, setTask };
