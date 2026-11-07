-- A small real orbit and changing point of attention, independent of the
-- opening presentation. Native queues/audio and the HUD never move or wait.
local V=...
local Action={ORBIT=math.rad(3.2),PERIOD=20,ATTENTION=.085,PUSH=.055,CHASE=.42,FADE=.75}
local function options(b)
  return b and b.game and b.game.save and b.game.save.options or {}
end
local function pinned()
  local setting=V.backSpritesSetting
  return setting and type(setting.get)=='function' and setting:get() and true or false
end
local function allowed(b)
  local o=options(b)
  if not (b and (b.phase=='menu' or b.phase=='moveSelect' or b.phase=='messages')
      and o.jpBattleCameraMotion~=false and o.animations~=false
      and not o.reduceMotion and not o.jpReduceMotion and not b.demo and not b.safari
      and not b.showPlayerBack and not b.showEnemyTrainer and not b.introBalls
      and not b.sendingOut and not b.enemySendingOut and not b.fieldCleared
      and not b.waitingUI and not b.growIn and not b.shrinkOut and not b.enemyHidden
      and (b.introSlide or 0)==0) then return false end
  local stack=b.game and b.game.stack
  if stack and type(stack.top)=='function' and stack:top()~=b then return false end
  -- Ball/send-out/capture programs are not moves. Leave their entire
  -- sequence on the original solved camera, including the gaps between rows.
  if b.animPlaying and not (b.data and b.data.moves and b.data.moves[b.animName]) then return false end
  for _,side in ipairs({'player','enemy'})do
    local mon=b[side]
    if mon and (mon.fainted or type(b.fxFaintActive)=='function' and b:fxFaintActive(mon)) then return false end
    local fx=mon and b.picFx and b.picFx[mon]
    if fx and fx.kind=='bounce' then return false end
  end
  return true
end
Action.allowed=allowed
local function target(b)
  local function side(mon,kind)
    if mon==b.player then return 1,kind end
    if mon==b.enemy then return -1,kind end
  end
  if b.phase=='menu' or b.phase=='moveSelect' then return 0,'idle' end
  if b.animPlaying then
    local mon=(b.pendingHit and b.pendingHit.blink) or b.jpCameraMoveTarget
    if not mon and type(b.cameraMoveTarget)=='function' then
      mon=b:cameraMoveTarget(b.animName,b.animAttackerIsPlayer)
    end
    mon=mon or (b.animAttackerIsPlayer and b.enemy or b.player)
    return side(mon,'attack')
  end
  if b.jpCameraHitTarget then return side(b.jpCameraHitTarget,'hit') end
  local blink=b.fx and b.fx.blink
  if blink and (blink.frames or 0)>0 then return side(blink.target,'hit') end
  if b.jpCameraMoveTarget then return side(b.jpCameraMoveTarget,'move') end
  return 0,'idle'
end
function Action.update(arena,battle)
  if not arena then return end
  if battle and (battle.phase=='menu' or battle.phase=='moveSelect') then
    arena.actionBlocked=nil
  elseif battle and battle.animPlaying then
    arena.actionBlocked=not (battle.data and battle.data.moves and battle.data.moves[battle.animName]) or nil
  end
  if not arena.encounter or arena.backgroundOnly or arena.actionBlocked or not allowed(battle) then
    arena.actionCamera=nil;return
  end
  local now=love.timer.getTime()
  local s=arena.actionCamera
  if not s or s.battle~=battle then
    s={battle=battle,time=0,weight=0,aim=0,push=0,lastTime=now,
      hitSerial=battle.jpFxHitSerial};arena.actionCamera=s
  end
  local dt=math.max(0,now-s.lastTime);s.lastTime=now
  if dt>.25 then dt=0 end -- exclude app/menu suspension and repeated logic ticks
  s.time=s.time+dt;s.weight=math.min(1,s.weight+dt/Action.FADE)
  -- A single short physical impulse on the already-solved camera. It uses
  -- the same hit serial and respects both camera and hit-reaction switches.
  if battle.jpFxHitSerial and s.hitSerial~=battle.jpFxHitSerial then
    s.hitSerial=battle.jpFxHitSerial;s.hitAt=s.time
    s.hitPower=battle.jpFxHitCritical and 1.35 or 1
  end
  local age=s.time-(s.hitAt or -100)
  s.impulse=options(battle).jpFxHitReaction~=false and age<.26
    and math.sin(age*math.pi/.26)*(1-age/.26)*(s.hitPower or 1) or 0
  local goal,kind=target(battle)
  s.kind=kind;s.goal=goal
  s.push=(s.push or 0)+((kind=='idle' and 0 or 1)-(s.push or 0))*(1-math.exp(-dt/Action.CHASE))
  if kind=='idle' then goal=math.sin(s.time*2*math.pi/31)*.18 end
  s.aim=s.aim+(goal-s.aim)*(1-math.exp(-dt/Action.CHASE))
end
function Action.finish(arena)
  if arena then
    arena.actionCamera=nil;arena.actionBlocked=nil
    if arena.jpMetrics then arena.jpMetrics.sceneLens=nil end
  end
  local Renderer=package.loaded['src.render.Renderer']
  if Renderer then Renderer.jpBattleSceneLens=nil end
end
local function project(camera,r,point)
  local view=V.require('Mat4').lookAt(camera.eye,camera.focus,camera.up or {0,1,0})
  local x,y,z=point[1],point[2],point[3]
  local depth=-(view[9]*x+view[10]*y+view[11]*z+view[12])
  if depth<=.01 then return end
  local tan=math.tan(camera.fov/2)
  return (1+(camera.filmX or 0)+(view[1]*x+view[2]*y+view[3]*z+view[4])/(depth*tan*r.pw/r.ph))*r.pw/2,
    (1+(camera.filmY or 0)-(view[5]*x+view[6]*y+view[7]*z+view[8])/(depth*tan))*r.ph/2,
    r.ph/(2*depth*tan)
end
local function geometry(arena,camera,r,battle,playerPinned)
  local P=require('src.battle.BattlePresentation')
  local Intro=V.require('BattleIntroFocus')
  local m=arena.jpMetrics;local ground=arena.groundY or 0
  local shapes={}
  for _,side in ipairs({'player','enemy'})do
    if side~='player' or not playerPinned then
      local b=battle[side]
      local ok,pic=pcall(battle.picImage,battle,b and b.sprite)
      if not (ok and pic and arena[side]) then return end
      local w,h=pic:getWidth(),pic:getHeight()
      local scale=P.pictureScale(m,side,w,h)
      local pixel=Intro.cardWorldPixel(arena,arena.cardCanonical or camera,side,ground,scale,r,false)
      shapes[#shapes+1]={side=side,point={arena[side][1],ground,arena[side][2]},w=w*pixel,h=h*pixel}
    end
  end
  return shapes
end
local function fit(camera,shapes,r,m)
  -- The canonical composition deliberately uses nearly every pixel. Create
  -- a little breathing room by physically retreating only as much as needed;
  -- never alter FOV, sprite world sizes, UI scale or the real arena cells.
  local bottom=(m.y+m.command.y*m.sy-r.vuy)*r.dpiY
  local minX,maxX,minY,maxY
  for _=1,10 do
    minX,maxX,minY,maxY=math.huge,-math.huge,math.huge,-math.huge
    for _,shape in ipairs(shapes)do
      local x,y,k=project(camera,r,shape.point)
      if not x then return false end
      minX,maxX=math.min(minX,x-shape.w*k/2),math.max(maxX,x+shape.w*k/2)
      minY,maxY=math.min(minY,y-shape.h*k),math.max(maxY,y)
    end
    if maxX-minX<=r.pw-4 and maxY-minY<=bottom-4 then break end
    local retreat=math.max((maxX-minX)/(r.pw-4),(maxY-minY)/(bottom-4))*1.0001
    for i=1,3 do camera.eye[i]=camera.focus[i]+(camera.eye[i]-camera.focus[i])*retreat end
  end
  if maxX-minX>r.pw-4 or maxY-minY>bottom-4 then return false end
  local dx=math.max(2-minX,math.min(0,r.pw-2-maxX))
  local dy=math.max(2-minY,math.min(0,bottom-2-maxY))
  camera.filmX=(camera.filmX or 0)+dx*2/r.pw
  camera.filmY=(camera.filmY or 0)+dy*2/r.ph
  return true
end
function Action.pose(arena,camera,r)
  local Renderer=require('src.render.Renderer')
  Renderer.jpBattleSceneLens=nil
  local m=arena and arena.jpMetrics
  if m then m.sceneLens=nil end
  local s=arena and arena.actionCamera
  if not (m and s and s.weight>0 and allowed(s.battle)) then return camera end
  local pose=V.require('BattleCameraBlend').copy(camera)
  local w=s.weight*s.weight*(3-2*s.weight)
  local yaw=math.sin(s.time*2*math.pi/Action.PERIOD)*Action.ORBIT*w
  local cx,cz=arena.mid[1],arena.mid[2]
  local x,z=camera.eye[1]-cx,camera.eye[3]-cz
  pose.eye[1],pose.eye[3]=cx+x*math.cos(yaw)-z*math.sin(yaw),cz+x*math.sin(yaw)+z*math.cos(yaw)
  local ax,az=arena.player[1]-arena.enemy[1],arena.player[2]-arena.enemy[2]
  -- Track the subject across the image plane instead of turning only the
  -- optical axis. Turning toward an off-axis card made that very card
  -- smaller (and its opponent larger). Equal eye/focus translation with
  -- zero forward component preserves both depths and the user's FOV.
  local delta={ax*s.aim*Action.ATTENTION*w,0,az*s.aim*Action.ATTENTION*w}
  local forward={pose.focus[1]-pose.eye[1],pose.focus[2]-pose.eye[2],pose.focus[3]-pose.eye[3]}
  local length=math.sqrt(forward[1]^2+forward[2]^2+forward[3]^2)
  for i=1,3 do forward[i]=forward[i]/length end
  local depth=delta[1]*forward[1]+delta[2]*forward[2]+delta[3]*forward[3]
  for i=1,3 do
    local pan=delta[i]-forward[i]*depth
    pose.eye[i]=pose.eye[i]+pan;pose.focus[i]=pose.focus[i]+pan
  end
  -- A modest physical push-in accompanies the subject tracking. The
  -- fitting pass may reduce it for large cards, keeping both actors visible.
  -- Native HUD and a deliberately pinned player back stay screen-fixed.
  for i=1,3 do pose.eye[i]=pose.eye[i]+forward[i]*length*
    (Action.PUSH*(s.push or 0)+.025*(s.impulse or 0))*w end
  local playerPinned=pinned()
  local shapes=geometry(arena,camera,r,s.battle,playerPinned)
  if not shapes or not fit(pose,shapes,r,m) then return camera end
  local actors={player={x=m.actor.player.x,y=m.actor.player.y},enemy={x=m.actor.enemy.x,y=m.actor.enemy.y}}
  for _,shape in ipairs(shapes)do
    local px,py=project(pose,r,shape.point)
    actors[shape.side]={x=(px-(m.x-r.vux)*r.dpiX)/(m.sx*r.dpiX),
      y=(py-(m.y-r.vuy)*r.dpiY)/(m.sy*r.dpiY)}
  end
  -- AnimPlayer translates each entire OAM tile group through effectPoint.
  -- Carry the same two real feet to it; do not rotate/stretch the finished
  -- native canvas or its individual tiles. A pinned back keeps its own foot.
  m.sceneLens={zoom=1,x=0,y=0,actors=actors}
  Renderer.jpBattleSceneLens=m.sceneLens
  s.yaw=yaw;s.lastPose=pose;s.actors=actors
  return pose
end
return Action
