-- Power Stone remaster rip: flycast driver script, v2 (pass 2: RAM motion capture).
-- Real gameplay only, no stand-ins: the game's own motion player poses the fighters and this script
-- records the bone node records out of RAM every vblank.
--
-- Install location: copied to ~/.flycast/flycast_drive.lua (config::LuaFileName)
-- Authoritative copy (tracked in git): tools/flycast_drive.lua
--
-- Protocol: the controller writes dumps/cmd/NNNN.txt (NNNN = 0001, 0002, ... in order, write to a tmp
-- name then mv). Each file holds command lines that are queued and run frame-accurately:
--   wait N                      block the queue N frames
--   press P BTN[+BTN] N         hold buttons on player P (1/2) for N frames, block until released (+1 frame)
--   hold P BTN[+BTN] N          same, but do not block
--   axis P AX VAL               setAxis (1 = x, 2 = y; -128..127)
--   shot name.png               screenshot into dumps/shots/
--   shotseq NAME N              a screenshot every vblank for N frames into dumps/shots/NAME/NNNNN.png (trailer: the
--                               real disc's footage frame by frame; counts as a capture in status.txt)
--   dump name.bin ADDR LEN      one RAM dump into dumps/
--   cap name ADDR LEN N         dump ADDR..+LEN every vblank for N frames into dumps/cap/name/NNNNN.bin
--   capseg name N A:L,A:L,...   every vblank for N frames append those segments (u32 reads) to dumps/cap/name.bin
--   lua FILE                    dofile(FILE): hot-load extra handlers without restarting the emulator
--   poke8/poke16/poke32 ADDR V  write memory once
--   freeze8/freeze16/freeze32 ADDR V   write every vblank (unfreeze ADDR to stop)
--   peek32 ADDR [n]             print n u32s
--   (save/load are disabled: savestates from the vblank callback deadlock the emu thread)
--   mark TEXT                   print a marker with the frame number
--   tape FILE                   (fidelity pass) from the next vblank on, set BOTH pads every frame from FILE: one line per
--                               frame "p1mask p2mask" (hex, BUTTONS bits below; a set bit = held); the queue blocks
--                               until the tape ends, then every button is released
--   tapelog NAME SEGS           with `tape`: capseg NAME for exactly the tape's length (same frames)
--   until8 ADDR VAL [MAX]       block the queue until byte ADDR == VAL (or MAX frames, default 600) (pass 3)
--   until8n ADDR VAL [MAX]      same, until byte ADDR != VAL
-- dumps/status.txt is rewritten every 30 frames: frame, next command seq, queued lines, active captures.

-- PS_FC_ROOT (env) points a second Flycast instance (its own HOME, see tools/fc2.sh) at its own command/dump folder
local ROOT      = os.getenv("PS_FC_ROOT") or "./dumps/"
local SHOTS_DIR = ROOT .. "shots/"
local CMD_DIR   = ROOT .. "cmd/"
local CAP_DIR   = ROOT .. "cap/"

local frame = 0
local seq = 1
local queue = {}
local waitFrames = 0
local untilCond = nil -- {addr, val, negate}
local holds = {}      -- {player, mask, left}
local caps = {}       -- name -> {addr, len, left, n}
local segcaps = {}    -- name -> {segs, left, file}
local shotseqs = {}   -- name -> {left, n}
local freezes = {}    -- addr -> {width, value}
local lastMark = ""
local tapeRows = nil  -- fidelity pass: {p1mask, p2mask} per frame
local tapePos = 0
local tapeLog = nil   -- {name, segs}
local ALLBTN = 0xFFF

local BUTTONS = {
  C = 0x1, B = 0x2, A = 0x4, START = 0x8,
  UP = 0x10, DOWN = 0x20, LEFT = 0x40, RIGHT = 0x80,
  Z = 0x100, Y = 0x200, X = 0x400, D = 0x800,
}

local function maskOf(s)
  local m = 0
  for b in s:gmatch("[^+]+") do m = m | (BUTTONS[b] or 0) end
  return m
end

local function num(s) if s == nil then return nil end if s:match("^0x") then return tonumber(s:sub(3), 16) end return tonumber(s) end

local function writeStatus()
  local f = io.open(ROOT .. "status.txt", "w")
  if not f then return end
  local nc = 0
  for _ in pairs(caps) do nc = nc + 1 end
  for _ in pairs(segcaps) do nc = nc + 1 end
  for _ in pairs(shotseqs) do nc = nc + 1 end
  f:write(string.format("frame=%d seq=%d queue=%d wait=%d caps=%d mark=%s\n", frame, seq, #queue, waitFrames, nc, lastMark))
  f:close()
end

local function pollCmd()
  local path = string.format("%s%04d.txt", CMD_DIR, seq)
  local f = io.open(path, "r")
  if not f then return end
  for raw in f:lines() do
    local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if #line > 0 and line:sub(1, 1) ~= "#" then table.insert(queue, line) end
  end
  f:close()
  os.remove(path)
  seq = seq + 1
end

local function runLine(line)
  local w = {}
  for t in line:gmatch("%S+") do table.insert(w, t) end
  local c = w[1]
  if c == "wait" then
    waitFrames = num(w[2]) or 1
  elseif c == "until8" or c == "until8n" then
    untilCond = { num(w[2]), num(w[3]), c == "until8n" }
    waitFrames = num(w[4]) or 600
  elseif c == "press" or c == "hold" then
    local p, m, n = num(w[2]), maskOf(w[3]), num(w[4]) or 6
    flycast.input.pressButtons(p, m)
    table.insert(holds, { p, m, n })
    if c == "press" then waitFrames = n + 1 end
  elseif c == "axis" then
    flycast.input.setAxis(num(w[2]), num(w[3]), num(w[4]))
  elseif c == "shot" then
    flycast.emulator.saveScreenshotTo(SHOTS_DIR .. w[2])
  elseif c == "shotseq" then
    os.execute('mkdir -p "' .. SHOTS_DIR .. w[2] .. '"')
    shotseqs[w[2]] = { num(w[3]), 0 }
  elseif c == "dump" then
    flycast.memory.dumpToFile(ROOT .. w[2], num(w[3]), num(w[4]))
  elseif c == "cap" then
    os.execute('mkdir -p "' .. CAP_DIR .. w[2] .. '"')
    caps[w[2]] = { num(w[3]), num(w[4]), num(w[5]), 0 }
  elseif c == "capseg" then
    local segs = {}
    for a, l in w[4]:gmatch("([^:,]+):([^:,]+)") do table.insert(segs, { num(a), num(l) }) end
    segcaps[w[2]] = { segs, num(w[3]), io.open(CAP_DIR .. w[2] .. ".bin", "wb") }
  elseif c == "tapelog" then
    tapeLog = { w[2], w[3] }
  elseif c == "tape" then
    tapeRows = {}
    for ln in io.lines(w[2]) do
      local a, b = ln:match("^(%x+)%s+(%x+)")
      if a then
        local cmds = {}
        for c in ln:gmatch(";%s*([^;]+)") do table.insert(cmds, (c:gsub("%s+$", ""))) end
        table.insert(tapeRows, { tonumber(a, 16), tonumber(b, 16), cmds })
      end
    end
    tapePos = 0
    if tapeLog then
      local segs = {}
      for a, l in tapeLog[2]:gmatch("([^:,]+):([^:,]+)") do table.insert(segs, { num(a), num(l) }) end
      segcaps[tapeLog[1]] = { segs, #tapeRows, io.open(CAP_DIR .. tapeLog[1] .. ".bin", "wb") }
      tapeLog = nil
    end
    waitFrames = #tapeRows + 1
    print(string.format("[drive] frame=%d tape %s (%d frames)", frame, w[2], #tapeRows))
  elseif c == "lua" then
    dofile(w[2])
  elseif c == "poke8" then flycast.memory.write8(num(w[2]), num(w[3]))
  elseif c == "poke16" then flycast.memory.write16(num(w[2]), num(w[3]))
  elseif c == "poke32" then flycast.memory.write32(num(w[2]), num(w[3]))
  elseif c == "freeze8" then freezes[num(w[2])] = { 8, num(w[3]) }
  elseif c == "freeze16" then freezes[num(w[2])] = { 16, num(w[3]) }
  elseif c == "freeze32" then freezes[num(w[2])] = { 32, num(w[3]) }
  elseif c == "unfreeze" then freezes[num(w[2])] = nil
  elseif c == "peek32" then
    local a, n = num(w[2]), num(w[3]) or 1
    local out = {}
    for i = 0, n - 1 do table.insert(out, string.format("%08X", flycast.memory.read32(a + 4 * i))) end
    print(string.format("[drive] frame=%d peek %08X: %s", frame, a, table.concat(out, " ")))
  elseif c == "save" or c == "load" then
    -- flycast.emulator.saveState/loadState call gui_open_settings -> Emulator::stop on the emu thread:
    -- from a vblank callback that deadlocks the emulator. Never call them here.
    print("[drive] save/load disabled (deadlocks inside vblank)")
  elseif c == "mark" then
    lastMark = line:sub(6)
    print(string.format("[drive] frame=%d mark %s", frame, lastMark))
  else
    print("[drive] unknown command: " .. line)
  end
end

-- tape row commands (fidelity setups, the remaster's tape mode does the same):
--   place P X Y Z ANG   fighter P (1/2) to x,y,z cm (feet), facing u16, velocity 0
--   hp P V              health (+0x71D4 and its two display copies)
--   gems P N            gem count + mask
local PBASE = { 0x0C7E40C4, 0x0C7EB394 }
local function f2u(v) return string.unpack("<I4", string.pack("<f", v)) end
function tapeCmd(c)
  local w = {}
  for t in c:gmatch("%S+") do table.insert(w, t) end
  local b = PBASE[tonumber(w[2] or "1")]
  if w[1] == "place" then
    for i = 0, 2 do
      local v = f2u(tonumber(w[3 + i]))
      flycast.memory.write32(b + 0x20 + 4 * i, v); flycast.memory.write32(b + 0x7264 + 4 * i, v)
      flycast.memory.write32(b + 0x7270 + 4 * i, 0)
    end
    flycast.memory.write16(b + 0x7248, tonumber(w[6]))
  elseif w[1] == "hp" then
    for i = 0, 2 do flycast.memory.write16(b + 0x71D4 + 2 * i, tonumber(w[3])) end
  elseif w[1] == "gems" then
    local n = tonumber(w[3]); flycast.memory.write8(b + 0x7230, n); flycast.memory.write8(b + 0x7231, (1 << n) - 1)
  else
    runLine(c)
  end
end

function cbStart()
  print("[drive] Game started: " .. flycast.state.media .. " id=" .. flycast.state.gameId)
  frame = 0
  os.execute('mkdir -p "' .. CMD_DIR .. '" "' .. CAP_DIR .. '" "' .. SHOTS_DIR .. '"')
end

function cbVBlank()
  frame = frame + 1

  for name, cp in pairs(caps) do
    flycast.memory.dumpToFile(string.format("%s%s/%05d.bin", CAP_DIR, name, cp[4]), cp[1], cp[2])
    cp[4] = cp[4] + 1
    if cp[4] >= cp[3] then caps[name] = nil; print(string.format("[drive] frame=%d cap %s done", frame, name)) end
  end

  for name, ss in pairs(shotseqs) do
    flycast.emulator.saveScreenshotTo(string.format("%s%s/%05d.png", SHOTS_DIR, name, ss[2]))
    ss[2] = ss[2] + 1
    if ss[2] >= ss[1] then shotseqs[name] = nil; print(string.format("[drive] frame=%d shotseq %s done", frame, name)) end
  end

  for name, sc in pairs(segcaps) do
    local parts = {}
    for _, sg in ipairs(sc[1]) do
      for a = sg[1], sg[1] + sg[2] - 4, 4 do table.insert(parts, string.pack("<I4", flycast.memory.read32(a))) end
    end
    sc[3]:write(table.concat(parts))
    sc[2] = sc[2] - 1
    if sc[2] <= 0 then sc[3]:close(); segcaps[name] = nil; print(string.format("[drive] frame=%d capseg %s done", frame, name)) end
  end

  -- freezes after the captures (pass 4): a capture sees what the game wrote this frame (a hit on a frozen health
  -- shows as a one-frame dip), then the frozen value goes back in for the next frame
  for a, fz in pairs(freezes) do
    if fz[1] == 8 then flycast.memory.write8(a, fz[2])
    elseif fz[1] == 16 then flycast.memory.write16(a, fz[2])
    else flycast.memory.write32(a, fz[2]) end
  end

  if tapeRows then
    tapePos = tapePos + 1
    local r = tapeRows[tapePos]
    if r then for _, c in ipairs(r[3]) do tapeCmd(c) end end
    for p = 1, 2 do
      flycast.input.releaseButtons(p, ALLBTN)
      if r and r[p] ~= 0 then flycast.input.pressButtons(p, r[p]) end
    end
    if not r then tapeRows = nil; print(string.format("[drive] frame=%d tape done", frame)) end
  end

  for i = #holds, 1, -1 do
    local h = holds[i]
    h[3] = h[3] - 1
    if h[3] <= 0 then flycast.input.releaseButtons(h[1], h[2]); table.remove(holds, i) end
  end

  if waitFrames > 0 then waitFrames = waitFrames - 1 end
  if untilCond then
    local v = flycast.memory.read8(untilCond[1])
    if (v == untilCond[2]) ~= untilCond[3] or waitFrames == 0 then untilCond = nil; waitFrames = 0 end
  end
  while waitFrames == 0 and #queue > 0 do
    runLine(table.remove(queue, 1))
  end

  pollCmd()
  -- dumps/cmd/now.txt: immediate commands that bypass the queue ("clear" drops the queue, holds and captures)
  local nf = io.open(CMD_DIR .. "now.txt", "r")
  if nf then
    local body = nf:read("*a"); nf:close(); os.remove(CMD_DIR .. "now.txt")
    for raw in body:gmatch("[^\n]+") do
      local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
      if line == "clear" then
        queue = {}; waitFrames = 0; untilCond = nil
        for name, sc in pairs(segcaps) do sc[3]:close() end
        segcaps = {}; caps = {}; shotseqs = {}
        print(string.format("[drive] frame=%d queue cleared", frame))
      elseif #line > 0 then runLine(line) end
    end
  end
  if frame % 30 == 0 then writeStatus() end
end

flycast_callbacks = {
  start = cbStart,
  vblank = cbVBlank,
}

print("[drive] flycast_drive.lua v2 loaded (queue protocol via " .. CMD_DIR .. ")")
