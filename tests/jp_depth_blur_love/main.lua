-- Synthetic GL depth/color/actor test: no game assets or ROM are loaded.
local function run()
  local root,out=assert(os.getenv("JP_QA_ROOT")),assert(os.getenv("JP_QA_OUT"))
  package.path=root.."/?.lua;"..package.path
  local g=love.graphics
  local V,modules={},{}
  function V.require(name)
    if not modules[name]then modules[name]=assert(loadfile(root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/"..name..".lua"))(V)end
    return modules[name]
  end
  local T=V.require("TiltShift")
  local Game={save={options={}}};package.loaded["src.core.Game"]=Game
  local checks=0
  local function check(ok,msg)assert(ok,msg);checks=checks+1;print("PASS "..msg)end
  local function write(name,bytes)local f=assert(io.open(out.."/"..name,"wb"));f:write(bytes);f:close()end
  local w,h=320,240
  local canvas=g.newCanvas(w,h,{dpiscale=1})
  canvas:setFilter("nearest","nearest")
  local depth=g.newCanvas(w,h,{dpiscale=1,format="depth24",readable=true})
  depth:setFilter("nearest","nearest")
  local near,far,focus=5,1000,100
  local scene=g.newShader([[
    uniform float depth;uniform float kind;
    #ifdef VERTEX
    vec4 position(mat4 tp,vec4 p){vec4 clip=tp*p;clip.z=(depth*2.0-1.0)*clip.w;return clip;}
    #endif
    #ifdef PIXEL
    vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
      float checker=mod(floor(sc.x/2.0)+floor(sc.y/2.0),2.0);
      if(kind<0.5)return vec4(vec3(.15+.7*checker),1.0);
      if(kind<1.5)return vec4(checker,.15,.8-checker*.4,1.0);
      return vec4(.1,checker,.1,1.0);
    }
    #endif
  ]])
  local function distance(d)return ((far+near-2*near*far/d)/(far-near)+1)*.5 end
  local farSurfaceDistance=300
  local function scenery()
    g.setCanvas({canvas,depthstencil=depth});g.clear(.1,.1,.1,1,0,1)
    g.setDepthMode("lequal",true);g.setShader(scene);g.setColor(1,1,1,1);g.setBlendMode("replace")
    scene:send("depth",distance(farSurfaceDistance));scene:send("kind",0);g.rectangle("fill",0,0,w,h)
    -- A nearby object at the TOP, proving depth rather than screen-y focus.
    scene:send("depth",distance(45));scene:send("kind",1);g.rectangle("fill",216,8,88,88)
    scene:send("depth",distance(60));g.rectangle("fill",16,176,288,48)
    g.setShader();g.setDepthMode();g.setCanvas()
  end
  local depthRead=g.newShader([[
    uniform LOVE_HIGHP_OR_MEDIUMP Image depthTex;
    vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){float d=Texel(depthTex,uv).r;
      return vec4(d,fract(d*256.0),fract(d*65536.0),1.0);}
  ]])
  local depthCopy=g.newCanvas(w,h,{dpiscale=1})
  local function depthBytes()
    g.push("all");g.setCanvas(depthCopy);g.setDepthMode();g.setShader(depthRead)
    depthRead:send("depthTex",depth);g.setColor(1,1,1,1);g.setBlendMode("replace");g.draw(canvas)
    g.pop();return depthCopy:newImageData():getString()
  end
  local function identicalRect(a,b,x,y,rw,rh)
    for yy=y,y+rh-1 do for xx=x,x+rw-1 do
      local ar,ag,ab,aa=a:getPixel(xx,yy);local br,bg,bb,ba=b:getPixel(xx,yy)
      if ar~=br or ag~=bg or ab~=bb or aa~=ba then return false end
    end end
    return true
  end
  local function variation(image,x,y,rw,rh)
    local sum,n=0,0
    for yy=y,y+rh-1 do for xx=x,x+rw-2 do
      local a,b,c=image:getPixel(xx,yy);local d,e,f=image:getPixel(xx+1,yy)
      sum=sum+math.abs(a-d)+math.abs(b-e)+math.abs(c-f);n=n+3
    end end
    return sum/n
  end
  local opts={near=near,far=far,focus=focus,amount=1}
  scenery();local original=canvas:newImageData()
  local depthBefore=depthBytes()
  T.setLevel(5)
  local targets={}
  local oldDraw=g.draw
  g.draw=function(...)
    local target=g.getCanvas();local tw,th=target:getDimensions()
    targets[#targets+1]={tw,th}
    return oldDraw(...)
  end
  check(T.battleBackground(canvas,depth,opts),"battle uses selected field level5")
  g.draw=oldDraw
  local softened=canvas:newImageData()
  check(#targets==4 and targets[1][1]==160 and targets[1][2]==120 and targets[2][1]==160 and targets[3][1]==160 and targets[4][1]==320,
    "level5 at240px uses half-resolution prefilter, contiguous horizontal/vertical kernel, full composite")
  check(identicalRect(original,softened,216,8,88,88),"near object at top is pixel-exact, proving depth masking")
  check(identicalRect(original,softened,16,176,288,48),"entire foreground remains pixel-exact")
  check(depthBytes()==depthBefore,"every sampled depth value remains unchanged by colour blur")
  local sharpVar=variation(original,24,24,144,104)
  local softVar=variation(softened,24,24,144,104)
  check(softVar<sharpVar*.2,"far checkerboard loses more than80percent high-frequency contrast")
  write("battle-depth-before.png",original:encode("png"):getString())
  write("battle-depth-after.png",softened:encode("png"):getString())
  -- Actor cards arrive only after blur. One card overlaps the near object:
  -- unchanged depth must still reject the hidden portion, and visible pixels
  -- must retain the exact authored checker pattern.
  local function actor()
    g.setCanvas({canvas,depthstencil=depth});g.setDepthMode("lequal",true);g.setShader(scene)
    scene:send("depth",distance(90));scene:send("kind",2);g.setColor(1,1,1,1);g.setBlendMode("replace")
    g.rectangle("fill",180,48,96,96);g.setShader();g.setDepthMode();g.setCanvas()
  end
  actor();local actorBlur=canvas:newImageData()
  scenery();actor();local actorRef=canvas:newImageData()
  check(identicalRect(actorRef,actorBlur,180,48,96,96),"subsequent actor is sharp with identical near-object occlusion")
  write("battle-sharp-actor.png",actorBlur:encode("png"):getString())
  Game.save.options.jpBattleBlur="strong";T.setLevel(0);scenery();local off=canvas:newImageData():getString()
  check(not T.battleBackground(canvas,depth,opts) and canvas:newImageData():getString()==off,"field OFF is exact in battle despite legacy strong value")
  T.setLevel(2);Game.save.options.jpBattleBlur="off";scenery();check(T.battleBackground(canvas,depth,opts),"shared level2 runs despite legacy off value")
  T.setLevel(5);scenery()
  check(T.battleBackground(canvas,depth,{near=near,far=far,focus=focus,amount=0}),"seamless initial frame processes with zero blend")
  check(canvas:newImageData():getString()==original:getString(),"wild entry starts pixel-identical before blur fades in")
  local changes={}
  for _,amount in ipairs({0,.25,.5,.75,1})do
    scenery();T.battleBackground(canvas,depth,{near=near,far=far,focus=focus,amount=amount})
    local image=canvas:newImageData();changes[#changes+1]=variation(image,24,24,144,104)
  end
  for i=2,#changes do check(changes[i]<changes[i-1],"encounter blur fades monotonically at step"..i)end
  scenery();check(T.battleBackground(canvas,nil,opts),"no-readable-depth fallback runs without framebuffer feedback")
  local fallback=canvas:newImageData()
  check(identicalRect(original,fallback,0,176,w,64),"strong depth fallback preserves nearest bottom region")
  -- World strengths retain level indices, keep the central half exact and
  -- allow a visibly broader radius at4/5 instead of the former3px clamp.
  scenery();local worldSource=canvas:newImageData()
  local world={}
  for level=0,5 do
    T.setLevel(level);local result=T.apply(canvas)
    check(T.level==level and T.levelLabel()==(level==0 and "OFF" or tostring(level)),"world saved strength index"..level.." remains valid")
    local image=result:newImageData();world[level]=image
    check(identicalRect(worldSource,image,0,60,w,120),"world sharp central half exact at level"..level)
    if level==5 then write("world-level5.png",image:encode("png"):getString())end
  end
  check(world[4]:getString()~=world[3]:getString() and world[5]:getString()~=world[4]:getString(),"both stronger world levels change pixels")
  -- GPU resources are stable after warmup and released on resize/invalidate.
  local allocations=0;local oldNew=g.newCanvas
  g.newCanvas=function(...)allocations=allocations+1;return oldNew(...)end
  for _=1,10 do T.apply(canvas);T.battleBackground(canvas,depth,opts)end
  g.newCanvas=oldNew;check(allocations==0,"world and battle cache separate targets without per-frame allocations")
  -- Restore all caller state, including filter and depth attachment.
  g.setCanvas({canvas,depthstencil=depth});g.setDepthMode("lequal",true);g.setShader(scene)
  g.setScissor(4,5,20,21);g.setColor(.2,.3,.4,.5);g.setBlendMode("alpha","premultiplied")
  canvas:setFilter("nearest","nearest")
  T.battleBackground(canvas,depth,opts)
  local mode,writes=g.getDepthMode();local sx,sy,sw,sh=g.getScissor();local r,gg,b,a=g.getColor()
  local restored=g.getCanvas()
  local function attachment(value)return type(value)=="table" and value[1] or value end
  local targetOkay=type(restored)=="table" and attachment(restored[1])==canvas and attachment(restored.depthstencil)==depth
  check(targetOkay and g.getShader()==scene and mode=="lequal" and writes,"battle blur restores depth target and shader")
  check(sx==4 and sy==5 and sw==20 and sh==21 and math.abs(r-.2)<1e-6 and math.abs(a-.5)<1e-6,"battle blur restores scissor and draw colour")
  check(canvas:getFilter()=="nearest","source nearest filter preserved")
  g.setCanvas();g.setShader();g.setDepthMode();g.setScissor();g.setColor(1,1,1,1)
  -- Close scenery, where jp21's STRONG shared NORMAL's deep focus region.
  farSurfaceDistance=125
  local contrasts={}
  for _,level in ipairs({0,2,5})do
    T.setLevel(level);scenery();T.battleBackground(canvas,depth,opts)
    contrasts[tostring(level)]=variation(canvas:newImageData(),24,24,144,104)
  end
  check(contrasts['5']>contrasts['0']*.75,"near-focus terrain no longer receives a separate strong battle mask")
  T.setLevel(5)
  farSurfaceDistance=300
  -- Compile the actual generated blur sources for GLES, in addition to
  -- executing their desktop programs above. This is not a device run.
  local shaderNew=g.newShader;local sources={}
  g.newShader=function(source,...)
    sources[source]=true;return shaderNew(source,...)
  end
  local fresh=assert(loadfile(root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/TiltShift.lua"))(V)
  fresh.setLevel(5);scenery();check(fresh.battleBackground(canvas,depth,opts),"fresh normal depth shader executes")
  fresh.setLevel(5);scenery();check(fresh.battleBackground(canvas,nil,opts),"fresh independent fallback executes")
  scenery();check(fresh.apply(canvas)~=canvas,"fresh field shader executes")
  g.newShader=shaderNew
  for source in pairs(sources)do
    local valid,why=g.validateShader(true,source)
    check(valid,"actual blur source validates for GLES: "..tostring(why or "ok"))
  end
  fresh.invalidate()
  local baselineGLES
  local oldPath=os.getenv('JP_QA_BLUR_BASELINE')
  if oldPath then
    g.newShader=function(source,...)
      if source:find('depthTex',1,true)then
        local valid,why=g.validateShader(true,source)
        baselineGLES={valid=valid,error=why}
      end
      return shaderNew(source,...)
    end
    local previous=assert(loadfile(oldPath))(V)
    Game.save.options.jpBattleBlur="strong"
    scenery();previous.battleBackground(canvas,depth,opts);previous.invalidate()
    g.newShader=shaderNew
    check(baselineGLES and not baselineGLES.valid
      and baselineGLES.error:find('precision qualifiers',1,true),
      'jp21 depth shader reproduces GLES effect parameter precision failure')
  end
  -- Simulate a GLES driver refusing the depth shader itself. The fallback
  -- must compile a different source with no depth declaration or sample.
  local failedDepth=false
  g.newShader=function(source,...)
    if source:find("depthTex",1,true) then
      failedDepth=true;error("QA depth program rejected")
    end
    return shaderNew(source,...)
  end
  local rejected=assert(loadfile(root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/TiltShift.lua"))(V)
  rejected.setLevel(5);scenery();local d0=depthBytes();local source=canvas:newImageData()
  local worked=rejected.battleBackground(canvas,depth,opts)
  g.newShader=shaderNew
  check(worked and failedDepth and rejected.lastBattleMode=="screen","depth compile rejection falls back to independent program")
  check(rejected.lastBattleError:find("QA depth program rejected",1,true),"depth compile error remains diagnosable")
  check(variation(canvas:newImageData(),24,4,144,20)<sharpVar*.2,"compile-rejected fallback visibly blurs upper background")
  check(depthBytes()==d0,"compile-rejected fallback preserves actor depth buffer")
  check(identicalRect(source,canvas:newImageData(),0,176,w,64),"compile-rejected fallback preserves lower foreground")
  rejected.invalidate()
  -- Simulate successful compilation but a driver refusing sampler/program
  -- binding at draw time; pcall must not silently switch the effect off.
  local depthProgram;local setShader=g.setShader
  g.newShader=function(source,...)
    local program=shaderNew(source,...)
    if source:find("depthTex",1,true)then depthProgram=program end
    return program
  end
  g.setShader=function(program)
    if program~=nil and program==depthProgram then error("QA depth bind rejected")end
    return setShader(program)
  end
  local bindFail=assert(loadfile(root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/TiltShift.lua"))(V)
  bindFail.setLevel(5);scenery();worked=bindFail.battleBackground(canvas,depth,opts)
  g.newShader,g.setShader=shaderNew,setShader
  check(worked and bindFail.lastBattleMode=="screen","depth program bind rejection falls back to independent program")
  check(bindFail.lastBattleError:find("QA depth bind rejected",1,true),"depth bind error remains diagnosable")
  check(variation(canvas:newImageData(),24,4,144,20)<sharpVar*.2,"bind-rejected fallback visibly blurs upper background")
  bindFail.invalidate()
  local quality=require("tests.jp23_blur_quality")(T,V,check,write)
  T.invalidate()
  write("results.json",require("src.link.Json").encode({checks=checks,romUsed=false,renderer={g.getRendererInfo()},
    farVariationBefore=sharpVar,farVariationAfter=softVar,entryVariation=changes,strongTargets=targets,
    quality=quality,closeBackgroundVariation=contrasts,glesValidatedSources=5,
    jp21DepthShaderGLES=baselineGLES,
    estimatedStrongTextureFetchPixels=160*120*(4+9*2)+320*240*2,
    jp22BattleStrongTextureFetchPixels=80*60*5*2+320*240*2,
    note="Actual GL colour/depth and post-blur actor draw. Far-only depth composite, unchanged foreground/depth/actor pixels. Shader sampling estimate excludes bandwidth/driver cost; no AndroidFPS claim."}))
  print(checks.." DEPTH BLUR CHECKS PASSED")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas()
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
