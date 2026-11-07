-- Voxel-map arena provider shared by the standalone native-card mode and the
-- optional StadiumBattleFX integration.

local V = ...
local Provider = {}
local BattleArena = V.require("BattleArena")
local Scene = V.require("VoxelBattleScene")

local function overworld()
  local Game = require("src.core.Game")
  local ow = Game and Game.overworld
  -- jp.90: a gen2 World is read through its Red-shaped host state.
  -- The generation probe is inline so Red never resolves Gen2Host.
  local okV, GV = pcall(require, "src.core.GameVersion")
  if ow and okV and type(GV) == "table" and GV.generation and select(2, pcall(GV.generation)) == 2 then
    local state = V.require("Gen2Host").state(ow)
    if type(state) == "table" then state.gen2Host = true end -- jp.91 D: marks the gen2 branch
    return state
  end
  return ow
end

local function wideBattleLayout(context)
  local battle = context and context.battle
  if require('src.battle.BattlePresentation').active(battle) then return false end
  if not (battle and type(battle.isWideBattleLayout) == "function") then
    return false
  end
  local ok, value = pcall(battle.isWideBattleLayout, battle)
  return ok and value and true or false
end

function Provider:available()
  local state = overworld()
  return state and state.map and state.player and V.require("Voxel3D").available()
end

function Provider:canTransition()
  local state=overworld()
  if not self:available() then return false end
  local arena=BattleArena.find(state.map,state.player.cellX,state.player.cellY,state.player.surfing,
    {encounter=true,facing=state.player.facing,
      blocked=function(x,y)return type(state.npcAtCell)=='function' and state:npcAtCell(x,y)~=nil end})
  return arena~=nil and Scene.ready(state,arena) and true or false
end

function Provider:arena(context)
  local state = overworld()
  local log = context and context.services and context.services.log
  local function decline(reason)
    if log and log.warn then
      log:warn("[DRAMALESS_SHAPE] voxel arena declined: %s", tostring(reason))
    end
    return nil
  end
  if not (state and state.map and state.player) then
    return decline("overworld state unavailable")
  end
  if state.gen2Host then return self:gen2Arena(context, state, log, decline) end
  local modern=require('src.battle.BattlePresentation').active(context and context.battle)
  local entryPose, cameraYaw, rigYaw
  if modern then
    local camera=V.require('Voxel3D')
    local angle=V.require('VoxelState').angle or 0
    local function copy(v)return v and {v[1],v[2],v[3]} or nil end
    if camera.eye and camera.focus and camera.fovY then
      entryPose={eye=copy(camera.eye),focus=copy(camera.focus),fov=camera.fovY,
        curve=camera.curveK or 0,curveX=camera.curveX,curveZ=camera.curveZ,
        filmX=camera.camera and camera.camera.filmX or 0,
        filmY=camera.camera and camera.camera.filmY or 0,
        up=copy(camera.camera and camera.camera.up)
          or (camera.camera and {0,1,0} or {0,math.sin(angle),-math.cos(angle)})}
      local dx,dz=camera.eye[1]-camera.focus[1],camera.eye[3]-camera.focus[3]
      if dx*dx+dz*dz>1e-8 then
        cameraYaw=math.atan2(dx,dz)
        local renderer=require('src.render.Renderer')
        local rect=renderer:frameRects()
        local game=context and context.battle and context.battle.game
        local options=game and game.save and game.save.options
        -- begin() may run before the first battle draw, while frameRects
        -- still describes the overworld. Resolve the requested battle layout
        -- locally without changing the renderer or any saved option.
        local presentation=require('src.battle.BattlePresentation')
        presentation.frame(rect,renderer.dialogScale or 1,options and options.jpBattleSpacing)
        local metrics=presentation.metrics(rect)
        local rig=V.require('BattleCam').rigFor({encounter=true,
          jpCompact=metrics.compact,jpMetrics=metrics})
        rigYaw=math.atan2(rig.side-rig.lookX,rig.back)
      end
    end
  end
  local groundCache={}
  local function ground(x,y)
    local key=x..':'..y
    if groundCache[key]==nil then
      local okay,h=pcall(V.require('VoxelScene').groundAt,state.map,x,y)
      groundCache[key]=okay and type(h)=='number' and h==h and math.abs(h)<math.huge and h or false
    end
    return groundCache[key]
  end
  local opts=modern and {encounter=true,facing=state.player.facing,
    cameraYaw=cameraYaw,rigYaw=rigYaw,
    blocked=function(x,y)
      return type(state.npcAtCell)=='function' and state:npcAtCell(x,y)~=nil
    end,
    -- The solved camera and native effects share one ground plane. Keep
    -- both feet on that plane; on a narrow uneven bank use the existing
    -- same-map native-picture fallback instead of floating either actor.
    pairAllowed=function(px,py,ex,ey)
      local a,b=ground(px,py),ground(ex,ey)
      return a~=false and b~=false and math.abs(a-b)<1e-6
    end} or nil
  local ok, arena = pcall(BattleArena.find, state.map,
    state.player.cellX, state.player.cellY, state.player.surfing,opts)
  if ok and not arena and modern then
    -- A safe pair is needed for world-space cards, not for the background.
    -- Keep the encounter map's 3D terrain even when the normal world pipeline
    -- is OFF. These symmetric points only define the existing camera rig;
    -- no actor is placed on them (they may be blocked or at unequal heights).
    local cx,cy=state.player.cellX,state.player.cellY
    local x,z=cx*16+8,cy*16+8
    arena={map=state.map,encounter=true,backgroundOnly=true,cam='wide',
      origin={cellX=cx,cellY=cy,x=x,z=z,mapId=state.map.id},
      mid={x,z},player={x,z+24},enemy={x,z-24},playerCell={cx,cy}}
    if log and log.event then
      log:event('battle','voxel-background-only',{map=state.map.id})
    end
  end
  if not (ok and arena) then
    return decline(ok and "no suitable arena on current map" or ("arena search failed: " .. tostring(arena)))
  end
  if not Scene.ready(state, arena) then
    return decline("voxel terrain is not ready")
  end

  -- The 304x144 WIDE layout translates the engine's battle slots while the
  -- voxel cards stay pinned to arena ground.  Tag the arena before asking
  -- BattleCam for its rig so both standalone Dramaless and StadiumBattleFX
  -- receive the WIDE-aware solved camera.
  arena.uiWide = wideBattleLayout(context)
  if modern then
    arena.entryPose=entryPose
    local kind=context and context.battle and context.battle.kind
    -- A trainer's original wipe already hides the camera cut. Start in the
    -- completed arena shot so its native silhouette slide is the entrance;
    -- do not add the wild encounter's half-second world-camera pan beneath
    -- it. Retain entryPose for the established return-to-overworld behavior.
    arena.presentationTime=(kind=='trainer' or kind=='link') and 1 or 0
  end

  -- Publish the same canonical rig original Dramaless solves this arena
  -- against. SBFX reads this public arena field for its default camera, so
  -- hosting the voxel stage does not silently substitute Stadium's taller,
  -- farther-back court framing. Custom SBFX camera providers can still
  -- override it through the normal camera slot.
  local BattleCam = V.require("BattleCam")
  local rig = BattleCam.rigFor(arena)
  if rig then
    arena.camera = {
      side = rig.side, back = rig.back, height = rig.height,
      lookX = rig.lookX, lookY = rig.lookY, frameH = rig.frameH,
    }
  end
  arena.id = "dramaless:voxel-map:" .. tostring(arena.map and arena.map.id or state.map.id)
  return arena
end

-- jp.91 D: a Crystal battle.  Game2 has no Renderer, so BattlePresentation
-- is never "modern" here; the arena is staged on the gen2 map facade with the
-- same encounter search Red uses (feet on open walkable floor on either side
-- of the player), falling back to the camera-only background at the player's
-- cell.  The gen2 BattleState draws the pics itself (no cards), so the arena
-- is a backdrop: cards, intro focus and the action camera stay off.
function Provider:gen2Arena(context, state, log, decline)
  local map, player = state.map, state.player
  local cx, cy = tonumber(player.cellX), tonumber(player.cellY)
  if not (cx and cy) then return decline("gen2 player cell unavailable") end
  local pick = nil
  local ok, arena = pcall(BattleArena.find, map, cx, cy, player.surfing and true or false,
    { encounter = true, facing = player.facing,
      blocked = function(x, y)
        local world = state.world
        if not (world and type(world.npcAt) == "function") then return false end
        local got, npc = pcall(world.npcAt, world, x, y)
        return got and npc ~= nil
      end })
  if ok and arena then
    pick = "encounter"
  else
    if not ok and log and log.warn then
      log:warn("[DRAMALESS_SHAPE] gen2 arena search failed: %s", tostring(arena))
    end
    local x, z = cx * 16 + 8, cy * 16 + 8
    arena = { map = map, encounter = true, backgroundOnly = true, cam = 'wide',
      origin = { cellX = cx, cellY = cy, x = x, z = z, mapId = map.id },
      mid = { x, z }, player = { x, z + 24 }, enemy = { x, z - 24 }, playerCell = { cx, cy } }
    pick = "background"
  end
  if not Scene.ready(state, arena) then
    return decline("voxel terrain is not ready")
  end
  arena.gen2 = true
  arena.uiWide = false
  arena.presentationTime = 1
  local BattleCam = V.require("BattleCam")
  local rig = BattleCam.rigFor(arena)
  if rig then
    arena.camera = {
      side = rig.side, back = rig.back, height = rig.height,
      lookX = rig.lookX, lookY = rig.lookY, frameH = rig.frameH,
    }
  end
  arena.id = "dramaless:voxel-map:" .. tostring(arena.map and arena.map.id or map.id)
  if log and log.event then
    log:event('battle', 'voxel-gen2-arena', { map = map.id, pick = pick,
      cell = cx .. ',' .. cy, enemy = arena.enemyCell and (arena.enemyCell[1] .. ',' .. arena.enemyCell[2]) or 'n/a' })
  end
  return arena
end

function Provider:begin(context, arena)
  V.require('BattleCameraBlend').cancel()
  self.currentArena=arena
  if not (arena and arena.gen2) then
    V.require("BattleIntroFocus").begin(arena,context and context.battle)
  end
  if context and context.battle and arena and arena.encounter and not arena.gen2 then
    context.battle.jpSeamlessCamera=arena.entryPose~=nil
  end
  self.state = overworld()
  self.log = context and context.services and context.services.log
  V.require("BattleCam").reset()
  if self.log and self.log.event then
    self.log:event("DRAMALESS_SHAPE", "voxel-arena-begin", {
      map = arena and arena.map and arena.map.id or "unknown",
      arena = arena and arena.id or "unknown",
    })
  end
  return self.state and true or (V.stadiumBattleApi and V.stadiumBattleApi.FALLBACK)
end

function Provider:update(context, dt)
  V.require("BattleCam").update(dt or 0)
  local arena=context and context.arena
  if arena and arena.gen2 then return end
  V.require("BattleIntroFocus").update(arena)
  if arena and arena.encounter then
    arena.presentationTime=arena.presentationClock and arena.presentationClock:position(dt)
      or (arena.presentationTime or 0)+(dt or 0)
  end
end

function Provider:render(context, arena, drawActors)
  if not self.state then return V.stadiumBattleApi and V.stadiumBattleApi.FALLBACK end
  -- Presentation must see the final logic state of this physical frame.
  -- In particular a native trainer retreat/send-out can begin after the
  -- input.step hook; settle its focus camera before capturing/drawing it.
  if not (arena and arena.gen2) then
    V.require("BattleIntroFocus").update(arena)
    V.require('BattleActionCamera').update(arena,context and context.battle)
    V.require('SceneEffects').battle(arena,context and context.battle)
    V.require("VoxelBattleCardProvider"):prepareFrame(context)
  end
  local camera = context and context.services and context.services.camera
  local canvas = Scene.render(self.state, arena, drawActors, camera)
  return canvas or (V.stadiumBattleApi and V.stadiumBattleApi.FALLBACK)
end

function Provider:finish(context, reason)
  local arena=self.currentArena
  V.require('BattleActionCamera').finish(arena)
  V.require('SceneEffects').finish(arena)
  if (reason=="battle.ended" or reason=="ended" or reason==nil)
      and arena and arena.encounter and arena.lastPose then
    V.require('BattleCameraBlend').returnFrom(arena.lastPose,.4)
  else
    V.require('BattleCameraBlend').cancel()
  end
  self.state, self.log, self.currentArena = nil, nil, nil
end

function Provider:invalidate()
  self:finish()
end

return Provider
