// Политика «обход комнат»: выбрать дверь комнаты (this_rooms_door_list), подойти к её середине,
// встать ровно по поперечной оси и давить в сторону двери (по повороту предмета в item_list).
// Застрял — несколько шагов в случайную сторону. Иногда стреляет. Параметры: seed, fire (доля шагов),
// trap (брать ли люки).
'use strict';
const { rng } = require('../scenario');

module.exports = function (cfg, S) {
  const rnd = rng(cfg.seed || 7);
  let room = -1, door = -1, lastPos = '', still = 0, wiggle = 0, wkeys = [], since = 0;
  const visited = new Set();
  return function (m, t) {
    const pk = (a) => m.ram[a];
    const px = pk(S.player_x), py = pk(S.player_y), h = pk(S.actual_player_height);
    const r = pk(S.room_number);
    const n = pk(S.this_rooms_door_count);
    if (r !== room || door >= n || since > 600) {
      // новая комната (или долго не выходит): дверь, дальняя от героя, с долей случайности
      room = r; visited.add(r); since = 0;
      const cand = [];
      for (let i = 0; i < n; i++) {
        const e = S.this_rooms_door_list + 8 * i;
        if (pk(e) === S.active_door_trapdoor && !cfg.trap) continue;
        const dx = pk(e + 1) - px, dy = pk(e + 2) - py;
        cand.push([i, dx * dx + dy * dy + rnd() * 4000]);
      }
      cand.sort((a, b) => b[1] - a[1]);
      door = cand.length ? cand[Math.min(cand.length - 1, Math.floor(rnd() * Math.min(2, cand.length)))][0] : -1;
    }
    since++;
    const keys = [];
    if (cfg.fire && rnd() < cfg.fire) keys.push('SPACE');
    if (wiggle > 0) { wiggle--; return keys.concat(wkeys); }
    const pos = px + ',' + py;
    if (pos === lastPos) still++; else still = 0;
    lastPos = pos;
    if (still > 12) {
      still = 0; wiggle = 6 + Math.floor(rnd() * 20);
      wkeys = [['UP'], ['DOWN'], ['LEFT'], ['RIGHT'], ['UP', 'LEFT'], ['DOWN', 'RIGHT']][Math.floor(rnd() * 6)];
      return keys.concat(wkeys);
    }
    if (door < 0) return keys;
    const e = S.this_rooms_door_list + 8 * door;
    const ptr = pk(e + 3) | pk(e + 4) << 8;
    const rot = m.peekPage(5, ptr + 5) & 0xc0;
    const tx = pk(e + 1) + pk(e + 5) - 4;          // середина двери минус половина героя
    const ty = pk(e + 2) + (pk(e + 6) >> 1) - (h >> 1);
    const dx = tx - px, dy = ty - py;
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
