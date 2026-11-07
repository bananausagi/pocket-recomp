-- Real LÖVE compositing regression. Synthetic geometry, no ROM/assets.
local function run()
  local root=assert(os.getenv("JP_QA_ROOT"))
  local out=assert(os.getenv("JP_QA_OUT"))
  package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local g=love.graphics
  local Renderer=require("src.render.Renderer")
  local Position=require("src.core.ScreenPosition")
  local Zoom=require("src.render.Zoom")
  local Viewport=require("src.render.GameViewport")
  local mat=dofile(root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/Mat4.lua")
  local voxel={angle=0,FOCAL=1}
  local camera=assert(loadfile(root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/Voxel3D.lua"))({
    require=function(n) if n=="Mat4" then return mat elseif n=="VoxelState" then return voxel end return {} end,
  })
  local checks=0
  local function check(ok,msg) assert(ok,msg);checks=checks+1;print("PASS "..msg) end
  local function write(name,bytes)
    local f=assert(io.open(out.."/"..name,"wb"));f:write(bytes);f:close()
  end
  local function point(m,w,h,x,z,y)
    y=y or 0
    local d=m[13]*x+m[14]*y+m[15]*z+m[16]
    return ( (m[1]*x+m[2]*y+m[3]*z+m[4])/d*.5+.5 )*w,
      ( (m[5]*x+m[6]*y+m[7]*z+m[8])/d*.5+.5 )*h
  end
  g.setDefaultFilter("nearest","nearest")
  for _,size in ipairs({{480,800},{800,480},{972,1536}}) do
    local w,h=unpack(size)
    assert(love.window.setMode(w,h,{vsync=0,resizable=false}))
    for _,mode in ipairs({"center","upper","top"}) do
     for _,angle in ipairs({0,45}) do
      voxel.angle=math.rad(angle)
      Renderer:init();Position.setMode(mode);Zoom.offset=0
      Renderer:beginFrame(true)
      local r=Renderer:frameRects()
      local vw,vh=Renderer:worldViewSize()
      local sp=Zoom.scale(r.Sp)
      local scene=g.newCanvas(w,h,{dpiscale=1})
      local target=g.newCanvas(w,h,{dpiscale=1})
      local vp=camera.viewProjection(0,0,vw,vh)
      g.setCanvas(scene);g.clear(.12,.17,.22,1);g.setColor(.28,.36,.42,1)
      -- Distorted at this storage resolution, as an unmodified MOD renders.
      for x=-512,512,16 do
        local x1,y1=point(vp,w,h,x,-vh*.65)
        local x2,y2=point(vp,w,h,x,vh*.65)
        g.line(x1,y1,x2,y2)
      end
      for y=-math.floor(vh*.65/16)*16,math.floor(vh*.65/16)*16,16 do
        local x1,y1=point(vp,w,h,-512,y)
        local x2,y2=point(vp,w,h,512,y)
        g.line(x1,y1,x2,y2)
      end
      -- A square billboard facing the real camera is square at every angle.
      local ca,sa=math.cos(voxel.angle),math.sin(voxel.angle)
      local x1,y1=point(vp,w,h,-8,-8*ca,8*sa)
      local x2,y2=point(vp,w,h,8,8*ca,-8*sa)
      g.setColor(1,0,1,1);g.rectangle("fill",x1,y1,x2-x1,y2-y1)
      local oldTarget=Viewport.setTarget
      Viewport.setTarget=function()g.setCanvas(target)end
      Renderer:setWorldOverride(scene,vw,vh);Renderer:endFrame()
      Viewport.setTarget=oldTarget;g.setCanvas()
      local pixels=target:newImageData()
      local minx,miny,maxx,maxy=w,h,-1,-1
      for y=0,h-1 do for x=0,w-1 do
        local a,b,c=pixels:getPixel(x,y)
        if a>.9 and b<.1 and c>.9 then
          minx=math.min(minx,x);miny=math.min(miny,y)
          maxx=math.max(maxx,x);maxy=math.max(maxy,y)
        end
      end end
      local tag=w.."x"..h.."-"..mode.."-angle"..angle
      check(maxx>=0,tag.." marker visible")
      check(math.abs((maxx-minx)-(maxy-miny))<=2,tag.." square marker is not stretched")
      check(math.abs(maxx-minx+1-16*sp)<=2,tag.." same zoom scale")
      check(math.abs((miny+maxy+1)/2-(h/2-r.lift))<=2,tag.." correct vertical position")
      for _,p in ipairs({{0,0},{w-1,0},{0,h-1},{w-1,h-1}}) do
        local a,b,c=pixels:getPixel(p[1],p[2])
        check(a+b+c>.25,tag.." world covers corner "..p[1]..","..p[2])
      end
      write(tag..".png",pixels:encode("png"):getString())
      scene:release();target:release()
     end
    end
  end
  write("summary.json",require("src.link.Json").encode({checks=checks,status="pass",rom_used=false}))
  print("World position: "..checks.." checks passed")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err) end
  love.event.quit(ok and 0 or 1)
end
