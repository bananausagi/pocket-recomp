-- No ROM: exercise the real Dramaless projection and engine presentation.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
love.getVersion = function() return 11, 5, 0 end
local T = require("tests.harness")
local Renderer = require("src.render.Renderer")
local Position = require("src.core.ScreenPosition")
local Zoom = require("src.render.Zoom")
local mat = dofile("vendor/jp-mods/DRAMALESS_SHAPE/lib/Mat4.lua")
local voxel = { angle = 0, FOCAL = 1 }
local camera = assert(loadfile("vendor/jp-mods/DRAMALESS_SHAPE/lib/Voxel3D.lua"))({
  require = function(name)
    if name == "Mat4" then return mat end
    if name == "VoxelState" then return voxel end
    return {} -- unused lighting/assets; projection itself is the real mod code
  end,
})
local function project(m, w, h, x, z)
  local a, b = m[1]*x + m[3]*z + m[4], m[5]*x + m[7]*z + m[8]
  local d = m[13]*x + m[15]*z + m[16]
  return (a/d*.5+.5)*w, (b/d*.5+.5)*h
end
local function near(a,b,msg)
  T.check(math.abs(a-b)<0.0001,msg..": "..tostring(a).." vs "..tostring(b))
end
local output
love.graphics.draw = function(image,x,y,angle,sx,sy)
  if image.fixture then output={x=x,y=y,sx=sx,sy=sy} end
end
local cases = {
  {360,640,360,640}, {640,360,640,360}, {400,650,1080,1756},
  {500,710,1351,1917}, {220,360,440,720},
}
for _,size in ipairs(cases) do
  local w,h,pw,ph=unpack(size)
  love.graphics.getDimensions=function() return w,h end
  love.graphics.getPixelDimensions=function() return pw,ph end
  for _,mode in ipairs({"center","upper","top"}) do
    for _,zoom in ipairs({0,-1,1}) do
      Renderer:init(); Position.setMode(mode); Zoom.offset=zoom
      Renderer:beginFrame(true)
      local r=Renderer:frameRects()
      local vw,vh=Renderer:worldViewSize()
      local scale=Zoom.scale(r.Sp)
      -- Deliberately screen-sized (the original MOD's contract), even when
      -- the enlarged view has a different aspect ratio. The output owner
      -- must not mistake this storage resolution for the projected geometry.
      local scene=love.graphics.newCanvas(pw,ph);scene.fixture=true
      local fxScaleX,fxScaleY=Renderer.worldOverlayScale(scene,vw,vh,scale)
      local vp=camera.viewProjection(0,0,vw,vh)
      local x1,y1=project(vp,pw,ph,-8,-8)
      local x2,y2=project(vp,pw,ph,8,8)
      Renderer:setWorldOverride(scene,vw,vh)
      Renderer:endFrame()
      local tag=table.concat({pw,ph,mode,zoom},"/")
      T.check(output~=nil,tag.." composites pipeline scene")
      local dx,dy=pw/w,ph/h
      near((x2-x1)*output.sx*dx,16*scale,tag.." horizontal scale")
      near((y2-y1)*output.sy*dy,16*scale,tag.." vertical scale stays square")
      near(fxScaleX*output.sx*dx,scale,tag.." overlay effect horizontal scale")
      near(fxScaleY*output.sy*dy,scale,tag.." overlay effect vertical scale")
      local cx,cy=project(vp,pw,ph,0,0)
      T.check(math.abs((output.x+cx*output.sx)*dx-pw/2)<=1,
        tag.." horizontal centre remains fixed")
      T.check(math.abs((output.y+cy*output.sy)*dy-(ph/2-r.lift))<=1,
        tag.." vertical centre moves by position lift")
      T.check(Renderer.worldOverrideView==nil,tag.." presentation metadata cleared")
    end
  end
end
-- Screen-space battle providers retain their existing explicit composition.
Renderer:init(); Position.setMode("top"); Renderer:beginFrame(true)
local scene=love.graphics.newCanvas(1351,1917);scene.fixture=true
Renderer:setWorldOverride(scene,200,400)
Renderer:setWorldOverride(scene)
T.check(Renderer.worldOverrideView==nil,"battle override clears prior world geometry")
Renderer:endFrame()
near(output.x,0,"battle x unchanged");near(output.y,0,"battle y unchanged")
Renderer:setWorldOverride(scene,160,144);Renderer:beginFrame(true)
T.check(Renderer.worldOverrideView==nil,"new frame cannot inherit world metadata")
Renderer:setWorldOverride(scene,160,144);Renderer:releaseCanvases()
T.check(Renderer.worldOverrideView==nil,"new session cannot inherit world metadata")
Position.setMode("center");Zoom.offset=0
T.finish("japanese_world_position")
