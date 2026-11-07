-- Actual loaded card provider and native BattleState picture/palette draws.
-- All terrain and sprites are authored fixtures; no retail ROM is used.
return function(Game,Renderer,V,state,check,write)
  local g,fs=love.graphics,love.filesystem
  local Battle=require('src.battle.BattleState')
  local Transition=require('src.render.BattleTransition')
  local Timing=require('src.core.Timing')
  local Host=V.require('VoxelBattleStandalone')
  local Cards=V.require('VoxelBattleCardProvider')
  local Scene=V.require('VoxelBattleScene')
  local V3=V.require('Voxel3D')
  local Blend=V.require('BattleCameraBlend')
  local P=require('src.battle.BattlePresentation')
  local Intro=V.require('BattleIntroFocus')
  local staged=os.getenv('JP_QA_TRAINER_STAGED')=='1'
  if staged then return require('tests.jp29_trainer_intro_render')(Game,Renderer,V,state,check,write)end
  local report={styles={},cases={},cameras={}}
  local pinned=V.backSpritesSetting:get()
  V.backSpritesSetting:sync(false)
  local art=g.newCanvas(56,56,{dpiscale=1})
  g.setCanvas(art);g.clear(0,0,0,0)
  g.setColor(0,0,0,1);g.rectangle('fill',6,4,44,52)
  g.setColor(2/3,2/3,2/3,1);g.rectangle('fill',8,6,40,48)
  g.setColor(1/3,1/3,1/3,1);g.rectangle('fill',12,12,32,8)
  g.rectangle('fill',12,38,32,6);g.setCanvas()
  fs.write('fixture/trainer-shades.png',art:newImageData():encode('png'))
  Game.data.field.playerPics={back='fixture/trainer-shades.png'}
  Game.data.trainers.OPP_FIX_YOUNGSTER.pic='fixture/trainer-shades.png'
  Game.save.options.jpDialogScale=.75
  Game.save.options.jpBattleIntro=staged and 'focus' or 'original'
  Game.save.options.textSpeed=1
  Game.save.options.colors='redpp'
  require('src.render.PaletteFX').setMode('redpp')
  state.isOpaque,state.isOverworld=true,true
  state.player.facing='up'
  local worldArena={map=state.map,mid={136,136},player={136,136},enemy={136,88},playerCell={8,8},cam='wide'}
  local pose={eye={136,130,200},focus={136,0,130},fov=.8,up={0,1,0},curve=0}
  function state:draw()
    local surface=Scene.render(self,worldArena,function()end,{pose=pose,pitch=.7})
    if surface then Renderer:setWorldOverride(surface)end
    V3.camera=pose
  end
  Game.overworld=state
  -- All four trainer bit patterns retain the exact native wipe+black hold.
  for _,row in ipairs({{false,false,'spiralin'},{true,false,'spiralout'},
      {false,true,'shrink'},{true,true,'split'}})do
    local done,popped=0,0
    local game={mods=Game.mods,data=Game.data,stack={pop=function()popped=popped+1 end}}
    local b={kind='trainer'}
    local t=Transition.new(game,function()done=done+1 end,
      {trainer=true,stronger=row[1],dungeon=row[2],battle=b})
    check(t.style==row[3] and not t.seamless,row[3]..' is the native trainer wipe')
    for _=1,t.wipeLen+59 do t:update(1/60)end
    check(done==0 and popped==0,row[3]..' holds all 60 native blackout frames')
    t:update(1/60)
    check(done==1 and popped==1,row[3]..' enters after exactly wipe+60 frames')
    report.styles[#report.styles+1]={style=t.style,frames=t.wipeLen+60}
  end
  local rawDraw=V3.draw
  local captures,skipCards
  V3.draw=function(mesh,texture,model,...)
    if captures and texture and texture.getWidth and texture:getWidth()==160
        and texture:getHeight()==144 and model then
      local copy={};for i=1,16 do copy[i]=model[i]end
      local data=texture:newImageData()
      local count,sum=0,0
      for y=0,143 do for x=0,159 do
        local r,b,c,a=data:getPixel(x,y)
        if a>.99 then count=count+1;sum=sum+(r+b+c)/3 end
      end end
      local _,_,_,alpha=g.getColor()
      captures[#captures+1]={model=copy,count=count,brightness=count>0 and sum/count or 0,alpha=alpha}
    end
    if skipCards and texture and texture.getWidth and texture:getWidth()==160
        and texture:getHeight()==144 and model then return end
    return rawDraw(mesh,texture,model,...)
  end
  for _,size in ipairs({{480,800},{800,480}})do
    assert(love.window.setMode(size[1],size[2],{vsync=0}))
    Game.stack.states={state};Game:draw()
    local battle=Battle.newTrainer(Game,'OPP_FIX_YOUNGSTER',1)
    Game.stack:push(battle)
    check(Host.session and battle.showPlayerBack and battle.showEnemyTrainer,'actual trainer entry initializes both native pictures')
    if staged then
      check(Host.session.context.arena.trainerIntro and not Host.session.context.arena.focusIntro,
        'modern trainer entrance owns staged camera and opposing picture paths')
    else
      check(not Host.session.context.arena.trainerIntro and not Host.session.context.arena.focusIntro,
        'original option retains its original fixed camera and simultaneous slides')
    end
    check(battle.introSlide==Timing.BATTLE_SLIDE_IN_FRAMES,'trainer retains the full original 72-frame silhouette entrance')
    check((Host.session.context.arena.presentationTime or 0)>=.55
      and Host.session.context.arena.entryDuration==nil,
      'trainer starts in settled battle view immediately after native blackout; no wild orbit')
    local function frame(slide,label,quiet)
      battle.introSlide=slide
      Cards:update(Host.session.context)
      captures={};Game:draw();g.setCanvas()
      local out=captures;captures=nil
      check(#out==2,label..' draws exactly two complete 3D trainer cards')
      local surface=require('src.render.GameViewport').target()
      if not quiet then write(label..'.png',surface:newImageData():encode('png'):getString())end
      if slide==0 then
        local context=Host.session.context
        local r=Renderer:frameRects();local metrics=P.metrics(r)
        local ratio=r.pw/context.services.renderSize.width
        local errorPixels=0
        for _,side in ipairs({'player','enemy'})do
          local foot=context.arena[side]
          local px,py=context.services.project(foot[1],context.groundY,foot[2])
          local target=metrics.actor[side]
          local expectedX=(metrics.x+target.x*metrics.sx-r.vux)*r.dpiX
          local expectedY=(metrics.y+target.y*metrics.sy-r.vuy)*r.dpiY
          errorPixels=math.max(errorPixels,math.abs(px*ratio-expectedX),math.abs(py*ratio-expectedY))
        end
        check(errorPixels<.1,label..' actual arena feet land on native UI/animation targets')
        local fov=math.deg(2*math.atan(math.tan(V3.fovY/2)*144*r.Up/r.ph))
        check(math.abs(fov-46)<.01,label..' actually uses the settled46-degree lens')
        local a,b=context.arena.player,context.arena.enemy
        local distanceScale=math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2)/48
        local thirdEye=13+4+48*math.sin(math.rad(10))
        local actualHeight=(V3.eye[2]-context.groundY)/distanceScale
        check(math.abs(actualHeight-thirdEye)<.01,label..' actual camera height matches normal3RD rig')
        report.cameras[#report.cameras+1]={label=label,nativeFov=fov,
          normalizedEyeHeight=actualHeight,anchorErrorPixels=errorPixels,
          presentationTime=context.arena.presentationTime}
      end
      for index,card in ipairs(out)do
        local ax,ay=index==1 and 124 or 80,index==1 and 56 or 96
        local x,y=ax/160-.5,1-ay/144
        local m=card.model
        card.x,card.y=V3.project(m[1]*x+m[2]*y+m[4],m[5]*x+m[6]*y+m[8],m[9]*x+m[10]*y+m[12])
        card.left=V3.project(m[1]*(x-28/160)+m[2]*y+m[4],m[5]*(x-28/160)+m[6]*y+m[8],m[9]*(x-28/160)+m[10]*y+m[12])
        card.right=V3.project(m[1]*(x+28/160)+m[2]*y+m[4],m[5]*(x+28/160)+m[6]*y+m[8],m[9]*(x+28/160)+m[10]*y+m[12])
        local _,top=V3.project(m[1]*x+m[2]*(y+56/144)+m[4],m[5]*x+m[6]*(y+56/144)+m[8],m[9]*x+m[10]*(y+56/144)+m[12])
        card.top=top
        card.model=nil
      end
      return out
    end
    local tag=size[1]..'x'..size[2]
    if staged then
      local rows={}
      for tick=0,71 do
        local cards=frame(72-tick,'staged-frame-'..tag..'-'..tick,true)
        check(cards[1].top>=1.9,'opponent head stays inside during every staged camera frame')
        if tick/72>=Intro.TRAINER_FOE_END then
          check(cards[1].left>=.9 and cards[1].right<=size[1]-.9,
            'landed foe stays horizontally framed throughout pull-back')
        end
        rows[#rows+1]={tick=tick,enemy=cards[1],player=cards[2]}
      end
      write('staged-frame-bounds-'..tag..'.json',assert(require('src.link.Json').encode(rows)))
    end
    local first=frame(72,'trainer-start-'..tag)
    local arrival,pull
    if staged then
      arrival=frame(45,'trainer-foe-arrival-'..tag)
      check(arrival[2].alpha==0,'near player remains invisible throughout opponent-first cut-in')
      check(Intro.weight(Host.session.context.arena)>.999,'opponent cut-in keeps the close camera')
      pull=frame(20,'trainer-pull-player-'..tag)
      check(pull[2].alpha==1,'player joins while the physical camera pulls back')
      check(Intro.weight(Host.session.context.arena)>0 and Intro.weight(Host.session.context.arena)<1,
        'player entrance runs during the real camera pull-back')
      local surface=require('src.render.GameViewport').target()
      local actual=surface:newImageData()
      skipCards=true;Game:draw();g.setCanvas();skipCards=false
      local absent=surface:newImageData()
      local r=Renderer:frameRects();local m=P.metrics(r);local p=m.panels or m
      local c=p.command;local same=true
      for yy=math.floor((p.y+(c.y+4)*p.sy)*r.dpiY),math.floor((p.y+(c.y+c.h-4)*p.sy)*r.dpiY)do
        for xx=math.floor((p.x+(c.x+4)*p.sx)*r.dpiX),math.floor((p.x+(c.x+c.w-4)*p.sx)*r.dpiX)do
          local ar,ag,ab=actual:getPixel(xx,yy);local br,bg,bb=absent:getPixel(xx,yy)
          if ar~=br or ag~=bg or ab~=bb then same=false end
        end
      end
      check(same,'native white dialogue stays above player card during the pull-back')
    end
    local mid=frame(36,'trainer-middle-'..tag)
    local near=frame(1,'trainer-landing-'..tag)
    local final=frame(0,'trainer-ready-'..tag)
    if staged then
      check(first[1].right<0,'opponent begins outside left edge of its close-up viewport')
      check(arrival[1].left>=0 and arrival[1].right<=size[1],'opponent fits fully once the first cut-in lands')
      check(first[2].alpha==0 and near[2].alpha==1,'player appears once after the opponent and stays present')
      check(final[1].x>final[2].x,'staged arrival ends in the established player/foe battle positions')
    else
      check(first[1].x<mid[1].x and mid[1].x<near[1].x and near[1].x<final[1].x,'enemy silhouette slides from left at native timing')
      check(first[2].x>mid[2].x and mid[2].x>near[2].x and near[2].x>final[2].x,'player silhouette slides from right at native timing')
      check(first[1].right<0 and first[2].left>size[1],'both trainer pictures begin fully outside physical viewport')
      check(first[1].x<first[2].x and final[1].x>final[2].x,
        'opposing trainer paths cross from their original sides into the modern battle layout')
    end
    for i=1,2 do
      check(first[i].count>100 and first[i].count==mid[i].count and mid[i].count==near[i].count and near[i].count==final[i].count,'side '..i..' keeps intact art throughout original slide')
      check(first[i].brightness<final[i].brightness-.1,'side '..i..' native silhouette recolors only when landing')
      check(final[i].left>=0 and final[i].right<=size[1],
        'side '..i..' complete picture settles inside the physical viewport')
    end
    battle:slidePic('foe',64,64,4);battle:slidePic('back',-72,-72,4)
    local departing=frame(0,'trainer-departure-'..tag)
    check(departing[1].x>final[1].x and departing[2].x<final[2].x,'native trainer exits go right/left without a wild fade')
    check(departing[1].left>size[1] and departing[2].right<0,'both trainer exits finish fully offscreen before engine hides them')
    for i=1,2 do
      check(departing[i].count==final[i].count and math.abs(departing[i].brightness-final[i].brightness)<.001,'trainer exit side '..i..' keeps whole opaque picture')
    end
    check(battle:picOffset('foe')==64 and battle:picOffset('back')==-72,'capture restores both live exit offsets')
    report.cases[#report.cases+1]={size=size,first=first,middle=mid,landing=near,ready=final,departure=departing}
    Host.finish('trainer-original-qa');Blend.cancel()
  end
  V3.draw=rawDraw
  V.backSpritesSetting:sync(pinned)
  check(#Game.mods.errors==0,'trainer provider raises no MOD runtime errors')
  write('trainer-original-results.json',require('src.link.Json').encode(report))
end
