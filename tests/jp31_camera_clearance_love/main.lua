-- Synthetic floor/forest/building geometry; real production scene, shader,
-- depth attachments and shared blur. No ROM or retail images are loaded.
local function run()
  local root,out,before=assert(os.getenv('JP_CLEAR_ROOT')),assert(os.getenv('JP_CLEAR_OUT')),assert(os.getenv('JP_CLEAR_BEFORE'))
  package.path=root..'/?.lua;'..package.path
  local g=love.graphics;g.setDefaultFilter('nearest','nearest')
  local T=require('tests.harness').suite('jp31 local tall-object clearance and low scenery')
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
    mods.Structures={forMap=function(map)return map.structure or {shapeAt={}} end}
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

  actorsEnabled=false
  current.mods.VoxelBattleCardProvider.presentationBounds=function()return nil end
  local function structure(height,faces)
    local shapes={}
    for _,face in ipairs(faces)do
      local x0,z0,x1,z1=math.huge,math.huge,-math.huge,-math.huge
      for _,p in ipairs(face)do x0,z0,x1,z1=math.min(x0,p[1]),math.min(z0,p[3]),math.max(x1,p[1]),math.max(z1,p[3])end
      for z=math.floor(z0/8),math.floor(z1/8)do for x=math.floor(x0/8),math.floor(x1/8)do
        shapes[(z+64)*4096+x+64]={h=height}
      end end
    end
    return {shapeAt=shapes,runs={}}
  end
  local report={actualGL=true,romUsed=false,cases={}}
  for _,size in ipairs({{800,480},{480,800}})do
    w,h=size[1],size[2];cam.fov=w<h and 1.45 or .92;love.window.setMode(w,h,{vsync=0})
    local tag=w..'x'..h
    cam.eye={0,14,64};cam.focus={0,7,0}
    nb.map.structure={shapeAt={}}
    local tall={};localBox(tall,16,0,16,55,8)
    local highMesh=mesh(tall)
    local empty=draw(current,nil,0)
    local high=draw(current,highMesh,0)
    T.eq(different(empty,high),0,tag..' lens-intersecting tall object clears completely')
    T.check(different(empty,draw(current,highMesh,0,false,false))>500,tag..' tall reference is visibly obstructing the camera')
    local far={};localBox(far,48,0,16,55,8)
    local farMesh=mesh(far)
    T.check(draw(current,farMesh,0):getString()==draw(current,farMesh,0,false,false):getString(),tag..' surrounding tall scenery is pixel-identical outside the local radius')
    -- Whole low object, including its top and vertical faces, survives.
    local low={};localBox(low,16,0,16,12,8)
    nb.map.structure=structure(12,low)
    local lowMesh=mesh(low)
    local kept=draw(current,lowMesh,0)
    local reference=draw(current,lowMesh,0,false,false)
    T.eq(different(kept,reference),0,tag..' low object retains every visible face')
    T.check(different(kept,empty)>100,tag..' retained low object has visible pixels')
    picture('low-object-kept-'..tag,kept)
    -- A tall structure with low-looking base cells is classified by its run.
    for key in pairs(nb.map.structure.shapeAt)do nb.map.structure.runs[key]={h=40,rise=15}end
    nb.map.structure={shapeAt=nb.map.structure.shapeAt,runs=nb.map.structure.runs}
    T.eq(different(draw(current,lowMesh,0),empty),0,tag..' tall-object base does not leave a stump')
    -- Decorative geometry stays present even without a low-object mask.
    nb.map.structure={shapeAt={}}
    current.mods.ChunkMesher.grass=function(map)return map==nb.map and lowMesh or nil end
    T.eq(different(draw(current,nil,0),reference),0,tag..' grass remains visible near the lens')
    current.mods.ChunkMesher.grass=function()end
    current.mods.ChunkMesher.flowers=function(map)return map==nb.map and lowMesh or nil end
    T.eq(different(draw(current,nil,0),reference),0,tag..' flowers remain visible near the lens')
    current.mods.ChunkMesher.flowers=function()end
    -- The clearance ends in a small coverage band, not an abrupt plane.
    local rim={};localBox(rim,30,0,8,55,.1)
    local rimMesh=mesh(rim)
    local faded=draw(current,rimMesh,0)
    local solid=draw(current,rimMesh,0,false,false)
    local fadedPixels,solidPixels=different(empty,faded),different(empty,solid)
    T.check(fadedPixels>0 and fadedPixels<solidPixels,tag..' boundary retains partial coverage')
    T.check(faded:getString()==draw(current,rimMesh,0):getString(),tag..' stationary boundary has no random flicker')
    picture('local-boundary-'..tag,faded)
    report.cases[#report.cases+1]={size=tag,lowPixels=different(reference,empty),boundaryPixels=fadedPixels,solidPixels=solidPixels}
    highMesh:release();farMesh:release();lowMesh:release();rimMesh:release()
  end
  local faces={};localBox(faces,16,0,16,12,8)
  local lowMesh=mesh(faces);nb.map.structure=structure(12,faces)
  draw(current,lowMesh,0,true)
  local allocations={image=0,mesh=0,shader=0,canvas=0};local original={}
  for key,api in pairs({image='newImage',mesh='newMesh',shader='newShader',canvas='newCanvas'})do
    original[api]=g[api];g[api]=function(...)allocations[key]=allocations[key]+1;return original[api](...)end
  end
  for i=1,60 do cam.eye[1]=math.sin(i*.1);draw(current,lowMesh,0,true)end
  for api,fn in pairs(original)do g[api]=fn end
  for key,n in pairs(allocations)do T.eq(n,0,'warm camera movement allocates no '..key)end
  report.allocations,report.checks,report.failures,report.messages=allocations,T.checks,T.failures,T.messages
  write('results.json',Json.encode(report));T.finish()
end
function love.load()local ok,err=xpcall(run,debug.traceback);if not ok then print(err);love.event.quit(1)else love.event.quit(0)end end
