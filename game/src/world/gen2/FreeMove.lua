-- jp.76 3D free movement (option jp3DFree, off by default, only while the 3D
-- field is live).  The player walks continuously in the direction of the
-- analog stick / touch stick / d-pad (8-way) instead of in whole-cell steps.
--
-- The grid is still the truth for the game: the player's cellX/cellY are the
-- cell under the body's centre, and the moment the centre crosses into a new
-- cell that crossing is reported as a landed step, so World:stepBody's own
-- arrival pipeline (warps, coord scripts, step count, wild grass) runs exactly
-- as it does for a grid step.  Whatever the grid has to decide on its own --
-- ledges, map connections, boulders, carpets, currents, ice, surfing, the
-- Cycling Road, any script -- is handed back to the grid by snapping the body
-- onto its cell first.
--
-- The core below (FreeMove.advance) is love-free so it can be tested headless.
local FreeMove = {}

FreeMove.RADIUS = 5.5          -- body half-width in pixels (a cell is 16)
FreeMove.PUSH_FRAMES = 8       -- frames of pushing a wall before the grid tries
FreeMove.DEADZONE = 0.25
local CELL = 16
local EPS = 1e-3

local function cellOf(v) return math.floor((v + 8) / CELL) end

local function dirOf(dx, dy)
  if math.abs(dx) >= math.abs(dy) then
    if dx > 0 then return "right" elseif dx < 0 then return "left" end
    return nil
  end
  return dy > 0 and "down" or "up"
end
FreeMove.dirOf = dirOf

-- The cells a body centred at (cx, cy) (pixel centre) covers.
local function span(c, r)
  return math.floor((c - r) / CELL), math.floor((c + r - EPS) / CELL)
end

-- May the body, standing in (fx, fy), come to overlap (tx, ty)?
-- canEnter(fx, fy, tx, ty, dir) answers one orthogonal step.
local function reachable(canEnter, fx, fy, tx, ty)
  if fx == tx and fy == ty then return true end
  local ddx, ddy = tx - fx, ty - fy
  if math.abs(ddx) > 1 or math.abs(ddy) > 1 then return false end
  local hx = ddx > 0 and "right" or "left"
  local hy = ddy > 0 and "down" or "up"
  if ddy == 0 then return canEnter(fx, fy, tx, ty, hx) == true end
  if ddx == 0 then return canEnter(fx, fy, tx, ty, hy) == true end
  return (canEnter(fx, fy, tx, fy, hx) == true and canEnter(tx, fy, tx, ty, hy) == true)
      or (canEnter(fx, fy, fx, ty, hy) == true and canEnter(fx, ty, tx, ty, hx) == true)
end

-- Move along one axis by d.  Only cells the moved body newly covers are
-- tested, so a body already overlapping something (an NPC that walked up)
-- can always back away.  Answers the moved-to coordinate and, when cut
-- short, the edge kind canEnter gave ("edge" for out of bounds).
local function moveAxis(body, axis, d, canEnter, r)
  if d == 0 then return true end
  local cx, cy = body.px + 8, body.py + 8
  local ox0, ox1 = span(cx, r)
  local oy0, oy1 = span(cy, r)
  local ncx, ncy = cx, cy
  if axis == "x" then ncx = cx + d else ncy = cy + d end
  local nx0, nx1 = span(ncx, r)
  local ny0, ny1 = span(ncy, r)
  local blockedEdge
  for gx = nx0, nx1 do
    for gy = ny0, ny1 do
      local old = gx >= ox0 and gx <= ox1 and gy >= oy0 and gy <= oy1
      if not old and not reachable(canEnter, body.cellX, body.cellY, gx, gy) then
        local hdir = axis == "x" and (d > 0 and "right" or "left")
          or (d > 0 and "down" or "up")
        local tx, ty = body.cellX, body.cellY
        if axis == "x" then tx = gx else ty = gy end
        local why = canEnter(body.cellX, body.cellY, tx, ty, hdir)
        blockedEdge = blockedEdge or (why == "edge" and "edge" or "blocked")
        if why == "edge" then blockedEdge = "edge" end
      end
    end
  end
  if not blockedEdge then
    if axis == "x" then body.px = body.px + d else body.py = body.py + d end
    return true
  end
  -- flush against the blocking cell, never backwards
  local c = axis == "x" and cx or cy
  local limit
  if d > 0 then
    local hi = (axis == "x") and nx1 or ny1
    limit = math.max(c, hi * CELL - r - EPS * 2)
    limit = math.min(limit, c + d)
  else
    local lo = (axis == "x") and nx0 or ny0
    limit = math.min(c, (lo + 1) * CELL + r + EPS * 2)
    limit = math.max(limit, c + d)
  end
  -- the flush point must itself be clear; if not, stay put
  if axis == "x" then body.px = limit - 8 else body.py = limit - 8 end
  return false, blockedEdge
end

-- One frame of free movement.
--   body     : { px, py, cellX, cellY, push = frames pushed }
--   vx, vy   : world-space direction, length <= 1
--   speed    : pixels per frame at full tilt
--   canEnter : function(fx, fy, tx, ty, dir) -> true | "edge" | false
-- Answers a result table:
--   crossed  : true when the centre entered a new cell (cellX/cellY updated)
--   dir      : the dominant direction of travel (nil when idle)
--   push     : a direction to hand to the grid (wall pushed long enough, or
--              the map edge) -- the caller snaps and runs the grid step
--   moved    : pixels travelled this frame
function FreeMove.advance(body, vx, vy, speed, canEnter, opts)
  local r = (opts and opts.radius) or FreeMove.RADIUS
  local pushFrames = (opts and opts.pushFrames) or FreeMove.PUSH_FRAMES
  local out = { crossed = false, moved = 0 }
  local mag = math.sqrt(vx * vx + vy * vy)
  if mag < EPS then body.push = 0; return out end
  if mag > 1 then vx, vy, mag = vx / mag, vy / mag, 1 end
  local dir = dirOf(vx, vy)
  out.dir = dir
  local sx, sy = body.px, body.py
  local dx, dy = vx * speed, vy * speed
  -- larger component first, so a diagonal into a corner keeps its main way
  local okx, edgex, oky, edgey = true, nil, true, nil
  if math.abs(dx) >= math.abs(dy) then
    okx, edgex = moveAxis(body, "x", dx, canEnter, r)
    oky, edgey = moveAxis(body, "y", dy, canEnter, r)
  else
    oky, edgey = moveAxis(body, "y", dy, canEnter, r)
    okx, edgex = moveAxis(body, "x", dx, canEnter, r)
  end
  local mainBlocked, mainEdge
  if dir == "left" or dir == "right" then mainBlocked, mainEdge = not okx, edgex
  else mainBlocked, mainEdge = not oky, edgey end

  -- doorway assist: pushing straight at a gap the body is a little off, slide
  -- toward the centre of the cell row/column it is in when the cell straight
  -- ahead is open.
  if mainBlocked then
    local d = (dir == "left" or dir == "right") and { (dir == "right") and 1 or -1, 0 }
      or { 0, (dir == "down") and 1 or -1 }
    local ahead = canEnter(body.cellX, body.cellY, body.cellX + d[1], body.cellY + d[2], dir)
    if ahead == true then
      -- the perpendicular input that pushed the body off the gap column is
      -- what is being corrected here, so the nudge is free (not limited by
      -- how far the main axis already went), and the main axis gets one more
      -- try in the same frame -- otherwise a slightly diagonal stick
      -- re-pushes sideways every frame and the body jitters at the door.
      local mainAxis = d[1] ~= 0 and "x" or "y"
      local perp = d[1] ~= 0 and "y" or "x"
      local off = (perp == "y") and (body.cellY * CELL - body.py) or (body.cellX * CELL - body.px)
      if math.abs(off) > EPS then
        local step = math.max(-speed, math.min(speed, off))
        moveAxis(body, perp, step, canEnter, r)
      end
      local rest = speed * ((mainAxis == "x") and math.abs(vx) or math.abs(vy))
      local moved = (mainAxis == "x") and math.abs(body.px - sx) or math.abs(body.py - sy)
      if rest - moved > EPS then
        moveAxis(body, mainAxis, (rest - moved) * ((mainAxis == "x") and d[1] or d[2]), canEnter, r)
      end
      -- still counted as blocked if the main axis made no headway at all, so
      -- a stuck push still reaches the grid (which steps straight in)
      local headway = (mainAxis == "x") and math.abs(body.px - sx) or math.abs(body.py - sy)
      mainBlocked = headway < EPS
    end
  end

  out.moved = math.sqrt((body.px - sx) ^ 2 + (body.py - sy) ^ 2)
  local ncx, ncy = cellOf(body.px), cellOf(body.py)
  if ncx ~= body.cellX or ncy ~= body.cellY then
    out.crossed = true
    out.fromX, out.fromY = body.cellX, body.cellY
    body.cellX, body.cellY = ncx, ncy
  end
  if mainBlocked and out.moved < speed * 0.25 then
    body.push = (body.push or 0) + 1
    if mainEdge == "edge" or body.push >= pushFrames then out.push = dir end
  else
    body.push = 0
  end
  return out
end

-- Snap a body onto its cell (the grid's own resting position).
function FreeMove.snap(p)
  if not p then return end
  p.px, p.py = p.cellX * CELL, p.cellY * CELL
  p.freeMoving = nil
  p.freePush = 0
end

function FreeMove.offGrid(p)
  return p and not p.moving and (p.px ~= p.cellX * CELL or p.py ~= p.cellY * CELL)
end

-- The input vector, screen space (x right, y down), length <= 1.
-- Priority: gamepad analog stick, touch stick, 8-way d-pad.
function FreeMove.inputVector(input, touch)
  local sa = input and input.stickAxis
  if sa then
    local x, y = tonumber(sa.x) or 0, tonumber(sa.y) or 0
    local m = math.sqrt(x * x + y * y)
    if m > FreeMove.DEADZONE then
      if m > 1 then x, y = x / m, y / m end
      return x, y
    end
  end
  if touch and touch.active then
    local x, y = tonumber(touch.x) or 0, tonumber(touch.y) or 0
    local m = math.sqrt(x * x + y * y)
    if m > FreeMove.DEADZONE then
      if m > 1 then x, y = x / m, y / m end
      return x, y
    end
  end
  if input and input.isDown then
    local x, y = 0, 0
    if input:isDown("left") then x = x - 1 end
    if input:isDown("right") then x = x + 1 end
    if input:isDown("up") then y = y - 1 end
    if input:isDown("down") then y = y + 1 end
    local m = math.sqrt(x * x + y * y)
    if m > 0 then return x / m, y / m end
  end
  return 0, 0
end

-- Screen-space input to map space for a camera yaw (radians, 0 = map up).
function FreeMove.rotate(x, y, yaw)
  local c, s = math.cos(yaw), math.sin(yaw)
  return x * c - y * s, x * s + y * c
end

return FreeMove
