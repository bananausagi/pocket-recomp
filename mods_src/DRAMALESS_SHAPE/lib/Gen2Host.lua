-- jp.90: the overworld state the voxel pipeline reads, built from a gen2
-- World.  VoxelScene/ThirdPerson read `state.map`, `state.neighbors[i].map`,
-- `state.ghosts[i].map`, `state.entities`, `state.player:pose()`,
-- `state.camera` and `state.flyAnim`; the gen2 World carries the same facts
-- under other shapes (neighbors by id, a Player without pose()).  One stable
-- table per world, refreshed in place each call, so identity-keyed caches in
-- the pipeline see the same objects frame to frame.

local V = ...

local Gen2Facade = V.require("Gen2Facade")

local Gen2Host = {}

local hosts = setmetatable({}, { __mode = "k" })

function Gen2Host.active()
  local ok, GV = pcall(require, "src.core.GameVersion")
  if not ok or not GV or not GV.generation then return false end
  local ok2, g = pcall(GV.generation)
  return ok2 and g == 2
end

-- Red's pose contract: sprite, px, visual py, facing, phase, flip, hopping
local function playerProxy(real)
  local proxy = setmetatable({}, { __index = real })
  proxy.pose = function()
    local p = real
    local phase = p.walkPhase and p:walkPhase() or 0
    local flip = p.drawFlip and p:drawFlip() or false
    return p.sprite, p.px, (p.py or 0) + (p.spriteYOffset or 0), p.facing,
      phase, flip, p.jumping and true or false
  end
  return proxy
end

-- jp.91: the game's clock for DayNight -- hHours plus hMinutes as a
-- fraction, 0..24.  World:hour honours the clockHour pin a driver sets
-- (POKEPORT_GOLD_HOUR), so a forced hour reaches the diorama as well as the
-- 2D palette.  nil when there is no world yet; DayNight then falls back to
-- the wall clock for that frame.
function Gen2Host.hours()
  local ok, Game = pcall(require, "src.core.Game")
  local world = ok and Game and Game.overworld or nil
  if not (world and world.hour) then return nil end
  local okH, h = pcall(world.hour, world)
  if not okH or type(h) ~= "number" then return nil end
  local m = 0
  if world.minute then
    local okM, mn = pcall(world.minute, world)
    if okM and type(mn) == "number" then m = mn end
  end
  return h + m / 60
end

-- The game's hour laid onto DayNight's dial.  The dial's dawn sits at 06:00
-- (Red syncs to the wall clock, where that is sunrise), but the game's
-- morning palette starts at MORN 04:00 and its night at 18:00.  Stretch the
-- day so those two edges land on the dial's dawn and dusk pins: 04..18 ->
-- 06..18 and 18..28 -> 18..30.  Pure arithmetic on the hour, so the dial's
-- own keyframes are untouched and Red (no game clock) never sees it.
function Gen2Host.dialHours()
  local h = Gen2Host.hours()
  if not h then return nil end
  if h < 4 then h = h + 24 end
  if h < 18 then return 6 + (h - 4) * (12 / 14) end
  return (18 + (h - 18) * (12 / 10)) % 24
end

-- Hand the clock to DayNight once.  Only ever reached when the generation is
-- 2 (module load below, and every state() refresh), so Red never sees it.
local function installClock()
  local DayNight = V.require("DayNight")
  if DayNight.gameClock ~= Gen2Host.dialHours then
    DayNight.gameClock = Gen2Host.dialHours
    DayNight.gameHour = Gen2Host.hours
  end
end

function Gen2Host.state(world)
  if not (world and world.map and world.maps) then return nil end
  installClock()
  local h = hosts[world]
  if not h then
    h = { neighbors = {}, ghosts = {}, entities = {}, proxies = setmetatable({}, { __mode = "k" }) }
    hosts[world] = h
  end
  local map = Gen2Facade.forMap(world, world.map.id)
  if not map then return nil end
  h.map = map
  h.world = world
  h.camera = world.camera
  h.flyAnim = world.flyAnim
  h.transitioning = world.transitioning

  local nb = h.neighbors
  local n = 0
  for _, src in ipairs(world.neighbors or {}) do
    local fm = src.id ~= nil and Gen2Facade.forMap(world, src.id) or nil
    if fm then
      n = n + 1
      local e = nb[n]
      if not e then e = {}; nb[n] = e end
      e.map, e.ox, e.oy, e.id = fm, src.ox or 0, src.oy or 0, fm.id
    end
  end
  for i = #nb, n + 1, -1 do nb[i] = nil end

  local gh = h.ghosts
  n = 0
  for _, g in ipairs(world.ghosts or {}) do
    local gid = g.map and g.map.id
    local fm = gid ~= nil and Gen2Facade.forMap(world, gid) or nil
    if fm and g.npc then
      n = n + 1
      local e = gh[n]
      if not e then e = {}; gh[n] = e end
      e.npc, e.map, e.ox, e.oy = g.npc, fm, g.ox or 0, g.oy or 0
    end
  end
  for i = #gh, n + 1, -1 do gh[i] = nil end

  local real = world.player
  local proxy = nil
  if real then
    proxy = h.proxies[real]
    if not proxy then proxy = playerProxy(real); h.proxies[real] = proxy end
  end
  h.player = proxy
  local ents = h.entities
  n = 0
  for _, e in ipairs(world.entities or {}) do
    n = n + 1
    ents[n] = (e == real) and proxy or e
  end
  for i = #ents, n + 1, -1 do ents[i] = nil end
  return h
end

-- jp.91: the clock is wanted before the first 3D frame too (the flat path's
-- DayTint and the world.tod hook read DayNight), so install it at load.
if Gen2Host.active() then installClock() end

return Gen2Host
