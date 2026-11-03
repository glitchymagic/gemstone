-- tools/fight_clips.py --lua: extra tape row commands for in-fight captures (loaded with the `lua FILE` queue command;
-- wraps flycast_drive.lua's global tapeCmd, every other command passes through unchanged).
--   itemid N            every floor item (object pool 0x0C7D0980 + slot * 0x31C: +2 type 3, +4 kind 6) -> item id N
--                       (+0x30C): its pick-up / hold / use motions are then that id's family (docs/ITEMS.md 6)
--   toitem P DX DZ ANG  fighter P (1/2) placed at the floor item nearest him + (DX, DZ) cm, keeping his feet height,
--                       facing u16 ANG, velocity 0 (the chest's item lands where the run's own rand puts it)
--   faceme P DIST       the other fighter placed DIST cm in front of fighter P (along P's +0x7248 facing), facing P
local POOL, STRIDE, SLOTS = 0x0C7D0980, 0x31C, 48
local PB = { 0x0C7E40C4, 0x0C7EB394 }
local function u2f(v) return string.unpack("<f", string.pack("<I4", v)) end
local function f2u(v) return string.unpack("<I4", string.pack("<f", v)) end
local function items()
  local out = {}
  for s = 0, SLOTS - 1 do
    local b = POOL + s * STRIDE
    if flycast.memory.read8(b + 2) == 3 and flycast.memory.read8(b + 4) == 6 then table.insert(out, b) end
  end
  return out
end
local baseTapeCmd = tapeCmd
function tapeCmd(c)
  local w = {}
  for t in c:gmatch("%S+") do table.insert(w, t) end
  if w[1] == "itemid" then
    for _, b in ipairs(items()) do
      flycast.memory.write8(b + 0x30C, tonumber(w[2]))
      print(string.format("[drive] itemid 0x%08X -> %s", b, w[2]))
    end
  elseif w[1] == "toitem" then
    local it = items()
    if #it == 0 then print("[drive] toitem: no floor item"); return end
    local p = PB[tonumber(w[2])]
    local px, pz = u2f(flycast.memory.read32(p + 0x20)), u2f(flycast.memory.read32(p + 0x28))
    local b, bd = nil, nil
    for _, o in ipairs(it) do   -- the floor item nearest the fighter
      local dx, dz = u2f(flycast.memory.read32(o + 0x20)) - px, u2f(flycast.memory.read32(o + 0x28)) - pz
      if bd == nil or dx * dx + dz * dz < bd then b, bd = o, dx * dx + dz * dz end
    end
    local x, y, z = u2f(flycast.memory.read32(b + 0x20)), u2f(flycast.memory.read32(b + 0x24)), u2f(flycast.memory.read32(b + 0x28))
    local v = { x + tonumber(w[3]), u2f(flycast.memory.read32(p + 0x24)), z + tonumber(w[4]) }   -- his own feet height
    for i = 0, 2 do
      flycast.memory.write32(p + 0x20 + 4 * i, f2u(v[i + 1])); flycast.memory.write32(p + 0x7264 + 4 * i, f2u(v[i + 1]))
      flycast.memory.write32(p + 0x7270 + 4 * i, 0)
    end
    flycast.memory.write16(p + 0x7248, tonumber(w[5]))
    print(string.format("[drive] toitem item 0x%08X at %.1f %.1f %.1f", b, x, y, z))
  elseif w[1] == "faceme" then
    local p, q = PB[tonumber(w[2])], PB[3 - tonumber(w[2])]
    local ang = flycast.memory.read16(p + 0x7248)
    local a, dist = ang / 65536 * 2 * math.pi, tonumber(w[3])
    local x, y, z = u2f(flycast.memory.read32(p + 0x20)), u2f(flycast.memory.read32(p + 0x24)), u2f(flycast.memory.read32(p + 0x28))
    local v = { x + math.sin(a) * dist, y, z + math.cos(a) * dist }
    for i = 0, 2 do
      flycast.memory.write32(q + 0x20 + 4 * i, f2u(v[i + 1])); flycast.memory.write32(q + 0x7264 + 4 * i, f2u(v[i + 1]))
      flycast.memory.write32(q + 0x7270 + 4 * i, 0)
    end
    flycast.memory.write16(q + 0x7248, (ang + 0x8000) % 0x10000)
    print(string.format("[drive] faceme %.1f %.1f %.1f", v[1], v[2], v[3]))
  else
    baseTapeCmd(c)
  end
end
print("[drive] fight_clips.lua loaded (itemid, toitem, faceme)")
