-- Wild opponents get a presentation-only close-up; trainers arrive opponent
-- first, then hold their close-up until the complete challenge was drawn.
-- A bounded host acknowledgement keeps that message on screen while the
-- camera pulls back; original music, silhouette and send-out cues stay owned
-- by the battle queue.
local V = ...
local Intro = {}
local Blend = V.require('BattleCameraBlend')
Intro.HOLD = .12
Intro.PULL = .90
Intro.TRAINER_FOE_END = .38
Intro.TRAINER_PLAYER_START = .10
local function smooth(t)
  t=math.max(0,math.min(1,t));return t*t*(3-2*t)
end

local function options(battle)
  return battle and battle.game and battle.game.save and battle.game.save.options or {}
end
local function enabled(battle)
  local o=options(battle)
  return o.jpBattleIntro~='original' and o.animations~=false
    and not o.reduceMotion and not o.jpReduceMotion
    and battle and not battle.demo and not battle.safari
    and (battle.kind=='wild' or battle.kind=='trainer')
end
Intro.enabled=enabled
local function trainerProgress(b,remaining,duration)
  local timing=b and b.jpTrainerIntroTiming
  if timing and timing.clock and timing.revealTime>timing.slideStart then
    return math.max(0,math.min(1,(timing.clock:position(0)-timing.slideStart)
      /(timing.revealTime-timing.slideStart)))
  end
  return 1-math.max(0,math.min(1,(remaining or b.introSlide or 0)
    /(duration or require('src.core.Timing').BATTLE_SLIDE_IN_FRAMES)))
end
function Intro.begin(arena,battle)
  if not (arena and arena.encounter and not arena.backgroundOnly and enabled(battle))
      or battle.jpOpponentFocusSeen then return end
  if battle.kind=='trainer' and battle.jpTrainerIntroTiming
      and not battle.jpTrainerIntroTiming.focus then return end
  if battle.phase and battle.phase~='intro'
      and not (battle.phase=='messages' and battle.showPlayerBack and battle.introSlide~=nil) then return end
  if battle.kind=='trainer' then
    -- The foe arrives on the native silhouette/music clock. Camera and
    -- player wait for the fully drawn challenge, rather than consuming
    -- their whole presentation before the text is even queued.
    local state=battle.jpTrainerPresentation
    if state and state.done then return end
    state=state or {battle=battle,time=0,active=true,done=false,
      heartbeat=love.timer.getTime()}
    battle.jpTrainerPresentation=state
    arena.trainerIntro=state
    return
  end
  arena.focusIntro={battle=battle,time=0,seen=false,done=false}
end
function Intro.finish(arena)
  local intro=arena and arena.focusIntro
  if intro then intro.done=true;intro.weight=0 end
  if arena and arena.trainerIntro then
    arena.trainerIntro.done=true
    arena.trainerIntro.active=false
    arena.trainerIntro.finalDrawPending=nil
    arena.trainerIntro.time=Intro.HOLD+Intro.PULL
  end
end
function Intro.update(arena)
  local trainer=arena and arena.trainerIntro
  if trainer and not trainer.done then
    local b=trainer.battle
    -- Sample once at the physical presentation boundary. A slow GL frame
    -- must not give camera, silhouette alpha and the two slides different
    -- live PCM positions while they are being rendered.
    trainer.progress=trainerProgress(b)
    if not enabled(b) or b.phase=='menu' or b.sendingOut or b.enemySendingOut
        or not b.showPlayerBack or not b.showEnemyTrainer
        or (type(b.picOffset)=='function'
          and (b:picOffset('back')~=0 or b:picOffset('foe')~=0)) then
      Intro.finish(arena)
    else
      local now=love.timer.getTime()
      if trainer.seen and b.jpIntroTextShown and not trainer.textSeen then
        trainer.textSeen=true;trainer.time=0;trainer.lastTime=now
      end
      if trainer.textSeen and trainer.lastTime then
        local dt=math.max(0,now-trainer.lastTime)
        if dt<=.25 then trainer.time=trainer.time+math.min(dt,1/15) end
      end
      trainer.lastTime=now
      if trainer.time>=Intro.HOLD+Intro.PULL then
        Intro.finish(arena)
        -- A 4x frame may still have logic ticks left after this update.
        -- Release the challenge only after the canonical pose was drawn,
        -- or a native trainer exit can start before that final image exists.
        trainer.active=true;trainer.finalDrawPending=true
      end
    end
  end
  local intro=arena and arena.focusIntro
  if not intro or intro.done then return end
  local battle=intro.battle
  -- A fast-forward/skip may finish the native introduction sooner. Settle
  -- before any send-out/attack: native OAM effects use the final fixed shot.
  if not enabled(battle) or battle.phase=='menu' or battle.sendingOut
      or battle.enemySendingOut or (intro.seen and not battle.showPlayerBack)
      or (intro.seen and type(battle.picOffset)=='function'
        and (battle:picOffset('back')~=0 or battle:picOffset('foe')~=0)) then
    return Intro.finish(arena)
  end
  local now=love.timer.getTime()
  -- The opening cry and the typewriter text own their native timing. Only
  -- a completed physical text draw releases the close shot; simulation ticks
  -- alone (including 4x speed) must never pull away before it is readable.
  if intro.seen and battle.jpIntroTextShown and not intro.textSeen then
    intro.textSeen=true;intro.time=0;intro.lastTime=now
  end
  if intro.textSeen and intro.lastTime then
    local dt=math.max(0,now-intro.lastTime)
    -- Native logic can update four times per physical frame. Measure actual
    -- presentation time, and exclude a background/menu suspension gap.
    if dt<=.25 then intro.time=intro.time+math.min(dt,1/15) end
  end
  intro.lastTime=now
  if intro.time>=Intro.HOLD+Intro.PULL then Intro.finish(arena) end
end
function Intro.shown(arena)
  local trainer=arena and arena.trainerIntro
  if trainer and trainer.finalDrawPending then
    trainer.finalDrawPending=nil;trainer.active=false
  end
  if trainer and not trainer.done then
    trainer.seen=true
    -- Refresh only when the card is really submitted, never from logic-only
    -- updates. If a renderer disappears the host can fail open safely.
    trainer.heartbeat=love.timer.getTime()
  end
  local intro=arena and arena.focusIntro
  if intro and not intro.done and not intro.seen then
    intro.seen=true;intro.lastTime=love.timer.getTime()
    intro.battle.jpOpponentFocusSeen=true
  end
end
function Intro.weight(arena)
  if arena and arena.trainerIntro then
    local intro=arena.trainerIntro
    if intro.done or not enabled(intro.battle) then return 0 end
    return 1-smooth(Intro.trainerPull(arena))
  end
  local intro=arena and arena.focusIntro
  if not intro or intro.done then return 0 end
  local t=math.max(0,math.min(1,(intro.time-Intro.HOLD)/Intro.PULL))
  return 1-t*t*(3-2*t)
end
function Intro.nativeSlide(arena)
  -- Only the entrance slide is replaced; post-intro trainer exits and all
  -- original-mode transitions retain their original movement/timing.
  return arena and arena.focusIntro~=nil
end
function Intro.trainerProgress(arena,remaining,duration)
  local intro=arena and arena.trainerIntro
  if not intro or intro.done then return 1 end
  local b=intro.battle
  return intro.progress or trainerProgress(b,remaining,duration)
end
function Intro.trainerPull(arena)
  local intro=arena and arena.trainerIntro
  if not intro or intro.done then return 1 end
  return math.max(0,math.min(1,((intro.time or 0)-Intro.HOLD)/Intro.PULL))
end
function Intro.trainerAlpha(arena,side)
  if side=='player' and arena and arena.trainerIntro
      and Intro.trainerPull(arena)<=Intro.TRAINER_PLAYER_START then return 0 end
  return 1
end
function Intro.entranceRemaining(arena,remaining,duration,side)
  local fraction=math.max(0,math.min(1,remaining/duration))
  if not (arena and arena.trainerIntro) then return fraction end
  if side then
    local t=Intro.trainerProgress(arena,remaining,duration)
    if side=='enemy' then return 1-smooth(t/Intro.TRAINER_FOE_END) end
    return 1-smooth((Intro.trainerPull(arena)-Intro.TRAINER_PLAYER_START)/(1-Intro.TRAINER_PLAYER_START))
  end
  return fraction*fraction*(3-2*fraction)
end
local function dimensions(battle)
  local path=battle.showEnemyTrainer and battle.trainerPic
    or battle.enemy and battle.enemy.sprite
  local ok,pic=pcall(battle.picImage,battle,path)
  return ok and pic and pic:getWidth() or 56,ok and pic and pic:getHeight() or 56
end
function Intro.worldPixel(camera,cell,ground,nativeScale,r)
  local e,f=camera.eye,camera.focus
  local dx,dy,dz=f[1]-e[1],f[2]-e[2],f[3]-e[3]
  local len=math.sqrt(dx*dx+dy*dy+dz*dz)
  local depth=((cell[1]-e[1])*dx+(ground-e[2])*dy+(cell[2]-e[3])*dz)/len
  return nativeScale*r.Up*2*depth*math.tan(camera.fov/2)/r.ph
end
-- Foe artwork has one world size referenced to the centre of the field. It
-- must not grow with its own distance merely to occupy a fixed screen box.
-- Keep the near-side size and every native feet/ball/move anchor unchanged.
function Intro.cardWorldPixel(arena,canonical,side,ground,nativeScale,r,trainer)
  local cell=arena[side]
  if side=='enemy' and not trainer and arena.mid then
    return Intro.worldPixel(canonical,arena.mid,ground,nativeScale,r)
  end
  return Intro.worldPixel(canonical,cell,ground,nativeScale,r)
end
function Intro.pose(arena,canonical,ground,r)
  arena.cardCanonical=Blend.copy(canonical)
  local weight=Intro.weight(arena)
  arena.focusCanonical=weight>0 and Blend.copy(canonical) or nil
  if weight<=0 then return canonical end
  local battle=(arena.trainerIntro or arena.focusIntro).battle
  local w,h=dimensions(battle)
  local m=arena.jpMetrics
  if not m or not arena.enemy then return canonical end
  local native=require('src.battle.BattlePresentation').pictureScale(m,'enemy',w,h)
  local pixel=Intro.cardWorldPixel(arena,canonical,'enemy',ground,native,r,battle.showEnemyTrainer)
  if pixel<=0 then return canonical end
  local view=V.require('Mat4').lookAt(canonical.eye,canonical.focus,{0,1,0})
  local centerHeight=h*pixel*.5
  local focus={arena.enemy[1]+view[5]*centerHeight,
    ground+view[6]*centerHeight,arena.enemy[2]+view[7]*centerHeight}
  local dx,dy,dz=canonical.eye[1]-canonical.focus[1],
    canonical.eye[2]-canonical.focus[2],canonical.eye[3]-canonical.focus[3]
  local length=math.sqrt(dx*dx+dy*dy+dz*dz)
  local fieldHeight=m.command.y*m.sy*r.dpiY
  local fieldWidth=m.width*m.sx*r.dpiX
  local height=math.min(math.max(h*native*r.Up*1.25,fieldHeight*.42),
    fieldHeight*.52,fieldWidth*.68*h/math.max(1,w))
  if arena.trainerIntro then
    -- A trainer introduction is an actual portrait close-up. The old wild
    -- framing cap made the foe scarcely larger than its final battle card,
    -- especially on phones; use the free field above the dialogue instead.
    height=math.min(math.max(h*native*r.Up*1.65,fieldHeight*.62),
      fieldHeight*.74,fieldWidth*.84*h/math.max(1,w))
  end
  local fov=canonical.fov
  local distance=h*pixel*r.ph/(2*math.tan(fov/2)*math.max(1,height))
  local close=Blend.copy(canonical)
  close.focus=focus
  close.eye={focus[1]+dx/length*distance,focus[2]+dy/length*distance,focus[3]+dz/length*distance}
  close.fov=fov
  close.filmX=2*((m.x-r.vux)*r.dpiX+fieldWidth*.5)/r.pw-1
  close.filmY=2*((m.y-r.vuy)*r.dpiY+fieldHeight*.48)/r.ph-1
  local pose=Blend.mix(canonical,close,weight)
  if arena.trainerIntro then
    -- Eye/target interpolation is not monotonic in projected screen space:
    -- a landscape pull-back can briefly raise the foe above both endpoint
    -- shots. Keep its fixed world-size card inside the frame using only a
    -- small film-plane correction; final canonical and the wild shot stay exact.
    local v=V.require('Mat4').lookAt(pose.eye,pose.focus,{0,1,0})
    local x,y,z=arena.enemy[1],ground,arena.enemy[2]
    local depth=-(v[9]*x+v[10]*y+v[11]*z+v[12])
    if depth>0 then
      local tan=math.tan(pose.fov/2)
      local top=(1+(pose.filmY or 0)
        -(v[5]*x+v[6]*y+v[7]*z+v[8]+h*pixel)/(depth*tan))*r.ph/2
      if top<2 then pose.filmY=(pose.filmY or 0)+(2-top)*2/r.ph end
      local aspect=r.pw/r.ph
      local center=(1+(pose.filmX or 0)
        +(v[1]*x+v[2]*y+v[3]*z+v[4])/(depth*tan*aspect))*r.pw/2
      local half=w*pixel*r.pw/(4*depth*tan*aspect)
      -- The native portrait destination itself may have a 1px side margin;
      -- preserve it so the correction tends to zero at the final frame.
      local shift=math.max(0,1-(center-half))-math.max(0,center+half-(r.pw-1))
      pose.filmX=(pose.filmX or 0)+shift*2/r.pw
    end
  end
  return pose
end
return Intro
