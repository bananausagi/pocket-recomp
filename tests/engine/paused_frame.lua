package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.modkit")
local V=require("src.render.GameViewport")
local P=require("src.render.PausedFrame")
local Runtime=require("src.mods.Runtime")
local Hooks=require("src.mods.Hooks")
Runtime.hooks=Hooks.new()
local g=love.graphics
local allocations,releases=0,0
local newCanvas=g.newCanvas
g.newCanvas=function(...)
  allocations=allocations+1
  local c=newCanvas(...)
  function c:release() releases=releases+1 end
  return c
end
local state={}
local game={stack={states={state},top=function(self)return self.states[#self.states]end}}
V.begin(1)
T.eq(P.begin(game),false,"live gameplay bypasses capture")
T.eq(allocations,0,"live gameplay creates no snapshot")
game.sessionMenu={}
T.eq(P.begin(game),false,"first paused frame runs normal rendering")
local first=V.outputTarget
T.eq(g.getCanvas(),first,"first paused frame targets snapshot")
V.setTarget()
T.eq(g.getCanvas(),first,"renderer final composition keeps snapshot target")
P.finish()
T.eq(V.outputTarget,nil,"capture clears target override")
T.eq(g.getCanvas(),nil,"capture presents to OS window")
T.eq(P.begin(game),true,"unchanged paused frame reuses completed image")
T.eq(allocations,1,"steady paused frames allocate nothing")
P.invalidate()
T.eq(P.begin(game),false,"settings changes request fresh pixels")
T.eq(V.outputTarget,first,"settings changes reuse allocated snapshot")
P.finish()
game.stack.states[2]={}
T.eq(P.begin(game),false,"state stack change invalidates background")
P.finish()
game.stack.states[2]=nil
T.eq(P.begin(game),false,"state removal invalidates background")
P.finish()
local hookRect={x=12,y=24,width=320,height=288}
Runtime.hooks:wrap("render.viewport",function()return hookRect end,0,"fixture")
V.begin(1)
T.eq(P.begin(game),false,"viewport layout change invalidates snapshot")
V.setTarget()
T.eq(g.getCanvas(),V.canvas,"internal viewport keeps its own target")
V.finish(game)
T.eq(g.getCanvas(),first,"viewport final composition targets snapshot")
P.finish()
T.eq(P.begin(game),true,"composed viewport is reusable")
hookRect.x=40
V.begin(1)
T.eq(P.begin(game),false,"viewport position change invalidates snapshot")
P.finish()
V.begin(2)
T.eq(P.begin(game),false,"viewport generation change invalidates snapshot")
P.finish()
love.window=love.window or {}
love.window.getSafeArea=function()return 0,12,640,552 end
T.eq(P.begin(game),false,"safe-area change invalidates snapshot")
P.finish()
local previous=releases
g.getDimensions=function()return 800,600 end
g.getPixelDimensions=function()return 800,600 end
V.begin(2)
T.eq(P.begin(game),false,"window resize requests a new capture")
T.eq(releases,previous+1,"resize releases old snapshot immediately")
P.finish()
g.getPixelDimensions=function()return 1200,900 end
V.begin(2)
T.eq(P.begin(game),false,"unsupported canvas DPI retains live rendering")
T.eq(V.outputTarget,nil,"unsupported DPI never redirects output")
local before=allocations
T.eq(P.begin(game),false,"unsupported DPI continues rendering")
T.eq(allocations,before,"unsupported DPI does not retry allocation every frame")
g.getPixelDimensions=function()return 800,600 end
V.begin(2)
T.eq(P.begin(game),false,"changed DPI retries matching capture")
P.finish()
game.sessionMenu=nil
previous=releases
T.eq(P.begin(game),false,"resuming returns to live rendering")
T.eq(releases,previous+1,"resuming releases GPU snapshot")
game.sessionMenu={}
P.begin(game);P.finish()
previous=releases
P.release()
T.eq(releases,previous+1,"session teardown releases snapshot")
P.release()
T.eq(releases,previous+1,"repeat teardown does not release twice")
T.eq(V.outputTarget,nil,"teardown removes capture target")
V.reset()
T.finish("paused frame")
