-- A small native LCD grid pass. No downloads or shader conversion bridge.
-- Runs before the touch controls and keeps the current color palette intact.
local DotMatrix = { level = 0 }
local shader, failed
local SOURCE = [[
extern vec2 gridOrigin;
extern vec2 gridPitch;
extern float gridStrength;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
  vec2 cell = mod(pixel - gridOrigin, gridPitch);
  vec2 gap = max(vec2(1.0), gridPitch * 0.12);
  vec2 edge = step(gridPitch - gap, cell);
  float mask = max(edge.x, edge.y);
  return vec4(0.0, 0.0, 0.0, mask * gridStrength * color.a);
}
]]
function DotMatrix.setLevel(value)
  DotMatrix.level = math.max(0, math.min(3, math.floor(tonumber(value) or 0)))
end
function DotMatrix.applyOptions(opts) DotMatrix.setLevel(opts and opts.jpDotMatrix) end
function DotMatrix.draw(rect)
  if DotMatrix.level == 0 or failed or not rect then return end
  local pitch = rect.uiPixelScale or rect.scale or 1
  -- A seam cannot fit inside a one-pixel cell; fade it out at small scales.
  local visibility = math.max(0, math.min(1, (pitch - 1) / 2))
  if visibility == 0 then return end
  if not shader then
    local ok, result = pcall(love.graphics.newShader, SOURCE)
    if not ok then
      failed = true
      require("src.core.Logger").warn("LCD grid unavailable: %s", tostring(result))
      return
    end
    shader = result
  end
  local g = love.graphics
  g.push("all")
  g.origin()
  g.setShader(shader)
  g.setBlendMode("alpha")
  g.setColor(1, 1, 1, 1)
  shader:send("gridOrigin", {
    (rect.uiX or rect.gameX or 0) * (rect.dpiX or 1),
    (rect.uiY or rect.gameY or 0) * (rect.dpiY or 1) })
  shader:send("gridPitch", { pitch, pitch })
  shader:send("gridStrength", ({ 0.18, 0.30, 0.44 })[DotMatrix.level] * visibility)
  local x, y = rect.viewX or 0, rect.viewY or 0
  local w, h = rect.viewWidth or rect.width, rect.viewHeight or rect.height
  g.setScissor(x, y, w, h)
  g.rectangle("fill", x, y, w, h)
  g.pop()
end
return DotMatrix
