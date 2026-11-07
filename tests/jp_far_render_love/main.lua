-- Original connected-map geometry and foliage; no retail maps/art/ROM.
-- Baseline is an archived jp.20 native PackedVoxelMesh, not a reimplementation.
local function run()
  local root,out,baseline=assert(os.getenv("JP_QA_ROOT")),assert(os.getenv("JP_QA_OUT")),assert(os.getenv("JP_QA_BASELINE"))
  package.path=root.."/?.lua;"..package.path
  local P=require("src.render.PackedVoxelMesh")
  local Old=assert(loadfile(baseline.."/PackedVoxelMesh.lua"))()
  local M=assert(loadfile(root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/Mat4.lua"))()
  local F=require("src.render.VoxelFrustum")
  local g=love.graphics
  local checks=0
  local function check(ok,msg)assert(ok,msg);checks=checks+1;print("PASS "..msg)end
  local function write(name,bytes)local f=assert(io.open(out.."/"..name,"wb"));f:write(bytes);f:close()end
  local fixture={}
  local uv={{0,1},{1,1},{1,0},{0,0}}
  local totals=setmetatable({},{__mode="k"})
  for i,origin in ipairs({{0,0},{-512,0},{0,-512}})do
    local ot,nt,og,ng=Old.new(nil,true),P.new(nil,true),Old.new(nil,false),P.new(nil,"ordered")
    local tcount,fcount=0,0
    local function terrain(q,s)ot.push(q,uv,s);nt.push(q,uv,s);tcount=tcount+6 end
    local function foliage(q,s)og.push(q,uv,s);ng.push(q,uv,s);fcount=fcount+6 end
    for z=0,496,16 do for x=0,496,16 do
      terrain({{x,0,z},{x+16,0,z},{x+16,0,z+16},{x,0,z+16}},.25+((x+z)%64)/200)
      if (x/16+z/16)%3==0 then
        local h=20+((x+z)%48)
        terrain({{x+2,0,z+3},{x+14,0,z+3},{x+14,h,z+3},{x+2,h,z+3}},.45)
        terrain({{x+2,h,z+3},{x+14,h,z+3},{x+14,h,z+13},{x+2,h,z+13}},.65)
        terrain({{x+2,0,z+13},{x+14,0,z+13},{x+14,h,z+13},{x+2,h,z+13}},.55)
      end
    end end
    for z=0,504,8 do for x=0,504,8 do
      foliage({{x,0,z+4},{x+8,0,z+4},{x+8,10,z+4},{x,10,z+4}},.65+((x+z)%32)/120)
    end end
    local row={model=M.translate(origin[1],0,origin[2]),old={ot.finish(),og.finish()},new={nt.finish(),ng.finish()}}
    for _,meshes in ipairs({row.old,row.new})do totals[meshes[1]]=tcount;totals[meshes[2]]=fcount end
    fixture[i]=row
    local gi=P.ranges(row.new[2]);check(gi and gi.ordered,"foliage has ordered bounds for map "..i)
    local a,b=row.old[2]:getVertexMap(),row.new[2]:getVertexMap()
    check(#a==#b,"foliage index count preserved "..i)
    for at=1,#a do assert(a[at]==b[at],"foliage alpha order changed")end
    check(true,"every source foliage index retains original order "..i)
  end
  -- Match the production world shader's model, bend and camera-ray pull.
  local sh=g.newShader([[
    varying float shade; uniform mat4 vp; uniform mat4 model;
    uniform vec3 curve; uniform vec3 eye; uniform float pull; uniform float foliage;
    #ifdef VERTEX
    attribute float VertexShade;
    vec4 position(mat4 ignored,vec4 p){vec4 w=model*p;
      if(curve.z>0.0){vec2 d=w.xz-curve.xy;w.y-=dot(d,d)*curve.z;}
      if(pull>0.0){w.xyz+=normalize(eye-w.xyz)*pull;}
      shade=VertexShade;return vp*w;}
    #endif
    #ifdef PIXEL
    vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){
      if(foliage>0.0 && fract(uv.x*4.0)<0.35)discard;
      return vec4(shade*(foliage>0.0?0.35:0.75),shade,shade*0.25,foliage>0.0?0.8:1.0);}
    #endif
  ]])
  local canvas=g.newCanvas(320,240,{dpiscale=1})
  local depth=g.newCanvas(320,240,{format="depth24",readable=false,dpiscale=1})
  local eye={48,180,280}
  local view=M.lookAt(eye,{48,0,-40},{0,1,0})
  local vp=M.mul(M.perspective(.95,320/240,1,4096),view)
  local oldDraw=g.draw
  local calls,indices=0,0
  g.draw=function(mesh,...)
    if totals[mesh]then
      local _,count=mesh:getDrawRange();calls=calls+1;indices=indices+(count or totals[mesh])
    end
    return oldDraw(mesh,...)
  end
  local function draw(optimized,camera,curve,eyePosition,shadow)
    g.setCanvas({canvas,depthstencil=depth});g.clear(.05,.08,.1,1,0,1)
    g.setShader(sh);g.setColor(1,1,1,1);g.setDepthMode("lequal",true);g.setMeshCullMode("none");g.setBlendMode("alpha")
    sh:send("vp","row",camera);sh:send("curve",{48,-40,curve});sh:send("eye",eyePosition)
    calls,indices=0,0
    for pass=1,2 do
      local pull=pass==2 and not shadow and 10 or 0
      sh:send("pull",pull);sh:send("foliage",pass==2 and 1 or 0)
      for _,row in ipairs(fixture)do
        local mesh=(optimized and row.new or row.old)[pass]
        sh:send("model","row",row.model)
        local handled
        if optimized then handled=P.draw(mesh,camera,row.model,48,-40,curve,pull)
        elseif pass==1 then handled=Old.draw(mesh,camera,row.model,48,-40,curve)end
        if not handled then g.draw(mesh)end
        assert(not mesh:getDrawRange(),"range leaked into subsequent pass")
      end
    end
    g.setShader();g.setDepthMode();g.setCanvas()
    return calls,indices
  end
  local scenes={
    {name="third-person-seam",vp=vp,eye=eye,k=0},
    {name="curved-world",vp=vp,eye=eye,k=.18/144},
    {name="north-facing",vp=M.mul(M.perspective(1.1,320/240,1,4096),M.lookAt({48,28,24},{48,24,-100},{0,1,0})),eye={48,28,24},k=0},
    {name="west-seam",vp=M.mul(M.perspective(.95,320/240,1,4096),M.lookAt({280,180,48},{-40,0,48},{0,1,0})),eye={280,180,48},k=0},
    {name="sun-pass",vp=M.mul(M.ortho(-200,200,-200,200,1,2000),M.lookAt({350,500,250},{0,0,0},{0,1,0})),eye={350,500,250},k=0,shadow=true},
  }
  local results={}
  for _,scene in ipairs(scenes)do
    local bc,bi=draw(false,scene.vp,scene.k,scene.eye,scene.shadow)
    local ref=canvas:newImageData():getString()
    local ac,ai=draw(true,scene.vp,scene.k,scene.eye,scene.shadow)
    local image=canvas:newImageData()
    check(ref==image:getString(),scene.name.." entire connected-map frame pixel-identical")
    results[#results+1]={name=scene.name,before={drawCalls=bc,submittedIndices=bi},after={drawCalls=ac,submittedIndices=ai}}
    if scene.name=="third-person-seam"then write("connected-map.png",image:encode("png"):getString())end
  end
  local timings={}
  for repetition=1,3 do for _,optimized in ipairs({false,true})do
    for _=1,15 do draw(optimized,vp,0,eye);g.present()end
    local started,cpu=love.timer.getTime(),os.clock()
    for _=1,90 do draw(optimized,vp,0,eye);g.present()end
    timings[#timings+1]={optimized=optimized,repetition=repetition,frames=90,wallMs=(love.timer.getTime()-started)*1000/90,cpuMs=(os.clock()-cpu)*1000/90}
  end end
  -- Every neighboring side remains visible as the camera crosses map origins.
  for x=-64,64,16 do
    local e={x,150,180};local p=M.mul(M.perspective(.95,320/240,1,4096),M.lookAt(e,{x,0,-70},{0,1,0}))
    draw(false,p,.001,e);local expected=canvas:newImageData():getString()
    draw(true,p,.001,e);check(expected==canvas:newImageData():getString(),"cross-map position "..x.." preserves distant/near scenery")
  end
  check(F.visible({1.05,0,0,1.1,.1,.1},M.identity(),nil,0,0,0,.2),"pull bounds keep foliage moved across side plane")
  check(F.visible({1000,0,0,1001,1,1},M.identity(),nil,0,0,0,0/0),"invalid pull draws full rather than dropping geometry")
  check(results[1].after.submittedIndices<results[1].before.submittedIndices*.7,"third-person omitted work exceeds 30 percent without pixel change")
  -- Exercise production ChunkMesher's split auxiliary upload, then production
  -- Voxel3D.draw's decision with a nonzero camera pull. The small fixture only
  -- replaces map discovery and shader-independent camera state.
  local fixtureAPI=require("tests.ledge_terrain_fixture").new()
  fixtureAPI.modules.VoxelMeshDisk.available=function()return false end
  local map=fixtureAPI:map("ORDERED_AUX",4,4)
  for at=1,5000 do
    local x,z=(at%64)*8,math.floor(at/64)*8
    map.S.grassQuads[at]={{x,0,z},{x+8,0,z},{x+8,10,z},{x,10,z},u=0,v=0,shade=1}
  end
  fixtureAPI.Mesher.get(map,true)
  local grass=fixtureAPI.Mesher.grass(map)
  check(grass and grass.voxelMeshParts and #grass.voxelMeshParts==2,"real auxiliary mesher retains bounded split uploads")
  for _,part in ipairs(grass.voxelMeshParts)do
    check(P.ranges(part) and P.ranges(part).ordered,"every production grass part retains ordered clip bounds")
  end
  local camera=fixtureAPI.Camera
  for at=1,50 do
    local name=debug.getupvalue(camera.draw,at)
    if not name then break end
    if name=="active"then debug.setupvalue(camera.draw,at,true)
    elseif name=="activeShader"then debug.setupvalue(camera.draw,at,sh)end
  end
  camera.vp,camera.curveX,camera.curveZ,camera.curveK=vp,48,-40,0
  g.setCanvas({canvas,depthstencil=depth});g.setShader(sh)
  calls,indices=0,0
  camera.draw(fixture[1].new[2],nil,nil,10)
  check(indices<totals[fixture[1].new[2]],"production Voxel3D culls foliage with nonzero pull")
  camera.grassClearance({32,32,0},nil,16)
  calls,indices=0,0;camera.draw(fixture[1].new[2],nil,nil,10)
  check(calls==1 and indices==totals[fixture[1].new[2]],"deformed battle grass keeps full mesh for safe bounds")
  camera.grassClearance(nil,nil)
  calls,indices=0,0;camera.draw(fixture[1].new[2],nil,nil,10)
  check(indices<totals[fixture[1].new[2]],"clearing battle deformation restores ordinary foliage clipping")
  g.setShader();g.setCanvas()
  local mesh=fixture[1].new[2]
  mesh:setDrawRange(19,12)
  local first,count
  g.draw=function()error("injected draw failure")end
  local ok=pcall(P.draw,mesh,M.identity()) -- may be culled; test enclosing camera next
  local all=M.mul(M.ortho(-2048,2048,-2048,2048,1,4000),M.lookAt({0,1000,0},{0,0,0},{0,0,-1}))
  ok=pcall(P.draw,mesh,all)
  first,count=mesh:getDrawRange();g.draw=oldDraw
  check(not ok and first==19 and count==12,"ordered range restores caller clip after graphics exception")
  mesh:setDrawRange()
  write("results.json",require("src.link.Json").encode({checks=checks,renderer={g.getRendererInfo()},romUsed=false,
    settings={distance="FAR (all three adjacent maps retained)",canvas={320,240},pull=10,shadow="same synthetic sun camera"},
    comparisons=results,timings=timings,note="Production native PackedVoxelMesh and conservative Frustum with original synthetic connected-map terrain/foliage. CPU/wall timings use Mesa software GL, not Android FPS."}))
  print(checks.." FAR RENDER CHECKS PASSED")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas()
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
