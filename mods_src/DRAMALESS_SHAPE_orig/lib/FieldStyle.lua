-- Compact-house proportions adapted from Ascendant; independently selectable.
local V=...
local M={}
M.height=V.require('ModSetting').new('buildingHeight','HOUSE HEIGHT',
  {1,1.4},{'ORIGINAL','TALL'},2)
local previous
function M.check()
  local value=M.height:get()
  if previous and previous~=value then
    V.require('Buildings').invalidate();V.require('ChunkMesher').invalidate()
  end
  previous=value
end
return M
