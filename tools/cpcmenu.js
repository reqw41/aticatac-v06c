#!/usr/bin/env node
// Снимок меню CPC (модель tools/cpc6128.js, 200 кадров после старта) -> build/game/menu_cpc.bin (формат
// tools/cpcboot.js shot). Нужен tools/mkgame.py: неподвижная часть меню (логотип, надписи, указатель).
'use strict';
const path = require('path');
const CPC = require('./cpc6128');
const { shot } = require('./cpcboot');
const m = new CPC(path.join(__dirname, '../build/cpcnew'));
const f = m.frames + 200; while (m.frames < f) m.step();
shot(m, path.join(__dirname, '../build/game/menu_cpc.bin'));
