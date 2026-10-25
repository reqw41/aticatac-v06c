// Реестр подпрограмм модели для теневой проверки (tools/shadow.js): имя метки CPC -> (M, регистры) -> выход.
// drawOnly — адреса, которые меняет только вывод (адреса экрана для стирания и т.п.): не сверяются.
'use strict';
const { S } = require('./core');
const pm = require('./playermove');
const sprite = require('./sprite');
const weapon = require('./weapon');
const boss = require('./boss');
const score = require('./score');

const R = {};
function reg(name, fn, out) { fn.out = out || []; R[name] = fn; }
const bc = (r) => r.b << 8 | r.c;

reg('move_player', (M) => { pm.move_player(M); });
reg('check_collision_squares', (M) => { pm.check_collision_squares(M); });
reg('check_corner_collision', (M, r) => pm.check_corner_collision(M, r.a, r.b), ['a', 'b']);
reg('update_sprite', (M, r) => { sprite.update_sprite(M, r.ix); });
reg('kill_sprite', (M, r) => { sprite.kill_sprite(M, r.ix); });
reg('reset_sprites', (M) => { sprite.reset_sprites(M); });
reg('fire_weapon', (M) => { weapon.fire_weapon(M); });
reg('move_weapon', (M) => { weapon.move_weapon(M); });
reg('draw_weapon', (M) => { weapon.draw_weapon(M); });
reg('check_weapon_hit', (M) => { weapon.check_weapon_hit(M); });
reg('add_to_score', (M, r) => { score.add_to_score(M, bc(r)); });
reg('init_boss', (M) => { boss.init_boss(M); });
reg('try_teleport_dracula', (M) => { boss.try_teleport_dracula(M); });

const drawOnly = new Set();
for (const s of [S.boss, S.sprite1, S.sprite2, S.sprite3]) for (const f of sprite.DRAW_FIELDS) drawOnly.add(s + f);
const SPR = S.sprite2 - S.sprite1;
for (const base of [S.old_room_sprites, S.temp_sprite_data])
  for (let k = 0; k < 3; k++) for (const f of sprite.DRAW_FIELDS) drawOnly.add(base + k * SPR + f);
for (const n of ['save_weapon_address_c0', 'save_weapon_pointer_c0', 'save_weapon_address_80', 'save_weapon_pointer_80'])
  { drawOnly.add(S[n]); drawOnly.add(S[n] + 1); }

module.exports = { routines: R, drawOnly };
