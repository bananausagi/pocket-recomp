-- Prepare presentation caches while the original opening/title is visible.
-- No world enter/update, script, input, save load or save hook is run here.
local V=...
local Mesh=V.require("ChunkMesher")
local Atlas=V.require("TerrainAtlas")
local Precache=V.require("VoxelPrecache")
local GPU=V.require("Voxel3D")
local Assets=require("src.render.Assets")
local Boot={SLICE=.002}
local clock=(love and love.timer and love.timer.getTime) or os.clock
local session

local function stopRequests(s)
  if not s then return end
  for _,row in ipairs(s.maps)do Mesh.cancelPending(row.id,row.body)end
end

function Boot.reset()
  stopRequests(session)
  Atlas.cancelPreparations()
  session=nil
end

local function bootScreen(top)
  return top and (top.isOpeningMovie or top.isTitleScreen or top.isPlayerStartMenu)
end

-- Base palette metadata is enough without invoking world.tod/map.palette
-- hooks or mutating OverworldController. Custom palette hooks simply defer
-- their atlas to the live renderer; geometry can still be prepared safely.
local function palette(game,map,lastOutdoor)
  if require("src.mods.Runtime").wantsHook("map.palette") then return nil,false end
  local data=game.data
  local defs=require("src.world.FieldDefaults").field(data,"palettes")
  local function lookup(id,tileset)
    if defs.byMap and defs.byMap[id] then return defs.byMap[id] end
    if defs.byTileset and defs.byTileset[tileset] then return defs.byTileset[tileset] end
    for _,row in ipairs(defs.byPrefix or {})do
      if row.prefix and id:find(row.prefix,1,true)==1 then return row.palette end
    end
  end
  local name=map.def.palette or lookup(map.id,map.def.tileset)
  if not name then
    local boot=data.field and data.field.boot or {}
    local outdoor=lastOutdoor or require("src.core.SaveData").defaultHeal(boot).map
    local def=outdoor and data.maps[outdoor]
    name=(outdoor and lookup(outdoor,def and def.tileset)) or defs.default
  end
  local P=require("src.render.PaletteFX")
  return P.effectiveColors(P.pal(data,name)),true
end

local function begin(game,id,lastOutdoor)
  Boot.reset()
  -- Ready the actual destination before its border: skipping the opening
  -- can then reuse a visible body while the same full-quality ring completes.
  local maps={{id=id,body=true},{id=id,body=false}}
  local seen={[id]=true}
  -- Same two-hop neighbourhood/masks as the live scene; a bounded set, not
  -- an all-world preloader. MapLoader keeps the exact objects for world enter.
  local Controller=require("src.world.OverworldController")
  for _,nb in ipairs(Controller.computeNeighbors(game.data.maps,id,2) or {})do
    if not seen[nb.id] and #maps<25 then
      seen[nb.id]=true;maps[#maps+1]={id=nb.id,body=true}
    end
  end
  session={game=game,data=game.data,target=id,lastOutdoor=lastOutdoor,maps=maps,
    loadIndex=1,atlasIndex=1,phase="shader",stats={frames=0,maxSeconds=0,stages={}}}
  return session
end

local function stepAtlas(s)
  local row=s.maps[s.atlasIndex]
  if not row then s.phase="done";return end
  if not row.map then s.atlasIndex=s.atlasIndex+1;return end
  if not row.paletteChecked then
    row.colors,row.canAtlas=palette(s.game,row.map,s.lastOutdoor)
    row.paletteChecked=true
  end
  if not row.canAtlas or Atlas.prepare(row.map,row.colors,Boot.SLICE) then
    row.atlasDone=true;s.atlasIndex=s.atlasIndex+1
  end
end

local function work(s)
  if s.phase=="shader" then
    -- Driver compilation is indivisible. One shader in its own update,
    -- before any map/image/mesh work; its duration is reported separately.
    GPU.shader();s.phase="battle"
  elseif s.phase=="battle" then
    -- jp.58: the first battle's programs, likewise one per update.
    if not V.require("VoxelBattleWarmup").compileNext() then s.phase="maps";return work(s) end
  elseif s.phase=="maps" then
    local row=s.maps[s.loadIndex]
    if not row then s.phase="mesh";return end
    row.map=require("src.world.MapLoader").load(s.data,row.id)
    Mesh.request(row.map,row.body,not row.body and Precache.masksFor(s.data,row.id) or nil,false)
    s.loadIndex=s.loadIndex+1
    if s.loadIndex==2 then s.phase="target" end
  elseif s.phase=="target" then
    -- Make the actual starting area useful before visiting every neighbour.
    -- Share the existing animation-friendly budget with its first atlas.
    Mesh.pump(false,Boot.SLICE*.5)
    local row=s.maps[1]
    if not row.paletteChecked then
      row.colors,row.canAtlas=palette(s.game,row.map,s.lastOutdoor)
      row.paletteChecked=true
    end
    if not row.atlasDone then
      row.atlasDone=not row.canAtlas or Atlas.prepare(row.map,row.colors,Boot.SLICE*.5)
    end
    if not Mesh.jobPending(row.id,true) and row.atlasDone then s.phase="maps" end
  elseif s.phase=="mesh" then
    Mesh.pump(false,Boot.SLICE)
    if Mesh.pending()==0 then s.phase="atlas" end
  elseif s.phase=="atlas" then stepAtlas(s) end
end

-- true means the visible boot page owns this frame's small build slice.
-- A quick skip never flushes the queue. Normal world streaming takes over
-- meshes, while any partly uploaded atlas continues one image per update.
function Boot.update(game,level)
  if not game or not game.data or (tonumber(level) or 0)<=0 then
    if session then Boot.reset() end
    return false
  end
  local top=game.stack and game.stack:top()
  local ow=game.overworld
  local visibleBoot=bootScreen(top)
  if not visibleBoot then
    if session and ow and ow.map then
      if session.phase=="atlas" or session.phase=="target" then
        -- Finish only the currently in-flight atlas, not every speculative
        -- neighbour after a skip. Cache publication stays atomic.
        local row=session.phase=="target" and session.maps[1] or session.maps[session.atlasIndex]
        if row and row.paletteChecked and not row.atlasDone then stepAtlas(session)
        else session.phase="done" end
      end
    elseif session then Boot.reset() end
    return false
  end
  local hint=top.presentationWarmup
  local id=hint and hint.map or (game.save and game.save.player and game.save.player.map)
  if type(id)~="string" or not game.data.maps[id] then return true end
  if not session or session.game~=game or session.data~=game.data or session.target~=id then
    begin(game,id,hint and hint.lastOutdoor)
  end
  local s=session
  local phase=s.phase;local started=clock()
  local ok,err=pcall(work,s)
  local elapsed=clock()-started
  s.stats.frames=s.stats.frames+1;s.stats.maxSeconds=math.max(s.stats.maxSeconds,elapsed)
  local st=s.stats.stages[phase] or {frames=0,totalSeconds=0,maxSeconds=0}
  st.frames=st.frames+1;st.totalSeconds=st.totalSeconds+elapsed;st.maxSeconds=math.max(st.maxSeconds,elapsed)
  s.stats.stages[phase]=st
  if not ok then
    stopRequests(s);Atlas.cancelPreparations();s.phase="done";s.stats.error=tostring(err)
  end
  return true
end

function Boot.status()
  return session and {target=session.target,phase=session.phase,stats=session.stats} or nil
end

Assets.register({invalidate=Boot.reset,release=Boot.reset})
return Boot
