-- Outdoor weather. Selection originally adapted from Voxel Ascendant (MIT),
-- 22c2bb5502290d4396aa3ab11d075ee2fb70e341; see ASCENDANT-FIELD-LICENSE.
-- The jp.43 presentation uses world geometry, never game RNG or save fields.
local V = ...
local Setting = V.require('ModSetting')
local W = { clock=0, AUTO_SECONDS=180, AUTO_BUCKETS=32, FADE_SECONDS=2.4,
  LIGHTNING_SECONDS=23, stats={weatherDraws=0} }
W.setting=Setting.new('weather','WEATHER',
  {'clear','auto','rain','snow','fog','storm'},
  {'CLEAR','AUTO','RAIN','SNOW','FOG','STORM'},2)
W.strengthSetting=Setting.new('weatherStrength','WEATHER STRENGTH',
  {.55,1,1.45},{'GENTLE','NORMAL','STRONG'},2)
W.lightningSetting=Setting.new('weatherLightning','LIGHTNING',
  {false,true},{'OFF','ON'},2)
local modes={'rain','snow','fog','storm'}
local COLD={INDIGO_PLATEAU=true,ROUTE_23=true}
local OUTSIDE={INDIGO_PLATEAU=true,ROUTE_23=true,ROUTE_10=true,ROUTE_9=true,
  ROUTE_4=true,ROUTE_3=true,CINNABAR_ISLAND=true,VIRIDIAN_FOREST=true,
  SAFARI_ZONE_CENTER=true,SAFARI_ZONE_EAST=true,SAFARI_ZONE_NORTH=true,
  SAFARI_ZONE_WEST=true,VERMILION_DOCK=true,SS_ANNE_BOW=true}
local function reduced()
  local game=require('src.core.Game')
  local o=game.save and game.save.options or {}
  return o.reduceMotion or o.jpReduceMotion
end
local function finite(x,fallback)
  if type(x)~='number' or x~=x or x==math.huge or x==-math.huge then return fallback end
  return x
end
local function id(map)return tostring(map and (map.id or map.def and map.def.id) or '')end
-- Also consumed by the battle's daylight rig; keep the outdoor contract.
function W.isOutdoor(map)
  if not (map and map.def) then return false end
  local d=map.def
  local outside=d.outdoor
  if outside==nil then outside=d.tileset=='OVERWORLD' end
  return outside==true or OUTSIDE[id(map)]==true
end
local current,from,target,started
local function zero()return {rain=0,snow=0,fog=0,storm=0}end
function W.setClock(value)
  W.clock=finite(value,0)%65521
  current,from,target,started=nil,nil,nil,nil
end
function W.update(dt)
  dt=finite(dt,0)
  if dt>0 and dt<.25 and not reduced() then W.clock=(W.clock+dt)%65521 end
end
function W.modeAt(map,selected,clock)
  if not W.isOutdoor(map) then return 'clear' end
  if selected~='auto' then
    for _,mode in ipairs(modes)do if mode==selected then return mode end end
    return 'clear'
  end
  -- One weather front across Kanto. A route ID must not reshuffle the sky
  -- at a connected boundary. The mountain's snow bias blends like any change.
  local period=math.floor(finite(clock,W.clock)/W.AUTO_SECONDS)
  local roll=(11+period*17)%W.AUTO_BUCKETS
  if roll==0 then return 'storm' end
  if roll<=2 then return 'fog' end
  if COLD[id(map)] and roll<=10 then return 'snow' end
  if roll<=8 or COLD[id(map)] and roll<=16 then return 'rain' end
  return 'clear'
end
function W.mode(map)
  return reduced() and 'clear' or W.modeAt(map,W.setting:get(),W.clock)
end
function W.frame(map)
  local selected=W.setting:get()
  local want=W.mode(map)
  -- Explicit OFF, rooms and reduced motion take effect immediately.
  if reduced() or not W.isOutdoor(map) or (selected~='auto' and want=='clear') then
    current,from,target,started=zero(),nil,'clear',W.clock
    return current
  end
  if not current then current=zero();if want~='clear' then current[want]=1 end;target=want end
  if from then
    local t=math.min(1,((W.clock-started)%65521)/W.FADE_SECONDS)
    t=t*t*(3-2*t)
    for _,m in ipairs(modes)do current[m]=from[m]*(1-t)+(m==target and t or 0)end
    if t>=1 then from=nil end
  end
  if want~=target then
    from={rain=current.rain,snow=current.snow,fog=current.fog,storm=current.storm}
    target,started=want,W.clock
  end
  return current
end
function W.lightning(clock)
  if not W.lightningSetting:get() or reduced() then return 0 end
  -- One soft distant pulse, no paired strobe or white-out.
  local t=(clock or W.clock)%W.LIGHTNING_SECONDS
  if t<7 or t>8.2 then return 0 end
  local a=math.sin((t-7)/1.2*math.pi)
  return .14*a*a
end
function W.prepare(state)
  local f=W.frame(state.map)
  V.require('WeatherParticles').observe(state)
  return f
end
local skyCache={}
function W.sky(sky,f)
  if not sky then return nil end
  local amount=math.min(.8,f.rain*.35+f.storm*.75+f.snow*.22+f.fog*.48)
  if amount<=0 then return sky end
  local key=math.floor(amount*32+.5)
  local function tone(c)
    local grey=c[1]*.24+c[2]*.52+c[3]*.24
    local a=key/32
    return {c[1]*(1-a)+grey*.65*a,c[2]*(1-a)+grey*.72*a,c[3]*(1-a)+grey*.8*a}
  end
  local color=tone(sky)
  sky[1],sky[2],sky[3]=color[1],color[2],color[3]
  if sky.bands then
    if skyCache.source~=sky.bands or skyCache.key~=key then
      local bands={};for i,c in ipairs(sky.bands)do bands[i]=tone(c)end
      skyCache={source=sky.bands,key=key,bands=bands}
    end
    sky.bands=skyCache.bands
  end
  sky.overcast=amount
  return sky
end
function W.bind(frame,sky)
  local C=V.require('Voxel3D')
  local amount=math.min(1,frame.fog+frame.rain*.20+frame.storm*.43+frame.snow*.18)
  if amount<=0 then return end
  V.require('Atmosphere').bind(love.graphics.getShader(),C.eye,C.focus,sky,
    amount*W.strengthSetting:get())
end
function W.draw(state,frame)
  return V.require('WeatherParticles').draw(state,frame,W.clock,W.strengthSetting:get())
end
-- A restrained exposure tint, after the world particles/glow, before HUD.
-- No screen-space precipitation and no rectangular fog bands.
function W.apply(canvas,map)
  if not canvas then return canvas end
  local f=W.frame(map)
  local strength=W.strengthSetting:get()
  local shade=math.min(.20,(f.rain*.05+f.storm*.14+f.snow*.014+f.fog*.022)*strength)
  local flash=W.lightning()*f.storm
  if shade+flash<=0 then return canvas end
  local g=love.graphics;local w,h=canvas:getDimensions()
  g.push('all')
  local ok,err=pcall(function()
    g.setCanvas(canvas);g.origin();g.setShader();g.setScissor();g.setDepthMode();g.setStencilTest()
    g.setBlendMode('alpha','alphamultiply')
    g.setColor(.31,.40,.51,shade);g.rectangle('fill',0,0,w,h)
    if flash>0 then g.setColor(.75,.82,1,flash);g.rectangle('fill',0,0,w,h)end
    W.stats.weatherDraws=W.stats.weatherDraws+1
  end)
  g.pop();W.lastError=not ok and tostring(err) or nil
  return canvas
end
function W.invalidate()
  V.require('WeatherParticles').invalidate()
  current,from,target,started=nil,nil,nil,nil
  skyCache={}
  W.lastError=nil
end
return W
