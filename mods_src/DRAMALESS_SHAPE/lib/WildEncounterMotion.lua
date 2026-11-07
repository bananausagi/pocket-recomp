-- Presentation curves only. Native battle queues, cries and send-out timings
-- remain owned by the engine; all returned offsets settle at the native pose.
local Motion = { HOP_SECONDS = .36, HOP_PIXELS = 12 }

local function clamp(x) return math.max(0, math.min(1, x)) end
local function smooth(x)
  x = clamp(x)
  return x*x*(3-2*x)
end

function Motion.castAlpha(time, duration)
  local progress = math.max(0, time or 0) / math.max(.001, duration or 1)
  -- Start with the exact overworld image. As the camera leaves the player,
  -- fade their small map sprite before the battle back picture takes over.
  return 1-smooth((progress-.12)/.34)
end

function Motion.hop(elapsed)
  local t = clamp((elapsed or 0)/Motion.HOP_SECONDS)
  if t >= 1 then return 0, 1 end
  -- A compact leap from the encounter tile, with zero vertical velocity at
  -- either end. A slight emergence in size never hides the first cry frame.
  return Motion.HOP_PIXELS*math.sin(math.pi*t)^2, .84+.16*smooth(t/.42)
end

function Motion.retreat(offset)
  local progress = smooth(-(offset or 0)/72)
  return 1-progress, -12*progress
end

return Motion
