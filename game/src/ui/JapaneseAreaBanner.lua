-- Presentation-only arrival notice. Observe the current map once per real
-- frame; connected terrain chunks and streamed neighbours are not arrivals.
local Banner = {}
local Map = require("src.world.Map")
local Font = require("src.render.Font")
local Layout = require("src.ui.GameUILayout")
local Viewport = require("src.render.GameViewport")
local Names = require("src.core.JapaneseStringsMenus")

local SETTLE, DURATION, SLIDE = 0.20, 2.70, 0.18
-- These places have their own town-map region even though their maps use
-- indoor tilesets. Floors/rooms share the same name and never repeat it.
local WILDERNESS = {}
for _, name in ipairs({"VIRIDIAN FOREST", "MT.MOON", "ROCK TUNNEL",
    "SEAFOAM ISLANDS", "VICTORY ROAD", "DIGLETT's CAVE", "SAFARI ZONE",
    "CERULEAN CAVE", "POWER PLANT"}) do WILDERNESS[Names[name]] = true end

local function japanese(text)
  return type(text) == "string" and text:find("[\227-\233]") ~= nil
end

local function translated(game, source)
  if type(source) ~= "string" or source == "" then return nil end
  local text = (game.data.strings or {})[source] or Names[source] or source
  -- Unknown MOD map IDs must not leak an English/internal fallback into a
  -- Japanese banner. A localized town-map name always takes priority.
  if japanese(text) then return text:gsub("[\r\n]", " ") end
end

function Banner.location(game, map)
  if not (map and map.id) then return nil end
  local tm = (game.data.field or {}).townMap or {}
  local entry = (tm.locations or tm)[map.id]
  local def = map.def or (game.data.maps or {})[map.id] or {}
  local source = type(entry) == "table" and (entry.name or entry.label)
  local name = translated(game, source) or translated(game, def.name)
    or translated(game, map.id:gsub("_", " "))
  return name, name ~= nil and (Map.isOutside(def) or WILDERNESS[name] == true)
end

-- A banner never overlaps text, menus, scripted walks, an encounter, or a
-- loading/fade state. Ordinary player movement is deliberately allowed.
function Banner.available(game)
  local ow = game and game.overworld
  if not (game and game.data and game.data.constants
      and game.data.constants.language == "ja" and ow and ow.map
      and ow.player and game.stack and game.stack:top() == ow) then return false end
  if game.sessionMenu or ow.transitioning or ow.engaging or ow.emote
      or ow.player.inputLocked or ow.flyAnim or ow.flyArrive or ow.spinArrive
      or ow.teleportOut or ow.holeFall or ow.holeArrive then return false end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return false end
  if ow.scriptMoves and #ow.scriptMoves > 0 then return false end
  if ow.pendingScripts and #ow.pendingScripts > 0 then return false end
  return true
end

function Banner.update(game, dt)
  if not (game.data and game.data.constants and game.data.constants.language == "ja") then
    game._jpAreaBanner = nil
    return
  end
  local s = game._jpAreaBanner
  if not s or s.save ~= game.save or s.data ~= game.data then
    s = {save = game.save, data = game.data}
    game._jpAreaBanner = s
  end
  local map = game.overworld and game.overworld.map
  local id = map and map.id
  if id ~= s.mapId then
    s.mapId = id
    s.name, s.eligible = Banner.location(game, map)
    if not s.eligible or not s.active or s.active.name ~= s.name then s.active = nil end
    s.pending = s.eligible and s.name ~= s.lastShown and s.name or nil
    s.settled = 0
  end
  if not s.eligible or not Banner.available(game) then
    s.settled = 0
    return
  end
  dt = math.max(0, math.min(tonumber(dt) or 0, 0.10))
  if s.pending then
    s.settled = (s.settled or 0) + dt
    if s.settled >= SETTLE then
      s.active = {name = s.pending, time = 0}
      s.pending = nil
    end
  end
  local active = s.active
  -- Do not consume the notice while no rendered frame has presented it.
  if active and active.presented then
    active.time = active.time + dt
    if active.time >= DURATION then s.active = nil end
  end
end

function Banner.metrics(game, text)
  local viewport = Viewport.active() and Viewport.rect
  local bounds = viewport and {x=viewport.x, y=viewport.y,
    w=viewport.width, h=viewport.height} or nil
  local rect = Layout.usable(false, bounds)
  local p = Layout.panelMetrics(game, {rect=rect, minHeight=32})
  local margin = math.min(p.margin, math.floor(math.min(rect.w*p.dpiX, rect.h*p.dpiY)*.04))
  if rect.h*p.dpiY-2*margin < 32 then return nil end
  local scale = math.max(1, math.min(p.scale,
    math.floor((rect.h*p.dpiY-2*margin)/32)))
  local maxWidth = math.floor((rect.w*p.dpiX-2*margin)/scale/8)*8
  if maxWidth < 40 then return nil end
  local spans = Font.split(text)
  local count = Font.spansFitting(spans, maxWidth-24)
  text = count > 0 and text:sub(1, spans[count].to) or ""
  local width = math.min(maxWidth, math.max(88, math.ceil((Font.width(text)+24)/8)*8))
  local x = math.floor(rect.x*p.dpiX+margin)/p.dpiX
  local y = math.floor(rect.y*p.dpiY+margin)/p.dpiY
  return {x=x, y=y, w=width*scale/p.dpiX, h=32*scale/p.dpiY,
    width=width, sx=scale/p.dpiX, sy=scale/p.dpiY, text=text, rect=rect}
end

function Banner.draw(game)
  local s = game._jpAreaBanner
  local active = s and s.active
  if not active or not Banner.available(game) then return end
  local m = Banner.metrics(game, active.name)
  if not m then return end
  local options = game.save and game.save.options or {}
  local offset = 0
  if not (options.reduceMotion or options.jpReduceMotion) then
    local t = math.min(1, active.time/SLIDE)
    offset = math.min(math.floor(4*(1-t)*(1-t))*m.sy,
      math.max(0,m.rect.y+m.rect.h-m.y-m.h))
  end
  local g = love.graphics
  g.push("all")
  g.origin()
  g.setShader()
  g.setScissor()
  g.setBlendMode("alpha")
  g.setColor(1,1,1,1)
  g.translate(m.x, m.y+offset)
  g.scale(m.sx, m.sy)
  Font.drawBox(0, 0, m.width/8, 4)
  Font.draw(m.text, math.floor((m.width-Font.width(m.text))/2), 16)
  g.pop()
  active.presented = true
  s.lastShown = active.name
  return m
end

return Banner
