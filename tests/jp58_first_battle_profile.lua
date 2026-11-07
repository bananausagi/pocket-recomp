-- jp.58: first-battle cold-start profile. Actual OW.pushBattle -> transition
-- -> BattleState.enter -> first frames, repeated with the identical call path.
-- Wall time per frame (update/draw/GPU sync) plus inclusive time of suspect
-- functions. Authored fixture art/PCM only; no ROM, no device claim.
-- JP_QA_FIRST_BATTLE58_ORDER=wild,wild (default) or e.g. trainer,wild,trainer.
return function(Game,Renderer,V,state,check,write)
  local g,fs=love.graphics,love.filesystem
  local now=love.timer.getTime
  local OW=require('src.world.OverworldController')
  local Battle=require('src.battle.BattleState')
  local Transition=require('src.render.BattleTransition')
  local Sound=require('src.core.Sound')
  local Music=require('src.core.Music')
  local Json=require('src.link.Json')
  local Pipelines=require('src.render.Pipelines')
  local Viewport=require('src.render.GameViewport')
  local Host=V.require('VoxelBattleStandalone')
  local Blend=V.require('BattleCameraBlend')
  local Mesher=V.require('ChunkMesher')
  local Stack,Input=Game.stack,Game.input

  -- Authored fixtures (same as the seamless encounter QA).
  local function tone(path,hz,seconds)
    local pack=love.data.pack;local samples={}
    for i=0,math.floor((seconds or .1)*8000)-1 do
      samples[#samples+1]=pack('string','<i2',math.floor(math.sin(i*hz*math.pi/4000)*2500))
    end
    local pcm=table.concat(samples)
    local wav='RIFF'..pack('string','<I4',36+#pcm)..'WAVEfmt '
      ..pack('string','<I4I2I2I4I4I2I2',16,1,1,8000,16000,2,16)..'data'..pack('string','<I4',#pcm)..pcm
    assert(fs.write(path,wav))
  end
  tone('fixture/p58-cry.wav',660);tone('fixture/p58-theme.wav',440,30)
  Game.data.audio=Game.data.audio or {}
  Game.data.audio.cries={FIXMON_A={file='fixture/p58-cry.wav'},FIXMON_C={file='fixture/p58-cry.wav'}}
  Game.data.audio.songs=Game.data.audio.songs or {}
  Game.data.audio.songs.QA_BATTLE={file='fixture/p58-theme.wav'}
  Game.data.audio.battle={wild='QA_BATTLE',trainer='QA_BATTLE'}
  Game.data.audio.sfx=Game.data.audio.sfx or {}
  Game.data.audio.sfx.Ball_Toss={file='fixture/p58-cry.wav'}
  Game.data.audio.sfx.Ball_Poof={file='fixture/p58-cry.wav'}
  Sound.invalidate()
  setmetatable(Game.data,{__index=require('src.core.Data')})
  local function sheet(path,w,h,draw)
    local c=g.newCanvas(w,h,{dpiscale=1})
    g.push('all');g.setCanvas(c);g.clear(0,0,0,0);draw();g.pop()
    fs.write(path,c:newImageData():encode('png'));c:release()
  end
  sheet('fixture/p58-walker.png',16,96,function()
    for i=0,5 do g.setColor(1,0,1,1);g.rectangle('fill',4,i*16+2,8,10)end
  end)
  sheet('fixture/p58-trainer.png',56,56,function()
    g.setColor(.2,.1,.5,1);g.rectangle('fill',10,8,36,48)
  end)
  Game.data.sprites.SPRITE_FIX_PLAYER.image='fixture/p58-walker.png'
  Game.data.sprites.SPRITE_FIX_PLAYER.trueColor=true
  Game.data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
  Game.data.field.playerPics={back='fixture/p58-trainer.png'}
  Game.data.field.flyWarps=Game.data.field.flyWarps or {}
  Game.data.field.waterTilesets=Game.data.field.waterTilesets or {}
  Game.data.field.forcedMovement=Game.data.field.forcedMovement or {}
  Game.data.field.forcedMovement.tiles=Game.data.field.forcedMovement.tiles or {}
  Game.data.text._WildMonAppearedText='あ！ やせいの\n{ENEMY}が とびだしてきた！{PROMPT}'
  Game.data.pokemon.FIXMON_C.name='テストモン'
  Game.data.trainers.OPP_FIX_YOUNGSTER.pic='fixture/p58-trainer.png'
  Game.save.options.textSpeed=1;Game.save.options.jpDialogScale=.75
  Game.save.options.jpBattleSpacing='wide'
  Game.save.options.pipelines={voxel=2}
  Pipelines.applyOptions(Game.save.options)
  local w,h=tonumber(os.getenv('JP_QA_P58_W')) or 1080,tonumber(os.getenv('JP_QA_P58_H')) or 1920
  love.window.setMode(w,h,{vsync=0})

  -- Instrumentation: inclusive wall time of each suspect, per frame bucket.
  local bucket,restores=nil,{}
  local slowLog,slowAt={},'setup'
  local traceLabel=os.getenv('JP_QA_P58_TRACE')
  local function pack(...)return {n=select('#',...),...}end
  local function wrap(tbl,key,label)
    local f=tbl and tbl[key]
    if type(f)~='function' then return end
    local traced=traceLabel and label:find(traceLabel)
    tbl[key]=function(...)
      local state
      if traced then
        -- GL state that selects a driver pipeline variant for this call.
        local c=g.getCanvas();local tex=select(2,...)
        local function desc(o)
          if type(o)=='table' then o=o[1] or o end
          if type(o)~='userdata' or not o.getDimensions then return tostring(o)end
          local ok,fmt=pcall(o.getFormat,o);local mn,mg=o:getFilter()
          return ('%s %dx%d %s %s/%s'):format(o:type(),o:getWidth(),o:getHeight(),ok and fmt or '?',mn,mg)
        end
        local b1,b2=g.getBlendMode();local d1,d2=g.getDepthMode()
        state=('target=%s tex=%s shader=%s blend=%s/%s depth=%s/%s'):format(
          type(c)=='table' and desc(c[1])..(c.depthstencil and ('+'..desc(c.depthstencil))or'') or desc(c),
          desc(tex),tostring(g.getShader()):sub(-8),b1,b2,tostring(d1),tostring(d2))
      end
      local t0=now()
      local out=pack(f(...))
      local dt=now()-t0
      if bucket then
        local e=bucket[label];if not e then e={n=0,t=0};bucket[label]=e end
        e.n=e.n+1;e.t=e.t+dt
        if dt>.008 and slowLog then
          slowLog[#slowLog+1]={at=slowAt,label=label,ms=dt*1000,
            where=(label:find('^gl%.') or traced) and ((state or '')..' '..debug.traceback('',2):sub(1,1500)) or nil}
        end
      end
      return unpack(out,1,out.n)
    end
    restores[#restores+1]=function()tbl[key]=f end
  end
  local GL={'newShader','newCanvas','newImage','newMesh','newFont','newArrayImage','newQuad'}
  for _,k in ipairs(GL)do wrap(g,k,'gl.'..k)end
  wrap(love.image,'newImageData','image.newImageData')
  wrap(love.audio,'newSource','audio.newSource')
  wrap(love.sound,'newSoundData','sound.newSoundData')
  wrap(V,'require','V.require')
  local function mod(name,keys)
    local m=V.require(name)
    for _,k in ipairs(keys)do wrap(m,k,name..'.'..k)end
  end
  mod('VoxelBattleStandalone',{'prepare','begin','draw','update','finish','install'})
  mod('VoxelBattleArenaProvider',{'arena','begin','render','update','canTransition'})
  mod('VoxelBattleCardProvider',{'install','begin','prepareFrame','terrainCards','drawWorld'})
  mod('VoxelBattleScene',{'render','ready'})
  mod('BattleArena',{'find'})
  mod('VoxelScene',{'castBattleShadows','render','prefetch','captureEncounterCast'})
  mod('Voxel3D',{'beginScene','endScene','shader','unlitShader'})
  mod('TiltShift',{'battleBackground','apply'})
  mod('SceneGlow',{'apply'})
  mod('AntiAlias',{'resolve'})
  mod('Atmosphere',{'drawContact'})
  mod('BattlePics',{'filled'})
  mod('BattleIntroFocus',{'begin','update','pose'})
  mod('SceneEffects',{'battle','draw','bind'})
  mod('BattleActionCamera',{'update','pose'})
  mod('BattleCam',{'rig','rigFor'})
  mod('ShadowMap',{'begin','finish','render'})
  mod('ChunkMesher',{'pump','request'})
  mod('TerrainAtlas',{'forMap','prepare'})
  mod('GlassMask',{'texture'})
  if pcall(V.require,'VoxelBattleWarmup')then mod('VoxelBattleWarmup',{'update','compileNext'})end
  wrap(Battle,'newWild','BattleState.newWild');wrap(Battle,'newTrainer','BattleState.newTrainer')
  wrap(Battle,'enter','BattleState.enter');wrap(Battle,'update','BattleState.update')
  wrap(Battle,'picImage','BattleState.picImage')
  wrap(Transition,'new','BattleTransition.new')
  wrap(OW,'pushBattle','OW.pushBattle')
  wrap(Music,'playBattle','Music.playBattle');wrap(Music,'update','Music.update')
  wrap(Sound,'playCry','Sound.playCry');wrap(Sound,'play','Sound.play')
  wrap(Renderer,'endFrame','Renderer.endFrame')
  for _,name in ipairs({'src.battle.BattlePresentation','src.battle.JapaneseBattlePanels'})do
    local ok,M=pcall(require,name)
    if ok and type(M)=='table' then
      for _,k in ipairs({'draw','drawPanels','drawCommand','compose','frame'})do wrap(M,k,name:match('[^.]+$')..'.'..k)end
    end
  end
  -- JP_QA_P58_DEEP=1: every function of the already-used render modules
  -- (never loads a module the game would not load itself).
  if os.getenv('JP_QA_P58_DEEP')=='1' then
    local wrapped={}
    local function deep(label,M)
      if type(M)~='table' or wrapped[M] then return end
      wrapped[M]=true
      local keys={}
      for k,v in pairs(M)do if type(v)=='function' and type(k)=='string' then keys[#keys+1]=k end end
      for _,k in ipairs(keys)do
        if not (label=='Voxel3D' and (k=='project' or k=='pushQuad')) then wrap(M,k,label..':'..k)end
      end
    end
    for _,name in ipairs({'Voxel3D','VoxelScene','Sky','Water','ShadowMap','AntiAlias','TiltShift','SceneGlow',
        'SceneEffects','Atmosphere','FieldAtmosphere','ChunkMesher','TerrainAtlas','GlassMask','BattlePics',
        'BattleBillboard','DayNight','Structures','SceneryTransition','VoxelLoadingVeil','PixelCanvas',
        'EffectParticles','WeatherParticles','SpriteBillboards','TreeInstances','VoxelCompanionHost'})do
      local ok,M=pcall(V.require,name)
      if ok then deep(name,M)end
    end
    deep('Renderer',Renderer)
    for _,name in ipairs({'src.render.PaletteFX','src.render.Font','src.render.TextBox','src.render.DotMatrix',
        'src.render.GameViewport','src.battle.BattlePresentation','src.battle.JapaneseBattlePanels'})do
      local ok,M=pcall(require,name)
      if ok then deep(name:match('[^.]+$'),M)end
    end
  end

  local function sync()
    -- glReadPixels of one texel: waits for this frame's queued GL work.
    local t=Viewport.target()
    if t then pcall(t.newImageData,t,1,1,0,0,1,1) end
  end
  -- The real app draws the touch cross on its title/continue pages before
  -- any field frame; do the same so its lazy artwork is not billed here.
  do
    local Touch=require('src.core.TouchControls')
    g.push('all');g.setCanvas(Viewport.target());Game.overworld=nil
    pcall(Touch.draw,Touch);g.pop()
  end
  -- jp.62: JP_QA_P62_WATER=1 gives the fixture tileset the GB water
  -- animation, so the terrain atlas prebuilds animation states like Kanto's.
  if os.getenv('JP_QA_P62_WATER')=='1' then
    for _,ts in pairs(Game.data.tilesets)do ts.animation='TILEANIM_WATER' end
  end
  local ow=setmetatable({},{__index=OW})
  ow:enter('FIX_ROUTE',8,12,'up',{via='boot',keepMusic=true})
  ow.paletteNameFor=state.paletteNameFor;ow.neighbors={}
  Game.overworld=ow;Stack.states={ow}
  ow.camera:follow(ow.player.px,ow.player.py,Renderer:worldViewSize())
  -- Game:update's per-frame work without its real-time FixedStep: one logic
  -- tick, the render pipelines (field streaming/warm-up) and audio.
  local function tick()
    Game:step(1/60);Pipelines.update(1/60);Music.update(Game.data)
  end
  local function fieldFrame()
    tick();Game:draw();g.setCanvas();sync()
  end
  local warm=0
  -- jp.62: the boot-to-field phase too -- per frame wall time and suspects,
  -- the first real voxel picture and when streaming settles.
  local bootTotals,bootFrames,firstPicture,bootStart={}, {},nil,now()
  local Warmup=select(2,pcall(V.require,'VoxelBattleWarmup'))
  local shownBefore=type(Warmup)=='table' and Warmup.fieldShown
  if shownBefore then
    Warmup.fieldShown=function(...)
      if not firstPicture then firstPicture={frame=warm+1,ms=(now()-bootStart)*1000}end
      return shownBefore(...)
    end
  end
  for i=1,900 do
    bucket={};slowAt='boot'..i
    local t0=now();fieldFrame();warm=i
    local dt=now()-t0
    bootFrames[#bootFrames+1]=dt*1000
    for k,e in pairs(bucket)do
      local a=bootTotals[k] or {n=0,t=0,max=0};bootTotals[k]=a
      a.n,a.t,a.max=a.n+e.n,a.t+e.t,math.max(a.max,e.t)
    end
    if i>=120 and Mesher.pending()==0 and Mesher.grass(ow.map) then break end
  end
  bucket=nil
  -- jp.62: JP_QA_P62_SPLIT=1 times one map's terrain rebuild synchronously:
  -- the shape analysis (Structures) versus emitting the vertices.
  if os.getenv('JP_QA_P62_SPLIT')=='1' then
    local S=V.require('Structures')
    for _,id in ipairs({'FIX_ROUTE','FIX_TOWN'})do
      local map=require('src.world.MapLoader').load(Game.data,id)
      S.invalidate(id)
      local t0=now();S.forMap(map);local t1=now()
      V.require('ChunkMesher').geometry(map,false)
      local t2=now()
      print(('P62 split %s structures=%.0fms geometry=%.0fms'):format(id,(t1-t0)*1000,(t2-t1)*1000))
    end
  end
  do
    local settled=(now()-bootStart)*1000
    local worst=0;for _,v in ipairs(bootFrames)do worst=math.max(worst,v)end
    print(('P62 boot jit=%s frames=%d settled=%.0fms firstPicture=%s worstFrame=%.0fms'):format(
      tostring(jit and jit.status and jit.status()),warm,settled,
      firstPicture and ('f'..firstPicture.frame..'@'..math.floor(firstPicture.ms)..'ms') or 'none',worst))
    local rows={}
    for k,a in pairs(bootTotals)do rows[#rows+1]={k=k,a=a}end
    table.sort(rows,function(x,y)return x.a.t>y.a.t end)
    for i=1,math.min(18,#rows)do
      local r=rows[i];print(('P62   %-44s %8.1fms n=%-5d max=%.1fms'):format(r.k,r.a.t*1000,r.a.n,r.a.max*1000))
    end
    local slow={}
    for i,v in ipairs(bootFrames)do if v>50 then slow[#slow+1]=('f%d:%.0f'):format(i,v)end end
    print('P62   frames over 50ms: '..table.concat(slow,' '))
  end
  check(Mesher.pending()==0,'fixture field streaming settles before the first battle ('..warm..' frames)')

  local order={}
  for kind in (os.getenv('JP_QA_FIRST_BATTLE58_ORDER') or 'wild,wild'):gmatch('[^,]+')do order[#order+1]=kind end
  local report={size={w,h},android=os.getenv('JP_QA_EMULATE_ANDROID')=='1',
    renderer={g.getRendererInfo()},warmFrames=warm,battles={}}
  local maxFrames=tonumber(os.getenv('JP_QA_P58_FRAMES')) or 40
  for index,kind in ipairs(order)do
    -- Idle field frames between battles (the same for every battle).
    Stack.states={ow};Game.overworld=ow;Input:reset()
    local idle={}
    local idleWorst,idleWorstLabels=0,nil
    for i=1,120 do
      bucket={};slowAt='b'..index..':idle'..i
      local t0=now();fieldFrame();idle[#idle+1]=now()-t0
      if idle[#idle]>idleWorst then idleWorst,idleWorstLabels=idle[#idle],bucket end
    end
    table.sort(idle)
    local okWarm,warmStatus=pcall(function()return V.require('VoxelBattleWarmup').status()end)
    Game.save.party[1].hp=Game.save.party[1].stats.hp
    bucket={};slowAt='b'..index..':start'
    local t0=now()
    local battle=kind=='trainer' and Battle.newTrainer(Game,'OPP_FIX_YOUNGSTER',1)
      or Battle.newWild(Game,'FIXMON_C',10)
    ow:pushBattle(battle)
    local startBucket,startTime=bucket,now()-t0
    local transition=Stack:top()
    local seamless=transition and transition.seamless and true or false
    local frames,firstBattle,firstMenu={},nil,nil
    local began=now()
    for frame=1,3000 do
      bucket={};slowAt='b'..index..':f'..frame
      local a=now()
      if firstBattle and frame%16==0 then Input:sourcePress('a','p58')
      elseif frame%16==1 then Input:sourceRelease('a','p58')end
      tick()
      local b=now()
      Game:draw();g.setCanvas()
      local c=now()
      sync()
      local d=now()
      local top=Stack:top()
      local inBattle=top==battle
      if inBattle and not firstBattle then firstBattle=frame end
      if inBattle and battle.phase=='menu' and not firstMenu then firstMenu=frame end
      local row={frame=frame,total=d-a,update=b-a,draw=c-b,sync=d-c,
        state=inBattle and 'battle' or (top and top.isOverworld and 'field') or 'transition',
        labels=bucket}
      frames[#frames+1]=row
      if firstMenu and frame>=firstMenu+10 then break end
      if now()-began>60 then break end
    end
    Input:sourceRelease('a','p58')
    local sum30,maxFrame,maxAt=0,0,0
    for i,row in ipairs(frames)do
      if i<=30 then sum30=sum30+row.total end
      if row.total>maxFrame then maxFrame,maxAt=row.total,row.frame end
    end
    local totals={}
    local function add(labels)
      for k,e in pairs(labels)do
        local t=totals[k] or {n=0,t=0};t.n=t.n+e.n;t.t=t.t+e.t;totals[k]=t
      end
    end
    add(startBucket);for _,row in ipairs(frames)do add(row.labels)end
    local result={index=index,kind=kind,seamless=seamless,start=startTime,startLabels=startBucket,
      idleMedian=idle[math.floor(#idle/2)+1],idleMax=idle[#idle],
      firstBattle=firstBattle,firstMenu=firstMenu,sum30=sum30,maxFrame=maxFrame,maxAt=maxAt,
      frameCount=#frames,totals=totals,idleWorstLabels=idleWorstLabels,warmup=okWarm and warmStatus or 'absent',frames={}}
    for i,row in ipairs(frames)do
      if i<=maxFrames or (firstBattle and math.abs(row.frame-firstBattle)<=2) or row.frame==maxAt then
        result.frames[#result.frames+1]=row
      end
    end
    report.battles[#report.battles+1]=result
    check(firstBattle and firstMenu,('battle %d (%s) reaches actual command menu'):format(index,kind))
    Stack.states={ow};Game.overworld=ow
    Host.finish('battle.ended');Blend.cancel();Music.stop()
    bucket=nil
  end
  for i=#restores,1,-1 do restores[i]()end
  report.slow=slowLog
  for _,e in ipairs(slowLog)do
    if e.where or e.ms>40 then print(('P58 SLOW %-14s %-40s %7.1fms %s'):format(e.at,e.label,e.ms,(e.where or ''):gsub('\n%s*',' | ')))end
  end
  write('first-battle-profile.json',assert(Json.encode(report)))
  -- Compact console summary (milliseconds).
  local function ms(v)return string.format('%.1f',(v or 0)*1000)end
  for _,b in ipairs(report.battles)do
    print(('P58 battle#%d %s seamless=%s start=%sms first30=%sms max=%sms@%d handoff=%s menu=%s idleMed=%sms idleMax=%sms')
      :format(b.index,b.kind,tostring(b.seamless),ms(b.start),ms(b.sum30),ms(b.maxFrame),b.maxAt,
        tostring(b.firstBattle),tostring(b.firstMenu),ms(b.idleMedian),ms(b.idleMax)))
    local rows={}
    for k,e in pairs(b.totals)do rows[#rows+1]={k,e}end
    table.sort(rows,function(x,y)return x[2].t>y[2].t end)
    for i=1,math.min(28,#rows)do
      print(('P58   %-44s %8sms  n=%d'):format(rows[i][1],ms(rows[i][2].t),rows[i][2].n))
    end
    local line={}
    for i=1,math.min(maxFrames,#b.frames)do
      local f=b.frames[i];line[#line+1]=f.state:sub(1,1)..ms(f.total)
    end
    print('P58   frames: '..table.concat(line,' '))
    print('P58   warmup before battle: '..(type(b.warmup)=='table' and Json.encode(b.warmup) or tostring(b.warmup)))
    local il={}
    for k,e in pairs(b.idleWorstLabels or {})do il[#il+1]={k,e}end
    table.sort(il,function(x,y)return x[2].t>y[2].t end)
    for i=1,math.min(6,#il)do print(('P58   idle-worst %-38s %8sms'):format(il[i][1],ms(il[i][2].t)))end
    local sl={}
    for k,e in pairs(b.startLabels)do sl[#sl+1]={k,e}end
    table.sort(sl,function(x,y)return x[2].t>y[2].t end)
    for i=1,math.min(16,#sl)do
      print(('P58   start %-38s %8sms  n=%d'):format(sl[i][1],ms(sl[i][2].t),sl[i][2].n))
    end
  end
  check(#Game.mods.errors==0,'first-battle profile MOD loader has no runtime errors')
end
