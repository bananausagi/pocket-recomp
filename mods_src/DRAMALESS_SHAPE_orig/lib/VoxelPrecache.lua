-- Predictive voxel-area precaching.
--
-- VoxelScene already streams the current map and the bodies of connected
-- neighbours.  That makes a seamless route crossing cheap, but a door/stair
-- warp names a map which is not rendered yet, so historically its first mesh
-- request happened only after the map swap.  This module uses the engine's
-- authoritative warp resolver to discover those destinations while the player
-- is still in the current area and feeds them through ChunkMesher's ordinary
-- cooperative queue.  Nothing is built synchronously and no option/menu action
-- is needed.
--
-- Direct connections have their own four-direction allocation, separate from
-- the two closest doors. All four bodies/atlases are prepared, while only the
-- nearest two connections within 16 cells request decorative full rings. The nearest
-- connection also prepares up to six bodies beyond the currently visible set,
-- so re-rooting the two-hop view at a seam has less new work to discover.
-- Everything uses the ordinary caches and the same cooperative frame budget.

local V = ...

local ChunkMesher = V.require("ChunkMesher")

local Precache = {}

local rootId, rootData, rootMap, lastX, lastY, lastOutdoor, lastViewW, lastViewH
local candidates, selected, arriving, ahead = {}, {}, {}, {}
local MAX_WARPS, MAX_AHEAD, ATLAS_SLICE = 2, 6, .001
local APPROACH_CELLS = 16
local confirmed

-- The native warp has resolved its exact destination before its fade.
-- Pin that destination instead of guessing among overlapping door tiles.
function Precache.prepareDestination(game,id)
  local ow=game and game.overworld
  if not (ow and ow.map and game.data and game.data.maps and game.data.maps[id]) or id==ow.map.id then return false end
  confirmed={id=id,map=ow.map,data=game.data}
  lastX=nil -- re-rank even if the player is stationary during the fade
  return true
end

local function addCandidate(out, seen, id, distance, kind)
  if not id then return end
  local previous=seen[id]
  if previous==true then return end
  if previous then
    -- A map connected outdoors must not lose its allocation merely because
    -- a door names that same map too.
    if kind=="connection" or (previous.kind~="connection" and distance<previous.distance) then
      previous.distance,previous.kind=distance,kind
    end
    return
  end
  local row={ id=id, distance=distance or math.huge, kind=kind }
  seen[id]=row
  out[#out+1]=row
end

local function warpDistance(player, warp)
  if not (player and warp) then return math.huge end
  local px = player.targetX or player.cellX or 0
  local py = player.targetY or player.cellY or 0
  local dx, dy = (warp.x or px) - px, (warp.y or py) - py
  return dx * dx + dy * dy
end

local function edgeDistance(player, def, dir, connection, dest)
  if not (player and def) then return math.huge end
  local x = player.targetX or player.cellX or 0
  local y = player.targetY or player.cellY or 0
  -- Distance to the actual connected strip, including its lateral offset;
  -- standing near an unrelated part of a long boundary is not an approach.
  local horizontal=dir=="north" or dir=="south"
  local offset=(connection.offset or 0)*2
  local first=math.max(0,offset)
  local last=math.min((horizontal and def.width or def.height)*2-1,
    offset+(horizontal and dest.width or dest.height)*2-1)
  if last<first then return math.huge end
  local along=horizontal and x or y
  local lateral=along-math.max(first,math.min(along,last))
  local across=dir=="north" and y or dir=="south" and (def.height*2-1-y)
    or dir=="west" and x or (def.width*2-1-x)
  return across*across+lateral*lateral
end

-- Pure candidate discovery, exposed for the headless suite.  Warp.destination
-- is deliberately used instead of reading destMap directly: LAST_MAP exits and
-- compatibility hooks must predict the same place the real step will enter.
function Precache.candidates(data, overworld)
  local map = overworld and overworld.map
  local maps = data and data.maps
  if not (map and map.def and maps) then return {} end

  local out, seen = {}, { [map.id] = true }
  local okWarp, Warp = pcall(require, "src.world.Warp")
  if okWarp and Warp then
    for _, warp in ipairs(map.def.warps or {}) do
      local ok, id = pcall(function()
        local dest = Warp.destination(data, warp, overworld.lastOutdoor)
        return dest
      end)
      if ok and maps[id] then
        addCandidate(out, seen, id, warpDistance(overworld.player, warp), "warp")
      end
    end
  end

  -- Connected bodies are already warm because they are visible, but their
  -- FULL variants (including the destination's own border ring) are not.
  -- Queue direct connections here so crossing a seam promotes a complete map.
  for dir, connection in pairs(map.def.connections or {}) do
    if connection and maps[connection.map] then
      addCandidate(out, seen, connection.map,
                   edgeDistance(overworld.player, map.def, dir, connection, maps[connection.map]), "connection")
    end
  end

  table.sort(out, function(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    if a.kind ~= b.kind then return a.kind == "warp" end
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

-- Full-mesh masks must match the placement logic used by the live renderer;
-- otherwise a cached destination could grow border trees through a connected
-- route.  The engine owns this graph math, so do not duplicate it here.
local function neighborsFor(data,mapId,overworld)
  local ok, Controller = pcall(require, "src.world.OverworldController")
  if not (ok and Controller and Controller.computeNeighbors) then return {} end
  local w,h=overworld and overworld.neighborViewW,overworld and overworld.neighborViewH
  local hops=data.constants and data.constants.world and data.constants.world.neighborHops or 2
  return Controller.computeNeighbors(data.maps,mapId,hops,
    w and math.floor(w/2)+64,h and math.floor(h/2)+64) or {}
end

function Precache.masksFor(data, mapId, overworld)
  local out = {}
  for _, nb in ipairs(neighborsFor(data,mapId,overworld)) do
    local def = data.maps[nb.id]
    if def then
      out[#out + 1] = {
        nb.ox, nb.oy,
        nb.ox + def.width * 32,
        nb.oy + def.height * 32,
      }
    end
  end
  return out
end

local function scene()
  local ok,value=pcall(V.require,"VoxelScene")
  return ok and value or nil
end

local function releaseAtlas(row)
  local sc=scene()
  if row.map and not row.atlasDone and sc and sc.cancelWarmAtlas then
    pcall(sc.cancelWarmAtlas,row.map)
  end
end

local function retain(live)
  if ChunkMesher.setPredictive then ChunkMesher.setPredictive(live) end
  local ok,atlas=pcall(V.require,"TerrainAtlas")
  if ok and atlas.setPredictive then atlas.setPredictive(live) end
end

local function rerank(data,overworld)
  local player=overworld.player or {}
  local x,y=player.targetX or player.cellX or 0,player.targetY or player.cellY or 0
  if rootId==overworld.map.id and rootData==data and rootMap==overworld.map
      and lastX==x and lastY==y and lastOutdoor==overworld.lastOutdoor
      and lastViewW==overworld.neighborViewW and lastViewH==overworld.neighborViewH then return end
  local reset=rootData~=data or rootMap~=overworld.map
  local previous={}
  for _,row in ipairs(selected) do previous[row.id]=row end
  for _,row in ipairs(ahead) do previous[row.id]=row end
  candidates=Precache.candidates(data,overworld)
  if confirmed and (confirmed.map~=overworld.map or confirmed.data~=data) then confirmed=nil end
  if confirmed then
    for i=#candidates,1,-1 do if candidates[i].id==confirmed.id then table.remove(candidates,i) end end
    table.insert(candidates,1,{id=confirmed.id,distance=0,kind="confirmed"})
  end
  local nextSelected,live,visible,nearby={},{},{[overworld.map.id]=overworld.map},{}
  for _,nb in ipairs(overworld.neighbors or {}) do visible[nb.map.id]=nb.map end
  local warps,connections=0,0
  for _,candidate in ipairs(candidates) do
    if candidate.kind=="connection" or warps<MAX_WARPS then
      if candidate.kind~="connection" then warps=warps+1 end
      if candidate.kind=="connection" then
        connections=connections+1
        candidate.bodyOnly=connections>2 or candidate.distance>APPROACH_CELLS^2
        if candidate.bodyOnly and ChunkMesher.cancelPending then ChunkMesher.cancelPending(candidate.id,false) end
      end
      local old=rootData==data and previous[candidate.id]
      if old then candidate.map,candidate.atlasDone=old.map,old.atlasDone end
      candidate.map=visible[candidate.id] or candidate.map
      candidate.masks=Precache.masksFor(data,candidate.id,overworld)
      nextSelected[#nextSelected+1]=candidate;live[candidate.id]=true
      if candidate.kind=="connection" and candidate.distance<=APPROACH_CELLS^2 then
        nearby[candidate.id]=candidate.distance*256
      end
    end
  end
  table.sort(nextSelected,function(a,b)
    local function rank(row)return row.kind=="confirmed" and 0 or row.kind=="connection" and 1 or 2 end
    if rank(a)~=rank(b) then return rank(a)<rank(b) end
    if a.distance~=b.distance then return a.distance<b.distance end
    return tostring(a.id)<tostring(b.id)
  end)
  local nextAhead={}
  for _,target in ipairs(nextSelected) do
    if target.kind=="connection" and target.distance<=APPROACH_CELLS^2 then
      for _,nb in ipairs(neighborsFor(data,target.id,overworld)) do
        if not visible[nb.id] and not live[nb.id] and #nextAhead<MAX_AHEAD then
          local old=rootData==data and previous[nb.id]
          nextAhead[#nextAhead+1]={id=nb.id,kind="ahead",distance=target.distance+APPROACH_CELLS^2,
            map=old and old.map,atlasDone=old and old.atlasDone}
          live[nb.id]=true
        end
      end
      break -- one future neighbourhood, never the union of all four
    end
  end
  for _,row in pairs(previous) do
    if not live[row.id] then
      if reset and row.map==overworld.map and not row.atlasDone then
        -- Entering a partly prepared destination transfers ownership. Cancelling
        -- here would force its first live forMap call to recreate every frame.
        arriving[#arriving+1]=row
      elseif not visible[row.id] then releaseAtlas(row) end
    end
  end
  for i=#arriving,1,-1 do
    local row=arriving[i]
    if row.map~=overworld.map then releaseAtlas(row);table.remove(arriving,i) end
  end
  rootId,rootData,rootMap=overworld.map.id,data,overworld.map
  lastX,lastY,lastOutdoor=x,y,overworld.lastOutdoor
  lastViewW,lastViewH=overworld.neighborViewW,overworld.neighborViewH
  selected,ahead=nextSelected,nextAhead
  retain(live)
  if ChunkMesher.setApproaching then ChunkMesher.setApproaching(nearby) end
end

-- Only enqueue geometry here. Full destination builds can now outrank a far
-- neighbour body instead of waiting for the entire two-hop world queue.
-- A single incremental atlas step follows, using the renderer's exact live
-- palette resolver. No forMap call can upload all animation frames at once.
function Precache.update(game)
  local ow=game and game.overworld
  local data=game and game.data
  if not (ow and ow.map and data and data.maps) then return end
  rerank(data,ow)
  local prepared=false
  if arriving[1] then
    local row=arriving[1];local sc=scene()
    if sc and sc.warmAtlas then
      local ok,done=pcall(sc.warmAtlas,row.map,ATLAS_SLICE)
      if ok and done==true then row.atlasDone=true;table.remove(arriving,1) end
      prepared=true
    end
  end
  local sc=scene()
  -- Start atlas preparation before geometry completes. Live rendering then
  -- reuses a static atlas while its immutable animation frames finish.
  if not prepared and sc and sc.atlasReady and not sc.atlasReady(ow.map) then
    pcall(sc.warmAtlas,ow.map,ATLAS_SLICE)
    prepared=true
  end
  if not (ChunkMesher.peek(ow.map,false) or ChunkMesher.peek(ow.map,true) or confirmed) then return end
  local okLoader,MapLoader=pcall(require,"src.world.MapLoader")
  if not (okLoader and MapLoader and MapLoader.load) then return end
  local loaded=false
  local function prepare(row)
    -- Reuse the live neighbour object without waiting for the one-new-map
    -- allowance. Re-check speculative instances after a native LRU trim.
    if MapLoader.cached then row.map=MapLoader.cached(row.id) end
    if not row.map and not loaded then
      local ok,map=pcall(MapLoader.load,data,row.id)
      if ok and map then row.map=map end
      loaded=true -- at most one new runtime map per update
    end
    if row.map then
      local bodyOnly=row.kind=="ahead" or row.bodyOnly or false
      local known=ChunkMesher.slotKnown(row.map,bodyOnly)
      if sc and sc.atlasReady then row.atlasDone=sc.atlasReady(row.map) or nil end
      -- A cancelled prediction keeps its completed mesh if it is still a
      -- visible neighbour. Re-requesting changes priority, never generation.
      local isConfirmed=row.kind=="confirmed"
      if isConfirmed and not known and not ChunkMesher.slotKnown(row.map,true) then
        ChunkMesher.request(row.map,true,nil,true,0,true)
      end
      ChunkMesher.request(row.map,bodyOnly,row.masks,false,
        row.distance*16*16,true)
      if (known or isConfirmed or row.kind=="connection" or bodyOnly) and not row.atlasDone and not prepared then
        if sc and sc.warmAtlas then
          local ok,done=pcall(sc.warmAtlas,row.map,ATLAS_SLICE)
          row.atlasDone=ok and done==true or nil
          prepared=true
        end
      end
    end
  end
  for _,row in ipairs(selected) do prepare(row) end
  -- Visible two-hop maps also need animated textures before their first draw.
  -- Reuse the very same bounded atlas slice, never one slice per neighbour.
  if not prepared and sc and sc.atlasReady and sc.warmAtlas then
    for _,nb in ipairs(ow.neighbors or {}) do
      if not sc.atlasReady(nb.map) then
        pcall(sc.warmAtlas,nb.map,ATLAS_SLICE);prepared=true;break
      end
    end
  end
  for _,row in ipairs(ahead) do prepare(row) end
  if loaded and MapLoader.trim then
    local keep={[ow.map.id]=true}
    for _,nb in ipairs(ow.neighbors or {}) do keep[nb.map.id]=true end
    for _,rows in ipairs({selected,ahead}) do for _,row in ipairs(rows) do keep[row.id]=true end end
    MapLoader.trim(keep)
  end
end

function Precache.reset()
  for _,row in ipairs(selected) do releaseAtlas(row) end
  for _,row in ipairs(arriving) do releaseAtlas(row) end
  for _,row in ipairs(ahead) do releaseAtlas(row) end
  rootId,rootData,rootMap,lastX,lastY,lastOutdoor=nil,nil,nil,nil,nil,nil
  lastViewW,lastViewH=nil,nil
  candidates,selected,arriving,ahead={},{},{},{}
  confirmed=nil
  retain({})
  if ChunkMesher.setApproaching then ChunkMesher.setApproaching({}) end
end

function Precache.progress()
  local done,active=0,nil
  for _,row in ipairs(selected) do
    if row.atlasDone then done=done+1 else active=active or row.id end
  end
  return done,#selected,active,rootId
end

function Precache.destinationReady(game,id)
  local ow=game and game.overworld
  if not ow or not ow.map or ow.map.id==id then return true end
  for _,row in ipairs(selected) do
    if row.id==id and row.map then
      local full,body=ChunkMesher.slotKnown(row.map,false),ChunkMesher.slotKnown(row.map,true)
      if not (full or body) then return false end
      if not (ChunkMesher.peek(row.map,false) or ChunkMesher.peek(row.map,true)) then return true end
      local sc=scene()
      return row.atlasDone or (sc and sc.atlasReady and sc.atlasReady(row.map)) or false
    end
  end
  return false
end

require("src.render.Assets").register(Precache.reset)
return Precache
