-- Exact screen-to-texture and depth interpolation for the two real card
-- triangles. Uses the captured alpha, never a rectangular scenery cutout.
local V=...
local M={}
local corners={{-.5,0,0,1},{.5,0,1,1},{.5,1,1,0},{-.5,1,0,0}}
local function row(a,b,c,va,vb,vc)
  local d=a.x*(b.y-c.y)+b.x*(c.y-a.y)+c.x*(a.y-b.y)
  if math.abs(d)<1e-8 then return nil end
  return {(va*(b.y-c.y)+vb*(c.y-a.y)+vc*(a.y-b.y))/d,
    (va*(c.x-b.x)+vb*(a.x-c.x)+vc*(b.x-a.x))/d,
    (va*(b.x*c.y-c.x*b.y)+vb*(c.x*a.y-a.x*c.y)+vc*(a.x*b.y-b.x*a.y))/d}
end
function M.project(card,v3,width,height)
  local model,vp=card.model,v3.vp
  local curve=V.require('WorldCurve')
  local points={}
  for i,p in ipairs(corners)do
    local x=model[1]*p[1]+model[2]*p[2]+model[4]
    local y=model[5]*p[1]+model[6]*p[2]+model[8]
    local z=model[9]*p[1]+model[10]*p[2]+model[12]
    y=y-curve.drop(v3.curveK or 0,v3.curveX or 0,v3.curveZ or 0,x,z)
    local ex,ey,ez=v3.eye[1]-x,v3.eye[2]-y,v3.eye[3]-z
    local n=math.sqrt(ex*ex+ey*ey+ez*ez)
    local pull=card.pull or 0
    if n>1e-8 then x,y,z=x+ex/n*pull,y+ey/n*pull,z+ez/n*pull end
    local cx=vp[1]*x+vp[2]*y+vp[3]*z+vp[4]
    local cy=vp[5]*x+vp[6]*y+vp[7]*z+vp[8]
    local cz=vp[9]*x+vp[10]*y+vp[11]*z+vp[12]
    local cw=vp[13]*x+vp[14]*y+vp[15]*z+vp[16]
    if cw<=1e-5 then return nil end
    points[i]={x=(cx/cw*.5+.5)*width,y=(cy/cw*.5+.5)*height,
      z=cz/cw*.5+.5,u=p[3]/cw,v=p[4]/cw,q=1/cw}
  end
  local out={}
  for i,ids in ipairs({{1,2,3},{1,3,4}})do
    local a,b,c=points[ids[1]],points[ids[2]],points[ids[3]]
    local u=row(a,b,c,a.u,b.u,c.u)
    if not u then return nil end
    local v,q=row(a,b,c,a.v,b.v,c.v),row(a,b,c,a.q,b.q,c.q)
    out[i]={uv={u[1],u[2],u[3],v[1],v[2],v[3],q[1],q[2],q[3]},
      depth=row(a,b,c,a.z,b.z,c.z)}
  end
  return out
end
return M
