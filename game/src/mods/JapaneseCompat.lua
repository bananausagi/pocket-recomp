-- Narrow runtime adapters for unmodified published mods. Archives, manifests,
-- saved options and global engine/graphics tables are never rewritten.
local GameVersion = require("src.core.GameVersion")
local JapaneseCompat = {}

function JapaneseCompat.chunkEnvironment(manifest, path)
  if GameVersion.get() ~= "red_jp" or not manifest
      or manifest.id ~= "DRAMALESS_SHAPE" or manifest.version ~= "2.0.4" then
    return nil
  end
  local target = "@" .. path .. "/lib/VoxelBattleScene.lua"
  return function(env, name)
    if name ~= target then return env end
    local child = setmetatable({}, { __index = env })
    local renderer, rendererView, loveView, graphicsView
    local function rects()
      renderer = renderer or env.require("src.render.Renderer")
      return renderer:frameRects()
    end
    child.require = function(module, ...)
      local actual = env.require(module, ...)
      if module ~= "src.render.Renderer" then return actual end
      if not rendererView then
        rendererView = setmetatable({ fitScale = function()
          -- The battle scene's camera must agree with the UI's presentation
          -- scale, including classic battles at a non-integer fill scale.
          local r = rects()
          return r and r.Up or actual:fitScale()
        end }, { __index = actual })
      end
      return rendererView
    end
    if env.love and env.love.graphics then
      graphicsView = setmetatable({}, { __index = env.love.graphics })
      graphicsView.getPixelDimensions = function()
        local r = rects()
        return math.max(1, math.floor(r.pw)), math.max(1, math.floor(r.ph))
      end
      graphicsView.getDimensions = function()
        local r = rects()
        return r.pw / r.dpiX, r.ph / r.dpiY
      end
      graphicsView.getWidth = function() return (graphicsView.getDimensions()) end
      graphicsView.getHeight = function() local _, h=graphicsView.getDimensions();return h end
      loveView = setmetatable({ graphics = graphicsView }, { __index = env.love })
      child.love = loveView
    end
    child._G = child
    return child
  end
end

return JapaneseCompat
