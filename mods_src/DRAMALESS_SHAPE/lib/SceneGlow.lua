-- Scenery highlights only. HUD/native move art never enters these targets.
-- Small, cached targets; failure leaves the original 3D scene available.
local V=...
local G={stats={allocations=0,draws=0},lastMode='off'}
local EXTRACT=[[
  uniform vec2 texel;
  vec3 bright(Image image,vec2 uv){
    vec3 rgb=Texel(image,uv).rgb;
    float l=dot(rgb,vec3(.299,.587,.114));
    return rgb*smoothstep(.52,.92,l);
  }
  vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
    vec2 d=texel*.75;
    vec3 rgb=bright(image,uv+vec2(-d.x,-d.y))+bright(image,uv+vec2(d.x,-d.y))
      +bright(image,uv+vec2(-d.x,d.y))+bright(image,uv+vec2(d.x,d.y));
    return vec4(rgb*.25,1.0)*c;
  }
]]
local BLUR=[[
  uniform vec2 stepUV;
  vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
    vec3 rgb=Texel(image,uv).rgb*.227027;
    rgb+=(Texel(image,uv+stepUV*1.384615).rgb+Texel(image,uv-stepUV*1.384615).rgb)*.316216;
    rgb+=(Texel(image,uv+stepUV*3.230769).rgb+Texel(image,uv-stepUV*3.230769).rgb)*.070270;
    return vec4(rgb,1.0)*c;
  }
]]
local extract,blur,slots
local function release(t)
  for _,c in ipairs(t or {})do c:release()end
end
local function compile()
  if extract==false then return false end
  if not extract then
    local ok,a=pcall(love.graphics.newShader,EXTRACT)
    if not ok then extract=false;G.error=tostring(a);return false end
    local yes,b=pcall(love.graphics.newShader,BLUR)
    if not yes then a:release();extract=false;G.error=tostring(b);return false end
    extract,blur=a,b;G.stats.allocations=G.stats.allocations+2
  end
  return true
end
-- jp.58: programs only, ahead of the first battle; targets stay lazy.
function G.warm()
  if V.require('Atmosphere').strength()>0 then compile() end
end
local function prepare(w,h)
  if not compile() then return end
  if slots and slots.w==w and slots.h==h then return slots end
  local made={w=w,h=h}
  for _,divisor in ipairs({2,4,4})do
    local ok,c=V.require('PixelCanvas').new(math.max(1,math.ceil(w/divisor)),math.max(1,math.ceil(h/divisor)))
    if not ok then release(made);G.error=tostring(c);return end
    c:setFilter('linear','linear');c:setWrap('clamp','clamp')
    made[#made+1]=c;G.stats.allocations=G.stats.allocations+1
  end
  release(slots);slots=made;return slots
end
function G.apply(canvas,amount)
  local strength=V.require('Atmosphere').strength()
  if not canvas or strength<=0 or (amount or 1)<=0 then G.lastMode='off';return false end
  local w,h=canvas:getDimensions();local s=prepare(w,h)
  if not s then G.lastMode='unavailable';return false end
  local g=love.graphics
  local min,mag,anisotropy=canvas:getFilter()
  g.push('all')
  local ok,err=pcall(function()
    g.origin();g.setScissor();g.setDepthMode();g.setStencilTest();g.setColor(1,1,1,1)
    g.setBlendMode('replace','premultiplied');canvas:setFilter('linear','linear')
    local function pass(target,input,program)
      g.setCanvas(target);g.setShader(program)
      g.draw(input,0,0,0,target:getWidth()/input:getWidth(),target:getHeight()/input:getHeight())
    end
    extract:send('texel',{1/w,1/h});pass(s[1],canvas,extract)
    blur:send('stepUV',{1/s[1]:getWidth(),0});pass(s[2],s[1],blur)
    blur:send('stepUV',{0,1/s[2]:getHeight()});pass(s[3],s[2],blur)
    -- No sampled depth attachment, depth writes or clear. Actors rendered
    -- after this in battle still see exactly the original terrain depth.
    g.setCanvas(canvas);g.setShader();g.setBlendMode('add','premultiplied')
    local power=.32*strength*math.max(0,math.min(1,amount or 1))
    g.setColor(power,power,power,0)
    g.draw(s[3],0,0,0,w/s[3]:getWidth(),h/s[3]:getHeight())
  end)
  canvas:setFilter(min,mag,anisotropy);g.pop()
  G.lastMode=ok and 'glow' or 'unavailable';G.error=not ok and tostring(err) or nil
  if ok then G.stats.draws=G.stats.draws+1 end
  return ok
end
function G.invalidate()
  release(slots);slots=nil
  if extract then extract:release();blur:release()end
  extract,blur=nil,nil
end
return G
