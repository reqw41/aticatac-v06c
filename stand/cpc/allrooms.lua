-- Эталон всех комнат: на входе в draw_collectables (0x205A) нарисованы контур и предметы комнаты
-- (без ключей, еды, спрайтов) в скрытом экране. Бп сохраняет 0x8000..0xFFFF, переменные экранов (0x56B,2),
-- банк комнат в окне 0x4000 (состояния дверей; .bank)
-- и номер комнаты (0x92E); кадровый обработчик раскладывает файлы в rooms/ и ставит следующую комнату:
-- room_number = N+1, room_changed = 1 — игра сама вызывает draw_room.
--   cd stand/cpc && mame cpc6128 ... -flop1 aticatac.dsk -script allrooms.lua
local m = manager.machine
local dbg = m.debugger
local mem = m.devices[":maincpu"].spaces["program"]
local space = m.ioport.ports[":kbrow.5"].fields["Space"]
local LAST = tonumber(os.getenv("LASTROOM") or "148")
os.execute("mkdir -p rooms")
dbg:command('bpset 0x205A,1,{save rm.bin,8000,8000; save rmv.bin,56B,2; save rmb.bin,4000,4000; save rmn.bin,92E,1; g}')
local frame, started, done, nextat = 0, false, {}, 0
local function exists(f) local h = io.open(f, "rb"); if h then h:close(); return true end; return false end
emu.register_frame_done(function()
  frame = frame + 1
  if frame == 100 then m.natkeyboard:post('run"atic\n') end
  for _, t in ipairs({1800, 2100, 2400, 2700}) do
    if frame == t then space:set_value(1) elseif frame == t + 10 then space:set_value(0) end
  end
  if exists("rmn.bin") then
    local h = io.open("rmn.bin", "rb"); local n = h:read(1):byte(); h:close()
    os.rename("rm.bin", string.format("rooms/r%03d.bin", n))
    os.rename("rmv.bin", string.format("rooms/r%03d.vars", n))
    os.rename("rmb.bin", string.format("rooms/r%03d.bank", n))
    os.remove("rmn.bin")
    done[n] = true
    started = true
    nextat = frame + 30
  end
  -- следующую комнату ставим с задержкой и повторяем, пока не придёт снимок (в начале игры draw_room
  -- зовётся из подготовки, а room_changed читает только основной цикл)
  if started and frame >= nextat then
    local nx = 0
    while done[nx] do nx = nx + 1 end
    if nx > LAST then m:exit() return end
    mem:write_u8(0x92E, nx)
    mem:write_u8(0x931, 1)
    nextat = frame + 100
  end
  if frame > 3000 + 150 * (LAST + 2) then m:exit() end
end)
