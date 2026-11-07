-- Bounded, depth-tested weather: one reusable mesh, one draw, no canvas or
-- image assets. The deterministic lattice stays attached to connected maps.
local V=...
local P={LIMIT=768,stats={allocations=0,draws=0,particles=0},originX=0,originZ=0}
local shader,mesh,rows
local map,neighbors,data
local SHADER=[[
  varying float shape;
  #ifdef VERTEX
  attribute float WeatherShape;
  uniform mat4 weatherVP;
  uniform vec3 weatherCurve;
  vec4 position(mat4 transform_projection,vec4 p){
    shape=WeatherShape;
    vec2 d=p.xz-weatherCurve.xy;
    p.y-=dot(d,d)*weatherCurve.z;
    return weatherVP*p;
  }
  #endif
  #ifdef PIXEL
  vec4 effect(vec4 color,Image tex,vec2 uv,vec2 sc){
    vec2 p=uv*2.0-1.0;
    float a;
    if(shape<.5){
      // Tapered rain, faint at the top and brightest at its falling tip.
      a=(1.0-smoothstep(.28,1.0,abs(p.x)))*sin(uv.y*3.14159265);
    }else if(shape<1.5){
      // A small flake with a soft edge, not a solid white screen tile.
      a=1.0-smoothstep(.30,1.0,length(p));
    }else if(shape<2.5){
      float r=length(p);
      a=(1.0-smoothstep(.07,.21,abs(r-.73)))*.8;
    }else{
      // Ground mist, smooth on every edge, broken up inside the ellipse.
      a=pow(max(0.0,1.0-dot(p,p)),2.0);
      a*=.65+.35*sin(uv.x*12.0+sin(uv.y*8.0));
    }
    if(a*color.a<.002) discard;
    return vec4(color.rgb,a*color.a);
  }
  #endif
]]
local corners={{-1,-1,0,1},{1,-1,1,1},{1,1,1,0},
  {-1,-1,0,1},{1,1,1,0},{-1,1,0,0}}
local function prepare()
  if shader==false then return false end
  if not shader then
    local ok,value=pcall(love.graphics.newShader,SHADER)
    shader=ok and value or false
    if not ok then P.lastError=tostring(value);return false end
    P.stats.allocations=P.stats.allocations+1
  end
  if not mesh then
    rows={};for i=1,P.LIMIT*6 do rows[i]={0,0,0,0,0,1,1,1,0,0}end
    mesh=love.graphics.newMesh({{'VertexPosition','float',3},{'VertexTexCoord','float',2},
      {'VertexColor','float',4},{'WeatherShape','float',1}},rows,'triangles','dynamic')
    P.stats.allocations=P.stats.allocations+1
  end
  return true
end
function P.observe(state)
  local game=require('src.core.Game')
  if data~=game.data then map,neighbors=nil,nil;P.originX,P.originZ=0,0;data=game.data end
  if map and map~=state.map then
    local x,z
    for _,n in ipairs(neighbors or {})do
      if n.map==state.map then x,z=P.originX+n.ox,P.originZ+n.oy;break end
    end
    if not x then for _,n in ipairs(state.neighbors or {})do
      if n.map==map then x,z=P.originX-n.ox,P.originZ-n.oy;break end
    end end
    P.originX,P.originZ=x or 0,z or 0
  end
  map=state.map
  -- Snapshot; native neighbors may be updated in place on the next step.
  neighbors={}
  for _,n in ipairs(state.neighbors or {})do neighbors[#neighbors+1]={map=n.map,ox=n.ox,oy=n.oy}end
end
local function hash(x,z,salt)
  -- All products are exact small integers in Lua's double; no shared RNG.
  local n=(x*7381+z*19391+salt*8347)%65521
  return (n*n*13+n*17+23)%65521/65521
end
local function clamp(x)return math.max(0,math.min(1,x))end
local function surface(state,x,z)
  local function on(m,px,pz)
    local cx,cz=math.floor(px/16),math.floor(pz/16)
    if not (m and m.inBounds and m:inBounds(cx,cz)) then return nil end
    local water=m.isWaterCell and m:isWaterCell(cx,cz)
    local open=water or m.isWalkableCell and m:isWalkableCell(cx,cz)
    local y=0
    if m.cellTile then
      local shape=V.require('TileShape').forMap(m)[m:cellTile(cx,cz)]
      y=shape and shape.h or 0
    end
    return y,open
  end
  local y,open=on(state.map,x,z)
  if y~=nil then return y,open end
  for _,n in ipairs(state.neighbors or {})do
    y,open=on(n.map,x-n.ox,z-n.oy);if y~=nil then return y,open end
  end
  return 0,false
end
function P.draw(state,f,clock,strength)
  local rain=f.rain+f.storm;local mist=f.fog+f.storm*.13+f.rain*.05
  P.stats.particles=0
  if rain+f.snow+mist<.001 then return 0 end
  local C=V.require('Voxel3D')
  if not (C.vp and C.eye and C.focus) or not prepare() then return 0 end
  local view=V.require('Mat4').lookAt(C.eye,C.focus,{0,1,0})
  local cx,cz=C.focus[1]+P.originX,C.focus[3]+P.originZ
  local n=0
  local function quad(kind,x,y,z,sx,sy,alpha,lean)
    if n>=P.LIMIT or alpha<.002 then return end
    -- Avoid giant flakes/streaks immediately in front of a first-person eye.
    local distance=(x-C.eye[1])*(C.focus[1]-C.eye[1])+
      (y-C.eye[2])*(C.focus[2]-C.eye[2])+(z-C.eye[3])*(C.focus[3]-C.eye[3])
    if distance<=0 then return end
    n=n+1
    for j,c in ipairs(corners)do
      local xx,yy=c[1]*sx,c[2]*sy
      local r=rows[(n-1)*6+j]
      if kind==2 then r[1],r[2],r[3]=x+xx,y,z+yy
      elseif kind==0 then r[1],r[2],r[3]=x+view[1]*xx-(lean or 0)*yy,y+yy,z+view[3]*xx
      else r[1],r[2],r[3]=x+view[1]*xx+view[5]*yy,y+view[6]*yy,z+view[3]*xx+view[7]*yy end
      r[4],r[5]=c[3],c[4]
      r[6],r[7],r[8],r[9],r[10]=.72,.84,.96,alpha,kind
      if kind==1 then r[6],r[7],r[8]=.94,.97,1
      elseif kind==3 then r[6],r[7],r[8]=.66,.75,.79 end
    end
  end
  local gx,gz=math.floor(cx/12),math.floor(cz/12)
  local wind=.10+.10*f.storm+.025*math.sin(clock*.43)
  for iz=gz-13,gz+13 do for ix=gx-13,gx+13 do
    local r=hash(ix,iz,1);local s=hash(ix,iz,3)
    local wx,wz=(ix+.1+r*.8)*12,(iz+.1+s*.8)*12
    local edge=clamp((156-math.max(math.abs(wx-cx),math.abs(wz-cz)))/24)
    local x,z=wx-P.originX,wz-P.originZ
    local wet=hash(ix,iz,5)<math.min(.97,(f.rain*.65+f.storm*.92)*strength)
    local snow=hash(ix,iz,7)<math.min(.75,f.snow*.30*strength)
    if edge>0 and (wet or snow) then
      local ground,open=surface(state,x,z)
      if wet then
        local phase=(clock/(2.4+r*.5-f.storm*.7)+s)%1
        if phase<.86 then
          local height=(1-phase/.86)*80
          quad(0,x-wind*height,ground+height,z,.28+r*.10,2.0+f.storm*1.4,
            edge*rain*(.40+r*.22),wind)
        elseif open then
          local t=(phase-.86)/.14
          quad(2,x,ground+.24,z,.45+t*2.8,.45+t*2.8,edge*rain*.32*(1-t))
        end
      end
      if snow then
        local phase=(clock/(11+r*7)+s)%1
        local height=(1-phase)*76
        local sway=math.sin(clock*(.65+r*.5)+s*6.28)*3
        local a=edge*f.snow*.72*clamp(phase*12)*clamp((1-phase)*9)
        quad(1,x+sway,ground+height,z+math.cos(clock*.37+r*6)*2,.43+r*.55,.43+r*.55,a)
      end
    end
  end end
  if mist>.001 then
    local mx,mz=math.floor(cx/64),math.floor(cz/64)
    for iz=mz-2,mz+2 do for ix=mx-2,mx+2 do
      local wx=(ix+.5)*64+math.sin(clock*.09+iz)*13
      local wz=(iz+.5)*64+math.cos(clock*.07+ix)*10
      local distance=math.sqrt((wx-cx)^2+(wz-cz)^2)
      local a=mist*strength*.13*clamp((distance-22)/50)*clamp((200-distance)/65)
      quad(3,wx-P.originX,6+hash(ix,iz,9)*4,wz-P.originZ,44,9,a)
    end end
  end
  if n==0 then return 0 end
  mesh:setVertices(rows,1,n*6);mesh:setDrawRange(1,n*6)
  local g=love.graphics;g.push('all')
  local ok,err=pcall(function()
    g.setShader(shader);g.setColor(1,1,1,1);g.setDepthMode('lequal',false)
    g.setMeshCullMode('none');g.setBlendMode('alpha','alphamultiply')
    shader:send('weatherVP','row',C.vp)
    shader:send('weatherCurve',{C.curveX or 0,C.curveZ or 0,C.curveK or 0})
    g.draw(mesh)
  end)
  g.pop();P.lastError=not ok and tostring(err) or nil
  P.stats.particles=n;P.stats.draws=P.stats.draws+(ok and 1 or 0)
  return ok and n or 0
end
function P.invalidate()
  if shader and shader.release then shader:release()end
  if mesh then mesh:release()end
  shader,mesh,rows,map,neighbors,data=nil,nil,nil,nil,nil,nil
  P.originX,P.originZ=0,0;P.lastError=nil
end
return P
