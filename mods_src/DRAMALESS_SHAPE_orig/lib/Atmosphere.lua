-- Shared scenery preference for depth haze, highlight glow and contact.
local V = ...
local Atmosphere = { stats = { allocations=0, contactDraws=0, fullScreenPasses=0 } }

function Atmosphere.strength()
  local game=require('src.core.Game')
  if not (game.data and game.data.constants and game.data.constants.language=='ja') then return 0 end
  local choice=game.save and game.save.options and game.save.options.jpAtmosphere
  return choice=='off' and 0 or choice=='gentle' and .35 or 1
end
function Atmosphere.enabled()
  return Atmosphere.strength()>0
end

-- Only outdoor scenes get distance haze. Use the same already palette-
-- transformed horizon colour as the sky, including GB and night modes.
-- Indoors still gets the soft face light, without a blue veil in rooms.
function Atmosphere.bind(shader, eye, focus, sky, weather)
  local dx,dy,dz=focus[1]-eye[1],focus[2]-eye[2],focus[3]-eye[3]
  local distance=math.max(1,math.sqrt(dx*dx+dy*dy+dz*dz))
  local strength=Atmosphere.strength()
  local enabled=strength>0
  local start=math.max(72,distance*.95)
  local spread=math.max(128,distance*1.15)
  local color=sky or {0,0,0}
  local opacity=enabled and sky and (.18+.18*strength) or 0
  if weather and weather>0 and sky then
    local amount=math.min(1,weather)
    enabled=true
    start=start*(1-amount*.40)
    spread=spread*(1-amount*.26)
    opacity=math.min(.76,opacity+(1-opacity)*amount*.66)
    -- The same day/night/palette horizon under a desaturated wet atmosphere.
    color={color[1]*.68+.21,color[2]*.68+.24,color[3]*.68+.26}
  end
  pcall(shader.send,shader,'atmosphere',{enabled and 1 or 0,start,spread,
    opacity})
  pcall(shader.send,shader,'atmosphereColor',{color[1],color[2],color[3]})
  pcall(shader.send,shader,'atmosphereView',{dx/distance,dy/distance,dz/distance})
end

function Atmosphere.solidGround(map,x,z)
  if not (map and type(map.isWaterCell)=='function') then return false end
  local cx,cy=math.floor(x/16),math.floor(z/16)
  if type(map.inBounds)=='function' and not map:inBounds(cx,cy) then return false end
  return not map:isWaterCell(cx,cy)
end

local CONTACT = [[
  #ifdef VERTEX
  uniform mat4 contactVP;
  uniform vec4 contactPlace;
  uniform vec3 contactCurve;
  vec4 position(mat4 transform_projection,vec4 vertex_position){
    vec3 w=vec3(contactPlace.x+vertex_position.x*contactPlace.w,
      contactPlace.y,contactPlace.z+vertex_position.z*contactPlace.w*.62);
    vec2 offset=w.xz-contactCurve.xy;
    w.y-=dot(offset,offset)*contactCurve.z;
    return contactVP*vec4(w,1.0);
  }
  #endif
  #ifdef PIXEL
  vec4 effect(vec4 color,Image image,vec2 uv,vec2 sc){
    vec2 p=uv*2.0-1.0;
    float a=max(0.0,1.0-dot(p,p));
    return vec4(color.rgb,color.a*a*a);
  }
  #endif
]]
local shader,quad
local place,curve={0,0,0,1},{0,0,0}
local function prepare()
  if shader==false then return false end
  if not shader then
    local ok,result=pcall(love.graphics.newShader,CONTACT)
    shader=ok and result or false
    if not shader then return false end
    Atmosphere.stats.allocations=Atmosphere.stats.allocations+1
  end
  if not quad then
    local ok,result=pcall(love.graphics.newMesh,
      {{'VertexPosition','float',3},{'VertexTexCoord','float',2}},
      {{-1,0,-1,0,0},{1,0,-1,1,0},{1,0,1,1,1},{-1,0,1,0,1}},'fan','static')
    if not ok then return false end
    quad=result;Atmosphere.stats.allocations=Atmosphere.stats.allocations+1
  end
  return true
end

-- A small analytic ellipse at the actual ground plane, with transparent
-- smooth edges. No texture/alpha cutoff, no depth writes or actor shading.
function Atmosphere.drawContact(x,ground,z,radius,opacity)
  if not Atmosphere.enabled() or not V.require('Shadows').enabled()
      or not love.graphics or (opacity or 1)<=0 or not prepare() then return false end
  local v3=V.require('Voxel3D')
  if not v3.vp then return false end
  local g=love.graphics
  place[1],place[2],place[3],place[4]=x,ground+.20,z,math.max(1,radius or 4)
  curve[1],curve[2],curve[3]=v3.curveX or 0,v3.curveZ or 0,v3.curveK or 0
  g.push('all')
  local ok=pcall(function()
    g.setShader(shader);g.setDepthMode('lequal',false)
    g.setBlendMode('alpha','alphamultiply');g.setMeshCullMode('none')
    g.setColor(.08,.09,.12,.22*math.min(1,opacity or 1))
    shader:send('contactVP','row',v3.vp)
    shader:send('contactPlace',place);shader:send('contactCurve',curve)
    g.draw(quad)
  end)
  g.pop()
  if ok then Atmosphere.stats.contactDraws=Atmosphere.stats.contactDraws+1 end
  return ok
end

-- jp.58: compile the contact program before the first battle needs it.
function Atmosphere.warm()
  if Atmosphere.enabled() and V.require('Shadows').enabled() then prepare() end
end

function Atmosphere.invalidate()
  if shader and shader.release then shader:release() end
  if quad and quad.release then quad:release() end
  shader,quad=nil,nil
end
return Atmosphere
