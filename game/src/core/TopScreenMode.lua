-- Top-screen-only display for clip-on controllers (for example a pad that
-- covers the lower half of a portrait phone). The game is drawn into a
-- square (or Game Boy 10:9) window-space rectangle placed under the top
-- safe-area inset; GameViewport renders and maps touches into it.
--
-- Pure layout logic: no love.* calls, so it runs under plain luajit.
-- Options are read live from the table given to applyOptions, so a settings
-- row takes effect on the next frame without a reload.

local M = {}

M.SHAPES = { off = true, square = true, gb = true }
-- Size and position move in 1% steps: size 50..100, position 0..100.
M.SIZE_MIN, M.SIZE_MAX = 50, 100
M.POS_MIN, M.POS_MAX = 0, 100
M.DEFAULT_SIZE = 100
M.DEFAULT_X = 50
M.DEFAULT_Y = 0
-- Game Boy screen is 160x144: height is 0.9 of the width.
M.GB_RATIO = 144 / 160

local current = nil

local function finite(v)
  return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function clamp(v, low, high, default)
  if not finite(v) then return default end
  return math.max(low, math.min(high, v))
end

function M.shape(opts)
  local value = type(opts) == "table" and opts.jpTopScreen or nil
  if value == true then return "square" end
  if M.SHAPES[value] then return value end
  return "off"
end

local RANGES = {
  jpTopScreenSize = { M.SIZE_MIN, M.SIZE_MAX },
  jpTopScreenY = { M.POS_MIN, M.POS_MAX },
  jpTopScreenX = { M.POS_MIN, M.POS_MAX },
}
local DEFAULTS = { jpTopScreenSize = 100, jpTopScreenY = 0, jpTopScreenX = 50 }

-- Whole number inside [low, high]; anything else is not a valid setting.
function M.valid(v, low, high)
  return finite(v) and v == math.floor(v) and v >= low and v <= high
end

-- Repairs saved values: unknown shape -> off, non-integer or out-of-range
-- numbers -> default. Every jp.67 value (100..60 / 0..100 by 10 / 0..100
-- by 25) is inside the ranges and survives unchanged.
function M.normalize(opts)
  if type(opts) ~= "table" then return opts end
  opts.jpTopScreen = M.shape(opts)
  for key, range in pairs(RANGES) do
    if not M.valid(opts[key], range[1], range[2]) then opts[key] = DEFAULTS[key] end
  end
  return opts
end

function M.applyOptions(opts)
  current = type(opts) == "table" and opts or nil
end

function M.options()
  return current
end

function M.enabled(opts)
  if opts == nil then opts = current end
  return M.shape(opts) ~= "off"
end

-- Returns the window-space rect {x, y, width, height} for a w x h window
-- whose top inset is safeTop, or nil when the mode is off.
function M.rect(w, h, safeTop, opts)
  if opts == nil then opts = current end
  local shape = M.shape(opts)
  if shape == "off" then return nil end
  if not finite(w) or not finite(h) or w < 1 or h < 1 then return nil end
  safeTop = clamp(safeTop, 0, h - 1, 0)
  local availW, availH = w, h - safeTop
  local ratio = shape == "gb" and M.GB_RATIO or 1
  -- Largest rect of the chosen ratio that fits the area under the inset.
  local width = math.min(availW, availH / ratio)
  local scale = clamp(opts.jpTopScreenSize, 50, 100, M.DEFAULT_SIZE) / 100
  width = math.max(1, math.floor(width * scale))
  local height = math.max(1, math.floor(width * ratio))
  local px = clamp(opts.jpTopScreenX, 0, 100, M.DEFAULT_X) / 100
  local py = clamp(opts.jpTopScreenY, 0, 100, M.DEFAULT_Y) / 100
  local x = math.floor((availW - width) * px + 0.5)
  local y = math.floor(safeTop + (availH - height) * py + 0.5)
  return { x = x, y = y, width = width, height = height }
end

return M
