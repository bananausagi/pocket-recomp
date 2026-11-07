-- A bounded world-space batch, shared by field and battle presentation.
-- No ROM art, screen overlay, render target or per-particle GPU allocation.
local V=...
local P={LIMIT=128,stats={draws=0,allocations=0,vertices=0}}
local SHADER=[[
  varying float shape;
  #ifdef VERTEX
  attribute float ParticleShape;
  uniform mat4 fxVP;
  uniform vec3 fxCurve;
  vec4 position(mat4 transform_projection,vec4 v){
    shape=ParticleShape;
    vec2 d=v.xz-fxCurve.xy; v.y-=dot(d,d)*fxCurve.z;
    return fxVP*v;
  }
  #endif
  #ifdef PIXEL
  vec4 effect(vec4 color,Image tex,vec2 uv,vec2 sc){
    vec2 q=uv*2.0-1.0;
    float r=length(q), a=0.0;
    if(shape<0.5) a=max(0.0,1.0-r)*0.8;
    else if(shape<1.5) a=(1.0-smoothstep(0.11,0.23,abs(r-0.77)))*0.8;
    else if(shape<2.5) a=1.0-step(0.9,abs(q.x)*0.7+abs(q.y)*1.6);
    else if(shape<3.5) a=1.0-step(0.20,abs(q.x-(q.y>0.0?0.24:-0.24)));
    else if(shape<4.5) a=1.0-step(0.8,abs(q.x)*1.8+abs(q.y));
    else if(shape<5.5) a=(1.0-smoothstep(0.07,0.19,abs(r-0.7)));
    else if(shape<6.5) a=1.0-step(0.85,abs(q.x)+abs(q.y));
    else if(shape<7.5){
      float toe=length(vec2(q.x*1.7,(q.y+.28)*1.7));
      float heel=max(abs(q.x)*2.0,abs(q.y-.52)*3.2);
      a=1.0-smoothstep(.72,.95,min(toe,heel));
    }
    else if(shape<8.5) a=(1.0-smoothstep(.06,.16,min(abs(q.x),abs(q.y))))*(1.0-r);
    else a=pow(max(0.0,1.0-abs(q.x)),2.0)*sin(uv.y*3.14159265);
    if(a<0.01) discard;
    return vec4(color.rgb,color.a*a);
  }
  #endif
]]
local shader,mesh
local vertices={}
local corners={{-1,-1,0,1},{1,-1,1,1},{1,1,1,0},{-1,-1,0,1},{1,1,1,0},{-1,1,0,0}}
local function prepare()
  if shader==false then return false end
  if not shader then
    local ok,value=pcall(love.graphics.newShader,SHADER)
    shader=ok and value or false
    if not shader then return false end
    P.stats.allocations=P.stats.allocations+1
  end
  if not mesh then
    for i=1,P.LIMIT*6 do vertices[i]={0,0,0,0,0,1,1,1,0,0} end
    mesh=love.graphics.newMesh({{'VertexPosition','float',3},{'VertexTexCoord','float',2},
      {'VertexColor','float',4},{'ParticleShape','float',1}},vertices,'triangles','dynamic')
    P.stats.allocations=P.stats.allocations+1
  end
  return true
end
function P.draw(particles)
  if #particles==0 or not prepare() then return 0 end
  local v3=V.require('Voxel3D')
  if not v3.vp then return 0 end
  local view=V.require('Mat4').lookAt(v3.eye,v3.focus,{0,1,0})
  local n=math.min(P.LIMIT,#particles)
  for i=1,n do
    local p=particles[i]
    local age=1-p.life/p.total
    local size=p.size*(p.kind==1 and (0.4+age*2.3) or 1)
    local alpha=p.alpha*math.min(1,p.life*5)*math.min(1,(age+.06)*10)
    for j,c in ipairs(corners) do
      local x,y=c[1]*size,c[2]*size
      local row=vertices[(i-1)*6+j]
      if p.kind==1 or p.kind==7 then
        local angle=p.angle or 0;local c,s=math.cos(angle),math.sin(angle)
        row[1],row[2],row[3]=p.x+c*x+s*y,p.y,p.z-s*x+c*y
      elseif p.kind==9 then
        local f=(c[2]+1)*.5
        row[1],row[2],row[3]=p.x+view[1]*x+f*(p.beamX or 0),
          p.y+f*(p.height or 22),p.z+view[3]*x+f*(p.beamZ or 0)
      else
        row[1],row[2],row[3]=p.x+view[1]*x+view[5]*y,
          p.y+view[2]*x+view[6]*y,p.z+view[3]*x+view[7]*y
      end
      row[4],row[5]=c[3],c[4]
      row[6],row[7],row[8],row[9],row[10]=p.r,p.g,p.b,alpha,p.kind
    end
  end
  mesh:setVertices(vertices,1,n*6);mesh:setDrawRange(1,n*6)
  local g=love.graphics
  g.push('all')
  local ok,err=pcall(function()
    g.setShader(shader);g.setColor(1,1,1,1)
    g.setDepthMode('lequal',false);g.setMeshCullMode('none')
    g.setBlendMode('alpha','alphamultiply')
    shader:send('fxVP','row',v3.vp)
    shader:send('fxCurve',{v3.curveX or 0,v3.curveZ or 0,v3.curveK or 0})
    g.draw(mesh)
  end)
  g.pop()
  if not ok then error(err,0) end
  P.stats.draws=P.stats.draws+1;P.stats.vertices=n*6
  return n
end
function P.invalidate()
  if shader and shader.release then shader:release() end
  if mesh and mesh.release then mesh:release() end
  shader,mesh=nil,nil;vertices={}
end
return P
