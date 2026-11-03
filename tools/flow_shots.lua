-- fx-flow: hot-loaded with the driver's `lua FILE` command. Wraps the vblank callback to save a screenshot every
-- FLOW_EVERY frames (counted from the vblank after loading, = the capseg row index + 1 when queued together).
local SH = (os.getenv("PS_FC_ROOT") or "./dumps/") .. "shots/"
local every = FLOW_EVERY or 30
local tag = FLOW_TAG or "fl"
local n = 0
local prev = flycast_callbacks.vblank
flycast_callbacks.vblank = function()
  prev()
  n = n + 1
  if n % every == 0 then flycast.emulator.saveScreenshotTo(SH .. string.format("%s_%06d.png", tag, n)) end
end
print("[flow] shots every " .. every .. " frames, tag " .. tag)
