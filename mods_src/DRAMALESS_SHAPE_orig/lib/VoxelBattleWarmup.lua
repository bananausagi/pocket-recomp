-- jp.58: take the first battle's one-time GPU cost before the encounter.
-- The first standalone voxel battle used to compile its battle programs and
-- have the driver finish them on first draw (plus allocate its targets)
-- inside the encounter/handoff frames; every later battle reused them. Here
-- one indivisible unit runs per update: each program compile on its own
-- (title or idle field), then two offscreen rehearsals of the real arena pass
-- (encounter approach, battle with cards), each only after the player has
-- stood still on an idle field for a moment. Nothing is presented, and no
-- battle, save, camera or gameplay state is created.
local V=...
local Warm={STILL_FRAMES=3}
local enabled=function()return false end
local compiled,rehearsed,failed=0,0,false
local still,picsWarmed,shown=0,false,false

-- jp.59: the player's back pic and lead Pokemon's back sprite are the same
-- in every battle. Decode, recolor and hole-fill them (a GPU read-back that
-- stalls a phone's pipeline) once here instead of in the first battle.
local function warmPics(game)
  local Battle=require("src.battle.BattleState")
  if not Battle.warmPics then return end
  local Pics=V.require("BattlePics")
  for _,image in ipairs(Battle.warmPics(game))do
    Pics.filled(image,true);Pics.filled(image,false)
  end
end

-- main.lua supplies the standalone VOXEL ARENA + 2D CARDS predicate.
function Warm.enabledWhen(fn)enabled=fn end

local function compileJobs()
  local Voxel3D=V.require("Voxel3D")
  local TiltShift=V.require("TiltShift")
  local jobs={
    function()Voxel3D.shader(false,true)end,
    function()if V.require("VoxelGrid").enabled()then Voxel3D.shader(true,true)end end,
    function()V.require("Atmosphere").warm()end,
    function()V.require("SceneGlow").warm()end,
  }
  for _,name in ipairs(TiltShift.BATTLE_WARM)do
    jobs[#jobs+1]=function()TiltShift.warm(name)end
  end
  return jobs
end

-- Compile the next battle program. true = one unit of work was done now.
-- Shader constructors cache their result (or refusal), so repeating a job
-- after an invalidation costs nothing when the program still exists.
function Warm.compileNext()
  if failed or not enabled()then return false end
  local jobs=compileJobs()
  if compiled>=#jobs then return false end
  compiled=compiled+1
  local ok,err=pcall(jobs[compiled])
  if not ok then failed=true;V.log:event("battle","warmup-failed",{step=compiled,error=tostring(err)})end
  return true
end

local Keep={"vp","eye","focus","fovY","nearPlane","farPlane","lookFlat","descent","camera",
  "cell","skyEdge","curveK","curveX","curveZ","focusW","tint","glassMask","glassNight","glassGlint"}

-- Real battle-scene passes at the current cell, rendered into the battle
-- slot and discarded. Pass 1 is the wild encounter approach (no cards yet,
-- the captured field cast). Pass 2 is the battle proper: two transparent
-- world cards and their contact shadows, with the same textures, shaders and
-- targets as the native card provider. Each pass gets its own update.
local PASSES=2
local function rehearse(state,pass)
  local Scene=V.require("VoxelBattleScene")
  local Voxel3D=V.require("Voxel3D")
  local Billboard=V.require("BattleBillboard")
  local cx,cy=state.player.cellX,state.player.cellY
  local x,z=cx*16+8,cy*16+8
  local arena={map=state.map,encounter=true,backgroundOnly=true,cam="wide",jpWarmup=true,
    origin={cellX=cx,cellY=cy,x=x,z=z,mapId=state.map.id},
    mid={x,z},player={x,z+24},enemy={x,z-24},playerCell={cx,cy}}
  if not Scene.ready(state,arena)then return false end
  local actors
  if pass==1 then
    local cast=V.require("VoxelScene").captureEncounterCast(state)
    actors=function()cast(1)end
  else
    local cards=V.require("VoxelBattleCardProvider").warmCanvases()
    if not cards then return false end
    local placed={}
    arena.jpWarmupCards=function(ground)
      for i,side in ipairs({"player","enemy"})do
        local p=arena[side]
        local model=Billboard.matrix(cards[i],80,96,p[1],ground,p[2],side=="player",1,
          {faceCamera=true,worldPerPixel=16/56})
        placed[i]={texture=cards[i],model=model,pull=Billboard.PULL,floor=ground,
          foot={p[1],p[2],ground,radius=8,pressure=0}}
      end
      return placed
    end
    actors=function(world)
      local Atmosphere=V.require("Atmosphere")
      for _,card in ipairs(placed)do
        Atmosphere.drawContact(card.foot[1],world.groundY or 0,card.foot[2],8,0.01)
        Voxel3D.seams(false);Voxel3D.glass(false)
        local r,g,b,a=love.graphics.getColor()
        love.graphics.setColor(r,g,b,0)
        Voxel3D.draw(Billboard.mesh(),card.texture,card.model,Billboard.PULL)
        love.graphics.setColor(r,g,b,a)
        Voxel3D.glass(true);Voxel3D.seams(true)
      end
    end
  end
  -- The field's own camera/projection is restored before anything reads it.
  local saved={}
  for _,key in ipairs(Keep)do saved[key]=Voxel3D[key]end
  local Renderer=require("src.render.Renderer")
  local lens=Renderer.jpBattleSceneLens
  local ok,err=pcall(Scene.render,state,arena,actors,nil)
  for _,key in ipairs(Keep)do Voxel3D[key]=saved[key]end
  Renderer.jpBattleSceneLens=lens
  if not ok then error(err,0)end
  return true
end

-- One unit of rehearsal work: the next pass, or the back pics after pass 1.
-- true = work was done (or refused); false = the field is not ready yet.
local function step(game,state)
  if rehearsed>=PASSES-1 and not picsWarmed then
    picsWarmed=true
    local ok,err=pcall(warmPics,game)
    if not ok then V.log:event("battle","warmup-pics-failed",{error=tostring(err)})end
    return true
  end
  local started=love.timer and love.timer.getTime()
  local ok,result=pcall(rehearse,state,rehearsed+1)
  if not ok then
    failed=true
    V.log:event("battle","warmup-failed",{step="rehearsal"..(rehearsed+1),error=tostring(result)})
    return true
  end
  if result then
    rehearsed,still=rehearsed+1,0
    V.log:event("battle","warmup-pass",{pass=rehearsed,map=state.map.id,burst=not shown or nil,
      ms=started and math.floor((love.timer.getTime()-started)*1000+.5) or nil})
  end
  return result
end

-- jp.59: drawWorld reports each real voxel field picture (not the veil).
function Warm.fieldShown()shown=true end

-- jp.60: the first field picture after boot waits for the rehearsal. Until
-- then drawWorld shows this plain cover rather than the flat map, so the
-- one-time pause reads as loading. Bounded: after COVER_SECONDS without
-- terrain the field is shown and the passes fall back to one per update.
Warm.COVER_SECONDS=4
local coverSince,cover
function Warm.pending(game)
  if shown or failed or rehearsed>=PASSES or not enabled()then return false end
  local state=game and game.overworld
  if not (state and state.map)then return false end
  local now=love.timer and love.timer.getTime() or 0
  coverSince=coverSince or now
  if now-coverSince>Warm.COVER_SECONDS then shown=true;return false end
  return true
end
function Warm.cover(w,h)
  if not (cover and cover:getWidth()==w and cover:getHeight()==h)then
    if cover then cover:release()end
    cover=love.graphics.newCanvas(w,h)
    love.graphics.push("all");love.graphics.setCanvas(cover);love.graphics.clear(0,0,0,1);love.graphics.pop()
  end
  return cover
end

-- Field hook: true while this update was spent on warm-up work.
function Warm.update(game)
  if failed or rehearsed>=PASSES or not enabled()then return false end
  local state=game and game.overworld
  -- jp.59/60: before the field's first picture after boot take every
  -- remaining unit in this one update, so the pause is part of loading
  -- rather than a stutter in a field that is already moving. Nothing here
  -- touches gameplay, so a menu, message or map script on top (common right
  -- after "つづきから") no longer postpones it until the field is visible.
  if not shown and state and state.map and state.player then
    local did=false
    while not failed and rehearsed<PASSES and enabled()do
      if not Warm.compileNext()then
        if not step(game,state)then break end
      end
      did=true
    end
    return did
  end
  local top=game and game.stack and game.stack:top()
  if not (state and top==state and state.map and state.player and not game.sessionMenu)then
    still=0;return false
  end
  local busy=state.transitioning
    or (state.runner and state.runner.isRunning and state.runner:isRunning())
  if Warm.compileNext()then return true end
  still=busy and 0 or still+1
  if still<Warm.STILL_FRAMES then return false end
  return step(game,state)
end
function Warm.status()
  return {compiled=compiled,rehearsed=rehearsed,failed=failed,pics=picsWarmed}
end

-- A graphics reset releases programs/targets; prepare them again.
function Warm.reset()compiled,rehearsed,failed,still,picsWarmed=0,0,false,0,false end

require("src.render.Assets").register({invalidate=Warm.reset,release=Warm.reset})
return Warm
