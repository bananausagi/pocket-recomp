local function run()
  local root,out=assert(os.getenv("JP_QA_ROOT")),assert(os.getenv("JP_QA_OUT"))
  package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local g=love.graphics
  local Packed=require("src.render.PackedVoxelMesh")
  local M=assert(loadfile(root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/Mat4.lua"))()
  local Json=require("src.link.Json")
  local checks=0
  local function check(ok,label)assert(ok,label);checks=checks+1;print("PASS "..label)end
  local function write(name,bytes)local f=assert(io.open(out.."/"..name,"wb"));f:write(bytes);f:close()end
  local full,culled=Packed.new(nil,false),Packed.new(nil,true)
  local uv={{0,0},{1,0},{1,1},{0,1}}
  local function quad(c,shade)full.push(c,uv,shade);culled.push(c,uv,shade)end
  for z=-512,496,16 do for x=-512,496,16 do
    quad({{x,0,z},{x+16,0,z},{x+16,0,z+16},{x,0,z+16}},0.25+((x+z)%64)/96)
    if (x/16+z/16)%5==0 then
      local h=24+((x-z)%64)
      quad({{x+2,0,z+8},{x+14,0,z+8},{x+14,h,z+8},{x+2,h,z+8}},0.8)
      quad({{x+8,0,z+2},{x+8,0,z+14},{x+8,h,z+14},{x+8,h,z+2}},0.6)
    end
  end end
  local original,optimized=full.finish(),culled.finish()
  local sh=g.newShader([[
    varying float shade;
    uniform mat4 vp; uniform mat4 model; uniform vec3 curve;
    #ifdef VERTEX
    attribute float VertexShade;
    vec4 position(mat4 ignored, vec4 p) {
      vec4 w=model*p;
      if(curve.z>0.0){vec2 d=w.xz-curve.xy;w.y-=dot(d,d)*curve.z;}
      shade=VertexShade;return vp*w;
    }
    #endif
    #ifdef PIXEL
    vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){return vec4(shade,shade*0.8,shade*0.6,1.0);}
    #endif
  ]])
  local color=g.newCanvas(192,144,{dpiscale=1})
  local depth=g.newCanvas(192,144,{format="depth24",readable=false,dpiscale=1})
  local function draw(mesh,vp,model,k,useCull)
    g.setCanvas({color,depthstencil=depth});g.clear(0.05,0.1,0.2,1,0,1)
    g.setDepthMode("lequal",true);g.setMeshCullMode("none");g.setBlendMode("replace")
    g.setShader(sh);g.setColor(1,1,1,1)
    sh:send("vp","row",vp);sh:send("model","row",model);sh:send("curve",{0,0,k})
    if useCull then check(Packed.draw(mesh,vp,model,0,0,k),"optimized mesh handled")
    else g.draw(mesh)end
    g.setShader();g.setDepthMode();g.setCanvas();g.setBlendMode("alpha")
    check(not mesh:getDrawRange(),"draw range restored for later passes")
    return color:newImageData()
  end
  local views={}
  for _,angle in ipairs({0.01,0.5,1.0,1.309})do
    for _,offset in ipairs({-192,0,192})do
      local eye={offset,240*math.cos(angle),240*math.sin(angle)}
      local view=M.lookAt(eye,{offset,0,0},{0,math.sin(angle),-math.cos(angle)})
      views[#views+1]={name="orbit-"..angle.."-"..offset,
        vp=M.mul(M.perspective(0.65,192/144,1,4096),view)}
    end
  end
  for _,yaw in ipairs({0,math.pi/2,math.pi,math.pi*1.5})do
    views[#views+1]={name="first-person-"..yaw,
      vp=M.mul(M.perspective(1.1,192/144,1,4096),M.lookAt({0,28,0},{math.sin(yaw)*100,24,math.cos(yaw)*100},{0,1,0}))}
  end
  views[#views+1]={name="shadow-camera",vp=M.mul(M.ortho(-240,240,-240,240,1,1600),
    M.lookAt({350,500,250},{0,0,0},{0,1,0})),shadow=true}
  -- A reflected camera is covered too, although the live water pass only
  -- reflects a copy of the original camera's visible screen-space texture.
  views[#views+1]={name="reflection-camera",vp=M.mul(M.perspective(0.65,192/144,1,4096),
    M.lookAt({0,-180,160},{0,0,0},{0,-1,0}))}
  local models={M.identity(),M.translate(127,0,-65)}
  local renders=0
  for _,v in ipairs(views)do for _,k in ipairs(v.shadow and {0} or {0,0.18/144,0.02})do
    for _,model in ipairs(models)do
      local reference=draw(original,v.vp,model,k,false)
      local actual=draw(optimized,v.vp,model,k,true)
      check(reference:getString()==actual:getString(),v.name.." curve="..k.." exact full/cull pixels")
      renders=renders+1
      if renders==14 then write("curved-terrain.png",actual:encode("png"):getString())end
    end
  end end
  -- Positioning is applied after the world pass, so identical terrain stays
  -- identical for centered, upper and top canvas placement as well.
  local layoutVP=views[7].vp
  local Frustum=require("src.render.VoxelFrustum")
  local context=Frustum.prepare(layoutVP,M.identity(),0,0,0)
  local submitted,total=0,0
  for _,range in ipairs(Packed.ranges(optimized))do
    total=total+range.count
    if Frustum.test(range.bounds,context)then submitted=submitted+range.count end
  end
  check(submitted>0 and submitted<total/2,"representative view excludes most offscreen terrain indices")
  local ref=draw(original,layoutVP,M.identity(),0,false)
  local opt=draw(optimized,layoutVP,M.identity(),0,true)
  local refImage,optImage=g.newImage(ref),g.newImage(opt)
  for _,y in ipairs({0,36,72})do
    local function composite(image)
      local c=g.newCanvas(240,288,{dpiscale=1});g.setCanvas(c);g.clear(0,0,0,1)
      g.draw(image,24,y);g.setCanvas();return c:newImageData():getString()
    end
    check(composite(refImage)==composite(optImage),"screen placement y="..y.." unchanged")
  end
  local allVP=M.mul(M.ortho(-1024,1024,-1024,1024,1,2000),
    M.lookAt({0,800,0},{0,0,0},{0,0,-1}))
  local oldDraw=g.draw
  g.draw=function()error("injected graphics draw failure")end
  local ok=pcall(Packed.draw,optimized,allVP,M.identity(),0,0,0)
  g.draw=oldDraw
  check(not ok and not optimized:getDrawRange(),"draw exception restores full mesh range")
  optimized:setDrawRange(1,6)
  g.draw=function()error("injected graphics draw failure")end
  ok=pcall(Packed.draw,optimized,allVP,M.identity(),0,0,0)
  g.draw=oldDraw
  local first,count=optimized:getDrawRange()
  check(not ok and first==1 and count==6,"draw exception restores caller-owned range")
  optimized:setDrawRange()
  write("results.json",Json.encode({checks=checks,pixelComparisons=renders+3,romUsed=false,
    representativeIndices={submitted=submitted,full=total}}))
  print(checks.." VOXEL FRUSTUM PIXEL CHECKS PASSED")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas()
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
