-- jp.91-preview2: notice when the GPU dropped every Canvas and rebuild what lived in one.
--
-- LOVE 11 keeps Images and Meshes across a window re-creation (setMode / fullscreen
-- toggles; on Android a fold, a rotation or a resume can do the same) but NOT the
-- pixels of a Canvas. Nothing here listened for that: Pipelines.invalidate() was never
-- called, so cached bakes (the 3D shadow map, the gen2 map bakes) kept sampling an empty
-- target -- the room turned dark or vanished until something else happened to rebake it.
--
-- A 1x1 sentinel canvas is painted opaque once. Whenever it reads back empty, every
-- canvas made before it is empty too: drop the pipelines' GPU objects and the world's
-- baked map images and let them come back on the next frame. Checked on resize,
-- regained visibility/focus and, as a backstop, every few seconds. Nothing is done
-- while the sentinel is intact, so normal play renders exactly as before.
local ContextGuard = {}

local sentinel = nil      -- nil = not made yet, false = this driver cannot make one
local frames = 0
local pending = nil       -- reason of an event check to run on the next update
local POLL_FRAMES = 300   -- ~5 s at 60 fps; one 1x1 readback

local function paint()
  if not (love.graphics and love.graphics.newCanvas) then sentinel = false; return end
  local ok, c = pcall(love.graphics.newCanvas, 1, 1, { dpiscale = 1 })
  if not (ok and c) then sentinel = false; return end
  local prev = love.graphics.getCanvas()
  local okDraw = pcall(function()
    love.graphics.setCanvas(c)
    love.graphics.clear(1, 1, 1, 1)
  end)
  love.graphics.setCanvas(prev)
  if not okDraw then pcall(c.release, c); sentinel = false; return end
  if sentinel and sentinel.release then pcall(sentinel.release, sentinel) end
  sentinel = c
end

-- true when the sentinel's pixel is gone (the context lost every canvas)
function ContextGuard.lost()
  if sentinel == false then return false end
  if sentinel == nil then paint(); return false end
  local ok, data = pcall(sentinel.newImageData, sentinel)
  if not (ok and data) then return true end
  local _, _, _, a = data:getPixel(0, 0)
  if data.release then pcall(data.release, data) end
  return a < 0.5
end

local function rebakeWorld(game)
  local w = game and game.world
  if not (w and type(w.mapImages) == "table" and w.map and w.imageFor) then return end
  w.mapImages = {}
  if w.scrollStrips then w.scrollStrips = {} end
  local ok = pcall(function()
    w.mapImage = w:imageFor(w.map.id)
    if w.rebuildNeighbors then w:rebuildNeighbors() end
  end)
  if not ok then w.mapImage = nil end
end

function ContextGuard.recover(game, reason)
  print("[ContextGuard] canvases lost (" .. tostring(reason) .. "), rebuilding")
  pcall(function() require("src.render.Pipelines").invalidate() end)
  pcall(rebakeWorld, game)
  paint()
end

-- Event hooks only flag; the readback runs from update, outside any draw.
function ContextGuard.request(reason) pending = pending or reason end

function ContextGuard.update(game)
  frames = frames + 1
  local reason = pending
  if not reason and frames >= POLL_FRAMES then reason = "poll" end
  if not reason then return end
  pending, frames = nil, 0
  if ContextGuard.lost() then ContextGuard.recover(game, reason) end
end

return ContextGuard
