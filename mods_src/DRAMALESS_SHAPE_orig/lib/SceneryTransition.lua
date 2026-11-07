-- Dissolve changed distant terrain in the live camera, before actors and UI.
-- Keep at most two mesh layouts, never a frozen screenshot or another large
-- render target. Common meshes draw once; retained pages keep normal ownership.
local V = ...
local Map = require('src.world.Map')
local Game = require('src.core.Game')
local Mat4 = V.require('Mat4')
local F = { DURATION = .60 }
F.setting = V.require('ModSetting').new('sceneryFade', 'SCENERY FADE',
  { false, true }, { 'OFF', 'ON' }, 2)
local current, previous, elapsed, data, reversed = nil, nil, 0, nil, false
local function release(frame)
  if frame then for _,r in ipairs(frame.rows) do r.mesh:release() end end
end
function F.invalidate()
  release(previous); release(current)
  previous, current, elapsed, data, reversed = nil, nil, 0, nil, false
end
function F.update(dt)
  if previous then
    elapsed = math.min(F.DURATION, elapsed + math.max(0, math.min(dt or 0, .1)))
    if elapsed >= F.DURATION then release(previous); previous = nil end
  end
end
local function enabled(state)
  local options = Game.save and Game.save.options or {}
  return state.map and Map.isOutdoor(state.map.def) and F.setting:get()
    and not options.reduceMotion and not options.jpReduceMotion
end
local function same(a, b)
  if not a or #a.rows ~= #b.rows then return false end
  for i,r in ipairs(a.rows) do
    local s = b.rows[i]
    if r.map ~= s.map or r.mesh ~= s.mesh or r.x ~= s.x or r.z ~= s.z then return false end
  end
  return true
end
local function retain(frame)
  for _,r in ipairs(frame.rows) do r.mesh:retain() end
  return frame
end
local function origin(state)
  if not current then return 0, 0 end
  if current.map == state.map then return current.x, current.z end
  -- Offsets come from the connection graph, not from the character's
  -- integer cell or screen position. Fractional walking stays continuous.
  for _,r in ipairs(current.neighbors) do
    if r.map == state.map then return current.x+r.ox, current.z+r.oy end
  end
  for _,r in ipairs(state.neighbors or {}) do
    if r.map == current.map then return current.x-r.ox, current.z-r.oy end
  end
end
function F.prepare(state, terrain, neighbors, visible)
  if data ~= Game.data or not enabled(state) then F.invalidate() end
  data = Game.data
  if not enabled(state) then return nil end
  local x,z = origin(state)
  if not x then F.invalidate(); data=Game.data; x,z=0,0 end
  local next = { map=state.map, x=x, z=z, rows={}, neighbors={} }
  local function add(map, mesh, ox, oz)
    if not mesh then return true end
    -- Foreign non-owning mesh types keep the ordinary rendering path.
    if type(mesh)~='table' or not mesh.retain then return false end
    next.rows[#next.rows+1]={ map=map, mesh=mesh, x=x+ox, z=z+oz }
    return true
  end
  if not add(state.map,terrain,0,0) then F.invalidate(); return nil end
  for i,nb in ipairs(state.neighbors or {}) do
    next.neighbors[i]={ map=nb.map, ox=nb.ox, oy=nb.oy }
    if visible(nb) and not add(nb.map,neighbors[i],nb.ox,nb.oy) then
      F.invalidate(); return nil
    end
  end
  table.sort(next.rows,function(a,b)return a.map.id < b.map.id end)
  if same(current,next) then
    -- The root may change while every ready mesh remains the same.
    current.map,current.x,current.z,current.neighbors=next.map,x,z,next.neighbors
  elseif previous and same(previous,next) then
    -- Turning back halfway through a boundary crossing reverses the same
    -- dissolve instead of jumping back to either complete scene.
    previous,current=current,previous
    current.map,current.x,current.z,current.neighbors=next.map,x,z,next.neighbors
    elapsed=F.DURATION-elapsed
    reversed=not reversed
  else
    retain(next)
    if previous and current.map == next.map then
      -- A late ring/body replaces the incoming layout without restarting
      -- the boundary fade. Its existing outgoing scenery stays visible.
      release(current)
    else
      release(previous); previous=current; elapsed=0; reversed=false
    end
    current=next
  end
  if not previous then return nil end
  return { current=current, previous=previous, x=x, z=z,
    progress=math.min(1,elapsed/F.DURATION), reversed=reversed }
end
function F.draw(frame, atlasFor)
  if not frame then return false end
  local C=V.require('Voxel3D')
  local t=frame.progress; t=t*t*(3-2*t)
  local common={}
  for _,r in ipairs(frame.current.rows) do
    for _,s in ipairs(frame.previous.rows) do
      if r.mesh==s.mesh and r.x==s.x and r.z==s.z then common[r]=true;common[s]=true;break end
    end
  end
  local function draw(r)
    C.draw(r.mesh,atlasFor(r.map),Mat4.translate(r.x-frame.x,0,r.z-frame.z))
  end
  C.sceneryDissolve(0)
  for _,r in ipairs(frame.current.rows) do if common[r] then draw(r) end end
  C.sceneryDissolve(1,t,frame.reversed)
  for _,r in ipairs(frame.current.rows) do if not common[r] then draw(r) end end
  C.sceneryDissolve(-1,t,frame.reversed)
  for _,r in ipairs(frame.previous.rows) do if not common[r] then draw(r) end end
  C.sceneryDissolve(0)
  return true
end
return F
