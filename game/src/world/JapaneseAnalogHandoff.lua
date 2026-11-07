-- Short visual continuity when fractional walking returns to the native
-- grid. The engine's pixels, cells, collision and step timing stay native;
-- pose(), the field camera and 3D ground placement share this same offset.
local Handoff = {}
local active = setmetatable({}, { __mode = "k" })
local FRAMES = 8

local function current(player)
  local h = active[player]
  if not h then return nil end
  local game = require("src.core.Game")
  local world, map = h.refs.world, h.refs.map
  if not world or not map or game.overworld ~= world or world.player ~= player
      or world.map ~= map or player.px ~= h.rawX or player.py ~= h.rawY then
    -- A warp/load/external move owns its new location, even on the same map.
    active[player] = nil
    return nil
  end
  return h
end

function Handoff.offset(player)
  local h = current(player)
  if not h then return 0, 0 end
  local weight = 1 - h.age / FRAMES
  return h.dx * weight, h.dy * weight
end

function Handoff.position(player)
  local dx, dy = Handoff.offset(player)
  return player.px + dx, player.py + dy
end

-- A live analog camera can resume before the grid offset has settled (for
-- example, closing settings immediately). Adopt the visible position once.
function Handoff.resume(player, world)
  local h = current(player)
  if not h or h.refs.world ~= world then return end
  local x, y = Handoff.position(player)
  active[player] = nil
  player.px, player.py = x, y
end

local function install()
  local Player = require("src.world.Player")
  if Player.jpAnalogHandoffHook then return end
  local update, pose = Player.update, Player.pose
  function Player:update(...)
    local h = current(self)
    local completed = update(self, ...)
    if h and active[self] == h then
      local world = h.refs.world
      if not world or world.map ~= h.refs.map or world.player ~= self
          or math.abs(self.cellX - h.cellX) > 1 or math.abs(self.cellY - h.cellY) > 1 then
        active[self] = nil
      else
        h.age = h.age + 1
        h.rawX, h.rawY = self.px, self.py
        h.cellX, h.cellY = self.cellX, self.cellY
        if h.age >= FRAMES then active[self] = nil end
      end
    end
    return completed
  end
  function Player:pose(...)
    local sprite, px, py, facing, phase, flip, hopping = pose(self, ...)
    local dx, dy = Handoff.offset(self)
    return sprite, px + dx, py + dy, facing, phase, flip, hopping
  end
  Player.jpAnalogHandoffHook = true
end

-- Called after FreeMove seats its owned point on the logical cell. Keep the
-- previous rendered point as a temporary offset, not as gameplay state.
function Handoff.begin(player, world, fromX, fromY)
  install()
  local dx, dy = fromX - player.px, fromY - player.py
  if math.abs(dx) < 1e-7 and math.abs(dy) < 1e-7 then active[player] = nil; return end
  -- Weak ownership breaks world -> player -> offset -> world cycles on
  -- LuaJIT, so a paused handoff cannot retain an old map after leaving play.
  active[player] = { refs = setmetatable({world=world,map=world.map},{__mode="v"}),
    dx = dx, dy = dy, age = 0,
    rawX = player.px, rawY = player.py, cellX = player.cellX, cellY = player.cellY }
end

return Handoff
