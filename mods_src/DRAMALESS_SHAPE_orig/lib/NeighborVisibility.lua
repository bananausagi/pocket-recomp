-- Distance to a connected map means distance to its nearest edge, not to
-- its top-left origin. A tall/wide route may start several screens away
-- while the player is standing immediately beside its south/east boundary.
-- Coordinates here are world pixels (map blocks: 32 px, player cells: 16 px).
local Visibility = {}

function Visibility.playerPosition(player)
  player = player or {}
  return tonumber(player.px) or (tonumber(player.cellX) or 0) * 16,
         tonumber(player.py) or (tonumber(player.cellY) or 0) * 16
end

function Visibility.distanceSquared(neighbor, player)
  local px, py = Visibility.playerPosition(player)
  local ox, oy = neighbor.ox or 0, neighbor.oy or 0
  local def = neighbor.map and neighbor.map.def or {}
  local ex, ey = ox + (def.width or 0) * 32,
                 oy + (def.height or 0) * 32
  local x, y = math.max(ox, math.min(px, ex)),
               math.max(oy, math.min(py, ey))
  return (px - x) ^ 2 + (py - y) ^ 2
end

function Visibility.contains(neighbor, player, radius)
  return Visibility.distanceSquared(neighbor, player) <= radius * radius
end

return Visibility
