local function run()
  local root, output = assert(os.getenv("JP_QA_ROOT")), assert(os.getenv("JP_QA_OUT"))
  package.path = root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local g = love.graphics
  local Input = require("src.core.Input")
  local TC = require("src.core.TouchControls")
  local Json = require("src.link.Json")
  local Style = require("src.core.TouchControlsStyle")
  local checks, frames = 0, {}
  local function check(value, name)
    assert(value, name); checks = checks + 1; print("PASS "..name)
  end
  local function write(name, content)
    local f=assert(io.open(output.."/"..name,"wb")); f:write(content); f:close()
  end
  local function image(canvas, name)
    local d = canvas:newImageData()
    if name then write(name..".png",d:encode("png"):getString()) end
    return d
  end
  local function background(w,h,mode)
    if mode=="white" then g.clear(1,1,1,1)
    elseif mode=="dark" then g.clear(0.025,0.025,0.025,1)
    else
      g.clear(0.45,0.57,0.33,1)
      for y=0,h,24 do for x=0,w,24 do
        g.setColor((x+y)%48==0 and 0.36 or 0.44,0.52,0.28,1)
        g.rectangle("fill",x,y,24,24)
        g.setColor(0.22,0.37,0.15,1)
        g.rectangle("fill",x+5,y+8,2,7); g.rectangle("fill",x+9,y+5,2,8)
      end end
      g.setColor(1,1,1,1)
      g.rectangle("fill",24,math.floor(h*.38),w-48,76)
      g.setColor(0,0,0,1);g.setLineWidth(2)
      g.rectangle("line",28,math.floor(h*.38)+4,w-56,68)
      g.rectangle("line",32,math.floor(h*.38)+8,w-64,60)
      g.setFont(g.newFont(18));g.print("ROM-free display fixture",44,math.floor(h*.38)+28)
    end
  end
  local function render(w,h,mode,name)
    local c=g.newCanvas(w,h,{dpiscale=1})
    g.push("all");g.setCanvas(c);g.origin();background(w,h,mode);TC:draw();g.pop()
    return image(c,name)
  end
  local cases={{320,480,"white"},{480,800,"world"},{800,480,"world"},
    {480,800,"dark"},{800,480,"white"},{972,1536,"world"}}
  for _, case in ipairs(cases) do
    local w,h,mode=unpack(case)
    assert(love.window.setMode(w,h,{vsync=0,resizable=false}))
    Input:init();TC:init();TC.active=true;TC:ensureImages()
    TC:applyOptions({hotbar=false,touchControls={enabled=true}})
    local L=TC:layout()
    check(TC:visible() and not TC.skinId,"existing default draws new style "..w.."x"..h.." "..mode)
    local config=Json.encode(TC:config())
    local name="touch-"..w.."x"..h.."-"..mode
    local idle=render(w,h,mode,name)
    check(TC:touchpressed("left",L.dpad.cx-L.dpad.w*.35,L.dpad.cy),"dpad input captured")
    check(TC:touchpressed("a1",L.a.cx,L.a.cy),"A input captured beside direction")
    check(TC:touchpressed("a2",L.a.cx,L.a.cy),"second A owner captured")
    check(Input:isDown("left") and Input:isDown("a"),"direction plus A held simultaneously")
    local pressed=render(w,h,mode,name.."-pressed")
    local x,y=math.floor(L.a.cx-L.a.w*.25),math.floor(L.a.cy)
    local before=idle:getPixel(x,y);local after=pressed:getPixel(x,y)
    check(before-after>.3,"pressed A visibly inverts on "..mode)
    TC:touchreleased("a1",L.a.cx,L.a.cy)
    check(Input:isDown("a"),"first release retains second A owner")
    TC:touchreleased("a2",L.a.cx,L.a.cy)
    check(not Input:isDown("a") and Input:isDown("left"),"last A release preserves dpad")
    TC:touchmoved("left",L.dpad.cx,L.dpad.cy-L.dpad.w*.35)
    check(Input:isDown("up") and not Input:isDown("left"),"dpad slide changes held direction")
    TC:touchreleased("left",0,0)
    check(not Input:isDown("up"),"dpad release clears direction")
    for _,id in ipairs({"start","select","b"}) do
      check(TC:touchpressed(id,L[id].cx,L[id].cy),id.." captures at saved geometry")
      check(Input:isDown(id),id.." retains input identity")
      TC:touchreleased(id,0,0)
    end
    check(Json.encode(TC:config())==config,"drawing and input preserve saved configuration")
    -- On a transparent target all default artwork must fit the unchanged
    -- control zones. This catches a reintroduced backing disc or outer text.
    local c=g.newCanvas(w,h,{dpiscale=1});g.setCanvas(c);g.clear(0,0,0,0)
    TC:draw();g.setCanvas();local d=c:newImageData();local outside=0
    for py=0,h-1 do for px=0,w-1 do
      local _,_,_,a=d:getPixel(px,py)
      if a>.01 then
        local contained=false
        for _,id in ipairs({"dpad","a","b","start","select"}) do
          local z=L[id]
          if math.abs(px+.5-z.cx)<=z.w*.5+1 and math.abs(py+.5-z.cy)<=z.w*.5+1 then contained=true end
        end
        if not contained then outside=outside+1 end
      end
    end end
    check(outside==0,"no decorative disc or label outside control bounds")
    frames[#frames+1]={width=w,height=h,background=mode,outsidePixels=outside}
  end
  local Game=require("src.core.Game");local P=require("src.render.Pipelines")
  Game.data={constants={language="ja"},render_pipelines={voxel={drawWorld=function()end}}}
  Game.overworld={};Game.stack={top=function()return Game.overworld end}
  P.install(Game.data);P.setLevel('voxel',1)
  for _,size in ipairs({{800,480},{480,800}})do
    local w,h=unpack(size);assert(love.window.setMode(w,h,{vsync=0}))
    TC:init();TC.active=true;TC:ensureImages();TC:applyOptions({jpTouchStick=true,hotbar=false});local z=TC:layout().dpad
    check(TC:stickEnabled(),'circle stick enabled in 3D '..w..'x'..h)
    local idle=render(w,h,'world','stick-'..w..'x'..h..'-idle')
    TC:touchpressed('stick',z.cx+z.w/6,z.cy-z.w/8)
    local pressed=render(w,h,'world','stick-'..w..'x'..h..'-pressed')
    check(idle:getString()~=pressed:getString(),'thumb visibly follows the owning finger')
    TC:touchmoved('stick',z.cx+z.w*2,z.cy-z.w);local position=TC:stickPosition(z)
    check(math.abs(position.x^2+position.y^2-1)<1e-6,'drawn thumb stays on its radial limit')
    render(w,h,'world','stick-'..w..'x'..h..'-edge')
    TC:touchreleased('stick',0,0)
    check(render(w,h,'world'):getString()==idle:getString(),'released thumb returns exactly to centre')
  end
  P.install({});assert(love.window.setMode(972,1536,{vsync=0}));TC:init();TC.active=true;TC:ensureImages();TC:applyOptions({hotbar=false})
  TC:setControlCenter("a",170,230)
  TC:setScale(.6)
  local config=TC:config();TC:applyOptions({hotbar=false,touchControls=config})
  check(math.abs(TC:layout().a.cx-170)<1,"edited position survives options round trip")
  TC:setPreview(true);TC.enabled=false
  render(972,1536,"white","touch-editor-disabled-preview")
  check(TC:visible(),"disabled controls remain visible in editor preview")
  TC:setPreview(false)
  check(not TC:visible(),"disabled controls stay hidden outside editor")
  TC:applyOptions({hotbar=false,touchControls={enabled=true,skin="gb_anim"}})
  check(TC.skinId=="gb_anim","existing selected skin remains selected")
  local original=Style.draw
  Style.draw=function()error("default style must not render over a selected skin")end
  local ok=pcall(render,972,1536,"white","touch-existing-gb-skin")
  Style.draw=original
  check(ok,"selected skin bypasses replacement artwork")
  write("summary.json",Json.encode({checks=checks,frames=frames,romFree=true,runtimeFiles={
    "src/core/TouchControls.lua","src/core/TouchControlsStyle.lua"}}))
  print(string.format("%d/%d checks passed (touch style actual LÖVE)",checks,checks))
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err) end
  love.event.quit(ok and 0 or 1)
end
