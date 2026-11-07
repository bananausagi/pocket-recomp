-- Shared, explicitly owned mesh pages. A full area reuses its body pages;
-- releasing/replacing either cache slot cannot free pages still in the other.
local M={}
function M.new(children)
  local parts={}
  for _,child in ipairs(children)do
    if type(child)=='table' and child.voxelMeshParts then
      for _,p in ipairs(child.voxelMeshParts)do parts[#parts+1]=p end
    else parts[#parts+1]=child end
  end
  local group={voxelMeshParts=parts}
  local refs=1
  function group:retain()
    assert(refs>0,'released mesh group');refs=refs+1;return self
  end
  function group:release()
    if refs==0 then return end
    refs=refs-1;if refs>0 then return end
    for _,child in ipairs(children)do pcall(child.release,child)end
    children={};self.voxelMeshParts={}
  end
  function group:getVertexCount()
    local n=0;for _,p in ipairs(self.voxelMeshParts)do n=n+p:getVertexCount()end;return n
  end
  function group:getVertex(i)
    for _,p in ipairs(self.voxelMeshParts)do
      local n=p:getVertexCount();if i<=n then return p:getVertex(i)end;i=i-n
    end
    error('vertex index out of range')
  end
  function group:getVertexMap()
    local out,base={},0
    for _,p in ipairs(self.voxelMeshParts)do
      for _,index in ipairs(p:getVertexMap() or {})do out[#out+1]=index+base end
      base=base+p:getVertexCount()
    end
    return out
  end
  return group
end
function M.wrap(mesh)
  if not mesh then return nil end
  if type(mesh)=='table' and mesh.retain then return mesh end
  return M.new({mesh})
end
function M.join(body,ring)
  if not body then return M.wrap(ring)end
  body:retain()
  if not ring then return body end
  return M.new({body,ring})
end
return M
