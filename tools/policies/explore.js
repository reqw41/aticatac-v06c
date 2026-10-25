// Политика «обход комнат»: цель — предмет комнаты (collectable_items: подойти и нажать огонь 2) или дверь
// (this_rooms_door_list: встать по середине и давить в сторону двери по повороту предмета в item_list).
// Застрял — несколько шагов в случайную сторону. Параметры: seed, fire (доля шагов с выстрелом),
// trap (доля люков среди дверей-целей), collect (брать ли предметы), drop (доля шагов с огнём 2 впустую).
'use strict';
const { rng } = require('../scenario');

module.exports = function (cfg, S) {
  const rnd = rng(cfg.seed || 7);
  let room = -1, target = null, lastPos = '', still = 0, wiggle = 0, wkeys = [], since = 0, pressZ = 0;
  const tried = new Set();
  return function (m, t) {
    const pk = (a) => m.ram[a];
    const px = pk(S.player_x), py = pk(S.player_y), h = pk(S.actual_player_height);
    const r = pk(S.room_number);
    const n = pk(S.this_rooms_door_count);
    const keys = [];
    if (pressZ > 0) { pressZ--; return ['Z']; }
    if (r !== room || !target || since > 700 || (target.kind === 'door' && target.i >= n)) {
      room = r; since = 0; target = null;
      if (cfg.collect !== false) {
        for (let ix = S.collectable_items, i = 0; pk(ix) !== 0xff && i < 40; ix += 8, i++)
          if (pk(ix) === r && !tried.has(r + ':' + i)) { target = { kind: 'item', i, ix }; break; }
      }
      if (!target) {
        const cand = [];
        for (let i = 0; i < n; i++) {
          const e = S.this_rooms_door_list + 8 * i;
          if (pk(e) === S.active_door_trapdoor && !(cfg.trap && rnd() < cfg.trap)) continue;
          const dx = pk(e + 1) - px, dy = pk(e + 2) - py;
          cand.push([i, dx * dx + dy * dy + rnd() * 4000]);
        }
        cand.sort((a, b) => b[1] - a[1]);
        if (cand.length) target = { kind: 'door', i: cand[Math.min(cand.length - 1, Math.floor(rnd() * Math.min(2, cand.length)))][0] };
      }
    }
    since++;
    if (cfg.fire && rnd() < cfg.fire) keys.push('SPACE');
    if (cfg.drop && rnd() < cfg.drop) { pressZ = 1; return keys.concat(['Z']); }
    if (wiggle > 0) { wiggle--; return keys.concat(wkeys); }
    const pos = px + ',' + py;
    if (pos === lastPos) still++; else still = 0;
    lastPos = pos;
    if (still > 12) {
      still = 0; wiggle = 6 + Math.floor(rnd() * 20);
      wkeys = [['UP'], ['DOWN'], ['LEFT'], ['RIGHT'], ['UP', 'LEFT'], ['DOWN', 'RIGHT']][Math.floor(rnd() * 6)];
      return keys.concat(wkeys);
    }
    if (!target) return keys;
    if (target.kind === 'item') {
      const ix = target.ix;
      if (pk(ix) !== r) { target = null; return keys; }
      const dx = 2 * pk(ix + 3) - px, dy = pk(ix + 4) - 2 - py;
      if (Math.abs(dx) <= 2 && Math.abs(dy) <= 3) {
        tried.add(r + ':' + target.i); target = null; pressZ = 2; return ['Z'];
      }
      if (Math.abs(dx) > 1) keys.push(dx < 0 ? 'LEFT' : 'RIGHT');
      if (Math.abs(dy) > 1) keys.push(dy < 0 ? 'UP' : 'DOWN');
      return keys;
    }
    const e = S.this_rooms_door_list + 8 * target.i;
    const ptr = pk(e + 3) | pk(e + 4) << 8;
    const rot = m.peekPage(5, ptr + 5) & 0xc0;
    const tx = pk(e + 1) + pk(e + 5) - 4;          // середина двери минус половина героя
    const ty = pk(e + 2) + (pk(e + 6) >> 1) - (h >> 1);
    const dx = tx - px, dy = ty - py;
    if (pk(e) === S.active_door_trapdoor) {        // люк: просто встать на него
      if (Math.abs(dx) > 1) keys.push(dx < 0 ? 'LEFT' : 'RIGHT');
      if (Math.abs(dy) > 1) keys.push(dy < 0 ? 'UP' : 'DOWN');
      return keys;
    }
    const horiz = rot === 0x40 || rot === 0xc0;    // дверь в боковой стене
    if (horiz) {
      if (Math.abs(dy) > 1) keys.push(dy < 0 ? 'UP' : 'DOWN');
      else keys.push(rot === 0x40 ? 'RIGHT' : 'LEFT');
      if (Math.abs(dx) > 12 && Math.abs(dy) > 1) keys.push(dx < 0 ? 'LEFT' : 'RIGHT');
    } else {
      if (Math.abs(dx) > 1) keys.push(dx < 0 ? 'LEFT' : 'RIGHT');
      else keys.push(rot === 0x80 ? 'DOWN' : 'UP');
      if (Math.abs(dy) > 12 && Math.abs(dx) > 1) keys.push(dy < 0 ? 'UP' : 'DOWN');
    }
    return keys;
  };
};
