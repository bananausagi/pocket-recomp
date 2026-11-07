-- SPDX-License-Identifier: GPL-3.0-only
-- Session menus stop simulation. Keep that same completed picture behind the
-- menu instead of rendering the unchanged 3D world on every display refresh.
-- Controls/menu are drawn afterward and remain live. No quality setting moves.
local Viewport = require("src.render.GameViewport")
local PausedFrame = {}
local canvas, key, pending, valid
local revision = 0

function PausedFrame.invalidate()
  revision = revision + 1
  valid = false
end

function PausedFrame.release()
  Viewport.setOutputTarget(nil)
  if canvas and canvas.release then canvas:release() end
  canvas, key, pending, valid = nil, nil, nil, false
end

local function currentKey(game)
  local g = love.graphics
  local w,h = g.getDimensions()
  local pw,ph = w,h
  if g.getPixelDimensions then pw,ph = g.getPixelDimensions() end
  local r = Viewport.rect or {}
  local sx,sy,sw,sh
  if love.window and love.window.getSafeArea then
    sx,sy,sw,sh = love.window.getSafeArea()
  end
  return { menu=game.sessionMenu, revision=revision, w=w,h=h,pw=pw,ph=ph,
    x=r.x,y=r.y,vw=r.width,vh=r.height,viewport=Viewport.canvas,
    generation=Viewport.generation, stack=game.stack, states=game.stack.states,
    count=#game.stack.states, top=game.stack:top(),
    sx=sx,sy=sy,sw=sw,sh=sh }
end

local function same(a,b)
  if not a or not b then return false end
  for k,v in pairs(a) do if b[k] ~= v then return false end end
  for k,v in pairs(b) do if a[k] ~= v then return false end end
  return true
end

local function blit()
  local g=love.graphics
  g.setCanvas()
  g.push("all")
  g.origin()
  g.setScissor()
  g.setShader()
  g.setColor(1,1,1,1)
  g.setBlendMode("alpha","premultiplied")
  g.draw(canvas,0,0)
  g.pop()
end

-- Called after Viewport.begin. true means the complete game image is ready;
-- false leaves the normal draw path active (capturing it once when possible).
function PausedFrame.begin(game)
  pending=nil
  if not game.sessionMenu then
    if canvas then PausedFrame.release() end
    return false
  end
  local nextKey=currentKey(game)
  if valid and same(key,nextKey) then blit(); return true end
  local resized=not key or key.w~=nextKey.w or key.h~=nextKey.h
    or key.pw~=nextKey.pw or key.ph~=nextKey.ph
  if resized then
    PausedFrame.release()
    -- Remember unsupported/failed geometry too: do not retry an allocation
    -- every paused frame. Resizing or opening a new menu permits a new attempt.
    key=nextKey
    local ok,made=pcall(love.graphics.newCanvas,nextKey.w,nextKey.h)
    if not ok or not made then return false end
    local pw,ph=made:getDimensions()
    if made.getPixelDimensions then pw,ph=made:getPixelDimensions() end
    -- Some multi-display Android surfaces report different X/Y DPI. A LOVE
    -- canvas cannot represent both; retain live rendering instead of resampling.
    if pw~=nextKey.pw or ph~=nextKey.ph then
      if made.release then made:release() end
      return false
    end
    canvas=made
    canvas:setFilter("nearest","nearest")
  end
  if not canvas then return false end
  key,pending,valid=nextKey,true,false
  Viewport.setOutputTarget(canvas)
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0,0,0,1)
  return false
end

-- Runs before OS controls and the session menu, so they are never captured.
function PausedFrame.finish()
  if not pending then return end
  pending=nil
  Viewport.setOutputTarget(nil)
  valid=true
  blit()
end

return PausedFrame
