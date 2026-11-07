-- Actual OW.pushBattle -> BattleTransition -> BattleState.enter, sampled at
-- per rendered frame against Source:tell(). Authored terrain/sprites/PCM;
-- no cartridge data and no claim about a physical audio output device.
return function(Game,Renderer,V,state,check,write,probe)
  local g,fs=love.graphics,love.filesystem
  local OW=require('src.world.OverworldController')
  local Battle=require('src.battle.BattleState')
  local Transition=require('src.render.BattleTransition')
  local P=require('src.battle.BattlePresentation')
  local Sound=require('src.core.Sound')
  local Music=require('src.core.Music')
  local Json=require('src.link.Json')
  local Host=V.require('VoxelBattleStandalone')
  local Blend=V.require('BattleCameraBlend')
  local V3=V.require('Voxel3D')
  local Stack,Input=Game.stack,Game.input
  local movieDir=os.getenv('JP_QA_VIDEO_FRAMES')
  local rawOverride=Renderer.setWorldOverride
  local observedView
  Renderer.setWorldOverride=function(self,surface,vw,vh)
    observedView=vw and vh and {width=vw,height=vh} or nil
    return rawOverride(self,surface,vw,vh)
  end
  local function physicalLandmarks()
    local r=Renderer:frameRects();local cw,ch=V3.size()
    local tw,th=r.pw,r.ph;local ox,oy=r.vux*r.dpiX,r.vuy*r.dpiY
    if observedView then
      local sp=require('src.render.Zoom').scale(r.Sp)
      tw,th=observedView.width*sp,observedView.height*sp
      ox=ox+math.floor((r.pw-tw)/2);oy=oy+math.floor((r.ph-th)/2)-r.lift
    end
    local out={}
    for i,point in ipairs({{136,0,200},{152,0,200},{136,0,184}})do
      local x,y=V3.project(unpack(point));if x then out[i]={(ox+x/cw*tw)/r.pw,(oy+y/ch*th)/r.ph}end
    end
    return out
  end
  local report={cases={},assets='authored; no retail ROM',logic_rate=60,
    sampleClock='actual OpenAL Source',physicalAudioVerified=false}
  local function copy(t)local out={};for k,v in pairs(t or {})do out[k]=v end;return out end
  local function maxDifference(a,b)
    local out=0;for i=1,#a do out=math.max(out,math.abs(a[i]-b[i]))end;return out
  end
  local function tone(path,hz,seconds)
    local pack=love.data.pack
    local samples={}
    for i=0,math.floor((seconds or .1)*8000)-1 do samples[#samples+1]=pack('string','<i2',math.floor(math.sin(i*hz*math.pi/4000)*2500))end
    local pcm=table.concat(samples)
    local wav='RIFF'..pack('string','<I4',36+#pcm)..'WAVEfmt '..pack('string','<I4I2I2I4I4I2I2',16,1,1,8000,16000,2,16)
      ..'data'..pack('string','<I4',#pcm)..pcm
    assert(fs.write(path,wav))
  end
  tone('fixture/seamless-cry.wav',660)
  tone('fixture/seamless-theme.wav',440,30)
  Game.data.audio=Game.data.audio or {}
  Game.data.audio.cries={FIXMON_A={file='fixture/seamless-cry.wav'},FIXMON_C={file='fixture/seamless-cry.wav'}}
  Game.data.audio.songs=Game.data.audio.songs or {}
  Game.data.audio.songs.QA_BATTLE={file='fixture/seamless-theme.wav'}
  Game.data.audio.battle={wild='QA_BATTLE',trainer='QA_BATTLE'}
  Game.data.audio.sfx=Game.data.audio.sfx or {}
  Game.data.audio.sfx.Ball_Toss={file='fixture/seamless-cry.wav'}
  Game.data.audio.sfx.Ball_Poof={file='fixture/seamless-cry.wav'}
  Sound.invalidate()
  setmetatable(Game.data,{__index=require('src.core.Data')})
  -- High-contrast authored walker makes the retained human cast observable.
  local walker=g.newCanvas(16,96,{dpiscale=1})
  g.push('all');g.setCanvas(walker);g.clear(0,0,0,0)
  for i=0,5 do
    g.setColor(1,0,1,1);g.rectangle('fill',4,i*16+2,8,10)
    g.setColor(0,1,1,1);g.rectangle('fill',4,i*16+12,3,4);g.rectangle('fill',9,i*16+12,3,4)
  end
  g.pop();fs.write('fixture/seamless-walker.png',walker:newImageData():encode('png'))
  Game.data.sprites.SPRITE_FIX_PLAYER.image='fixture/seamless-walker.png'
  Game.data.sprites.SPRITE_FIX_PLAYER.trueColor=true
  Game.data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
  Game.data.field.flyWarps=Game.data.field.flyWarps or {}
  Game.data.field.waterTilesets=Game.data.field.waterTilesets or {}
  Game.data.field.forcedMovement=Game.data.field.forcedMovement or {}
  Game.data.field.forcedMovement.tiles=Game.data.field.forcedMovement.tiles or {}
  Game.save.options.pipelines={voxel=2}
  require('src.render.Pipelines').applyOptions(Game.save.options)
  local ow=setmetatable({},{__index=OW})
  ow:enter('FIX_ROUTE',8,12,'up',{via='boot',keepMusic=true})
  -- Actual state/entry method with the already prepared fixture's real GL
  -- world pass. Only world actors/maps are authored; no transition is mocked.
  ow.paletteNameFor=state.paletteNameFor;ow.neighbors={}
  Game.overworld=ow
  local tick,audio,playback
  local function musicPosition()
    return playback and playback.source:tell('seconds') or 0
  end
  local rawCry,rawBattleMusic,rawSound=Sound.playCry,Music.playBattle,Sound.play
  Sound.play=function(data,name,...)
    local src=rawSound(data,name,...)
    audio[#audio+1]={kind='sfx',name=name,frame=tick,source=src~=nil,music=musicPosition()}
    return src
  end
  Sound.playCry=function(data,species,...)
    local src=rawCry(data,species,...)
    audio[#audio+1]={kind='cry',species=species,frame=tick,source=src~=nil,music=musicPosition()}
    return src
  end
  Music.playBattle=function(...)
    local result=rawBattleMusic(...)
    audio[#audio+1]={kind='theme',frame=tick,newPlayback=result~=playback,music=musicPosition()}
    playback=result
    return result
  end
  local function castMask(pixels,reference)
    local out,n={},0
    for y=0,pixels:getHeight()-1 do for x=0,pixels:getWidth()-1 do
      local r,g,b=pixels:getPixel(x,y);local rr,gg,bb=reference:getPixel(x,y)
      if math.max(math.abs(r-rr),math.abs(g-gg),math.abs(b-bb))>.03 then out[y*pixels:getWidth()+x]=true;n=n+1 end
    end end
    return out,n
  end
  local function frameStats(pixels)
    local dark,light,n=0,0,0
    local step=8
    for y=4,pixels:getHeight()-1,step do for x=4,pixels:getWidth()-1,step do
      local r,b,c=pixels:getPixel(x,y);n=n+1
      if math.max(r,b,c)<.025 then dark=dark+1 end
      if math.min(r,b,c)>.975 then light=light+1 end
    end end
    return dark/n,light/n
  end
  local cases={{480,800,.75,1,1},{800,480,.75,4,2},{480,800,1,1,3}}
  local selectedCase=tonumber(os.getenv('JP_QA_SEAMLESS_CASE'))
  if selectedCase then
    local selected=assert(cases[selectedCase],'unknown JP_QA_SEAMLESS_CASE')
    cases={selected}
    report.selectedCase=selectedCase
  end
  if os.getenv('JP_QA_TRAINER_ONLY')=='1' then cases={} end
  for _,case in ipairs(cases)do
    local caseIndex=case[5]
    local w,h,factor=case[1],case[2],case[3]
    local speed=case[4]
    local tag=w..'x'..h..'-'..factor
    love.window.setMode(w,h,{vsync=0})
    Game.save.options.jpDialogScale=factor
    Game.save.options.screenPos=caseIndex==3 and 'upper' or 'center'
    require('src.core.ScreenPosition').applyOptions(Game.save.options)
    Host.finish('seamless-next');Blend.cancel();Input:reset();Music.stop()
    Stack.states={ow};Game.overworld=ow
    tick,audio,playback=0,{},nil
    probe.render()
    ow.camera:follow(ow.player.px,ow.player.py,Renderer:worldViewSize())
    for _=1,60 do require('src.render.Pipelines').update(1/60);probe.render()end
    local entities=ow.entities;ow.entities={}
    local noPlayer=probe.render();ow.entities=entities
    local before=probe.render('seamless-before-'..tag)
    local beforeCast,beforeCastCount=castMask(before,noPlayer)
    local firstCastCount,castOverlap
    local firstCastPixels,firstNoCastPixels
    local beforeVP=copy(V3.vp)
    local beforeEye=copy(V3.eye)
    local beforeLandmarks=physicalLandmarks()
    local beforeWorldView=observedView and copy(observedView)
    Game.save.party[1].hp=Game.save.party[1].stats.hp
    local battle=Battle.newWild(Game,'FIXMON_C',10)
    ow:pushBattle(battle)
    local transition=Stack:top()
    local cue=transition.revealTime
    local entryPose=Blend.copy(Host.session.context.arena.entryPose)
    local entryCast=Host.session.cast
    check(getmetatable(transition)==Transition and transition.seamless,
      tag..' actual OW.pushBattle enters the ready 3D transition')
    local frames,firstUI,firstBattle,firstMenu={},nil,nil,nil
    local maxDark,maxWhite,firstVP,lastVP=0,0
    local maskFrames=0
    local maxEyeStep,totalEyeDistance,movingFrames=0,0,0
    local musicStable=true
    local previousEye,previousVP=beforeEye,beforeVP
    local previousLandmarks,maxLandmarkStep=beforeLandmarks,0
    local firstLandmarkError,handoffLandmarkStep=0,0
    local commandShown,sendoutShown=false,false
    local afterCamera
    local firstBattleMusic,previousMusic,maxMusicStep=0,0,0
    for frame=0,900 do
      tick=frame
      if frame>0 then
        if not firstMenu and frame>105 and frame%16==0 then Input:sourcePress('a','seamless-qa')
        elseif frame%16==1 then Input:sourceRelease('a','seamless-qa')end
        for _=1,speed do Game:step(1/60)end
        Music.update(Game.data)
      end
      local pixels,m=probe.render()
      local music=musicPosition()
      maxMusicStep=math.max(maxMusicStep,music-previousMusic);previousMusic=music
      musicStable=musicStable and Music.current()=='QA_BATTLE'
      local dark,white=frameStats(pixels)
      if frame==0 then
        local cast=Host.session.cast;Host.session.cast=nil
        local noCast=probe.render();Host.session.cast=cast
        pixels,m=probe.render()
        -- Defer the CPU pixel comparison until the cue has finished; doing
        -- hundreds of thousands of getPixel calls here stalls the test's
        -- render loop while the real audio device quite correctly continues.
        firstCastPixels,firstNoCastPixels=pixels,noCast
      end
      maxDark,maxWhite=math.max(maxDark,dark),math.max(maxWhite,white)
      if Renderer.screenVeil or Renderer.battleWipe then maskFrames=maskFrames+1 end
      local top=Stack:top()
      if top==battle and not firstBattle then firstBattle=frame;firstBattleMusic=music end
      local ui=Renderer.jpBattleModern and Renderer.battlePresentationCanvas
      local uiPixels=ui and ui:newImageData()
      local hasUI=false
      if uiPixels then
        local panel=m.panels or m
        local _,_,_,a=uiPixels:getPixel(panel.command.x+panel.command.w-6,panel.command.y+6)
        hasUI=a>.99
      end
      if hasUI and not firstUI then firstUI=frame end
      local vp,eye=copy(V3.vp),copy(V3.eye)
      local landmarks=physicalLandmarks()
      for i,value in ipairs(landmarks)do
        local last=previousLandmarks and previousLandmarks[i]
        if frame==0 and last then firstLandmarkError=math.max(firstLandmarkError,math.abs(value[1]-last[1]),math.abs(value[2]-last[2]))end
        if (not firstBattle or frame<=firstBattle) and last and math.abs(value[1]-.5)<.8 and math.abs(value[2]-.5)<.8
            and math.abs(last[1]-.5)<.8 and math.abs(last[2]-.5)<.8 then
          maxLandmarkStep=math.max(maxLandmarkStep,math.abs(value[1]-last[1]),math.abs(value[2]-last[2]))
          if frame==firstBattle then
            handoffLandmarkStep=math.max(handoffLandmarkStep,math.abs(value[1]-last[1]),math.abs(value[2]-last[2]))
          end
        end
      end
      if frame==0 then firstVP=maxDifference(vp,beforeVP)end
      local distance=0
      for i=1,3 do distance=distance+(eye[i]-previousEye[i])^2 end
      distance=math.sqrt(distance)
      if not firstBattle or frame<=firstBattle then
        maxEyeStep=math.max(maxEyeStep,distance);totalEyeDistance=totalEyeDistance+distance
        if distance>1e-5 then movingFrames=movingFrames+1 end
      end
      if firstBattle and frame==firstBattle then
        afterCamera={vp=vp,eye=eye,pose=Blend.copy(Host.session.context.arena.lastPose)}
        lastVP=maxDifference(vp,previousVP)
      end
      frames[#frames+1]={frame=frame,dark=dark,white=white,eye=eye,vp=vp,landmarks=landmarks,
        battle=top==battle,ui=hasUI,phase=battle.phase,introSlide=battle.introSlide,
        music=music,time=Host.session and Host.session.context.arena.presentationTime}
      if frame==0 or frame==15 or frame==30 or frame==45 or frame==49 or frame==60 or frame==75 then
        write('seamless-'..tag..'-'..string.format('%03d',frame)..'.png',pixels:encode('png'):getString())
      end
      if battle.sendingOut and not sendoutShown then
        sendoutShown=true;write('seamless-sendout-'..tag..'.png',pixels:encode('png'):getString())
      end
      if battle.phase=='menu' and top==battle then
        firstMenu=firstMenu or frame
        if not commandShown then
          commandShown=true;write('seamless-commands-'..tag..'.png',pixels:encode('png'):getString())
          g.push('all');g.setCanvas(require('src.render.GameViewport').target());g.origin()
          require('src.core.TouchControls'):draw();g.pop()
          write('seamless-commands-'..tag..'-touch.png',require('src.render.GameViewport').target():newImageData():encode('png'):getString())
        end
      end
      if movieDir and caseIndex<=2 and frame%2==0 then
        local path=movieDir..'/'..tag..'-'..string.format('%04d',frame/2)..'.png'
        local f=assert(io.open(path,'wb'));f:write(pixels:encode('png'):getString());f:close()
      end
      previousVP,previousEye,previousLandmarks=vp,eye,landmarks
      if firstMenu and frame>=firstMenu+30 then break end
    end
    Input:sourceRelease('a','seamless-qa')
    local afterCast,count=castMask(firstCastPixels,firstNoCastPixels);firstCastCount=count
    local overlap=0;for k in pairs(beforeCast)do if afterCast[k]then overlap=overlap+1 end end
    castOverlap=overlap/math.max(1,beforeCastCount)
    local maxPathError=0
    for _,sample in ipairs(frames)do
      if firstBattle and sample.frame<=firstBattle then
        local expected=Blend.encounter(entryPose,afterCamera.pose,math.min(1,sample.time/cue))
        maxPathError=math.max(maxPathError,maxDifference(sample.eye,expected.eye))
      end
    end
    write('seamless-clock-'..tag..'.json',assert(Json.encode({frames=frames,cue=cue,speed=speed,
      firstBattleMusic=firstBattleMusic,maxMusicStep=maxMusicStep,
      beforeLandmarks=beforeLandmarks,beforeWorldView=beforeWorldView,
      maxPathError=maxPathError,handoffLandmarkStep=handoffLandmarkStep})))
    check(maxDark<.95 and maxWhite<.95,tag..' every rendered frame retains visible terrain without a black/white cut')
    check(maskFrames==0,tag..' supported 3D entry never requests a flash veil or tile wipe')
    print('CAST',tag,beforeCastCount,firstCastCount,castOverlap)
    print('CONTINUITY',tag,firstLandmarkError,maxLandmarkStep,maxEyeStep,totalEyeDistance,firstBattle,firstUI,firstMenu)
    check(beforeCastCount>20 and firstCastCount>20 and castOverlap>.5,tag..' first approach frame retains the visible authored overworld player')
    local firstLandmarkPhysicalError=firstLandmarkError*math.max(before:getWidth(),before:getHeight())
    local mobileRounding=os.getenv('JP_QA_EMULATE_ANDROID')=='1'
    check(mobileRounding and firstLandmarkPhysicalError<=1 or firstLandmarkError<1e-6,
      tag..' first transition retains composed landmarks within '..(mobileRounding and 'one physical pixel' or 'exact projection'))
    check(firstBattle and firstBattleMusic>=cue and firstBattleMusic-cue<maxMusicStep+.06,
      tag..' '..speed..'X callback reveals Pokemon on actual music cue '..cue..'s')
    check(firstUI and firstUI>=firstBattle,tag..' white battle windows are withheld during the initial approach')
    check(afterCamera and totalEyeDistance>1 and movingFrames>=10,
      tag..' camera moves through multiple intermediate poses on the audio clock')
    check(maxPathError<1e-4,tag..' every camera sample follows the continuous path at its actual audio phase')
    local handoffLandmarkPhysicalStep=handoffLandmarkStep*math.max(before:getWidth(),before:getHeight())
    check(handoffLandmarkPhysicalStep<=1,tag..' terrain landmarks stay within one physical pixel at the transition-to-battle handoff')
    check(firstMenu and sendoutShown,tag..' actual cry/message/sendout queue reaches the command menu')
    local arena=assert(Host.session).context.arena
    check(arena.map==ow.map and arena.origin.cellX==8 and arena.origin.cellY==12,
      tag..' transition and battle retain the original encounter map/cell')
    local enemyCry,playerCry,cues=nil,nil,0
    local enemyCries,playerCries=0,0
    for _,event in ipairs(audio)do
      if event.kind=='sfx' and event.name=='Ball_Toss' and event.frame==0 and event.source then cues=cues+1 end
      if event.kind=='cry' and event.species=='FIXMON_C' then enemyCry=event;enemyCries=enemyCries+1 end
      if event.kind=='cry' and event.species=='FIXMON_A' then playerCry=event;playerCries=playerCries+1 end
    end
    check(musicStable,tag..' battle theme stays current through the approach and handoff')
    check(cues==0,tag..' wild camera approach adds no ball-toss sound')
    local earlySfx,sendoutPoof=0,0
    for _,event in ipairs(audio)do
      if event.kind=='sfx' and event.frame<firstBattle then earlySfx=earlySfx+1 end
      if event.kind=='sfx' and event.name=='Ball_Poof' and event.source then sendoutPoof=sendoutPoof+1 end
    end
    check(earlySfx==0,tag..' seamless approach adds no substitute sound effect')
    check(sendoutPoof==1,tag..' original send-out sound still loads a real audio source')
    check(audio[1] and audio[1].kind=='theme' and audio[1].frame==0,
      tag..' real OW entry starts the battle theme before camera movement')
    check(enemyCries==1 and playerCries==1 and enemyCry and enemyCry.source and enemyCry.frame>=firstBattle and playerCry and playerCry.source
      and playerCry.frame>enemyCry.frame,tag..' enemy and player cries each play once using real audio sources in original order')
    check(enemyCry.music>=firstBattleMusic and enemyCry.music-cue<2*maxMusicStep+.06,
      tag..' appearance and enemy cry share actual playback phase at '..speed..'X')
    local starts=0;for _,event in ipairs(audio)do if event.kind=='theme' and event.newPlayback then starts=starts+1 end end
    check(starts==1,tag..' transition and battle entry share one BGM playback without restart')
    require('tests.jp_wild_encounter_motion_render')(V,battle,entryCast,
      ow.player.sprite:resolveImage(),tag,probe.render,check,write)
    probe.render()
    local r=Renderer:frameRects();local context=Host.session.context
    local metrics=P.metrics(r)
    local body=r.body or {x=r.vux,y=r.vuy,w=r.vuw,h=r.vuh}
    local centerError=math.abs(metrics.y+metrics.height*metrics.sy/2-(body.y+body.h/2))
    check(centerError<1,tag..' whole battle composition remains centred in the usable area excluding touch controls')
    local bounds=V.require('VoxelBattleCardProvider'):presentationBounds(metrics,'enemy')
    local enemyTop=metrics.y+(metrics.actor.enemy.y-bounds.height)*metrics.sy
    check(enemyTop>=r.vuy,tag..' full enemy silhouette remains below the viewport top')
    for _,side in ipairs({'player','enemy'})do
      local foot=arena[side];local px,py=context.services.project(foot[1],context.groundY,foot[2])
      local m=P.metrics(r);local a=m.actor[side]
      local scale=r.pw/context.services.renderSize.width
      check(math.abs(px*scale-(m.x+a.x*m.sx-r.vux)*r.dpiX)<.1
        and math.abs(py*scale-(m.y+a.y*m.sy-r.vuy)*r.dpiY)<.1,
        tag..' final '..side..' foot matches native animation coordinates')
    end
    if caseIndex==1 and os.getenv('JP_QA_ACTIONS_ONLY')~='1' then
      probe.measure('seamless-final-native-player-'..tag,battle,false,false,'player')
      local pinned=V.backSpritesSetting:get()
      for _,side in ipairs({'enemy','player'})do
        if side=='player' then V.backSpritesSetting:sync(false);V.require('VoxelBattleCardProvider'):update(Host.session.context)end
        probe.measure('seamless-final-grass-'..side..'-'..tag,battle,false,false,side)
        probe.building(battle,'seamless-'..tag,side)
        probe.building(battle,'seamless-'..tag,side,'flowers')
      end
      V.backSpritesSetting:sync(pinned);V.require('VoxelBattleCardProvider'):update(Host.session.context)
    end
    local composition={scale=metrics.scale,x=metrics.x,y=metrics.y,width=metrics.width,height=metrics.height,
      command=copy(metrics.command),actors={}}
    local pm=metrics.panels or metrics
    composition.panels={scale=pm.scale,x=pm.x,y=pm.y,width=pm.width,height=pm.height,
      command=copy(pm.command)}
    local Touch=require('src.core.TouchControls')
    local controls=Touch:visible() and Touch:layout() or {}
    local overlaps=0
    for _,rect in ipairs({pm.command,pm.enemyHUD,pm.playerHUD})do
      local x,y=pm.x+rect.x*pm.sx,pm.y+rect.y*pm.sy
      local w,h=rect.w*pm.sx,rect.h*pm.sy
      for _,name in ipairs({'dpad','a','b','start','select'})do
        local c=controls[name]
        if c then
          local radius=c.w/2
          local dx=c.cx-math.max(x,math.min(x+w,c.cx))
          local dy=c.cy-math.max(y,math.min(y+h,c.cy))
          if dx*dx+dy*dy<radius*radius then overlaps=overlaps+1 end
        end
      end
    end
    check(overlaps==0,tag..' white battle windows avoid actual visible touch-control circles')
    composition.touchOverlaps=overlaps
    for _,side in ipairs({'player','enemy'})do
      local b=V.require('VoxelBattleCardProvider'):presentationBounds(metrics,side)
      if not b then
        local _,_,pw,ph=battle:pictureAnchor(side)
        local scale=P.pictureScale(metrics,side,pw,ph,true)
        b={width=pw*scale,height=ph*scale,native=true}
      end
      local a=metrics.actor[side]
      composition.actors[side]={x=metrics.x+a.x*metrics.sx,y=metrics.y+a.y*metrics.sy,
        width=b.width*metrics.sx,height=b.height*metrics.sy}
    end
    local introAudio=copy(audio)
    local actions
    if caseIndex<=2 and os.getenv('JP_QA_SKIP_ACTIONS')~='1' then
      actions=require('tests.jp_battle_scene_actions_render')(Game,Renderer,V,battle,tag,probe.render,check,
        function()tick=tick+1;Game:step(1/60);Music.update(Game.data)end)
    end
    local result={size={w,h},factor=factor,speed=speed,cue=cue,firstBattleMusic=firstBattleMusic,
      enemyCryMusic=enemyCry.music,maxMusicStep=maxMusicStep,
      screenPos=Game.save.options.screenPos,frames=frames,audio=introAudio,
      composition=composition,actions=actions,
      beforeCastPixels=beforeCastCount,transitionCastPixels=firstCastCount,castOverlap=castOverlap,
      beforeLandmarks=beforeLandmarks,beforeWorldView=beforeWorldView,
      firstBattle=firstBattle,firstUI=firstUI,firstMenu=firstMenu,
      maxDark=maxDark,maxWhite=maxWhite,maskFrames=maskFrames,firstVPError=firstVP,firstLandmarkError=firstLandmarkError,
      firstLandmarkPhysicalError=firstLandmarkPhysicalError,movingFrames=movingFrames,
      maxPathError=maxPathError,handoffLandmarkStep=handoffLandmarkStep,handoffLandmarkPhysicalStep=handoffLandmarkPhysicalStep,
      lastCameraStep=lastVP,maxEyeStep=maxEyeStep,totalEyeDistance=totalEyeDistance,
      maxLandmarkStep=maxLandmarkStep,centerError=centerError,enemyTop=enemyTop,
      usable={body.x,body.y,body.w,body.h},viewport={r.vux,r.vuy,r.vuw,r.vuh}}
    write('seamless-trace-'..tag..'.json',assert(Json.encode(result)))
    result.frameCount=#frames;result.frames=nil
    report.cases[#report.cases+1]=result
    Host.finish('seamless-qa');Blend.cancel()
  end
  -- Trainer presentation uses the same physical music clock as wild entry.
  -- Compare 1x/4x logic and the new close-up versus the original slide.
  love.window.setMode(800,480,{vsync=0});Game.save.options.jpDialogScale=.75
  report.trainers={}
  local savedIntro=Game.save.options.jpBattleIntro
  for _,mode in ipairs({'original','focus'})do for _,speed in ipairs({1,4})do
    Game.save.options.jpBattleIntro=mode
    Stack.states={ow};Game.overworld=ow;Input:reset();Host.finish('trainer-qa');Blend.cancel();Music.stop()
    tick,audio,playback=0,{},nil;require('src.core.ScreenPosition').setMode('center');probe.render()
    if os.getenv('JP_QA_TRAINER_ONLY')=='1' then
      -- The full suite warms this route during its preceding wild battles.
      -- A focused retry still prepares through the real world update/draw.
      ow.camera:follow(ow.player.px,ow.player.py,Renderer:worldViewSize())
      for _=1,60 do require('src.render.Pipelines').update(1/60);probe.render() end
    end
    Game.data.trainers.OPP_FIX_YOUNGSTER.pic='fixture/intro-trainer.png'
    local trainer=Battle.newTrainer(Game,'OPP_FIX_YOUNGSTER',1)
    ow:pushBattle(trainer)
    local transition=Stack:top()
    local tag='trainer-'..mode..'-'..speed..'x'
    check(getmetatable(transition)==Transition and not transition.seamless,
      tag..' actual OW.pushBattle retains the original native wipe')
    check(transition.nativeMusicClock and transition.trainerFocus==(mode=='focus'),
      tag..' live renderer readiness selects the requested synchronized presentation')
    local cue=transition.revealTime
    local expectedEntry=transition.nativeTransferTime
    local firstBattleMusic,landedMusic,firstBlack,lastBlack
    local frames,wipeFrames,maxMusicStep,previousMusic={},0,0,0
    local began=love.timer.getTime()
    for frame=0,1800 do
      tick=frame
      if frame>0 then
        for _=1,speed do Game:step(1/60)end
        Music.update(Game.data)
      end
      local awaiting=trainer.jpEncounterAwaitDraw
      local pixels=probe.render()
      local at=musicPosition()
      maxMusicStep=math.max(maxMusicStep,at-previousMusic);previousMusic=at
      local inBattle=Stack:top()==trainer
      if inBattle and not firstBattleMusic then
        firstBattleMusic=at
        write(tag..'-first-visible.png',pixels:encode('png'):getString())
        if mode=='focus' then
          check(awaiting==true and trainer.jpEncounterAwaitDraw==nil,
            tag..' first real focus draw acknowledges entry before queued text/sounds')
          check(trainer.introSlide>0 and frameStats(pixels)<.9,
            tag..' native entrance interval presents the shared battle field instead of black')
          local arena=assert(Host.session.context.arena)
          check(arena.trainerIntro and not arena.focusIntro,
            tag..' both trainers use one shared camera during their crossing entrance')
        end
      end
      if inBattle and (trainer.introSlide or 0)==0 and not landedMusic then
        landedMusic=at;write(tag..'-landed.png',pixels:encode('png'):getString())
      end
      if Renderer.battleWipe then
        wipeFrames=wipeFrames+1
        if Renderer.battleWipe.prog>=1 then
          firstBlack=firstBlack or at;lastBlack=at
          if firstBlack==at then
            check(frameStats(pixels)>.99,tag..' original wipe still lands on full black')
            write(tag..'-black-hold.png',pixels:encode('png'):getString())
          end
        end
      end
      frames[#frames+1]={frame=frame,music=at,battle=inBattle,slide=trainer.introSlide,
        phase=trainer.phase,clock=transition.nativeMusicClock:position(),awaitDraw=awaiting or false}
      if landedMusic and at>cue+.35 then break end
      assert(love.timer.getTime()-began<12,tag..' actual Source cue timed out')
      love.timer.sleep(.004)
    end
    local tolerance=maxMusicStep+.06
    write(tag..'-clock-observed.json',assert(Json.encode({
      firstBattleMusic=firstBattleMusic,expectedEntry=expectedEntry,cue=cue,
      landedMusic=landedMusic,maxMusicStep=maxMusicStep,tolerance=tolerance,
      frames=frames})))
    check(firstBattleMusic and firstBattleMusic+1e-6>=expectedEntry
      and firstBattleMusic-expectedEntry<tolerance,tag..' first battle frame follows actual Source entry cue')
    check(landedMusic and landedMusic+1e-6>=cue and landedMusic-cue<tolerance,
      tag..' completed entrance follows same native music phase at any logic speed')
    check(wipeFrames>10 and firstBlack and lastBlack,
      tag..' preserves native progressive wipe and opaque hold')
    local starts=0
    for _,event in ipairs(audio)do
      if event.kind=='theme' and event.newPlayback then starts=starts+1 end
      check(not(event.kind=='sfx' and event.name=='Ball_Toss'),tag..' no extra ball throw cue during intro')
    end
    check(starts==1 and Music.current()=='QA_BATTLE',tag..' uses one uninterrupted battle theme Source')
    check(transition.nativeMusicClock.synchronized,tag..' timing uses sounding Source rather than fallback')
    local result={mode=mode,speed=speed,style=transition.style,cue=cue,expectedEntry=expectedEntry,
      firstBattleMusic=firstBattleMusic,landedMusic=landedMusic,firstBlack=firstBlack,lastBlack=lastBlack,
      maxMusicStep=maxMusicStep,wipeFrames=wipeFrames,sourceStarts=starts,frames=frames}
    write(tag..'-clock.json',assert(Json.encode(result)))
    result.frames=nil;report.trainers[#report.trainers+1]=result
  end end
  Game.save.options.jpBattleIntro=savedIntro
  Host.finish('seamless-qa');Blend.cancel()
  Sound.playCry,Music.playBattle,Sound.play=rawCry,rawBattleMusic,rawSound
  Renderer.setWorldOverride=rawOverride
  check(#Game.mods.errors==0,'actual seamless encounter MOD loader has no runtime errors')
  write('seamless-results.json',assert(Json.encode(report)))
end
