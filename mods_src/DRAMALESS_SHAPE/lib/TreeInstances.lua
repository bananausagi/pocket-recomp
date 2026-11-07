-- Shared tree templates + placement streams, adapted from Voxel Ascendant
-- 22c2bb5502290d4396aa3ab11d075ee2fb70e341 (MIT; ASCENDANT-FIELD-LICENSE).
-- Exact per-quad seam clipping and AO stay with ChunkMesher. Drivers without
-- instancing use its existing paged expansion, with identical scenery depth.
local V=...
local M={stats={templates=0,placements=0}}
local Budget=V.require('BuildBudget')
local Packed=require('src.render.PackedVoxelMesh')
local supported
function M.available()
  if supported~=nil then return supported end
  local g=love.graphics
  local ok,caps=pcall(g.getSupported)
  supported=ok and caps.instancing==true and type(g.drawInstanced)=='function' and Packed.available() or false
  return supported
end
function M.reject()supported=false end
function M.new(job)return {byTemplate={},groups={},job=job}end
local function track(job,mesh)
  job.pendingAux=job.pendingAux or {};job.pendingAux[mesh]=true
end
function M.add(plan,quads,signature,flags,mx,mz,uvFor,shadeFor)
  local variants=plan.byTemplate[quads]
  if not variants then variants={};plan.byTemplate[quads]=variants end
  -- Bound each placement batch to the same 128px spatial cells as the
  -- original packed terrain, so off-screen forests can be skipped.
  signature=signature..':'..math.floor(mx/128)..','..math.floor(mz/128)
  local group=variants[signature]
  if not group then
    local sink=Packed.new(Budget.check,false)
    plan.job.pendingBuilds=plan.job.pendingBuilds or {};plan.job.pendingBuilds[sink]=true
    group={sink=sink,offsets={},bounds={math.huge,math.huge,math.huge,-math.huge,-math.huge,-math.huge}};variants[signature]=group
    plan.groups[#plan.groups+1]=group
    for qi,q in ipairs(quads)do
      if not flags or flags[qi]=='\1' then
        sink.push(q,uvFor(q),shadeFor(q,q.shade))
        for i=1,4 do for axis=1,3 do
          group.bounds[axis]=math.min(group.bounds[axis],q[i][axis])
          group.bounds[axis+3]=math.max(group.bounds[axis+3],q[i][axis])
        end end
      end
      Budget.tick()
    end
  end
  group.offsets[#group.offsets+1]={mx,0,mz}
  group.minX=math.min(group.minX or mx,mx);group.maxX=math.max(group.maxX or mx,mx)
  group.minZ=math.min(group.minZ or mz,mz);group.maxZ=math.max(group.maxZ or mz,mz)
end
local function leaf(mesh,source,offsets,bounds)
  local result={instanceMesh=mesh,instanceSource=source,instanceCount=#offsets,instanceBounds=bounds}
  local count=mesh:getVertexCount()
  function result:getVertexCount()assert(self.instanceMesh,'released tree instances');return count*self.instanceCount end
  function result:getVertex(i)
    local at=math.floor((i-1)/count)+1
    local x,y,z,u,v,s=mesh:getVertex((i-1)%count+1);local o=offsets[at]
    return x+o[1],y,z+o[3],u,v,s
  end
  function result:getVertexMap()
    local indices=mesh:getVertexMap();local out={}
    for i=0,self.instanceCount-1 do
      for _,n in ipairs(indices)do out[#out+1]=i*count+n end
    end
    return out
  end
  function result:release()
    if not self.instanceMesh then return end
    mesh:release();source:release();offsets={}
    self.instanceMesh,self.instanceSource=nil,nil
  end
  return result
end
function M.finish(plan)
  local parts={};local job=plan.job
  for _,group in ipairs(plan.groups)do
    local mesh=assert(group.sink.finish(),'empty tree template')
    job.pendingBuilds[group.sink]=nil;track(job,mesh)
    local offsets=group.offsets
    local source=love.graphics.newMesh({{'InstanceOffset','float',3}},offsets,'points','static')
    track(job,source)
    local ok,err=pcall(mesh.attachAttribute,mesh,'InstanceOffset',source,'perinstance')
    if not ok then error({treeInstancingUnsupported=true,message=tostring(err)},0)end
    local b=group.bounds
    local bounds={b[1]+group.minX,b[2],b[3]+group.minZ,b[4]+group.maxX,b[5],b[6]+group.maxZ}
    local item=leaf(mesh,source,offsets,bounds);track(job,item)
    job.pendingAux[mesh],job.pendingAux[source]=nil,nil
    parts[#parts+1]=item
    M.stats.templates=M.stats.templates+1;M.stats.placements=M.stats.placements+#offsets
    Budget.check()
  end
  return #parts>0 and V.require('MeshParts').new(parts) or nil
end
return M
