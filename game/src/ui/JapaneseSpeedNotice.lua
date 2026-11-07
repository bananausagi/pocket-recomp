-- jp.74.1: make the logic-speed multiplier visible.  The speed hotkey
-- (shoulder/trigger, keyboard "1", skin toggle) used to change the saved
-- speed with nothing on screen, so a stray press left the game running at
-- 2X-10X with no clue why.  Presentation only: a short toast when the speed
-- changes, and a small badge in the top-right while the overworld runs
-- faster than 1X.
local Notice = {}
local Font = require("src.render.Font")
local Layout = require("src.ui.GameUILayout")
local Viewport = require("src.render.GameViewport")

Notice.DURATION = 1.60

local function japanese(game)
  return game and game.data and game.data.constants
    and game.data.constants.language == "ja"
end

function Notice.label(speed)
  speed = tonumber(speed) or 1
  return string.format("%dX", math.floor(speed + 0.5))
end

function Notice.show(game, speed)
  if not game then return end
  game._jpSpeedNotice = {text = "はやさ " .. Notice.label(speed), time = 0}
end

function Notice.update(game, dt)
  local s = game and game._jpSpeedNotice
  if not s then return end
  dt = math.max(0, math.min(tonumber(dt) or 0, 0.10))
  -- Do not consume the toast while no rendered frame has presented it.
  if s.presented then
    s.time = s.time + dt
    if s.time >= Notice.DURATION then game._jpSpeedNotice = nil end
  end
end

-- The badge only shows over plain overworld play, never over text/menus.
function Notice.badgeSpeed(game)
  if not japanese(game) or game.sessionMenu then return nil end
  local Banner = require("src.ui.JapaneseAreaBanner")
  if not Banner.available(game) then return nil end
  local ok, speed = pcall(game.logicSpeed, game)
  if ok and type(speed) == "number" and speed > 1 then return speed end
  return nil
end

function Notice.metrics(game, text, tiles)
  local viewport = Viewport.active() and Viewport.rect
  local bounds = viewport and {x=viewport.x, y=viewport.y,
    w=viewport.width, h=viewport.height} or nil
  local rect = Layout.usable(false, bounds)
  local p = Layout.panelMetrics(game, {rect=rect, minHeight=tiles*8})
  local margin = math.min(p.margin, math.floor(math.min(rect.w*p.dpiX, rect.h*p.dpiY)*.04))
  if rect.h*p.dpiY-2*margin < tiles*8 then return nil end
  local scale = math.max(1, math.min(p.scale,
    math.floor((rect.h*p.dpiY-2*margin)/(tiles*8))))
  local width = math.ceil((Font.width(text)+24)/8)*8
  local maxWidth = math.floor((rect.w*p.dpiX-2*margin)/scale/8)*8
  if width > maxWidth then return nil end
  local right = math.floor((rect.x+rect.w)*p.dpiX-margin)
  local x = (right - width*scale)/p.dpiX
  local y = math.floor(rect.y*p.dpiY+margin)/p.dpiY
  return {x=x, y=y, width=width, tiles=tiles, sx=scale/p.dpiX, sy=scale/p.dpiY, text=text}
end

local function drawBox(m)
  local g = love.graphics
  g.push("all")
  g.origin()
  g.setShader()
  g.setScissor()
  g.setBlendMode("alpha")
  g.setColor(1,1,1,1)
  g.translate(m.x, m.y)
  g.scale(m.sx, m.sy)
  Font.drawBox(0, 0, m.width/8, m.tiles)
  -- Same text row as JapaneseAreaBanner: the row above holds dakuten.
  Font.draw(m.text, math.floor((m.width-Font.width(m.text))/2), m.tiles*8-16)
  g.pop()
end

function Notice.draw(game)
  if not japanese(game) then return end
  local s = game._jpSpeedNotice
  if s and not game.sessionMenu then
    local m = Notice.metrics(game, s.text, 4)
    if m then drawBox(m) end
    s.presented = true
    return m
  end
  local speed = Notice.badgeSpeed(game)
  if not speed then return end
  local m = Notice.metrics(game, Notice.label(speed), 3)
  if m then drawBox(m) end
  return m
end

return Notice
