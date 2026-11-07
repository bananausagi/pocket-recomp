-- Optional presentation. The state is disposable, separate from saves/game RNG.
local V=...
local Prefs=require('src.core.JapaneseEffects')
local Map=require('src.world.Map')
local Particles=V.require('EffectParticles')
local E={stats={emitted=0,peak=0},LIMIT=Particles.LIMIT}
local world
local zero={0,0,0,0}
local colours={FIRE={1,.38,.10},ELECTRIC={1,.85,.20},WATER={.2,.65,1},ICE={.55,.85,1},
  GRASS={.4,.85,.35},PSYCHIC={.9,.4,.8},GHOST={.6,.42,.9},POISON={.7,.4,.8},
  DRAGON={.5,.6,1},NORMAL={1,.85,.6},FIGHTING={1,.65,.3},GROUND={.8,.65,.4},
  ROCK={.8,.7,.5},FLYING={.7,.9,1},BUG={.65,.8,.35}}
local floating={GASTLY=true,HAUNTER=true,MAGNEMITE=true,MAGNETON=true,KOFFING=true,
  WEEZING=true,ZUBAT=true,GOLBAT=true,BUTTERFREE=true,BEEDRILL=true,GEODUDE=true,MEW=true}
local function options(b)
  local game=b and b.game or require('src.core.Game')
  return game and game.save and game.save.options or {}
end
local function enabled(s,key) return Prefs.enabled(s.options,key,s.battle~=nil) end
local function newState(map,battle)
  return {map=map,battle=battle,particles={},pool={},seed=173,time=0,lastTime=love.timer.getTime(),
    options=options(battle),step=zero,gust=zero,light=zero,lightColor={0,0,0},
    ambientClock=0,statusClock=0,distance=0,hits={}}
end
local function rand(s)
  s.seed=(s.seed*48271)%2147483647
  return s.seed/2147483647
end
local function emit(s,key,kind,x,y,z,size,life,color,vx,vy,vz,gravity)
  if not enabled(s,key) or #s.particles>=(s.limit or E.LIMIT) then return end
  local p=table.remove(s.pool) or {}
  p.angle,p.height,p.beamX,p.beamZ=nil,nil,nil,nil
  p.key,p.kind,p.x,p.y,p.z,p.size=key,kind,x,y,z,size
  p.life,p.total,p.alpha=life,life,.70
  p.r,p.g,p.b=color[1],color[2],color[3]
  p.vx,p.vy,p.vz,p.gravity=vx or 0,vy or 0,vz or 0,gravity or 0
  s.particles[#s.particles+1]=p
  E.stats.emitted=E.stats.emitted+1;E.stats.peak=math.max(E.stats.peak,#s.particles)
  return p
end
local function tick(s)
  local now=love.timer.getTime()
  local dt=math.max(0,now-s.lastTime);s.lastTime=now
  if dt>.25 then dt=0 end -- pause/resume never sprays accumulated particles
  s.options=options(s.battle);s.time=s.time+dt
  s.limit=math.min(E.LIMIT,math.floor(96*Prefs.density(s.options)))
  for i=#s.particles,1,-1 do
    local p=s.particles[i];p.life=p.life-dt
    if p.life<=0 or not enabled(s,p.key) or i>s.limit then
      table.remove(s.particles,i);s.pool[#s.pool+1]=p
    else
      p.x,p.y,p.z=p.x+p.vx*dt,p.y+p.vy*dt,p.z+p.vz*dt
      p.vy=p.vy-p.gravity*dt
    end
  end
  return dt
end
local function ground(map,x,z)
  local ok,y=pcall(V.require('VoxelScene').groundAt,map,math.floor(x/16),math.floor(z/16))
  return ok and type(y)=='number' and y or 0
end
local function water(map,x,z)
  local cx,cy=math.floor(x/16),math.floor(z/16)
  return map and map.isWaterCell and (not map.inBounds or map:inBounds(cx,cy))
    and map:isWaterCell(cx,cy)
end
local function burst(s,key,x,y,z,count,kind,color,power)
  count=math.max(1,math.floor(count*Prefs.density(s.options)+.5))
  for _=1,count do
    local a=rand(s)*math.pi*2;local speed=(2+rand(s)*5)*(power or 1)
    local residue=key=='jpFxAfterglow'
    emit(s,key,kind,x,y+.7,z,(residue and 1 or .75)+rand(s)*.8,
      (residue and .75 or .5)+rand(s)*.5,color,
      math.cos(a)*speed,3+rand(s)*6,math.sin(a)*speed,kind==6 and 14 or 5)
  end
end
local function track(s,key,x,y,z,dx,dz,color)
  local len=math.sqrt(dx*dx+dz*dz)
  if len<.01 then return end
  s.leftFoot=not s.leftFoot
  local side=s.leftFoot and 1.6 or -1.6
  local px,pz=x+dz/len*side,z-dx/len*side
  if E.surface(s.map,px,pz)=='water' then return end
  local p=emit(s,key,7,px,ground(s.map,px,pz)+.23,pz,1.8,5.2,color)
  if p then p.angle=math.atan2(dx,dz);p.alpha=.48 end
end

-- Sunbeams add neither another dust emitter nor a second day/night system.
-- Reuse the scene's clock and only place a few beams on open forest cells.
local function sunbeams(s,dt,x,z)
  if not enabled(s,'jpFxLightShafts') or not (s.map.def and s.map.def.tileset=='FOREST') then return end
  local ok,day=pcall(V.require,'DayNight')
  local body=ok and day.body and day.body()
  if not body or body.moon or body.dy<.04 then
    for i=#s.particles,1,-1 do if s.particles[i].kind==9 then
      s.pool[#s.pool+1]=table.remove(s.particles,i)
    end end
    s.beamClock=0;return
  end
  s.beamClock=(s.beamClock or 0)+dt
  if s.beamClock<1.1/Prefs.density(s.options) then return end
  s.beamClock=0
  local count=0;for _,p in ipairs(s.particles)do if p.kind==9 then count=count+1 end end
  if count>=math.ceil(2*Prefs.density(s.options)) then return end
  local px,pz=x+(rand(s)-.5)*72,z+(rand(s)-.5)*56
  local cx,cy=math.floor(px/16),math.floor(pz/16)
  if s.map.inBounds and not s.map:inBounds(cx,cy)
      or not s.map.isWalkableCell or not s.map:isWalkableCell(cx,cy) or water(s.map,px,pz) then return end
  local p=emit(s,'jpFxLightShafts',9,px,ground(s.map,px,pz)+.3,pz,3.8,5.4,{1,.94,.68})
  if p then
    p.height=32;p.alpha=.24*math.min(1,body.dy*4)
    p.beamX,p.beamZ=body.dx*18,body.dz*18
  end
end
local function weather(s)
  local outside=s.map and s.map.def and Map.isOutdoor(s.map.def)
  local forest=s.map and s.map.def and s.map.def.tileset=='FOREST'
  local yes=enabled(s,'jpFxWind') and (outside or forest)
  s.wind={s.time,yes and .9 or 0,yes and outside and .13 or 0,0}
end
function E.surface(map,x,z)
  local cx,cy=math.floor(x/16),math.floor(z/16)
  if not map or map.inBounds and not map:inBounds(cx,cy) then return 'none' end
  if water(map,x,z) then return 'water' end
  if map.isGrassCell and map:isGrassCell(cx,cy) then return 'grass' end
  local ts=map.def and map.def.tileset
  if ts=='CAVERN' or ts=='FOREST' then return 'soil' end
  -- In the original outdoor atlas these are the walkable sand/path tiles.
  -- Other tiles (pavement, roofs, floors) deliberately do not emit dust.
  local tile=map.cellTile and map:cellTile(cx,cy)
  if ts=='OVERWORLD' and (tile==0x04 or tile==0x0E or tile==0x20 or tile==0x2C) then return 'soil' end
  return 'stone'
end
local function ambient(s,dt,x,z)
  if not enabled(s,'jpFxAmbient') then s.ambientClock=0;return end
  local ts=s.map and s.map.def and s.map.def.tileset
  local forest=ts=='FOREST';local cave=ts=='CAVERN'
  local inside=s.map and s.map.def and not Map.isOutdoor(s.map.def)
  if not (forest or cave or inside) then return end
  s.ambientClock=s.ambientClock+dt
  if s.ambientClock<.30/Prefs.density(s.options) then return end
  s.ambientClock=0
  local px,pz=x+(rand(s)-.5)*100,z+(rand(s)-.5)*64
  local cx,cy=math.floor(px/16),math.floor(pz/16)
  if s.map.inBounds and not s.map:inBounds(cx,cy) then return end
  if s.map.isWalkableCell and not s.map:isWalkableCell(cx,cy) then return end
  local y=ground(s.map,px,pz)
  if forest then
    emit(s,'jpFxAmbient',2,px,y+12+rand(s)*10,pz,1.3,4.5,{.65,.78,.28},
      enabled(s,'jpFxWind') and 4 or .7,-2,1.2)
  elseif cave then
    emit(s,'jpFxAmbient',4,px,y+13,pz,.8,.8,{.6,.8,.9},0,-12,0,8)
  else
    emit(s,'jpFxAmbient',0,px,y+6+rand(s)*10,pz,.7,4,{1,.92,.7},.4,.4,.2)
  end
end
function E.world(state)
  if not (state and state.map and state.player) then world=nil;return end
  if not world or world.map~=state.map or world.owner~=state then
    world=newState(state.map);world.owner=state
  end
  local s,p=world,state.player
  local dt=tick(s);weather(s)
  local x,z=(p.px or 0)+8,(p.py or 0)+8
  local dx,dz=x-(s.x or x),z-(s.z or z)
  local distance=math.sqrt(dx*dx+dz*dz)
  local teleported=distance>32
  if teleported then distance=0;s.distance=0;s.particles={};s.step=zero;s.wetUntil=nil end
  s.distance=s.distance+distance
  s.x,s.z=x,z
  local y=ground(state.map,x,z)
  if s.wasSurfing and not p.surfing and not teleported then s.wetUntil=s.time+3.4 end
  s.wasSurfing=p.surfing==true
  if s.distance>=7 and distance>0 then
    s.distance=s.distance%7
    local surface=E.surface(state.map,x,z)
    local running=(tonumber(p.stepFrames) or tonumber(p.framesPerCell) or 16)<16
      or dt>0 and distance/dt>85
    local strength=running and 1.8 or 1.25
    if enabled(s,'jpFxGrass') and surface=='grass' and not p.surfing
        and not (p.hopFrames and p.hopFrames>0) then
      s.step={x,z,12,strength};s.stepAt=s.time;s.stepFloor=y;s.stepPower=strength
      burst(s,'jpFxGrass',x,y+1,z,3,2,{.35,.65,.2},.5)
    end
    if not p.surfing and not (p.hopFrames and p.hopFrames>0) then
      if surface=='soil' then
        -- Running Shoes already uses the native dust animation at this step.
        if not state.dustAnim then
          burst(s,'jpFxFootsteps',x,y,z,running and 5 or 3,0,{.76,.68,.52},strength)
        end
      elseif surface=='water' then
        burst(s,'jpFxFootsteps',x,y,z,4,4,{.65,.86,1},strength)
      end
      if enabled(s,'jpFxWater') and s.wetUntil and s.time<s.wetUntil and surface~='water' then
        -- One footprint source per step; a wet mark replaces the dry one.
        track(s,'jpFxWater',x,y,z,dx,dz,{.22,.35,.42})
        burst(s,'jpFxWater',x,y,z,2,4,{.65,.86,1},.45)
      elseif surface=='soil' then
        track(s,'jpFxTracks',x,y,z,dx,dz,{.3,.25,.18})
      end
    elseif p.surfing and surface=='water' then
      local len=math.max(.1,math.sqrt(dx*dx+dz*dz))
      emit(s,'jpFxWater',1,x-dx/len*5,y+.4,z-dz/len*5,3.2,1.1,{.8,.94,1})
    end
  end
  if not enabled(s,'jpFxGrass') or s.stepAt and s.time-s.stepAt>.75 then s.step=zero
  elseif s.step~=zero then s.step[4]=(s.stepPower or 1)*math.max(0,1-(s.time-s.stepAt)/.75) end
  if state.fishing~=s.fishing then
    s.fishing=state.fishing
    if state.fishing then
      local dir=({up={0,-1},down={0,1},left={-1,0},right={1,0}})[p.facing] or {0,1}
      local fx,fz=x+dir[1]*16,z+dir[2]*16
      if water(state.map,fx,fz) then
        local fy=ground(state.map,fx,fz)+.4
        emit(s,'jpFxWater',1,fx,fy,fz,4.5,1.4,{.75,.92,1})
        burst(s,'jpFxWater',fx,fy,fz,6,4,{.7,.9,1},1)
      end
    end
  end
  ambient(s,dt,x,z)
  sunbeams(s,dt,x,z)
  return s
end
local function visible(b,side)
  local mon=b and b[side]
  if not mon or mon.fainted or b.fieldCleared or b.demo or b.safari then return false end
  local pinned=V.backSpritesSetting
  if side=='player' and pinned and pinned.get and pinned:get() then return false end
  if side=='player' and (b.showPlayerBack or b.sendingOut or b.shrinkOut)
    or side=='enemy' and (b.showEnemyTrainer or b.enemyHidden or b.enemySendingOut) then return false end
  if b.growIn or b.introBalls or (b.introSlide or 0)>0 then return false end
  if mon.substituteHP or mon.minimized then return false end
  return true
end
local function sideOf(b,mon)
  if mon==b.player then return 'player' elseif mon==b.enemy then return 'enemy' end
end
function E.battle(arena,b)
  if not (arena and b and arena.encounter and not arena.backgroundOnly) then return end
  local s=arena.jpSceneEffects
  if not s or s.battle~=b then s=newState(arena.map,b);arena.jpSceneEffects=s end
  local dt=tick(s);weather(s)
  if b.phase~='menu' and b.phase~='moveSelect' and b.phase~='messages' then
    s.particles={};s.light=zero;s.gust=zero;s.hits={};return s
  end
  local paused=b.game and b.game.stack and b.game.stack.top and b.game.stack:top()~=b
  s.paused=paused
  if paused then s.particles={};s.light=zero;s.gust=zero;s.hits={};return s end
  if b.jpFxMoveSerial and s.moveSerial~=b.jpFxMoveSerial then
    s.moveSerial=b.jpFxMoveSerial;s.moveAt=s.time
    s.moveName=b.jpFxMoveName
    local move=b.data and b.data.moves and b.data.moves[s.moveName] or {}
    s.moveType=type(move.type)=='string' and move.type:upper() or 'NORMAL'
    s.moveSide=sideOf(b,b.jpFxMoveTarget)
    s.lightColor=colours[s.moveType] or colours.NORMAL
  end
  local target=s.moveSide and arena[s.moveSide]
  local age=s.time-(s.moveAt or -100)
  if target and enabled(s,'jpFxMoveLight') and age<.9 and visible(b,s.moveSide) then
    s.light={target[1],(arena.groundY or 0)+6,target[2],.60*math.sin(math.pi*age/.9)}
  else s.light=zero end
  if target and enabled(s,'jpFxBattleEnvironment') and age<.9 and visible(b,s.moveSide) then
    s.gust={target[1],target[2],52,1-age/.9}
  else s.gust=zero end
  if b.jpFxHitSerial and s.hitSerial~=b.jpFxHitSerial then
    s.hitSerial=b.jpFxHitSerial
    local side=sideOf(b,b.jpFxHitTarget);local point=side and arena[side]
    if point and visible(b,side) then
      s.hits[side]=s.time
      local y=ground(arena.map,point[1],point[2])
      local wet=water(arena.map,point[1],point[2])
      local name=b.jpFxHitMoveName or s.moveName
      local move=b.data and b.data.moves and b.data.moves[name] or {}
      local kind=type(move.type)=='string' and move.type:upper() or s.moveType
      burst(s,'jpFxHitReaction',point[1],y,point[2],6,wet and 4 or 0,
        wet and {.65,.86,1} or {.8,.72,.58},1)
      if not wet and (kind=='GROUND' or kind=='ROCK' or kind=='FIGHTING'
        or name=='BODY_SLAM' or name=='STOMP') then
        local ring=emit(s,'jpFxBattleEnvironment',1,point[1],y+.3,point[2],10,.6,{.82,.77,.62})
        if ring then ring.alpha=.45 end
        burst(s,'jpFxBattleEnvironment',point[1],y,point[2],7,6,{.65,.61,.53},1.5)
      elseif kind=='FLYING' or kind=='GRASS' then
        burst(s,'jpFxBattleEnvironment',point[1],y+2,point[2],5,2,{.55,.75,.3},1.5)
      end
      -- One landed-hit emitter, shared by every type; no duplicate status
      -- emitter and no changes to the native move queue or timing.
      local shape=({FIRE=4,WATER=4,ICE=6,ELECTRIC=3,PSYCHIC=5,
        GHOST=5,POISON=5,DRAGON=6})[kind]
      if shape then
        burst(s,'jpFxAfterglow',point[1],y+7,point[2],7,shape,colours[kind],1.1)
      end
      if b.jpFxHitCritical then
        local star=emit(s,'jpFxCritical',8,point[1],y+10,point[2],5,.24,{1,.94,.65})
        if star then star.alpha=.95 end
      end
    end
  end
  s.statusClock=s.statusClock+dt
  if s.statusClock>=.7 then
    s.statusClock=0
    for _,side in ipairs({'player','enemy'}) do
      local mon=b[side];local p=arena[side]
      if p and visible(b,side) then
        -- The presentation status is revealed with the HUD, not before the
        -- corresponding queued message has reached the player.
        local status=mon.shownStatus
        local y=(arena.groundY or 0)+8
        if status=='PSN' then
          emit(s,'jpFxStatus',5,p[1]+(rand(s)-.5)*5,y,p[2],.6,1.3,{.7,.36,.8},0,3,0)
        elseif status=='PAR' then
          emit(s,'jpFxStatus',3,p[1]+(rand(s)-.5)*7,y,p[2],1,.24,{1,.9,.3})
        elseif status=='SLP' then
          emit(s,'jpFxStatus',5,p[1]+3,y+5,p[2],1.3,1.7,{.75,.9,1},.5,1.2,0)
        elseif status=='BRN' then
          emit(s,'jpFxStatus',4,p[1]+(rand(s)-.5)*5,y,p[2],.7,.8,{1,.5,.15},0,2,0)
        elseif status=='FRZ' then
          emit(s,'jpFxStatus',6,p[1]+(rand(s)-.5)*5,y,p[2],.7,1,{.6,.85,1},0,-1,0)
        end
      end
    end
  end
  return s
end
function E.pose(arena,b,side,trainer)
  local s=arena and arena.jpSceneEffects
  if not s or s.paused or trainer or not visible(b,side) then return 0,0,0,1,1 end
  local dx,dy,dz,sx,sy=0,0,0,1,1
  local age=s.time-(s.hits[side] or -100)
  if enabled(s,'jpFxHitReaction') and age<.42 then
    local own,other=arena[side],arena[side=='player' and 'enemy' or 'player']
    if own and other then
      local x,z=own[1]-other[1],own[2]-other[2];local len=math.max(.1,math.sqrt(x*x+z*z))
      local push=math.sin(math.pi*age/.42)*2.2
      dx,dz=x/len*push,z/len*push;sy=1-push*.02
    end
  elseif enabled(s,'jpFxIdle') and (b.phase=='menu' or b.phase=='moveSelect') and not b.animPlaying then
    local phase=s.time*2.1+(side=='player' and 0 or 2)
    local mon=b[side];local species=mon.mon and mon.mon.species or mon.species
    if floating[species] then dy=.4+.4*math.sin(phase)
    else sy=1-.008*(.5+.5*math.sin(phase));dx=.12*math.sin(phase*.5) end
  end
  return dx,dy,dz,sx,sy
end
function E.bind(s)
  V.require('Voxel3D').effects(s and {wind=s.wind,step=s.step,stepFloor=s.stepFloor,gust=s.gust,
    light=s.light,lightColor=s.lightColor} or nil)
end
function E.battleFeet(arena,cards)
  local s=arena and arena.jpSceneEffects
  if not (s and cards and enabled(s,'jpFxBattleEnvironment')) then return nil,nil end
  return cards[1] and cards[1].foot,cards[2] and cards[2].foot
end
function E.draw(s) return s and Particles.draw(s.particles) or 0 end
function E.finish(arena)
  if arena then arena.jpSceneEffects=nil else world=nil end
end
function E.invalidate() world=nil;Particles.invalidate() end
return E
