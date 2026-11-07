-- Actual battle enter/queue/sendout with real loaded MODs and extruded grass.
-- The handwritten artwork is test-only; no retail sprites or ROM are used.
return function(Game,Renderer,V,state,check,write)
  require('tests.jp_battle_camera_override')(V)
  local g,fs=love.graphics,love.filesystem
  local Battle=require('src.battle.BattleState')
  local P=require('src.battle.BattlePresentation')
  local Viewport=require('src.render.GameViewport')
  local Input=Game.input
  local Stack=Game.stack
  local Host=V.require('VoxelBattleStandalone')
  local Cards=V.require('VoxelBattleCardProvider')
  local Scene=V.require('VoxelBattleScene')
  local Mesher=V.require('ChunkMesher')
  local V3=V.require('Voxel3D')
  local Blend=V.require('BattleCameraBlend')
  local rawGrass=Mesher.grass
  local rawFlowers=Mesher.flowers
  local rawOcclusion=V3.battleOcclusion
  local noGrass=false
  local foregroundWall,wallTexture,disableCutaway,foregroundKind
  Mesher.grass=function(map)return not noGrass and rawGrass(map) or nil end
  Mesher.flowers=function(map)
    local shader=g.getShader()
    if foregroundKind=='flowers' and shader and shader:hasUniform('battleRectA') then
      -- Keep the world's cached shadow map identical in actual/reference.
      -- This box belongs only to the real battle decoration colour pass.
      return not noGrass and foregroundWall or nil
    end
    return rawFlowers(map)
  end
  V3.battleOcclusion=function(spots,stage)
    if disableCutaway then rawOcclusion()else rawOcclusion(spots,stage)end
    -- A test-authored solid building facade participates in the actual
    -- terrain depth pass. No actor draw or production shader is replaced.
    if spots and foregroundWall and foregroundKind~='flowers' and not noGrass then V3.draw(foregroundWall,wallTexture)end
  end
  local trainer=g.newCanvas(28,28,{dpiscale=1})
  g.setCanvas(trainer);g.clear(0,0,0,0)
  g.setColor(.2,.1,.5,1);g.rectangle('fill',5,4,18,24)
  g.setColor(.9,.5,.2,1);g.rectangle('fill',9,2,15,8)
  g.setCanvas();fs.write('fixture/intro-trainer.png',trainer:newImageData():encode('png'))
  Game.data.field.playerPics={back='fixture/intro-trainer.png'}
  Game.data.text._WildMonAppearedText='あ！ やせいの\n{ENEMY}が とびだしてきた！{PROMPT}'
  Game.data.pokemon.FIXMON_C.name='テストモン'
  Game.save.options.textSpeed=1;Game.save.options.jpDialogScale=1
  Game.save.options.jpBattleSpacing='wide'
  local windowQA=os.getenv('JP_QA_BATTLE_WINDOWS')=='1'
  if windowQA then
    Game.save.party[1].moves={{id='FIX_TACKLE',pp=20},{id='FIX_EMBERISH',pp=0},
      {id='FIX_SCRATCH',pp=20},{id='FIX_CUT',pp=10,ppUps=2}}
  end
  state.map=require('src.world.MapLoader').load(Game.data,'FIX_ROUTE')
  state.neighbors={};state.player={cellX=8,cellY=12,facing='up'}
  state.isOpaque,state.isOverworld=true,true
  local worldArena={map=state.map,mid={136,200},player={136,200},enemy={136,152},playerCell={8,12},cam='wide'}
  -- Ascendant's phone path publishes its current BODY before grass and
  -- the scenery transaction finish. Warm the actual world update/render
  -- lanes; keeping the raw grass assertion below proves the real geometry.
  if os.getenv('JP_QA_EMULATE_ANDROID')=='1' and V.mod.id=='VOXEL_ASCENDANT' then
    local World=V.require('VoxelScene')
    local Gate=V.require('MobileSceneryGate')
    local voxel=V.require('VoxelState')
    state.player.px,state.player.py=128,192
    state.camera=state.camera or {x=16,y=120}
    state.ghosts,state.entities={},{}
    Game.overworld=state
    local complete,frames=false,0
    g.push('all');g.origin()
    for frame=1,300 do
      frames=frame
      voxel.update(1/60,3)
      World.prefetch(state)
      World.stageMobileScenery(state)
      Mesher.pump(true,false,not voxel.ready)
      local canvas=World.render(state,480,320,240,160,function()return nil end)
      local receipt=Gate.status(state.map)
      complete=canvas~=nil and receipt and receipt.active and not receipt.failed
        and Mesher.auxReady(state.map) and rawGrass(state.map)~=nil
      if complete then break end
    end
    g.setCanvas();g.pop()
    check(complete,'Android actual world, scenery and grass finish bounded warmup')
    write('android-battle-warmup.json',require('src.link.Json').encode({
      frames=frames,complete=complete,scenery=Gate.status(state.map),
      auxReady=Mesher.auxReady(state.map),romUsed=false}))
  end
  -- jp25 publishes drawable terrain before its asynchronous decoration
  -- continuation. This fixture needs both, since it measures real grass.
  for _=1,150 do
    if Scene.ready(state,worldArena) and rawGrass(state.map) then break end
    Mesher.pump(true)
  end
  local grass=assert(rawGrass(state.map),'fixture needs actual grass mesh')
  local maxY,grassVertices=0,0
  local function inspectGrass(mesh,base,copies)
    if not mesh then return end
    grassVertices=grassVertices+mesh:getVertexCount()*(copies or 1)
    for i=1,mesh:getVertexCount()do
      local _,y=mesh:getVertex(i);maxY=math.max(maxY,y+(base or 0))
    end
  end
  if grass.__voxelMeshBundle then
    inspectGrass(grass.base)
    for _,group in ipairs(grass.instances or {})do
      local base=0
      for i=1,group.count do local _,y=group.source:getVertex(i);base=math.max(base,y)end
      inspectGrass(group.mesh,base,group.count)
    end
  else inspectGrass(grass)end
  check(maxY>=8 and grassVertices>100,'fixture has real raised grass slabs and tips')
  local pose={eye={136,140,256},focus={136,0,194},fov=.8,up={0,1,0},curve=0}
  function state:draw()
    local surface=Scene.render(self,worldArena,function()end,{pose=pose,pitch=.7})
    if surface then Renderer:setWorldOverride(surface)end
    V3.camera=pose
  end
  Game.overworld=state
  local function render(label)
    Game:draw();g.setCanvas()
    local pixels=Viewport.target():newImageData()
    if label then
      write(label..'.png',pixels:encode('png'):getString())
      if os.getenv('JP_QA_BATTLE_SEAMLESS')=='1' then
        g.push('all');g.setCanvas(Viewport.target());g.origin()
        require('src.core.TouchControls'):draw();g.pop()
        write(label..'-touch.png',Viewport.target():newImageData():encode('png'):getString())
      end
    end
    return pixels,P.metrics(Renderer:frameRects())
  end
  local function measure(label,battle,entry,expectDefect,side)
    side=side or 'enemy'
    noGrass=false;local actual,m=render(label)
    noGrass=true;local reference=render(label..'-grass-reference');noGrass=false
    local b=Cards:presentationBounds(m,side)
    if not b and side=='player' then
      local _,_,w,h=battle:pictureAnchor(side)
      local scale=P.pictureScale(m,side,w,h,true)
      b={width=w*scale,height=h*scale}
    end
    check(b~=nil,label..' '..side..' owns live capture or native picture bounds')
    local context=Host.session.context
    local r=Renderer:frameRects()
    local foot=context.arena[side]
    local px,py=context.services.project(foot[1],context.groundY,foot[2])
    px=r.vux*r.dpiX+px*r.pw/context.services.renderSize.width
    py=r.vuy*r.dpiY+py*r.ph/context.services.renderSize.height
    local x0=math.max(0,math.floor(px-b.width*r.Up/2))
    local x1=math.min(actual:getWidth()-1,math.ceil(px+b.width*r.Up/2))
    local y0=math.max(0,math.floor(py-b.height*r.Up))
    local y1=math.min(actual:getHeight()-1,math.ceil(py))
    -- Isolate the real visible silhouette by subtracting an otherwise
    -- identical no-enemy reference. This includes black outlines and the
    -- intro silhouette, independently of palette or authored body colours.
    local hiddenKey=side=='enemy' and 'enemyHidden' or 'sendingOut'
    local oldHidden=battle[hiddenKey]
    battle[hiddenKey]=true;Cards:update(context);noGrass=true
    local background=render();noGrass=false
    battle[hiddenKey]=oldHidden;Cards:update(context)
    local actor,lost=0,0
    for y=y0,y1 do for x=x0,x1 do
      local r,green,blue=reference:getPixel(x,y)
      local br,bg,bb=background:getPixel(x,y)
      if math.max(math.abs(r-br),math.abs(green-bg),math.abs(blue-bb))>.02 then
        actor=actor+1
        local rr,gg,bb=actual:getPixel(x,y)
        if math.max(math.abs(rr-r),math.abs(gg-green),math.abs(bb-blue))>.02 then lost=lost+1 end
      end
    end end
    check(actor>100,label..' reference contains visible '..side..' artwork')
    print('ACTOR OCCLUSION',label,side,lost,actor)
    if expectDefect or os.getenv('JP_QA_EXPECT_GRASS_BUG')=='1' then
      check(lost>0,label..' reproduces foreground covering '..side)
    else
      check(lost==0,label..' foreground never covers '..side..' picture pixels')
    end
    if not entry then check(battle.introSlide==0 or not battle.introSlide,label..' uses completed actual slide-in')end
  end
  local function buildingProbe(battle,tag,side,kind)
    side=side or 'enemy';kind=kind or 'terrain';foregroundKind=kind
    local arena=Host.session.context.arena
    local foot,eye=arena[side],arena.lastPose.eye
    local dx,dz=eye[1]-foot[1],eye[3]-foot[2]
    local distance=math.sqrt(dx*dx+dz*dz)
    local cx,cz=foot[1]+dx/distance*20,foot[2]+dz/distance*20
    local x0,x1,z0,z1=cx-24,cx+24,cz-12,cz+12
    local vertices,indices={},{}
    local function face(points)
      local n=#vertices
      for _,p in ipairs(points)do vertices[#vertices+1]={p[1],p[2],p[3],.5,.5,1}end
      for _,i in ipairs({1,2,3,1,3,4})do indices[#indices+1]=n+i end
    end
    face({{x0,0,z0},{x1,0,z0},{x1,64,z0},{x0,64,z0}})
    face({{x1,0,z1},{x0,0,z1},{x0,64,z1},{x1,64,z1}})
    face({{x0,0,z1},{x0,0,z0},{x0,64,z0},{x0,64,z1}})
    face({{x1,0,z0},{x1,0,z1},{x1,64,z1},{x1,64,z0}})
    face({{x0,64,z0},{x1,64,z0},{x1,64,z1},{x0,64,z1}})
    foregroundWall=assert(V3.newMesh(vertices,indices))
    local tex=love.image.newImageData(1,1);tex:setPixel(0,0,.65,.2,.15,1)
    wallTexture=g.newImage(tex)
    disableCutaway=true;measure(kind..'-'..side..'-no-cutaway-'..tag,battle,false,true,side)
    disableCutaway=false;measure(kind..'-'..side..'-visible-'..tag,battle,false,false,side)
    foregroundWall:release();wallTexture:release();foregroundWall,wallTexture=nil,nil
    foregroundKind=nil
  end
  if os.getenv('JP_QA_TRAINER_SENDOUT_29')=='1' then
    require('tests.jp29_trainer_sendout_render')(Game,Renderer,V,state,check,write,render)
    Mesher.grass,Mesher.flowers=rawGrass,rawFlowers;V3.battleOcclusion=rawOcclusion
    return
  end
  if os.getenv('JP_QA_SHADOWS24')=='1' then
    require('tests.jp24_shadows_render')(Game,Renderer,V,state,check,write,render)
    Mesher.grass,Mesher.flowers=rawGrass,rawFlowers;V3.battleOcclusion=rawOcclusion
    return
  end
  if os.getenv('JP_QA_ATMOSPHERE')=='1' then
    require('tests.jp23_atmosphere_render')(Game,Renderer,V,state,check,write,render)
    Mesher.grass,Mesher.flowers=rawGrass,rawFlowers;V3.battleOcclusion=rawOcclusion
    return
  end
  if os.getenv('JP_QA_BATTLE_BLUR')=='1' then
    require('tests.jp22_battle_blur_render')(Game,Renderer,V,state,check,write,render)
    Mesher.grass,Mesher.flowers=rawGrass,rawFlowers;V3.battleOcclusion=rawOcclusion
    return
  end
  if os.getenv('JP_QA_BATTLE_TEMPORAL_24')=='1' then
    require('tests.jp24_battle_temporal_render')(Game,Renderer,V,state,check,write,render)
    Mesher.grass,Mesher.flowers=rawGrass,rawFlowers;V3.battleOcclusion=rawOcclusion
    return
  end
  if os.getenv('JP_QA_BATTLE_FOCUS_23')=='1' then
    require('tests.jp23_battle_focus_render')(Game,Renderer,V,state,check,write,render)
    Mesher.grass,Mesher.flowers=rawGrass,rawFlowers;V3.battleOcclusion=rawOcclusion
    return
  end
  if os.getenv('JP_QA_BATTLE_FOCUS')=='1' then
    require('tests.jp_battle_focus_render')(Game,Renderer,V,state,check,write,render)
    Mesher.grass,Mesher.flowers=rawGrass,rawFlowers;V3.battleOcclusion=rawOcclusion
    return
  end
  if os.getenv('JP_QA_BATTLE_SEAMLESS')=='1' then
    require('tests.jp_battle_seamless_render')(Game,Renderer,V,state,check,write,
      {render=render,measure=measure,building=buildingProbe})
    Mesher.grass,Mesher.flowers=rawGrass,rawFlowers;V3.battleOcclusion=rawOcclusion
    return
  end
  local sizes={{972,1536},{800,480}}
  if windowQA then sizes[#sizes+1]={1536,1152}end
  for _,size in ipairs(sizes)do
    love.window.setMode(size[1],size[2],{vsync=0})
    Stack.states={state};render('world-'..size[1]..'x'..size[2])
    local battle=Battle.newWild(Game,'FIXMON_C',10)
    Stack:push(battle) -- invokes the real enter(), cry/message queue and event.
    check(Host.session and battle.showPlayerBack,'real enter creates trainer intro and MOD arena')
    local tag=tostring(size[1])..'x'..tostring(size[2])
    measure('entry-zero-'..tag,battle,true)
    for _=1,16 do Game:step(1/60)end
    measure('entry-blend-'..tag,battle,true)
    for _=17,100 do Game:step(1/60)end
    check(battle.showPlayerBack and battle.introBalls and battle.phase=='messages',tag..' remains before first Pokémon sendout')
    measure('intro-'..tag,battle)
    if windowQA then require('tests.jp_battle_window_render')(Game,Renderer,battle,tag,render,check)end
    local sawSendout=false
    for frame=1,1200 do
      if frame%16==0 then Input:sourcePress('a','intro-qa')
      elseif frame%16==1 then Input:sourceRelease('a','intro-qa')end
      Game:step(1/60)
      if battle.sendingOut and not sawSendout then
        sawSendout=true;render('sendout-'..tag)
      end
      if battle.phase=='menu' then break end
    end
    Input:sourceRelease('a','intro-qa')
    check(sawSendout and battle.phase=='menu' and not battle.showPlayerBack,tag..' actual queue completes sendout and commands')
    measure('commands-'..tag,battle)
    if windowQA then require('tests.jp_battle_window_render')(Game,Renderer,battle,tag,render,check)end
    if size[1]==972 then buildingProbe(battle,tag)end
    Host.finish('intro-qa');Blend.cancel()
  end
  Mesher.grass=rawGrass
  Mesher.flowers=rawFlowers
  V3.battleOcclusion=rawOcclusion
  check(#Game.mods.errors==0,'actual MOD loader has no runtime errors')
end
