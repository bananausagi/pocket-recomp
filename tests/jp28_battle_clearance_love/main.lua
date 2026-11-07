-- Synthetic floor/forest/building geometry; real production scene, shader,
-- depth attachments and shared blur. No ROM or retail images are loaded.
local function run()
  local root,out,before=assert(os.getenv('JP_CLEAR_ROOT')),assert(os.getenv('JP_CLEAR_OUT')),assert(os.getenv('JP_CLEAR_BEFORE'))
  package.path=root..'/?.lua;'..package.path
  local g=love.graphics;g.setDefaultFilter('nearest','nearest')
  local T=require('tests.harness').suite('jp28 camera-side foreground clipping')
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
  for _,size in ipairs({{800,480},{480,800}})do
    w,h=size[1],size[2];cam.fov=w<h and 1.45 or .92;love.window.setMode(w,h,{vsync=0})
    local tag=w..'x'..h
    for _,kind in ipairs({'forest','building-corner'})do
      local faces={}
      if kind=='forest' then
        -- The eye is INSIDE a canopy; other near trees close the rays toward
        -- both feet. Distant and sideways trees establish a retained world.
        box(faces,70,0,95,38,85,38)
        for _,p in ipairs({{40,55},{12,40},{36,15},{-55,-100},{0,-100},{60,-95},{-80,-30}})do box(faces,p[1],0,p[2],22,50,22)end
        nb.map.texture=treeTex
      else
        box(faces,72,0,84,24,105,65)
        box(faces,45,0,64,70,105,18)
        box(faces,-90,0,-80,42,68,40)
        box(faces,0,0,-100,40,68,32)
        nb.map.texture=buildingTex
      end
      local obstacle=mesh(faces)
      local reference=draw(current,nil,2)
      local a=draw(old,obstacle,2);local b=draw(current,obstacle,2)
      picture(kind..'-before-'..tag,a);picture(kind..'-after-'..tag,b)
      local different=0;for y=0,h-1 do for x=0,w-1 do
        local ar,ag,ab=a:getPixel(x,y);local br,bg,bb=b:getPixel(x,y)
        if math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)>.05 then different=different+1 end
      end end
      T.check(different>w*h*.2,kind..' '..tag..' camera-side clipping fixes more than tiny sprite windows')
      for i=1,2 do local points=actorPixels(reference,i);local missing=lost(reference,b,points)
        T.check(#points>200,kind..' '..tag..' reference actor '..i..' is visible')
        T.eq(missing,0,kind..' '..tag..' complete actor '..i..' remains unobstructed with blur ON')
      end
      -- Retained surroundings are real geometry, not a removed-map fallback.
      local worldPixels=0
      for y=0,h-1 do for x=0,w-1 do local ar,ag,ab=reference:getPixel(x,y);local br,bg,bb=b:getPixel(x,y)
        if math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)>.05 then worldPixels=worldPixels+1 end
      end end
      T.check(worldPixels>w*h*.01,kind..' '..tag..' preserves visible distant or sideways scenery')
      receipts[#receipts+1]={size=tag,kind=kind,changedPixels=different,retainedSceneryPixels=worldPixels}
      obstacle:release()
    end
  end
  -- Scenery directly behind the opponent must stay, even within one cell:
  -- a per-actor circular clearing incorrectly removes this real backdrop.
  w,h=800,480;cam.fov=.92;love.window.setMode(w,h,{vsync=0})
  local nx,nz=-70/math.sqrt(70*70+95*95),-95/math.sqrt(70*70+95*95)
  local bx,bz=marks[2][1]+nx*4,marks[2][2]+nz*4
  local rx,rz=-nz*60,nx*60
  local backMesh=mesh({{{bx-rx,0,bz-rz},{bx+rx,0,bz+rz},{bx+rx,55,bz+rz},{bx-rx,55,bz-rz}}});nb.map.texture=treeTex;actorsEnabled=false
  local behindBefore=draw(current,backMesh,0,false,false);local behindAfter=draw(current,backMesh,0)
  T.check(behindAfter:getString()==behindBefore:getString(),'raised scenery immediately behind opponent remains pixel-identical')
  backMesh:release();actorsEnabled=true
  -- A real moving close-up/pull-back path uses the instantaneous lens. The
  -- scene has no dependence on a sprite capture existing during the slide.
  w,h=800,480;cam.fov=.92;love.window.setMode(w,h,{vsync=0})
  local faces={};box(faces,70,0,95,38,85,38);box(faces,40,0,45,28,70,28)
  local obstacle=mesh(faces);nb.map.texture=treeTex
  current.mods.VoxelBattleCardProvider.presentationBounds=function()return nil end
  for i=0,8 do
    local t=i/8
    cam.eye={20+50*t,26+12*t,35+60*t};cam.focus={20*(1-t),12,-20*(1-t)}
    local reference=draw(current,nil,2);local actual=draw(current,obstacle,2)
    for side=1,2 do local points=actorPixels(reference,side)
      if #points>0 then T.eq(lost(reference,actual,points),0,'moving intro pose '..i..' actor '..side..' has no capture-dependent hole')end
    end
  end
  cam.eye={70,38,95};cam.focus={0,12,0}
  -- Narrow maps keep native pictures over the same 3D background. Their
  -- synthetic camera feet may sit on a canopy: only the real player floor
  -- defines protection, and foreground cutting still applies.
  local normal=draw(current,obstacle,2)
  local groundAt=current.mods.VoxelScene.groundAt
  current.mods.VoxelScene.groundAt=function(_,x,z)return x==-2 and z==1 and 0 or 80 end
  arena.backgroundOnly=true
  local fallback=draw(current,obstacle,2)
  T.check(fallback:getString()==normal:getString(),'background-only fallback clips foreground using real origin floor, not blocked virtual feet')
  picture('background-only-after-800x480',fallback)
  arena.backgroundOnly=nil;current.mods.VoxelScene.groundAt=groundAt
  -- Ordinary scenery, floor and a new scene after an interrupted caller.
  actorsEnabled=false
  local groundBefore=draw(old,nil,0);local groundAfter=draw(current,nil,0)
  T.check(groundAfter:getString()==groundBefore:getString(),'the actual standing floor is pixel-identical')
  local worldBefore=draw(old,obstacle,0,false,false);local worldAfter=draw(current,obstacle,0,false,false)
  T.check(worldAfter:getString()==worldBefore:getString(),'non-encounter/world rendering is pixel-identical')
  actorsEnabled=true
  draw(current,obstacle,2,true)
  local allocations={canvas=0,image=0,mesh=0,shader=0};local original={}
  for key,api in pairs({canvas='newCanvas',image='newImage',mesh='newMesh',shader='newShader'})do
    original[api]=g[api];g[api]=function(...)allocations[key]=allocations[key]+1;return original[api](...)end
  end
  local startCasts=current.casts
  for i=1,120 do cam.eye={70+math.sin(i*.04)*3,38,95};draw(current,obstacle,2,true)end
  for api,fn in pairs(original)do g[api]=fn end
  for key,n in pairs(allocations)do T.eq(n,0,'120 warm moving frames create no new GPU '..key)end
  T.eq(current.casts-startCasts,120,'no duplicate shadow pass is requested')
  write('results.json',Json.encode({checks=T.checks,failures=T.failures,messages=T.messages,romUsed=false,renderer={g.getRendererInfo()},cases=receipts,warmAllocations=allocations}))
  T.finish()
end
function love.load()local ok,err=xpcall(run,debug.traceback);if not ok then print(err);love.event.quit(1)else love.event.quit(0)end end
