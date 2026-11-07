-- Actual GL shadow ownership, live settings, fallbacks and target caching.
-- Uses authored fixture maps/sprites only; no retail ROM or Android claim.
return function(Game,Renderer,V,state,check,write,render)
  local g=love.graphics
  local A,V3,SM=V.require('Atmosphere'),V.require('Voxel3D'),V.require('ShadowMap')
  local S,Q=V.require('Shadows'),V.require('Quality')
  local DN=V.require('DayNight')
  local Host,Blend=V.require('VoxelBattleStandalone'),V.require('BattleCameraBlend')
  local Pipelines=require('src.render.Pipelines')
  local report={renderer={g.getRendererInfo()},physicalAndroid=false,authoredAssets=true,cases={},checks={}}
  local strict=os.getenv('JP_QA_SHADOWS_OBSERVE')~='1'
  local function test(ok,msg)
    report.checks[#report.checks+1]={ok=not not ok,message=msg}
    if strict then check(ok,msg)else print((ok and 'PASS ' or 'DEFECT ')..msg)end
  end
  local function shot(name)
    local pic=render();write(name..'.png',pic:encode('png'):getString());return pic
  end
  local function diff(a,b)
    local n=0
    for y=0,a:getHeight()-1 do for x=0,a:getWidth()-1 do
      local ar,ag,ab=a:getPixel(x,y);local br,bg,bb=b:getPixel(x,y)
      if ar~=br or ag~=bg or ab~=bb then n=n+1 end
    end end
    return n
  end
  local oldTime=love.timer.getTime;local fixed=oldTime()
  love.timer.getTime=function()return fixed end
  love.window.setMode(800,480,{vsync=0})
  Game.save.options.jpDialogScale=.75;Game.save.options.jpDotMatrix=0
  Game.save.options.jpBattleIntro='original'
  require('src.render.DotMatrix').setLevel(0)
  Pipelines.setLevel('tiltshift',0)
  local OW=require('src.world.OverworldController')
  setmetatable(Game.data,{__index=require('src.core.Data')})
  Game.data.maps.FIX_ROUTE.outdoor=true
  Game.data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
  Game.data.field.flyWarps=Game.data.field.flyWarps or {}
  Game.data.field.waterTilesets=Game.data.field.waterTilesets or {}
  Game.data.field.forcedMovement=Game.data.field.forcedMovement or {tiles={}}
  Game.data.field.forcedMovement.tiles=Game.data.field.forcedMovement.tiles or {}
  local ow=setmetatable({},{__index=OW})
  ow:enter('FIX_ROUTE',8,12,'up',{via='boot',keepMusic=true})
  ow.paletteNameFor=state.paletteNameFor;ow.neighbors={}
  Game.stack.states={ow};Game.overworld=ow
  Game.save.options.pipelines={voxel=2,tiltshift=0};Pipelines.applyOptions(Game.save.options)
  DN.setting:sync('day');S.setting:sync('high')
  Game.save.options.jpAtmosphere='soft'
  for _=1,60 do Pipelines.update(1/60);ow.camera:follow(ow.player.px,ow.player.py,Game.renderer:worldViewSize());render()end
  local sprite=ow.player:pose();local playerTex=sprite:resolveImage()
  local baseBegin,baseDraw,baseShadow=SM.begin,SM.draw,V3.shadowMatrix
  local casts,actors,drops=0,0,0
  SM.begin=function(...)local result=baseBegin(...);if result then casts=casts+1 end;return result end
  SM.draw=function(mesh,texture,...)if mesh and texture==playerTex then actors=actors+1 end;return baseDraw(mesh,texture,...)end
  V3.shadowMatrix=function(...)drops=drops+1;return baseShadow(...)end
  local function counters()casts,actors,drops=0,0,0;return A.stats.contactDraws end
  SM.discard();local contacts=counters()
  local on=shot('field-soft-shadows-on')
  test(SM.active(),'actual field shadow map is active')
  test(actors>0,'player remains a real sun-map caster')
  test(drops==0,'active map never also draws projected fallback')
  test(A.stats.contactDraws==contacts,'HD2D does not add a second field contact ellipse')
  report.cases.field={casts=casts,actorCasts=actors,fallbacks=drops,contacts=A.stats.contactDraws-contacts,resolution=SM.res}
  local originalCanvas=g.newCanvas;local allocations=0
  g.newCanvas=function(...)allocations=allocations+1;return originalCanvas(...)end
  counters();for _=1,6 do render()end
  g.newCanvas=originalCanvas
  test(allocations==0,'six stable real field frames allocate no replacement shadow targets')
  test(casts==0,'six stable field frames reuse the ready sun map')
  report.steadyField={allocations=allocations,casts=casts}
  for _,style in ipairs({'soft','off'})do
    Game.save.options.jpAtmosphere=style;S.setting:sync('off')
    contacts=counters();local off=shot('field-'..style..'-shadows-off')
    test(Q.shadowsOff(),'fallback selector agrees with canonical shadow OFF in '..style)
    test(not SM.active() and casts==0 and actors==0 and drops==0 and A.stats.contactDraws==contacts,
      'shadow OFF draws no field sun map, fallback or contact in '..style)
    local alpha=V3.SHADOW_ALPHA;V3.SHADOW_ALPHA=0
    local forcedOff=render();V3.SHADOW_ALPHA=alpha
    test(diff(off,forcedOff)==0,'shadow OFF pixels equal a forced zero-opacity reference in '..style)
    report.cases['off-'..style]={casts=casts,actors=actors,drops=drops,contacts=A.stats.contactDraws-contacts,forcedOffDifference=diff(off,forcedOff)}
  end
  S.setting:sync('high');Game.save.options.jpAtmosphere='soft';SM.discard()
  local baseAvailable=SM.available;SM.available=function()return false end
  contacts=counters();local fallback=shot('field-map-unavailable-single-fallback')
  local posedCount=#ow.entities+#(ow.ghosts or {})
  test(drops==posedCount and drops>0,'unavailable sun map draws exactly one projected fallback per posed entity')
  test(A.stats.contactDraws==contacts,'unavailable map never adds a second atmosphere ellipse')
  report.cases.fallback={drops=drops,entities=posedCount,contacts=A.stats.contactDraws-contacts}
  S.setting:sync('off');contacts=counters();render()
  test(drops==0 and A.stats.contactDraws==contacts,'shadow OFF also suppresses forced-driver-failure fallback')
  SM.available=baseAvailable;S.setting:sync('high');SM.discard();render()
  Host.finish('shadow-test-battle');Blend.cancel()
  local battle=require('src.battle.BattleState').newWild(Game,'FIXMON_C',10)
  Game.stack:push(battle)
  local arena=assert(Host.session).context.arena
  arena.presentationTime=10;arena.entryDuration=nil;arena.entryPose=nil;V.require('BattleIntroFocus').finish(arena)
  battle.phase,battle.current,battle.queue='menu',nil,{}
  battle.introSlide,battle.introBalls,battle.showPlayerBack=0,false,false
  battle.enemyHudPending,battle.enemySendingOut=false,false
  render();SM.discard();contacts=counters();local battleOn=shot('battle-single-contact')
  test(casts==1 and SM.active(),'battle prepares a terrain shadow map once')
  test(actors==0,'battle map excludes the old overworld player silhouette')
  test(A.stats.contactDraws>contacts,'battle combatants retain their single ground contact')
  report.cases.battle={casts=casts,oldActorCasts=actors,contacts=A.stats.contactDraws-contacts}
  local ui=Renderer.battlePresentationCanvas:newImageData():getString()
  counters();allocations=0;g.newCanvas=function(...)allocations=allocations+1;return originalCanvas(...)end
  for _=1,6 do render()end;g.newCanvas=originalCanvas
  test(casts==0 and allocations==0,'six stable battle frames reuse terrain shadow target and cached map')
  report.steadyBattle={allocations=allocations,casts=casts}
  S.setting:sync('off');contacts=counters();shot('battle-shadows-off')
  test(not SM.active() and casts==0 and A.stats.contactDraws==contacts,'same shadow OFF disables battle terrain and contact shadows')
  test(Renderer.battlePresentationCanvas:newImageData():getString()==ui,'shadow toggle leaves white HUD pixel-exact')
  local opts=Game.save.options
  local oldColor,oldBlur,oldStyle=opts.colors,opts.pipelines.tiltshift,opts.jpAtmosphere
  for _,choice in ipairs({'high','off','high'})do
    S.setting:sync(choice)
    test(Q.shadowsOff()==S.off(),'legacy fallback accessor follows live '..choice)
    test(opts.colors==oldColor and opts.pipelines.tiltshift==oldBlur and opts.jpAtmosphere==oldStyle,
      'shadow toggle never overwrites palette, blur or atmosphere '..choice)
  end
  test(not A.solidGround({isWaterCell=function()return true end},8,8),'water still receives no battle contact')
  test(not A.solidGround(nil,8,8),'unknown ground still receives no battle contact')
  local Scene=V.require('VoxelBattleScene')
  local baseRender=Scene.render
  Scene.render=function()return nil end
  local okay=pcall(render)
  Scene.render=baseRender
  test(okay,'temporary nil battle render keeps its valid fallback without error')
  local baseReady=Scene.ready
  Scene.ready=function()return false end
  SM.discard();counters();render();Scene.ready=baseReady
  test(actors>0,'unavailable battle scene restores normal underlying field casters')
  Host.finish('shadow-test-handback');Blend.cancel()
  Game.stack.states={ow};Game.overworld=ow
  SM.discard();counters();shot('field-after-battle')
  test(actors>0 and SM.active(),'battle end restores the normal player and NPC sun shadows')
  counters();render();test(casts==0,'field cache remains stable after battle handback')
  test(#Game.mods.errors==0,'real world and battle shadow paths report no MOD errors')
  SM.begin,SM.draw,V3.shadowMatrix=baseBegin,baseDraw,baseShadow
  love.timer.getTime=oldTime;Host.finish('shadow-test-end');Blend.cancel()
  write('results.json',assert(require('src.link.Json').encode(report)))
end
