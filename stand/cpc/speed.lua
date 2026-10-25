-- Atic Atac (CPC, shaymanjohn) — темп: смены экрана (switch_em 0x013C) и вызовы состояния (0x379F)
-- за окна по 250 кадров: покой, вправо, вверх, влево, вниз. Снимки в начале каждого окна.
local m = manager.machine
local dbg = m.debugger
local frame = 0
local k9 = m.ioport.ports[":kbrow.9"].fields
local space = m.ioport.ports[":kbrow.5"].fields["Space"]
dbg:command('bpset 0x13C,1,{logerror "FL\\n"; g}')
dbg:command('bpset 0x379F,1,{logerror "ST\\n"; g}')
local T0 = tonumber(os.getenv("AT_T0") or "3000")
local phases = { {"IDLE", nil}, {"RIGHT", "P1 Right"}, {"UP", "P1 Up"}, {"LEFT", "P1 Left"}, {"DOWN", "P1 Down"}, {"RIGHT2", "P1 Right"} }
local sched = { [100] = 'run"atic\n' }
local held = nil
emu.register_frame_done(function()
  frame = frame + 1
  if sched[frame] then m.natkeyboard:post(sched[frame]) end
  for _, t in ipairs({1800, 2100, 2400, 2700}) do
    if frame == t then space:set_value(1) elseif frame == t + 10 then space:set_value(0) end
  end
  if frame % 250 == 0 and frame < T0 then m.video:snapshot() end
  if frame >= T0 then
    local i = (frame - T0) // 250 + 1
    if (frame - T0) % 250 == 0 then
      if held then held:set_value(0); held = nil end
      if phases[i] then
        dbg:command('logerror "PH ' .. phases[i][1] .. '\\n"')
        m.video:snapshot()
        if phases[i][2] then held = k9[phases[i][2]]; held:set_value(1) end
      else
        dbg:command('logerror "PH END\\n"'); m:exit()
      end
    end
  end
end)
