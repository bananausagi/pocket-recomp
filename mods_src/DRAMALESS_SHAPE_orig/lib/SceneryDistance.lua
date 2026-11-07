-- Full original hulls beside the map; coarser, shared voxel hulls farther out.
-- Visual geometry only. Connection masks and walkable map bounds stay owned
-- by ChunkMesher/Map, so extending the forest cannot block a route or a warp.
local V=...
local M={stats={sourceQuads=0,distantQuads=0,templates=0}}
M.setting=V.require('ModSetting').new('borderDepth','OUTER SCENERY',
  {4,12,20},{'COMPACT','DEEP','WIDE'},2)
local Budget=V.require("BuildBudget")
local cache=setmetatable({},{__mode='k'})
function M.tiles()return M.setting:get()end
function M.quads(template,mx,mz,tw,th,r)
  r=r or 8
  local distance=math.max(-mx-r,mx-r-tw*8,-mz-r,mz-r-th*8)
  if distance<32 then return template.quads end
  local step=distance>=64 and 4 or 2
  local variants=cache[template]
  if not variants then variants={};cache[template]=variants end
  if variants[step] then return variants[step]end
  local out,seen={},{}
  for _,q in ipairs(template.quads)do
    local a={u=q.u,v=q.v,uv=q.uv,shade=q.shade}
    local signature={}
    for i=1,4 do
      local c={}
      for axis=1,3 do c[axis]=math.floor(q[i][axis]/step+.5)*step;signature[#signature+1]=c[axis]end
      a[i]=c
    end
    local ux,uy,uz=a[2][1]-a[1][1],a[2][2]-a[1][2],a[2][3]-a[1][3]
    local vx,vy,vz=a[3][1]-a[1][1],a[3][2]-a[1][2],a[3][3]-a[1][3]
    local area=math.abs(uy*vz-uz*vy)+math.abs(uz*vx-ux*vz)+math.abs(ux*vy-uy*vx)
    local key=table.concat(signature,',')
    if area>0 and not seen[key] then seen[key]=true;out[#out+1]=a end
    Budget.tick()
  end
  variants[step]=out
  M.stats.templates=M.stats.templates+1
  M.stats.sourceQuads=M.stats.sourceQuads+#template.quads
  M.stats.distantQuads=M.stats.distantQuads+#out
  return out
end
local previous
function M.check()
  local value=M.tiles()
  if previous and previous~=value then V.require('ChunkMesher').invalidate()end
  previous=value
end
return M
