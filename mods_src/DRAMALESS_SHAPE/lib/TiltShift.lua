-- One field/battle blur ladder. Prefilter before reducing resolution, then
-- use a contiguous Gaussian kernel: spreading a handful of taps across the
-- original image aliases pixel art into blocks and repeated silhouettes.
-- Battle compositing still runs before actors/HUD and retains scene depth.
local V = ...
local TiltShift = { level=0, LABELS={"OFF","1","2","3","4","5"},FOCUS_Y=.5 }
TiltShift.PRESETS={
  [1]={sigma=.0018,band=.14,range=.32,saturation=1.10},
  [2]={sigma=.0030,band=.10,range=.30,saturation=1.18},
  [3]={sigma=.0045,band=.07,range=.28,saturation=1.28},
  [4]={sigma=.0065,band=.06,range=.27,saturation=1.28},
  [5]={sigma=.0090,band=.05,range=.26,saturation=1.28},
}
-- Every reduction is at most 2x per axis. Four bilinear samples integrate
-- a [1,3,3,1] tent in each axis BEFORE decimation, including odd dimensions.
local PREFILTER=[[
  uniform vec2 texel;
  vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
    vec2 d=texel*.75;
    return (Texel(image,uv+vec2(-d.x,-d.y))+
            Texel(image,uv+vec2(d.x,-d.y))+
            Texel(image,uv+vec2(-d.x,d.y))+
            Texel(image,uv+vec2(d.x,d.y)))*.25*c;
  }
]]
-- Nine bilinear fetches cover ALL 17 neighbouring texels. Offset/weight
-- pairs are calculated from a normalized Gaussian; offsets never spread
-- neighbouring taps apart to imitate a larger radius. Larger radii use
-- another properly filtered pyramid level instead.
local GAUSSIAN=[[
  uniform vec2 stepUV;
  uniform float centerWeight;
  uniform vec4 pairWeights;
  uniform vec4 pairOffsets;
  vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
    vec4 sum=Texel(image,uv)*centerWeight;
    sum+=(Texel(image,uv+stepUV*pairOffsets.x)+Texel(image,uv-stepUV*pairOffsets.x))*pairWeights.x;
    sum+=(Texel(image,uv+stepUV*pairOffsets.y)+Texel(image,uv-stepUV*pairOffsets.y))*pairWeights.y;
    sum+=(Texel(image,uv+stepUV*pairOffsets.z)+Texel(image,uv-stepUV*pairOffsets.z))*pairWeights.z;
    sum+=(Texel(image,uv+stepUV*pairOffsets.w)+Texel(image,uv-stepUV*pairOffsets.w))*pairWeights.w;
    return sum*c;
  }
]]
local WORLD=[[
  uniform Image blurred;
  uniform float focusY; uniform float band; uniform float spread;
  uniform float saturation;
  vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
    vec4 original=Texel(image,uv);
    float amount=clamp((abs(uv.y-focusY)-band)/spread,0.0,1.0);
    amount*=amount;
    vec4 soft=Texel(blurred,uv);
    vec4 result=mix(original,soft,amount);
    float luma=dot(result.rgb,vec3(.299,.587,.114));
    result.rgb=mix(vec3(luma),result.rgb,saturation);
    return result*c;
  }
]]
local BATTLE=[[
  // LOVE declares effect() before this source. Changing default precision
  // here changes its parameter signature on GLES and fails to compile.
  // Qualify only depth arithmetic, leaving the engine's signature intact.
  uniform LOVE_HIGHP_OR_MEDIUMP Image depthTex;
  uniform LOVE_HIGHP_OR_MEDIUMP vec2 clipPlanes;
  uniform LOVE_HIGHP_OR_MEDIUMP float focusDistance;
  uniform LOVE_HIGHP_OR_MEDIUMP float fadeDistance;
  uniform float strength;
  vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
    LOVE_HIGHP_OR_MEDIUMP float depth=Texel(depthTex,uv).r;
    LOVE_HIGHP_OR_MEDIUMP float n=clipPlanes.x;
    LOVE_HIGHP_OR_MEDIUMP float f=clipPlanes.y;
    // Equivalent linear depth with no near*far product overflowing fp16.
    LOVE_HIGHP_OR_MEDIUMP float distance=n/max(0.000001,1.0-depth*(1.0-n/f));
    float amount=clamp((distance-focusDistance)/fadeDistance,0.0,1.0);
    amount=amount*amount*(3.0-2.0*amount)*strength;
    if(amount<=0.0)return vec4(0.0);
    vec4 soft=Texel(image,uv);
    return vec4(soft.rgb*amount,amount)*c;
  }
]]
-- A SEPARATE program: turning off a depth uniform cannot rescue a shader
-- which a GLES driver refused to compile/link. This path never mentions or
-- samples a depth texture and works with the internal depth-buffer fallback.
local BATTLE_FALLBACK=[[
  uniform float strength; uniform vec2 focusBand;
  vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
    float amount=clamp((focusBand.x-uv.y)/focusBand.y,0.0,1.0);
    amount=amount*amount*(3.0-2.0*amount)*strength;
    vec4 soft=Texel(image,uv);
    return vec4(soft.rgb*amount,amount)*c;
  }
]]
local shaders,slots,shaderErrors={},{},{}
local function rememberError(name,err)
  err=tostring(err)
  TiltShift.lastBattleError=name..": "..err
  if shaderErrors[name]==err then return end
  shaderErrors[name]=err
  local ok,log=pcall(require,"src.core.Logger")
  if ok and log and log.warn then log.warn("battle blur %s: %s",name,err)end
end
local function shader(name,source)
  if shaders[name]==nil then
    local ok,result=pcall(love.graphics.newShader,source)
    shaders[name]=ok and result or false
    if not ok then rememberError(name,result)end
  end
  return shaders[name] or nil
end
local function release(slot)
  if not slot then return end
  for _,canvas in ipairs(slot.chain or {})do canvas:release()end
  for _,key in ipairs({"b","output"})do
    if slot[key] and slot[key].release then pcall(slot[key].release,slot[key])end
  end
end
local function kernel(sigma)
  local weights,total={},0
  for i=0,8 do
    weights[i]=math.exp(-.5*i*i/(sigma*sigma))
    total=total+weights[i]*(i==0 and 1 or 2)
  end
  local pairs,offsets={},{}
  for i=1,4 do
    local a=i*2-1;local sum=weights[a]+weights[a+1]
    pairs[i]=sum/total
    offsets[i]=sum>0 and a+weights[a+1]/sum or a
  end
  return {center=weights[0]/total,weights=pairs,offsets=offsets}
end
local function canvases(name,w,h,preset,withOutput)
  local sigma=math.max(1.25,h*preset.sigma)
  local divisor=2
  while sigma/divisor>2.5 and divisor<16 do divisor=divisor*2 end
  local slot=slots[name]
  if slot and slot.w==w and slot.h==h and slot.divisor==divisor then
    if slot.sigma~=sigma then
      slot.kernel=kernel(math.max(.6,math.sqrt(math.max(0,sigma*sigma-(divisor*divisor-1)/4))/divisor))
      slot.sigma=sigma
    end
    return slot
  end
  local PixelCanvas=V.require("PixelCanvas")
  local created={w=w,h=h,divisor=divisor,chain={},sigma=sigma}
  local function allocate(rw,rh,linear)
    local ok,result=PixelCanvas.new(rw,rh)
    if not ok then return nil end
    result:setFilter(linear and "linear" or "nearest",linear and "linear" or "nearest")
    pcall(result.setWrap,result,"clamp","clamp")
    return result
  end
  local rw,rh=w,h
  for _=1,math.floor(math.log(divisor)/math.log(2)+.5)do
    rw,rh=math.max(1,math.ceil(rw/2)),math.max(1,math.ceil(rh/2))
    local canvas=allocate(rw,rh,true)
    if not canvas then release(created);return nil end
    created.chain[#created.chain+1]=canvas
  end
  created.rw,created.rh=rw,rh
  created.a=created.chain[#created.chain]
  created.b=allocate(rw,rh,true)
  if not created.b then release(created);return nil end
  if withOutput then
    created.output=allocate(w,h,false)
    if not created.output then release(created);return nil end
  end
  created.kernel=kernel(math.max(.6,math.sqrt(math.max(0,sigma*sigma-(divisor*divisor-1)/4))/divisor))
  release(slot);slots[name]=created
  return created
end
local function blur(canvas,slot,gaussian,prefilter)
  local g=love.graphics
  g.setColor(1,1,1,1);g.setBlendMode("replace","premultiplied")
  local input=canvas
  g.setShader(prefilter)
  for _,target in ipairs(slot.chain)do
    local iw,ih=input:getDimensions();local ow,oh=target:getDimensions()
    g.setCanvas(target);prefilter:send("texel",{1/iw,1/ih})
    g.draw(input,0,0,0,ow/iw,oh/ih)
    input=target
  end
  local k=slot.kernel
  g.setShader(gaussian)
  gaussian:send("centerWeight",k.center)
  gaussian:send("pairWeights",k.weights);gaussian:send("pairOffsets",k.offsets)
  g.setCanvas(slot.b);gaussian:send("stepUV",{1/slot.rw,0});g.draw(slot.a)
  g.setCanvas(slot.a);gaussian:send("stepUV",{0,1/slot.rh});g.draw(slot.b)
end
local function selectedLevel()
  -- Menu previews can draw while pipeline update is paused. Read the same
  -- live ladder the settings row edits, instead of one-frame-stale state or
  -- the retired separate jpBattleBlur option. Isolated renderers retain the
  -- explicit setLevel/update interface.
  local ok,pipelines=pcall(require,"src.render.Pipelines")
  if ok and pipelines.get("tiltshift")then
    return math.max(0,math.min(5,math.floor(tonumber(pipelines.level("tiltshift")) or 0)))
  end
  return TiltShift.level
end
function TiltShift.setLevel(level)TiltShift.level=math.max(0,math.min(5,math.floor(tonumber(level) or 0)))end
function TiltShift.update(_,level)TiltShift.setLevel(level)end
function TiltShift.levelLabel(level)return TiltShift.LABELS[(level or TiltShift.level)+1] or "OFF"end
function TiltShift.active()return TiltShift.level>0 end
function TiltShift.reset()TiltShift.level=0 end
function TiltShift.apply(canvas)
  local preset=TiltShift.PRESETS[selectedLevel()]
  if not (preset and canvas)then return canvas end
  local gaussian,compose=shader("gaussian",GAUSSIAN),shader("world",WORLD)
  local prefilter=shader("prefilter",PREFILTER)
  if not (gaussian and prefilter and compose)then return canvas end
  local w,h=canvas:getDimensions();local slot=canvases("world",w,h,preset,true)
  if not slot then return canvas end
  local g=love.graphics
  local min,mag,anisotropy=canvas:getFilter()
  g.push("all")
  local ok=pcall(function()
    g.origin();g.setScissor();g.setDepthMode();g.setStencilTest()
    canvas:setFilter("linear","linear");blur(canvas,slot,gaussian,prefilter)
    canvas:setFilter(min,mag,anisotropy)
    g.setCanvas(slot.output);g.setShader(compose)
    compose:send("blurred",slot.a);compose:send("focusY",TiltShift.FOCUS_Y)
    compose:send("band",preset.band);compose:send("spread",preset.range)
    compose:send("saturation",1+(preset.saturation-1)*V.require("Atmosphere").strength())
    g.draw(canvas)
  end)
  canvas:setFilter(min,mag,anisotropy);g.pop()
  return ok and slot.output or canvas
end
-- Blend only FAR pixels over the scene colour in-place. Depth is detached
-- while read, never cleared or overwritten, then reattached before actors.
function TiltShift.battleBackground(canvas,depth,options)
  if not canvas then return false end
  options=options or {}
  -- jp.91 D: an explicit options.level (Crystal arenas only) overrides the
  -- live ladder; Red's caller never passes one, so Red reads selectedLevel().
  local level=tonumber(options.level)
  level=level and math.max(0,math.min(5,math.floor(level))) or selectedLevel()
  local preset=TiltShift.PRESETS[level]
  if not preset then TiltShift.lastBattleMode="off";return false end
  -- jp.91 D: the presets size sigma by canvas height, which in Red is the
  -- window Red presents its 160x144 frame in at Red's own scale.  Crystal
  -- draws the same world frame into the same-sized canvas at its larger
  -- panel scale, so the identical pixel sigma covered less of the scenery;
  -- options.sigmaScale (Crystal arenas only, nil for Red) is the ratio of
  -- the two presentation scales and keeps the blur the same size against
  -- the scene.
  local sigmaScale=tonumber(options.sigmaScale)
  if sigmaScale and sigmaScale>0 and math.abs(sigmaScale-1)>1e-6 then
    local scaled={}
    for key,value in pairs(preset)do scaled[key]=value end
    scaled.sigma=preset.sigma*sigmaScale
    preset=scaled
  end
  local n,f=options.near,options.far
  local readable=depth and type(n)=="number" and type(f)=="number" and n>0 and f>n
  local gaussian=shader("gaussian",GAUSSIAN)
  local prefilter=shader("prefilter",PREFILTER)
  local compose=readable and shader("battle",BATTLE)
  if not compose then readable=false;compose=shader("battleFallback",BATTLE_FALLBACK)end
  if not (gaussian and prefilter and compose)then TiltShift.lastBattleMode="unavailable";return false end
  local w,h=canvas:getDimensions();local slot=canvases("battle",w,h,preset,false)
  if not slot then
    TiltShift.lastBattleMode="unavailable"
    rememberError("targets","could not allocate blur canvases")
    return false
  end
  local focus=math.max(1,tonumber(options.focus) or 100)
  local g=love.graphics
  local min,mag,anisotropy=canvas:getFilter()
  g.push("all")
  local strength=math.max(0,math.min(1,options.amount or 1))
  local function composite(useDepth,program)
    -- A sampled depth attachment is illegal on GLES even when writes are off.
    g.setCanvas(canvas);g.setShader(program);g.setBlendMode("alpha","premultiplied")
    if useDepth then
      program:send("depthTex",depth)
      program:send("clipPlanes",{n,f})
      program:send("focusDistance",focus*1.04)
      program:send("fadeDistance",math.max(32,focus*.72))
    else
      program:send("focusBand",{.48,.36})
    end
    program:send("strength",strength)
    g.draw(slot.a,0,0,0,w/slot.rw,h/slot.rh)
    TiltShift.lastBattleMode=useDepth and "depth" or "screen"
  end
  local ok,err=pcall(function()
    g.origin();g.setScissor();g.setDepthMode();g.setStencilTest()
    canvas:setFilter("linear","linear");blur(canvas,slot,gaussian,prefilter)
    local done,problem=pcall(composite,readable,compose)
    if not done and readable then
      rememberError("depth composite",problem)
      -- A driver can compile a program yet refuse the depth sampler bind.
      -- Disable only this session's depth variant; still preserve depth for
      -- actor occlusion after the independent colour-only fallback draw.
      shaders.battle=false
      compose=shader("battleFallback",BATTLE_FALLBACK)
      if compose then done,problem=pcall(composite,false,compose)end
    end
    if not done then error(problem,0)end
  end)
  canvas:setFilter(min,mag,anisotropy);g.pop()
  if not ok then TiltShift.lastBattleMode="unavailable";rememberError("render",err)end
  return ok
end
-- jp.58: the battle blur's shared programs, one per warm-up step, when blur
-- is on. The depth composite still compiles on the path that selects it.
TiltShift.BATTLE_WARM={"prefilter","gaussian"}
function TiltShift.warm(name)
  if not TiltShift.PRESETS[selectedLevel()] then return end
  local source=({prefilter=PREFILTER,gaussian=GAUSSIAN})[name]
  if source then shader(name,source)end
end
function TiltShift.invalidate()
  for _,slot in pairs(slots)do release(slot)end
  slots={}
end
return TiltShift
