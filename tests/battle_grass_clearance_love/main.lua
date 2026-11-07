local function run()
  local root,out,before=assert(os.getenv('JP_GRASS_ROOT')),assert(os.getenv('JP_GRASS_OUT')),assert(os.getenv('JP_GRASS_BEFORE'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local g=love.graphics
  g.setDefaultFilter('nearest','nearest')
  local T=require('tests.harness').suite('Battle visibility and local grass clearance')
  local Json=require('src.link.Json')
  local lib=root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/'
  local function load(name,V,path)return assert(loadfile((path or lib)..name..'.lua'))(V)end
  local M=load('Mat4')
  local blankData=love.image.newImageData(1,1);blankData:setPixel(0,0,0,0,0,0)
  local blank=g.newImage(blankData)
  local function texture(r,green,b)
    local id=love.image.newImageData(1,1);id:setPixel(0,0,r,green,b,1)
    return g.newImage(id)
  end
  local grassTex,actorTex,wallTex=texture(0.1,0.8,0.2),texture(1,0.25,0.1),texture(0.2,0.2,0.7)
  local gridOn=false
  local stubs={Mat4=M,VoxelState={angle=.8,FOCAL=2},
    ShadowMap={active=function()return false end,texture=function()return blank end,bias=.001,res=16,KX=0,KZ=0,invalidate=function()end},
    VoxelGrid={enabled=function()return gridOn end,DARK=.3,width=function()return 1 end},
    WorldCurve={k=function()return 0 end,drop=function(k,x,z,wx,wz)return ((wx-x)^2+(wz-z)^2)*k end},
    Sky={paint=function()end,invalidate=function()end},DayNight={},
    GlassMask={blank=function()return blank end,invalidate=function()end},
    PixelCanvas=load('PixelCanvas'),Water={invalidate=function()end}}
  local V={require=function(name)return assert(stubs[name],name)end}
  local current=load('Voxel3D',V)
  local original=load('Voxel3D',V,before..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/')
  T.check(current.available() and original.available(),'both original and current real shaders compile')
  T.check(current.unlitShader()~=nil,'unlit actor shader compiles with grass disabled')
  T.check(current.shader(false,true)~=nil,'battle-only foreground shader compiles')
  local function mesh(spec,low)
    local verts,map={},{}
    for _,s in ipairs(spec)do
      local x,y,z,h,w=s[1],s[2],s[3],s[4],s[5] or 4
      if low and s[6] then h=1 end
      local n=#verts
      for _,p in ipairs({{x-w/2,y,z},{x+w/2,y,z},{x+w/2,y+h,z},{x-w/2,y+h,z}})do
        verts[#verts+1]={p[1],p[2],p[3],.5,.5,1}
      end
      for _,i in ipairs({1,2,3,1,3,4})do map[#map+1]=n+i end
    end
    return assert(current.newMesh(verts,map))
  end
  -- Two feet sit on different floor heights. The middle/far tuft must stay
  -- full height. All near vertices lie in the clearing's fully low core.
  local specs={{-28,0,0,8,6,true},{28,12,0,8,6,true},{0,0,0,8,6,false}}
  local full,low=mesh(specs),mesh(specs,true)
  local actor=mesh({{-28,0,-2,16,8},{28,12,-2,16,8}})
  local wall=mesh({{-28,0,2,22,12}})
  local savedVerts={}
  for i=1,full:getVertexCount()do savedVerts[i]={full:getVertex(i)}end
  local player,enemy={-28,0,0},{28,0,12}
  local function picture(api,shape,clear,opts)
    opts=opts or {}
    g.reset();g.setDefaultFilter('nearest','nearest')
    api.camera={eye={0,72,140},focus={0,6,0},fov=.65,curve=opts.curve or 0}
    T.check(api.beginScene(480,320,0,0,120,80,{.05,.07,.1,1},opts.slot or 'grass-test'),'actual depth scene begins')
    if opts.occlusion then api.battleOcclusion(opts.occlusion(api))end
    if clear then api.grassClearance(player,enemy,16)end
    api.draw(shape,grassTex,opts.model)
    if api.grassClearance and not opts.leaveEnabled then api.grassClearance()end
    if api.battleOcclusion and not opts.leaveEnabled then api.battleOcclusion()end
    if opts.actors then
      api.lighting(false);api.draw(actor,actorTex);api.lighting(true)
    end
    if opts.wall then api.draw(wall,wallTex)end
    local result=api.endScene():newImageData();api.camera=nil
    return result
  end
  local function bytes(id)return id:getString()end
  local function write(name,id)
    local f=assert(io.open(out..'/'..name..'.png','wb'));f:write(id:encode('png'):getString());f:close()
  end
  local old=picture(original,full,false)
  local ordinary=picture(current,full,false)
  T.eq(bytes(old),bytes(ordinary),'ordinary-world grass is pixel-identical to the frozen previous shader')
  local cut=picture(current,full,true)
  local expected=picture(current,low,false)
  T.check(bytes(cut)~=bytes(ordinary),'local clearance changes the two tall foot tufts')
  T.eq(bytes(cut),bytes(expected),'GPU matches known one-pixel tufts at both distinct floor heights; far tuft unchanged')
  local model=M.translate(64,0,-8)
  player,enemy={36,-8,0},{92,-8,12}
  local translated=picture(current,full,true,{model=model})
  local shiftedLow=picture(current,low,false,{model=model})
  T.eq(bytes(translated),bytes(shiftedLow),'neighbour mesh translation uses world-space clearings')
  player,enemy={-28,0,0},{28,0,12}
  local curved=picture(current,full,true,{curve=.001})
  local curvedLow=picture(current,low,false,{curve=.001})
  T.eq(bytes(curved),bytes(curvedLow),'grass clearance occurs before curved-world deformation')
  picture(current,full,true,{leaveEnabled=true})
  T.eq(bytes(picture(current,full,false)),bytes(ordinary),'new scene clears an interrupted grass uniform')
  local actorBefore=picture(current,full,false,{actors=true})
  local actorAfter=picture(current,full,true,{actors=true})
  local actorExpected=picture(current,low,false,{actors=true})
  T.eq(bytes(actorAfter),bytes(actorExpected),'grass scope ends before native actor geometry')
  local function redPixels(id)
    local n=0
    for y=0,id:getHeight()-1 do for x=0,id:getWidth()-1 do
      local r,green,b=id:getPixel(x,y);if r>.9 and green<.4 and b<.2 then n=n+1 end
    end end
    return n
  end
  local visibleBefore,visibleAfter=redPixels(actorBefore),redPixels(actorAfter)
  T.check(visibleAfter>visibleBefore,'more actor pixels remain visible above the low grass')
  local wallAfter=picture(current,full,true,{actors=true,wall=true})
  local wallExpected=picture(current,low,false,{actors=true,wall=true})
  T.eq(bytes(wallAfter),bytes(wallExpected),'wall depth occlusion is preserved outside the grass pass')
  T.check(redPixels(wallAfter)<visibleAfter,'ordinary wall still hides the actor behind it')
  T.eq(Json.encode(savedVerts),Json.encode((function()local v={}for i=1,full:getVertexCount()do v[i]={full:getVertex(i)}end return v end)()),'mesh vertices are never rebuilt or mutated by repeated clearance draws')
  if g.getSupported().shaderderivatives then
    gridOn=true
    T.check(current.shader(true)~=nil,'voxel-grid shader compiles')
    local gridCut=picture(current,full,true)
    T.check(bytes(gridCut)~=bytes(picture(current,full,false)),'voxel-grid variant also lowers local grass')
    gridOn=false
  end
  write('before-local-grass',actorBefore);write('after-local-grass',actorAfter);write('after-wall-depth',wallAfter)

  local tree=mesh({{-28,0,2,24,18},{28,12,2,24,18},{0,0,2,24,10}})
  local cutRects
  local function actorBounds(api)
    local spots={};cutRects={}
    for _,point in ipairs({{-28,0},{28,12}})do
      local x,floor=point[1],point[2]
      local fx,fy=api.project(x,floor,-2)
      local tx,ty=api.project(x,floor+16,-2)
      local lx=api.project(x-4,floor,-2)
      local rx=api.project(x+4,floor,-2)
      local w,h=rx-lx,fy-ty
      spots[#spots+1]={x=x,y=floor,z=-2,width=w,height=h,floor=floor,padding=3}
      cutRects[#cutRects+1]={fx-w/2-3,fy-h-3,fx+w/2+3,fy+3}
    end
    return spots
  end
  local covered=picture(current,tree,false,{actors=true,slot='battle'})
  local revealed=picture(current,tree,false,{actors=true,slot='battle',occlusion=actorBounds})
  T.check(redPixels(revealed)>redPixels(covered),'local foreground clearing reveals actors behind the two trees')
  local outsideChanges=0
  for y=0,319 do for x=0,479 do
    local inside=false
    for _,r in ipairs(cutRects)do if x+.5>=r[1] and x+.5<r[3] and y+.5>=r[2] and y+.5<r[4] then inside=true end end
    local a,b={covered:getPixel(x,y)},{revealed:getPixel(x,y)}
    if not inside and Json.encode(a)~=Json.encode(b)then outsideChanges=outsideChanges+1 end
  end end
  T.eq(outsideChanges,0,'pixels outside the two actual actor bounds remain exact, including the middle tree')
  local lowFloor=mesh({{-28,0,2,1,18},{28,12,2,1,18}})
  local floorBefore=picture(current,lowFloor,false,{actors=true,slot='battle'})
  local floorAfter=picture(current,lowFloor,false,{actors=true,slot='battle',occlusion=actorBounds})
  T.eq(bytes(floorBefore),bytes(floorAfter),'both local floors remain untouched inside actor bounds')
  local behind=mesh({{-28,0,-16,24,18},{28,12,-16,24,18}})
  local behindBefore=picture(current,behind,false,{actors=true,slot='battle'})
  local behindAfter=picture(current,behind,false,{actors=true,slot='battle',occlusion=actorBounds})
  T.eq(bytes(behindBefore),bytes(behindAfter),'geometry behind the actor-facing planes is preserved')
  T.eq(bytes(picture(current,tree,false,{actors=true,slot='world',occlusion=actorBounds})),
    bytes(picture(current,tree,false,{actors=true,slot='world'})),
    'ordinary-world shader cannot enable a battle-only cutaway')
  picture(current,tree,false,{slot='battle',occlusion=actorBounds,leaveEnabled=true})
  T.eq(bytes(picture(current,tree,false,{actors=true,slot='battle'})),bytes(covered),
    'new battle scene resets an interrupted foreground cutaway')
  write('before-foreground-trees',covered);write('after-foreground-trees',revealed)

  -- Actual Scene.render with protocol stubs checks scope/gating/cleanup,
  -- separate from the real-shader pixel comparisons above.
  local savedPackages={}
  local overrides={['src.core.Game']={data={}},['src.render.PaletteFX']={pal=function()return {}end},
    ['src.world.Map']={isOutdoor=function()return false end},
    ['src.render.Renderer']={frameRects=function()return {pw=480,ph=320,Up=1}end},
    ['src.battle.BattlePresentation']={filmOffset=function()return 0,0 end,metrics=function()return {compact=false}end}}
  for name,value in pairs(overrides)do savedPackages[name]=package.loaded[name];package.loaded[name]=value end
  local calls,enabled,fail={},false,false
  local cutEnabled,decoration=false,false
  local fake={available=function()return true end,beginScene=function()
      enabled=false
      local sx=g.getScissor();local x,y=g.transformPoint(2,3)
      T.check(sx==nil and x==2 and y==3,'scene clears inherited scissor and transform before framebuffer draws')
      return true
    end,
    endScene=function()return 'canvas' end,eye={0,72,140},focus={0,6,0},fovY=.65,
    battleOcclusion=function(spots)cutEnabled=spots and (spots[1] or spots[2]) and true or false end,
    grassClearance=function(p,e,r)enabled=p~=nil;decoration=false;calls[#calls+1]={kind='clear',enabled=enabled,player=p,enemy=e,radius=r}end,
    battleDecoration=function(on)decoration=on and true or false end,
    draw=function(shape)
      calls[#calls+1]={kind=shape,enabled=enabled,cutEnabled=cutEnabled,decoration=decoration}
      if fail and shape=='grass' then error('injected grass draw failure')end
    end}
  local host={id='host',tileset={},def={}}
  local nb={map={id='neighbour',tileset={},def={}},ox=160,oy=0}
  local sceneDeps={Mat4=M,Voxel3D=fake,
    ChunkMesher={grass=function(m)return m==host and 'grass' or 'neighbour-grass' end,flowers=function()return 'flowers'end},
    TerrainAtlas={forMap=function()return grassTex end},
    VoxelScene={prefetch=function()return 'terrain',{'neighbour-terrain'},nil,{}end,
      groundAt=function(_,cx)return cx==1 and 0 or 12 end,_modeColors=function()return {}end,
      skyColor=function()return nil end,skyShade=function()return {0,0,0,1}end,pull=function()return 2 end},
    BattleCam={rig=function()return {eye={0,72,140},focus={0,6,0},fov=.65},.8 end,frameH=function()return 80 end},
    DayNight={applyRig=function()end,tint=function()return {1,1,1}end,isCanopy=function()return false end,windowLight=function()return 0 end},
    AntiAlias={expand=function(w,h)return w,h end,resolve=function(c)return c end},
    GlassMask={texture=function()return nil end},BattleCameraBlend={copy=function(v)return v end}}
  sceneDeps.VoxelBattleCardProvider={presentationBounds=function(_,_,side)return {width=40,height=64,worldYOffset=0}end}
  local scene=load('VoxelBattleScene',{require=function(n)return assert(sceneDeps[n],n)end})
  local state={map=host,neighbors={nb},paletteNameFor=function()return 'TEST' end}
  local arena={map=host,player={24,8},enemy={56,8},playerCell={1,0},enemyCell={3,0},mid={40,8},encounter=true}
  local function runScene(encounter,throws)
    calls={};arena.encounter=encounter;fail=throws
    local ok,res=pcall(scene.render,state,arena,function()calls[#calls+1]={kind='actors',enabled=enabled,cutEnabled=cutEnabled,decoration=decoration}end)
    if not ok then print('Scene result: '..tostring(res))end
    return ok,res
  end
  g.setScissor(3,7,5,8);g.translate(11,13)
  local priorX,priorY=g.transformPoint(2,3)
  local ok=runScene(true,false)
  local sx,sy,sw,sh=g.getScissor();local px,py=g.transformPoint(2,3)
  T.check(sx==3 and sy==7 and sw==5 and sh==8 and px==priorX and py==priorY,'successful scene restores inherited scissor and transform')
  T.check(ok,'actual battle Scene.render completes')
  local spots
  for _,c in ipairs(calls)do
    if c.kind=='clear' and c.enabled then spots=c end
    if c.kind~='clear' then
      local isGrass=c.kind=='grass' or c.kind=='neighbour-grass'
      T.eq(c.enabled,isGrass,'clearance scope for '..c.kind)
      local occluding=c.kind=='terrain' or c.kind=='neighbour-terrain' or isGrass or c.kind=='flowers'
      T.eq(c.cutEnabled,occluding,'foreground cutaway scope for '..c.kind)
      T.eq(c.decoration,c.kind=='flowers','separate decoration floor exemption scope for '..c.kind)
    end
  end
  T.check(spots and spots.player[3]==0 and spots.enemy[3]==12,'each foot queries its own terrain height')
  T.check(spots and spots.player.radius>16 and spots.player.radius<=32,'grass radius follows the larger actual picture')
  T.check(not enabled and not cutEnabled and fake.camera==nil,'successful grass pass clears state')
  ok=runScene(false,false)
  local enabledCalls=0
  for _,c in ipairs(calls)do if c.enabled then enabledCalls=enabledCalls+1 end end
  T.check(ok and enabledCalls==0,'legacy/non-encounter battle never enables local grass clearance')
  local ok,err=runScene(true,true)
  T.check(not ok and tostring(err):find('injected grass draw failure',1,true)~=nil,'grass exception propagates')
  T.check(not enabled and not cutEnabled and fake.camera==nil,'grass exception clears uniforms and camera before returning')
  local sx,sy,sw,sh=g.getScissor();local px,py=g.transformPoint(2,3)
  T.check(sx==3 and sy==7 and sw==5 and sh==8 and px==priorX and py==priorY,'failed scene restores inherited scissor and transform')
  for name in pairs(overrides)do package.loaded[name]=savedPackages[name]end
  local f=assert(io.open(out..'/results.json','wb'));f:write(Json.encode({checks=T.checks,failures=T.failures,messages=T.messages,romUsed=false,visibleActorPixels={before=visibleBefore,after=visibleAfter}}));f:close()
  T.finish()
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
