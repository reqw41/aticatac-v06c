// Проигрыватель сценария для стендов CPC (cpc_trace.js, shadow.js): меню по кадрам, потом клавиши на
// каждый шаг игры (steps, затем random или политика). Шаг = вызов задачи из главного цикла.
'use strict';
const fs = require('fs');
const path = require('path');
const CPC = require('./cpc6128');

const ROOT = path.join(__dirname, '..');
const SYM = {};
for (const l of fs.readFileSync(path.join(ROOT, 'build/cpcsrc/rasmoutput.sym'), 'utf8').split('\n')) {
  const m = l.match(/^(\w+) #([0-9A-F]+)/); if (m) SYM[m[1].toLowerCase()] = parseInt(m[2], 16);
}

function rng(seed) { let s = seed >>> 0 || 1; return () => { s ^= s << 13; s >>>= 0; s ^= s >> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; }; }

// машина в начале первого шага игры (PC = current_game_state) и функция «клавиши шага t»
// opts.step(m) — свой шаг машины (теневая проверка смотрит и меню/старт игры); opts.onCreate(m)
function start(sc, opts) {
  opts = opts || {};
  const m = new CPC(path.join(ROOT, 'build/cpcnew'));
  if (opts.onCreate) opts.onCreate(m);
  const step = opts.step || ((mm) => mm.step());
  const frames = (n) => { const f = m.frames + n; while (m.frames < f) step(m); };
  const until = (pc, lim) => { const end = m.total + lim; while (m.total < end) { if (m.pc === pc) return true; step(m); } return false; };
  for (const st of sc.menu || []) { m.keysOnly(st.keys || []); frames(st.frames); }
  m.keysOnly([]);
  if (!until(SYM.game_tasks, CPC.T_FRAME * 3000)) throw new Error('игра не началась');
  until(SYM.current_game_state, CPC.T_FRAME * 10);
  const plan = [];
  for (const st of sc.steps || []) for (let i = 0; i < st.ticks; i++) plan.push(st.keys || []);
  const rnd = sc.random ? rng(sc.random.seed) : null;
  let hold = 0, rkeys = [];
  let policy = null;
  if (sc.policy) policy = require(path.join(__dirname, 'policies', sc.policy.name + '.js'))(sc.policy, SYM);
  const N = sc.ticks || plan.length;
  // pokes: [{ "tick": t, "set": { "room_number": 85, "room_changed": 1 } }] — запись в память перед шагом t
  // (значение "@метка" — текущее значение переменной игры, например "@mummy_room")
  const pokes = new Map();
  for (const p of sc.pokes || []) pokes.set(p.tick, p.set);
  function keysFor(t) {
    if (t >= N) return null;
    const pk = pokes.get(t);
    if (pk) for (const [k, v] of Object.entries(pk)) {
      const a = k in SYM ? SYM[k] : parseInt(k, 16);
      m.poke(a, typeof v === 'string' && v[0] === '@' ? m.peek(SYM[v.slice(1)]) : v);   // "@метка" — значение переменной
    }
    if (t < plan.length) return plan[t];
    if (policy) return policy(m, t);
    if (!rnd) return null;
    if (hold <= 0) {
      rkeys = sc.random.keys.filter(() => rnd() < (sc.random.p || 0.3));
      hold = sc.random.hold[0] + Math.floor(rnd() * (sc.random.hold[1] - sc.random.hold[0] + 1));
    }
    hold--; return rkeys;
  }
  return { m, keysFor, N };
}

module.exports = { start, SYM, ROOT, rng };
