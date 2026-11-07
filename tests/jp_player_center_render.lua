-- Full installed Dramaless world renderer with a synthetic magenta player.
return function(Game,Renderer,V,state,check,write)
  local g,fs=love.graphics,love.filesystem
  local Pipelines=require("src.render.Pipelines")
  local Viewport=require("src.render.GameViewport")
  local Position=require("src.core.ScreenPosition")
  local Camera=require("src.render.Camera")
  local Zoom=require("src.render.Zoom")
  local Voxel=V.require("VoxelState")
  local FirstPerson=V.require("FirstPerson")
  local marker=g.newCanvas(16,96,{dpiscale=1})
  g.setCanvas(marker);g.clear(1,0,1,1);g.setCanvas()
  fs.write("fixture-player-centre.png",marker:newImageData():encode("png"))
  local sprite=require("src.render.SpriteRenderer").new({
    image="fixture-player-centre.png",frames=6,trueColor=true})
  -- Marker hue is diagnostic, independent of any installed palette preset.
  function sprite:resolveImage() return self.image end
  local player={sprite=sprite,px=128,py=128,cellX=8,cellY=8,facing="down"}
  function player:pose() return self.sprite,self.px,self.py,self.facing,0,false end
  state.player,state.entities,state.camera=player,{player},Camera.new()
  Game.overworld=state
  Voxel.level,FirstPerson.blend=3,0
  Pipelines.setLevel("voxel",3)
  Renderer.uiFill,Renderer.dialogScale,Renderer.uiCentered=false,1,true
  Zoom.offset=0
  local report={}
  for _,size in ipairs({{480,800},{800,480}}) do
    love.window.setMode(size[1],size[2],{vsync=0})
    for _,position in ipairs({"center","upper","top"}) do
      Position.setMode(position)
      for _,angle in ipairs({0,35,75}) do
        Voxel.angle=math.rad(angle)
        for _,step in ipairs({0,0.5,1}) do
          player.px,player.py=128+step*16,128-step*16
          Viewport.begin(1);Renderer:beginFrame(true)
          local r=Renderer:frameRects()
          local vw,vh=Renderer:worldViewSize()
          state.camera:follow(player.px,player.py,vw,vh)
          local savedCamera=state.camera
          local oldX,oldY=state.camera.x,state.camera.y
          local scene=Pipelines.drawWorld("voxel",{state=state,cam=state.camera,vw=vw,vh=vh,
            width=r.pw,height=r.ph,scale=Zoom.scale(r.Sp),level=3,
            paletteFor=function()return nil end,drawFx=function()end})
          local label=table.concat({size[1].."x"..size[2],position,angle,step},"-")
          check(scene~=nil,label.." real 3D world renders")
          check(state.camera==savedCamera and state.camera.x==oldX and state.camera.y==oldY,
            label.." player and gameplay camera coordinates remain unchanged")
          Renderer:setWorldOverride(scene,vw,vh);Renderer:endFrame();g.setCanvas()
          local pixels=Viewport.target():newImageData()
          local minx,miny,maxx,maxy=size[1],size[2],-1,-1
          for y=0,size[2]-1 do for x=0,size[1]-1 do
            local red,green,blue=pixels:getPixel(x,y)
            if red>0.2 and blue>0.2 and green<red*0.2 then
              minx,miny=math.min(minx,x),math.min(miny,y)
              maxx,maxy=math.max(maxx,x),math.max(maxy,y)
            end
          end end
          if maxx<0 then write("missing-player.png",pixels:encode("png"):getString()) end
          check(maxx>=0,label.." actual player card is visible")
          local cx,cy=(minx+maxx+1)/2,(miny+maxy+1)/2
          check(math.abs(cx-size[1]/2)<=1,label.." player card horizontally centres")
          check(math.abs(cy-(size[2]/2-r.lift))<=1,
            label.." player card centres vertically with chosen screen position")
          report[#report+1]={case=label,playerX=cx,playerY=cy,
            targetX=size[1]/2,targetY=size[2]/2-r.lift}
          if angle==35 and step==0 then write("player-centre-"..label..".png",pixels:encode("png"):getString()) end
        end
      end
    end
  end
  write("player-centre-geometry.json",require("src.link.Json").encode({romUsed=false,cases=report}))
end
