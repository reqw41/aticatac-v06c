-- перечень полей клавиатуры CPC в MAME
local m = manager.machine
for tag, port in pairs(m.ioport.ports) do
  for name, f in pairs(port.fields) do print(tag .. ' | ' .. name) end
end
m:exit()
