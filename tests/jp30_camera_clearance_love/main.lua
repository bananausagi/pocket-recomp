-- Synthetic floor/forest/building geometry; real production scene, shader,
-- depth attachments and shared blur. No ROM or retail images are loaded.
local function run()
  local root,out,before=assert(os.getenv('JP_CLEAR_ROOT')),assert(os.getenv('JP_CLEAR_OUT')),assert(os.getenv('JP_CLEAR_BEFORE'))
  package.path=root..'/?.lua;'..package.path
  local g=love.graphics;g.setDefaultFilter('nearest','nearest')
  local T=require('tests.harness').suite('jp30 camera-near foreground clearance')
  local Json=require('src.link.Json')
  local Game={data={constants={language='ja'}},save={options={jpAtmosphere='off'}}}
  package.loaded['src.core.Game']=Game
  package.loaded['src.render.PaletteFX']={pal=function()return {}end}
  package.loaded['src.world.Map']={isOutdoor=function()return true end}
  local w,h=800,480
  package.loaded['src.render.Renderer']={frameRects=function()return {pw=w,ph=h,Up=h/144}end}
  package.loaded['src.battle.BattlePresentation']={metrics=function()return {}end,filmOffset=function()return 0,0 end}
  local function write(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
  local function picture(name,id)write(name..'.png',id:encode('png'):getString())end
  local function tex(r,green,b,checker)
    local data=love.image.newImageData(8,8)
    for y=0,7 do for x=0,7 do local c=checker and ((x+y)%2==0) and .6 or 1;data:setPixel(x,y,r*c,green*c,b*c,1)end end
    return g.newImage(data)
  end
  local blank=tex(0,0,0)
  local groundTex=tex(.64,.71,.48,true)
  local treeTex=tex(.13,.33,.08,true)
  local buildingTex=tex(.5,.3,.13,true)
  local actorTex={tex(1,.16,.02),tex(.7,.05,1)}
  local runtimes={}
  local function runtime(path)
    local mods,V={},{}
    function V.require(name)
      if not mods[name]then mods[name]=assert(loadfile(path..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/'..name..'.lua'))(V)end
      return mods[name]
    end
    mods.VoxelState={angle=.8,FOCAL=2}
    mods.ShadowMap={active=function()return false end,texture=function()return blank end,bias=.001,res=16,KX=0,KZ=0,invalidate=function()end}
    mods.VoxelGrid={enabled=function()return false end,DARK=.3,width=function()return 1 end}
    mods.WorldCurve={k=function()return 0 end,drop=function()return 0 end}
    mods.Sky={paint=function()end,invalidate=function()end}
    mods.GlassMask={blank=function()return blank end,texture=function()return blank end,invalidate=function()end}
    mods.DayNight={applyRig=function()end,tint=function()return {1,1,1}end,isCanopy=function()return false end,windowLight=function()return 0 end}
    mods.Water={invalidate=function()end}
    mods.AntiAlias={expand=function(a,b)return a,b end,resolve=function(c)return c end}
    mods.BattleCam={frameH=function()return 144 end}
    mods.BattleIntroFocus={pose=function(_,cam)return cam end}
    mods.BattleActionCamera={pose=function(_,cam)return cam end,finish=function()end}
    mods.BattleCameraBlend={copy=function(cam)return cam end}
    mods.VoxelBattleCardProvider={presentationBounds=function()return {width=32,height=40}end}
    local r={V=V,mods=mods,casts=0}
    r.v3=V.require('Voxel3D');r.blur=V.require('TiltShift')
    T.check(r.v3.available() and r.v3.shader(false,true)~=nil,path..' actual GL battle shader compiles')
    mods.TerrainAtlas={forMap=function(map)return map.texture end}
    mods.ChunkMesher={grass=function()end,flowers=function()end}
    mods.VoxelScene={prefetch=function()return r.base,r.obstacles and {r.obstacles} or {},nil,{}end,
      groundAt=function()return 0 end,_modeColors=function()return {}end,
      skyColor=function()return {.52,.68,.8,1}end,pull=function()return 0 end,
      castBattleShadows=function()r.casts=r.casts+1 end}
    r.scene=V.require('VoxelBattleScene');runtimes[#runtimes+1]=r;return r
  end
  local current=runtime(root);local old=runtime(before)
  local shaderFile=assert(io.open(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/Voxel3D.lua','rb'))
  local shaderSource=assert(shaderFile:read('*a'):match('local SHADER = %[%[(.-)%]%]'));shaderFile:close()
  for _,prefix in ipairs({'','#define VOXEL_GRID 1\n','#define BATTLE_OCCLUSION 1\n',
      '#define BATTLE_OCCLUSION 1\n#define VOXEL_GRID 1\n','#define UNLIT_ONLY 1\n'})do
    local valid,why=g.validateShader(true,prefix..shaderSource)
    T.check(valid,'GLES shader variant validates '..prefix..tostring(why or ''))
  end
  local function mesh(faces)
    local vertices,indices={},{}
    for _,face in ipairs(faces)do local n=#vertices
      for i,p in ipairs(face)do vertices[#vertices+1]={p[1],p[2],p[3],(i==2 or i==3) and 1 or 0,i>2 and 1 or 0,1}end
      for _,i in ipairs({1,2,3,1,3,4})do indices[#indices+1]=n+i end
    end
    return assert(current.v3.newMesh(vertices,indices))
  end
  local function box(faces,x,y,z,sx,sy,sz)
    local a,b,c,d=x-sx/2,x+sx/2,z-sz/2,z+sz/2
    faces[#faces+1]={{a,y,c},{b,y,c},{b,y+sy,c},{a,y+sy,c}}
    faces[#faces+1]={{b,y,d},{a,y,d},{a,y+sy,d},{b,y+sy,d}}
    faces[#faces+1]={{a,y,d},{a,y,c},{a,y+sy,c},{a,y+sy,d}}
    faces[#faces+1]={{b,y,c},{b,y,d},{b,y+sy,d},{b,y+sy,c}}
    faces[#faces+1]={{a,y+sy,c},{b,y+sy,c},{b,y+sy,d},{a,y+sy,d}}
  end
  local floorFaces={}
  for z=-180,160,16 do for x=-180,160,16 do floorFaces[#floorFaces+1]={{x,0,z},{x+16,0,z},{x+16,0,z+16},{x,0,z+16}}end end
  local base=mesh(floorFaces)
  local marks={{-20,20},{20,-20}}
  local cam={eye={70,38,95},focus={0,12,0},fov=.92,curve=0}
  local host={id='host',def={},texture=groundTex};local nb={map={id='trees',texture=treeTex},ox=0,oy=0}
  local state={map=host,neighbors={nb},paletteNameFor=function()return 'TEST' end}
  local arena={map=host,encounter=true,player=marks[1],enemy=marks[2],playerCell={-2,1},enemyCell={1,-2},mid={0,0}}
  local function actorMesh(p,eye)
    local dx,dz=eye[1]-p[1],eye[3]-p[2];local len=math.sqrt(dx*dx+dz*dz)
    local rx,rz=dz/len*10,-dx/len*10
    return mesh({{{p[1]-rx,1,p[2]-rz},{p[1]+rx,1,p[2]+rz},{p[1]+rx,27,p[2]+rz},{p[1]-rx,27,p[2]-rz}}})
  end
  local actors={actorMesh(marks[1],cam.eye),actorMesh(marks[2],cam.eye)}
  local actorsEnabled=true
  local function draw(r,obstacles,level,noRead,encounter)
    r.base,r.obstacles=base,obstacles;r.blur.setLevel(level or 2)
    arena.encounter=encounter~=false
    local beforeCast=r.casts
    local c=r.scene.render(state,arena,function()
      if actorsEnabled then r.v3.lighting(false)
        for i,m in ipairs(actors)do r.v3.draw(m,actorTex[i])end
        r.v3.lighting(true)
      end
    end,{pose=cam,pitch=.35})
    assert(c,'real Scene.render must return its 3D canvas')
    assert(r.casts==beforeCast+1,'exactly one shadow request per frame')
    assert(r.v3.camera==nil,'scene restores world camera ownership')
    return not noRead and c:newImageData() or c
  end
  local function actorPixels(id,index)
    local points={}
    for y=0,id:getHeight()-1 do for x=0,id:getWidth()-1 do
      local r,green,b=id:getPixel(x,y)
      if index==1 and r>.95 and green<.25 and b<.1 or index==2 and r>.65 and r<.75 and green<.1 and b>.95 then points[#points+1]={x,y}end
    end end
    return points
  end
  local function lost(reference,actual,points)
    local n=0
    for _,p in ipairs(points)do local a,b,c=reference:getPixel(p[1],p[2]);local x,y,z=actual:getPixel(p[1],p[2])
      if math.abs(a-x)+math.abs(b-y)+math.abs(c-z)>.02 then n=n+1 end
    end
    return n
  end
  local receipts={}
  local function different(a,b)
    local n=0
    for y=0,a:getHeight()-1 do for x=0,a:getWidth()-1 do
      local ar,ag,ab=a:getPixel(x,y);local br,bg,bb=b:getPixel(x,y)
      if math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)>.05 then n=n+1 end
    end end
    return n
  end
  local function basis()
    local dx,dz=cam.focus[1]-cam.eye[1],cam.focus[3]-cam.eye[3]
    local len=math.sqrt(dx*dx+dz*dz)
    return dx/len,dz/len,len
  end
  local function localBox(faces,depth,side,width,height,thickness)
    local nx,nz=basis()
    local x,z=cam.eye[1]+nx*depth-nz*side,cam.eye[3]+nz*depth+nx*side
    -- Test boxes use view-aligned depth walls, so every vertex's horizontal
    -- depth is precisely known without depending on perspective or pixels.
    local points={}
    for _,d in ipairs({-thickness/2,thickness/2})do
      for _,a in ipairs({-width/2,width/2})do
        points[#points+1]={x+nx*d-nz*a,z+nz*d+nx*a}
      end
    end
    local a,b,c,d=points[1],points[2],points[4],points[3]
    for _,pair in ipairs({{a,b},{b,c},{c,d},{d,a}})do
      local p,q=pair[1],pair[2]
      faces[#faces+1]={{p[1],0,p[2]},{q[1],0,q[2]},{q[1],height,q[2]},{p[1],height,p[2]}}
    end
    faces[#faces+1]={{a[1],height,a[2]},{b[1],height,b[2]},{c[1],height,c[2]},{d[1],height,d[2]}}
  end
  for _,size in ipairs({{800,480},{480,800}})do
    w,h=size[1],size[2];cam.fov=w<h and 1.45 or .92;love.window.setMode(w,h,{vsync=0})
    local tag=w..'x'..h
    for _,kind in ipairs({'forest','building-corner'})do
      local inside,remaining={},{}
      if kind=='forest' then
        -- Lens inside one 2x2-cell canopy. Other near/mid trees lie beyond
        -- the one-block camera clearance and must not be erased with it.
        box(inside,70,0,95,38,85,38)
        for _,p in ipairs({{50,-28},{50,28},{75,-42},{75,42},{95,-48},{95,48},
            {145,-70},{145,-35},{145,0},{145,35},{145,70}})do
          localBox(remaining,p[1],p[2],14,42,14)
        end
        nb.map.texture=treeTex
      else
        -- Eye intersects a wall corner. The street's facades beyond the
        -- lens clearance remain, including those before the battle feet.
        box(inside,75,0,99,38,95,32)
        localBox(remaining,62,-37,20,55,48)
        localBox(remaining,62,37,20,55,48)
        localBox(remaining,148,-45,40,60,28)
        localBox(remaining,148,45,40,60,28)
        nb.map.texture=buildingTex
      end
      local nearMesh=mesh(inside);local savedMesh=mesh(remaining)
      local all={};for _,f in ipairs(inside)do all[#all+1]=f end;for _,f in ipairs(remaining)do all[#all+1]=f end
      local obstacle=mesh(all)
      local reference=draw(current,savedMesh,2)
      local a=draw(old,obstacle,2);local b=draw(current,obstacle,2)
      picture(kind..'-before-'..tag,a);picture(kind..'-after-'..tag,b)
      T.eq(different(reference,b),0,kind..' '..tag..' only lens-intersecting object is removed')
      local removed=draw(current,nearMesh,0)
      local empty=draw(current,nil,0)
      T.eq(different(removed,empty),0,kind..' '..tag..' lens-intersecting canopy/corner is fully cleared')
      local changes=different(a,b)
      T.check(changes>w*h*.02,kind..' '..tag..' restores substantial near/mid scenery deleted by jp29')
      local scenery=different(empty,draw(current,savedMesh,0))
      T.check(scenery>w*h*.04,kind..' '..tag..' retains actual surrounding scenery')
      receipts[#receipts+1]={size=tag,kind=kind,restoredPixels=changes,retainedSceneryPixels=scenery}
      nearMesh:release();savedMesh:release();obstacle:release()
    end
  end
  w,h=800,480;cam.fov=.92;love.window.setMode(w,h,{vsync=0});actorsEnabled=false;nb.map.texture=treeTex
  -- A visible screen-filling marker at 34 world pixels is well before the
  -- battle feet yet strictly outside the 32px clearance. Test near/middle/
  -- far bands against a clip-disabled image, not against our own formulas.
  for _,depth in ipairs({34,48,75,110,150})do
    local faces={};localBox(faces,depth,0,160,70,1)
    local obstacle=mesh(faces)
    local uncropped=draw(current,obstacle,0,false,false)
    local cropped=draw(current,obstacle,0)
    T.check(cropped:getString()==uncropped:getString(),'raised scenery at depth '..depth..' remains pixel-identical')
    T.check(different(cropped,draw(current,nil,0))>w*h*.15,'preserved depth '..depth..' contains visible marker geometry')
    if depth==48 then picture('near-scenery-kept-800x480',cropped)end
    obstacle:release()
  end
  for _,depth in ipairs({8,16,24,30})do
    local faces={};localBox(faces,depth,0,100,70,1)
    local obstacle=mesh(faces)
    T.eq(different(draw(current,obstacle,0),draw(current,nil,0)),0,'raised lens-near geometry at depth '..depth..' is removed')
    obstacle:release()
  end
  -- During close-ups the 32px maximum must not reach or cross the subject:
  -- on a 24px horizontal focus distance the boundary contracts to 12px.
  cam.eye={20,22,4};cam.focus={20,12,-20}
  local near,kept={},{}
  localBox(near,8,0,40,60,1);localBox(kept,16,0,40,60,1)
  local nearMesh,keptMesh=mesh(near),mesh(kept)
  T.eq(different(draw(current,nearMesh,0),draw(current,nil,0)),0,'close-up clears lens intersection at depth 8')
  T.check(draw(current,keptMesh,0):getString()==draw(current,keptMesh,0,false,false):getString(),'close-up retains raised scenery before focus at depth 16')
  picture('close-up-keeps-subject-surroundings',draw(current,keptMesh,0))
  nearMesh:release();keptMesh:release()
  cam.eye={70,38,95};cam.focus={0,12,0}
  -- Rotation uses the actual final camera, rather than the battle midpoint
  -- or captured sprite position. Evaluate both orbit extrema and a complete
  -- slow sweep with a fixed canopy around the lens + real scenery beyond it.
  current.mods.VoxelBattleCardProvider.presentationBounds=function()return nil end
  for i=0,16 do
    local yaw=math.rad(3.2)*math.sin(i/16*math.pi*2)
    cam.eye={70*math.cos(yaw)-95*math.sin(yaw),38,70*math.sin(yaw)+95*math.cos(yaw)}
    cam.focus={math.sin(i/16*math.pi*2)*3,12,-math.sin(i/16*math.pi*2)*3}
    local near,kept={},{}
    localBox(near,12,0,100,70,12);localBox(kept,38,0,100,70,1)
    local nearMesh,keptMesh=mesh(near),mesh(kept)
    T.eq(different(draw(current,nearMesh,2),draw(current,nil,2)),0,'orbit frame '..i..' clears lens-near geometry using final eye/focus')
    T.check(draw(current,keptMesh,2):getString()==draw(current,keptMesh,2,false,false):getString(),'orbit frame '..i..' retains nearby field geometry using final eye/focus')
    if i==4 or i==12 then picture('orbit-'..i..'-kept',draw(current,keptMesh,2))end
    nearMesh:release();keptMesh:release()
  end
  cam.eye={70,38,95};cam.focus={0,12,0};actorsEnabled=true
  local faces={};box(faces,70,0,95,38,85,38);localBox(faces,70,42,14,42,14)
  local obstacle=mesh(faces)
  local groundAt=current.mods.VoxelScene.groundAt
  local normal=draw(current,obstacle,2)
  current.mods.VoxelScene.groundAt=function(_,x,z)return x==-2 and z==1 and 0 or 80 end
  arena.backgroundOnly=true
  local fallback=draw(current,obstacle,2)
  T.check(fallback:getString()==normal:getString(),'background-only fallback protects actual origin floor rather than elevated virtual foot')
  picture('background-only-after-800x480',fallback)
  arena.backgroundOnly=nil;current.mods.VoxelScene.groundAt=groundAt
  actorsEnabled=false
  T.check(draw(old,nil,0):getString()==draw(current,nil,0):getString(),'standing floor remains pixel-identical')
  T.check(draw(old,obstacle,0,false,false):getString()==draw(current,obstacle,0,false,false):getString(),'ordinary non-encounter rendering remains pixel-identical')
  actorsEnabled=true
  local empty=draw(current,nil,2)
  local actorsActual=draw(current,obstacle,2)
  for i=1,2 do
    local pixels=actorPixels(empty,i)
    T.check(#pixels>200,'reference actor '..i..' is visible')
    T.eq(lost(empty,actorsActual,pixels),0,'cleared camera object does not cover actor '..i..' and clip is reset before cards')
  end
  draw(current,obstacle,2,true)
  local allocations={canvas=0,image=0,mesh=0,shader=0};local original={}
  for key,api in pairs({canvas='newCanvas',image='newImage',mesh='newMesh',shader='newShader'})do
    original[api]=g[api];g[api]=function(...)allocations[key]=allocations[key]+1;return original[api](...)end
  end
  local startCasts=current.casts
  for i=1,120 do cam.eye={70+math.sin(i*.04)*3,38,95};draw(current,obstacle,2,true)end
  for api,fn in pairs(original)do g[api]=fn end
  for key,n in pairs(allocations)do T.eq(n,0,'120 warm moving frames create no new GPU '..key)end
  T.eq(current.casts-startCasts,120,'one shadow request per frame, no added pass')
  write('results.json',Json.encode({checks=T.checks,failures=T.failures,messages=T.messages,romUsed=false,renderer={g.getRendererInfo()},cases=receipts,warmAllocations=allocations,clearance={maximumWorldPixels=32,maximumFocusFraction=.5,cellPixels=16}}))
  T.finish()
end
function love.load()local ok,err=xpcall(run,debug.traceback);if not ok then print(err);love.event.quit(1)else love.event.quit(0)end end
