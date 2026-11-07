-- jp.90: engine Assets plus an in-memory image registry.
-- The mod sandbox cannot write to the save dir, so Gen2Facade registers the
-- proxy tile sheets it bakes here under a virtual path.  Every other path
-- (all of Red's) falls straight through to src.render.Assets unchanged.
local V = ...
local Assets = require("src.render.Assets")

local VA = setmetatable({}, { __index = Assets })
local images = {}

function VA.put(path, imageData)
  images[path] = imageData
end

function VA.has(path)
  return images[path] ~= nil
end

function VA.imageData(path)
  local data = images[path]
  if data then return data:clone() end
  return Assets.imageData(path)
end

return VA
