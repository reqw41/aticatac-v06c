// player.asm: появление/исчезновение героя, жизни, столкновение с врагами и боссами. Вывод не моделируется.
'use strict';
const { S } = require('./core');
const snd = require('./sound');
const lazy = (m) => () => require(m);
const sprite = lazy('./sprite'), chicken = lazy('./chicken'), score = lazy('./score');

function init_player(M) {
  M.wr(S.anim_frames_table, M.rd(S.selected_player)); M.wr(S.anim_frames_table + 1, M.rd(S.selected_player + 1));
  M.wr(S.actual_player_height, M.rd(S.selected_player_height));
  M.wr(S.num_lives, 3);
  make_player_appear(M);
}

function make_player_appear(M) {
  M.wr(S.player_frame, S.default_frame);
  M.wr(S.player_x, 0x2c);
  M.wr(S.player_y, 0x53);
  M.wr(S.player_orientation, S.player_is_going_right);
  M.wr(S.player_growing, S.player_appearing);
  M.wr(S.current_player_height, 1);
  const a = (M.rd(S.actual_player_height) - 1) & 0xff;
  M.wr16(S.current_height_gfx_offset, a * 5);
  M.wr(S.health, S.max_health);
}

function make_player_disappear(M) {
  M.wr(S.player_growing, S.player_disappearing);
  M.wr(S.current_player_height, M.rd(S.actual_player_height));
  M.wr16(S.current_height_gfx_offset, 0);
  for (const s of [S.sprite1, S.sprite2, S.sprite3])
    if (M.rd(s + S.spr_state) !== S.state_dead) sprite().kill_sprite(M, s);
}

function decrease_lives(M) {
  const a = M.rd(S.num_lives);
  if (!a) { M.wr(S.game_over, S.game_finished); return; }
  M.wr(S.num_lives, a - 1);                       // remove_life — вывод
}

// -> 1, если задет обычный враг (iyh)
function player_vs_baddie(M, ix) {
  if (M.rd(ix + S.spr_state) !== S.state_active) return 0;
  const px = M.rd(S.player_x), py = M.rd(S.player_y);
  if (px >= ((M.rd(ix) + M.rd(ix + 5)) & 0xff)) return 0;
  if (((px + S.player_width) & 0xff) < M.rd(ix)) return 0;
  if (py >= ((M.rd(ix + 1) + M.rd(ix + 6)) & 0xff)) return 0;
  if (((py + M.rd(S.actual_player_height)) & 0xff) < M.rd(ix + 1)) return 0;
  if (M.rd(ix + 26)) { touching_boss(M, ix); return 0; }
  sprite().kill_sprite(M, ix);
  chicken().health_down(M);
  return 1;
}

const inPockets = (M, v) => M.rd(S.pocket1) === v || M.rd(S.pocket1 + 1) === v || M.rd(S.pocket1 + 2) === v;

function touching_boss(M, ix) {
  if (M.rd(S.room_number) === 0x55 && inPockets(M, S.wrench)) {
    sprite().kill_sprite(M, ix);
    M.wr(S.frank_dead, 1);
    score().add_to_score(M, 0x845);
    return;
  }
  if (M.rd(S.room_number) === M.rd(S.dracula_room) && inPockets(M, S.crucifix)) return;
  snd.play_sfx(M, S.sound_clock);
  chicken().health_decay(M);
}

function check_player_hit_baddie(M) {
  player_vs_baddie(M, S.boss);
  if (player_vs_baddie(M, S.sprite1)) return;
  if (player_vs_baddie(M, S.sprite2)) return;
  player_vs_baddie(M, S.sprite3);
}

module.exports = { init_player, make_player_appear, make_player_disappear, decrease_lives, check_player_hit_baddie };
