-- Real Game:update -> input.step hook -> native battle logic -> physical GL
-- frame. Captures are observed, never manually refreshed by this fixture.
return function(Game,Renderer,V,state,check,write,render)
  local Battle=require('src.battle.BattleState')
  local Host=V.require('VoxelBattleStandalone')
  local Cards=V.require('VoxelBattleCardProvider')
  local Blend=V.require('BattleCameraBlend')
  local Fixed=require('src.core.FixedStep')
  local Json=require('src.link.Json')
  local Input=Game.input
  local rawDraw,rawWorld=Battle.drawPicsLayer,Cards.drawWorld
  local rawTime=love.timer.getTime
  local now=100
  love.timer.getTime=function()return now end
  local lastCapture,observations,captureCounts={},{},{}
  local report={cases={},assets='authored; no ROM',physicalAndroid=false,
    update='actual Game:update with actual FixedStep and MOD input.step hook'}
  local function stateOf(b,side)
    local target=side=='enemy' and b.enemy or b.player
    local trainer=side=='enemy' and b.showEnemyTrainer or side=='player' and b.showPlayerBack
    local grow=b:growInScale(target) or b:shrinkOutScale(target)
    return {frame=b.frame or -1,trainer=trainer==true,
      hidden=b.fieldCleared==true or (not trainer and ((grow~=nil and grow<=0) or b:fxHidden(target)
        or (side=='enemy' and (b.enemyHidden or b.enemySendingOut))
        or (side=='player' and b.sendingOut)))==true,
      offset=b:picOffset(side=='enemy' and 'foe' or 'back') or 0,
      grow=b:growInScale(target) or -1,
      sprite=trainer and tostring(side=='enemy' and b.trainerPic or b.playerBackPic)
        or tostring(target and target.sprite)}
  end
  Battle.drawPicsLayer=function(b,slide,sx,sy,side,...)
    if Host.session and Host.session.capturingNativePics and side then
      lastCapture[side]=stateOf(b,side)
      captureCounts[side]=(captureCounts[side] or 0)+1
    end
    return rawDraw(b,slide,sx,sy,side,...)
  end
  Cards.drawWorld=function(self,context,...)
    local answer=rawWorld(self,context,...)
    for _,side in ipairs({'enemy','player'})do
      local live=stateOf(context.battle,side)
      local captured=lastCapture[side]
      local world=self:covers(context,side)
      local expectedHidden=live.hidden
      local stale=world and (expectedHidden or not captured
        or captured.trainer~=live.trainer or captured.sprite~=live.sprite
        or captured.grow~=live.grow)
      -- A hidden previous frame must not cause native UI fallback when the
      -- current frame is visible: that changes the picture's size/position.
      local pinned=side=='player' and V.backSpritesSetting:get()
        and not (context.battle.showPlayerBack and context.arena.focusIntro)
      if not expectedHidden and not pinned and not world then stale=true end
      observations[#observations+1]={side=side,live=live,captured=captured,
        world=world,stale=stale==true,pinned=pinned==true}
    end
    return answer
  end
  local function step(speed,dt)
    now=now+(dt or 1/60)
    Game.save.options.speedBattle=speed
    Game:update(dt or 1/60)
  end
  local function create(kind,speed,pinned)
    Game.stack.states={state};Game.overworld=state;Input:reset()
    Host.finish('temporal-next');Blend.cancel();lastCapture={}
    V.backSpritesSetting:sync(pinned)
    Game.save.options.speedBattle=speed
    Game.save.options.jpBattleIntro='focus'
    Game.save.options.jpDialogScale=.75
    Game.save.options.animations=true;Game.save.options.textSpeed=1
    Fixed:init(function(dt)Game:step(dt)end)
    Fixed.setHz(60)
    local b=kind=='trainer' and Battle.newTrainer(Game,'OPP_FIX_YOUNGSTER',1)
      or Battle.newWild(Game,'FIXMON_C',10)
    if kind=='trainer' then b.trainerPic=love.graphics.newImage('fixture/intro-trainer.png')end
    Game.stack:push(b)
    Host.session.context.arena.presentationTime=1
    -- Reproduce the post-handoff wild arena published by Host.prepare.
    if kind=='wild' then Host.session.context.arena.entryDuration=1 end
    return b
  end
  local ok,err=xpcall(function()
    local cases={{kind='wild',speed=1,pinned=true},{kind='wild',speed=4,pinned=false},
      {kind='trainer',speed=1,pinned=true},{kind='trainer',speed=4,pinned=false}}
    if os.getenv('JP_QA_TEMPORAL_ONE')=='1' then cases={cases[1]}end
    love.window.setMode(480,800,{vsync=0})
    for _,c in ipairs(cases)do
      local tag=c.kind..'-'..c.speed..'x-'..(c.pinned and 'pinned' or 'world')
      local b=create(c.kind,c.speed,c.pinned)
      local row={tag=tag,intro={},damage={},stale=0,frames=0,preRenderCaptures=0,maxCapturesPerSide=0}
      for frame=0,1100 do
        observations={};captureCounts={}
        if frame>0 then
          if frame%12==0 then Input:sourcePress('a','temporal-qa')
          elseif frame%12==1 then Input:sourceRelease('a','temporal-qa')end
          step(c.speed)
        end
        row.preRenderCaptures=row.preRenderCaptures+(captureCounts.enemy or 0)+(captureCounts.player or 0)
        local pixels=render()
        row.maxCapturesPerSide=math.max(row.maxCapturesPerSide,captureCounts.enemy or 0,captureCounts.player or 0)
        for _,o in ipairs(observations)do if o.stale then
          row.stale=row.stale+1;row.intro[#row.intro+1]=o
          if row.stale<=3 then write('temporal-'..tag..'-stale-'..row.stale..'.png',pixels:encode('png'):getString())end
        end end
        if os.getenv('JP_QA_TEMPORAL_REFERENCE')=='1' and #row.intro>0 and row.stale<=3
            and row.intro[#row.intro].live.frame==b.frame then
          -- Separate diagnostic replay: refresh after preserving the actual
          -- frame, then compare identical logical state and camera time.
          Cards:update(Host.session.context)
          local reference=render()
          local changed=0
          for y=0,pixels:getHeight()-1 do for x=0,pixels:getWidth()-1 do
            local r,g,b=pixels:getPixel(x,y);local rr,gg,bb=reference:getPixel(x,y)
            if math.max(math.abs(r-rr),math.abs(g-gg),math.abs(b-bb))>3/255 then changed=changed+1 end
          end end
          row.intro[#row.intro].changedPixels=changed
          write('temporal-'..tag..'-corrected-'..row.stale..'.png',reference:encode('png'):getString())
        end
        row.frames=frame
        if b.phase=='menu' then break end
      end
      Input:sourceRelease('a','temporal-qa')
      check(b.phase=='menu',tag..' native intro queue reaches menu through Game:update')
      -- Trigger the engine's damage feedback while varying the unrelated
      -- battle frame. Observe every physical presentation including 30 Hz.
      for _,side in ipairs({'enemy','player'})do
        local target=side=='enemy' and b.enemy or b.player
        b:applyHitFx({animType=4,blink=target})
        for frame=0,70 do
          observations={}
          if frame>0 then step(1,frame>30 and 1/30 or 1/60)end
          local pixels=render()
          for _,o in ipairs(observations)do if o.side==side then
            row.damage[#row.damage+1]=o
            if o.stale then
              row.stale=row.stale+1
              if row.stale<=5 then write('temporal-'..tag..'-damage-stale-'..row.stale..'.png',pixels:encode('png'):getString())end
            end
          end end
          if frame>0 and (not b.fx.blink or b.fx.blink.frames<=0)then break end
        end
      end
      report.cases[#report.cases+1]=row
      write('temporal-'..tag..'.json',assert(Json.encode(row)))
      print('TEMPORAL_STALE',tag,row.stale)
      if os.getenv('JP_QA_TEMPORAL_BASELINE')~='1' then
        check(row.stale==0,tag..' current native state and actual world picture agree on every frame')
        check(row.preRenderCaptures==0 and row.maxCapturesPerSide<=1,tag..' zero prelogic captures and at most one per side per physical frame')
      else check(row.stale>0,tag..' baseline reproduces visible stale cards/native fallback')end
    end
    -- Static image probe intentionally refreshes jp23 captures as well: it
    -- isolates native fixed-window clipping independently of stale frames.
    local b=create('wild',1,false)
    b.phase='menu';b.introSlide=0;b.introBalls=false;b.showPlayerBack=false
    b.enemyHudPending=false;b.enemySendingOut=false;b.sendingOut=false
    local arena=Host.session.context.arena
    arena.focusIntro.done=true;arena.focusIntro.time=10
    local V3=V.require('Voxel3D');local mesh=V.require('BattleBillboard').mesh()
    local rawV3=V3.draw;local cardImages
    V3.draw=function(m,tex,...)
      if m==mesh and tex and tex.newImageData then cardImages[#cardImages+1]=tex:newImageData()end
      return rawV3(m,tex,...)
    end
    local function staticCard(effect)
      b.picFx={};b.fx={}
      if effect then b.picFx[b.enemy]={kind='blink',t=5,ox=0,oy=0}end
      Cards:update(Host.session.context) -- static old/new parity, no temporal check
      cardImages={};render()
      local img=assert(cardImages[1],'actual enemy card texture was drawn')
      check(b.wideRegion==nil,'capture restores native wideRegion ownership')
      local count=0
      for y=0,img:getHeight()-1 do for x=0,img:getWidth()-1 do
        local _,_,_,a=img:getPixel(x,y);if a>.1 then count=count+1 end
      end end
      write('picfx-'..(effect and 'blink-visible' or 'normal')..'.png',img:encode('png'):getString())
      return count
    end
    local normal,blink=staticCard(false),staticCard(true)
    V3.draw=rawV3
    report.picFx={normalPixels=normal,blinkPixels=blink}
    check(normal>100,'normal actual card has authored opaque body pixels')
    if os.getenv('JP_QA_TEMPORAL_BASELINE')=='1' then
      check(blink<normal*.5,'baseline reproduces clipped visible half of native picFx blink')
    else check(blink==normal,'visible picFx blink frame preserves every source body pixel')end
    write('temporal-results.json',assert(Json.encode(report)))
    check(#Game.mods.errors==0,'temporal capture sequence has no MOD errors')
  end,debug.traceback)
  Battle.drawPicsLayer,Cards.drawWorld=rawDraw,rawWorld
  Host.finish('temporal-finished');Blend.cancel();love.timer.getTime=rawTime
  if not ok then error(err,0)end
end
