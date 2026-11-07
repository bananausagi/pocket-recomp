-- Full installed world renderer; transitions preserve the displayed orbit
-- endpoint and the independent placed-camera endpoint in both directions.
return function(Game,Renderer,V,state,check,write)
 local g,fs=love.graphics,love.filesystem
 local Pipelines=require('src.render.Pipelines')
 local Viewport=require('src.render.GameViewport')
 local Position=require('src.core.ScreenPosition')
 local Camera=require('src.render.Camera')
 local Zoom=require('src.render.Zoom')
 local FP,TP,Voxel,C3D=V.require('FirstPerson'),V.require('ThirdPerson'),V.require('VoxelState'),V.require('Voxel3D')
 local Mat4=V.require('Mat4')
 local before=os.getenv('JP_CAMERA_FRAMING_BEFORE')
 if before then package.loaded['src.render.JapaneseCameraFraming']=assert(loadfile(before..'/src/render/JapaneseCameraFraming.lua'))() end
 local marker=g.newCanvas(16,96,{dpiscale=1})
 g.setCanvas(marker);g.clear(1,0,1,1);g.setCanvas()
 fs.write('fixture-free-camera-player.png',marker:newImageData():encode('png'))
 local sprite=require('src.render.SpriteRenderer').new({image='fixture-free-camera-player.png',frames=6,trueColor=true})
 function sprite:resolveImage()return self.image end
 local player={sprite=sprite,px=128,py=128,cellX=8,cellY=8,facing='up'}
 function player:pose()return self.sprite,self.px,self.py,self.facing,0,false end
 state.player,state.entities,state.camera=player,{player},Camera.new()
 Game.overworld=state
 Renderer.uiFill,Renderer.dialogScale,Renderer.uiCentered=false,1,true
 Zoom.offset=0
 local function copy(a)return {a[1],a[2],a[3]}end
 local function snapshot()
  local cam=C3D.camera
  return {eye=copy(C3D.eye),focus=copy(C3D.focus),fov=C3D.fovY,
   up=copy(cam and cam.up or {0,math.sin(Voxel.angle),-math.cos(Voxel.angle)})}
 end
 local function matrix(pose,w,h)
  local e,f=pose.eye,pose.focus
  local dist=math.sqrt((e[1]-f[1])^2+(e[2]-f[2])^2+(e[3]-f[3])^2)
  return Mat4.mul(Mat4.mul(Mat4.scale(1,-1,1),Mat4.perspective(pose.fov,w/h,math.max(1,dist*.05),dist*4+4096)),Mat4.lookAt(e,f,pose.up))
 end
 local function project(m,p,w,h)
  local x,y,z=p[1],p[2],p[3]
  local cw=m[13]*x+m[14]*y+m[15]*z+m[16]
  if cw<=1e-6 then return end
  return (m[1]*x+m[2]*y+m[3]*z+m[4])/cw*w*.5+w*.5,
         (m[5]*x+m[6]*y+m[7]*z+m[8])/cw*h*.5+h*.5
 end
 local function distance(a,b)
  local total=math.abs(a.fov-b.fov)
  for _,key in ipairs({'eye','focus','up'})do for i=1,3 do total=total+math.abs(a[key][i]-b[key][i])end end
  return total
 end
 local report={}
 for _,size in ipairs({{480,800},{800,480}})do
  love.window.setMode(size[1],size[2],{vsync=0})
  for _,position in ipairs({'center','upper','top'})do
   Position.setMode(position)
   for _,level in ipairs({6,7})do
    Pipelines.setLevel('voxel',level);Voxel.level=level;Voxel.angle=math.rad(75);Voxel.ready=true
    FP.yaw=math.pi;FP.pitch=FP.PITCH_DEFAULT
    TP.out=level==7 and 1 or 0;TP.zoom,TP.zoomGoal=1,1;TP.len=level==7 and TP.BOOM or 0
    local name=size[1]..'x'..size[2]..'-'..position..'-'..(level==6 and 'first' or 'third')
    local frames={}
    for i,blend in ipairs({0,1e-6,.5,1-1e-6,1,1-1e-6,.5,1e-6,0})do
     -- Frame one is the orbit displayed before the input changes modes;
     -- frames six onward are the transition after switching back to orbit.
     local selected=(i==1 or i>=6) and 5 or level
     Pipelines.setLevel('voxel',selected);Voxel.level=selected
     FP.blend=blend
     Viewport.begin(1);Renderer:beginFrame(true)
     local r=Renderer:frameRects();local vw,vh=Renderer:worldViewSize()
     -- Fractional walking coordinates exercise the same interpolated pose.
     player.px,player.py=136,120
     state.camera:follow(player.px,player.py,vw,vh)
     local original=state.camera;local x,y=original.x,original.y
     local scene=Pipelines.drawWorld('voxel',{state=state,cam=state.camera,vw=vw,vh=vh,
      width=r.pw,height=r.ph,scale=Zoom.scale(r.Sp),level=level,
      paletteFor=function()return nil end,drawFx=function()end})
     check(scene~=nil,name..' blend '..blend..' real world renders')
     check(state.camera==original and original.x==x and original.y==y,name..' render preserves gameplay camera')
     local pose=snapshot();frames[i]=pose
     Renderer:setWorldOverride(scene,vw,vh);Renderer:endFrame();g.setCanvas()
     if position=='center' and (i==1 or i==3 or i==5 or i==9)then
      local pixels=Viewport.target():newImageData()
      write(name..'-frame'..i..'.png',pixels:encode('png'):getString());pixels:release()
     end
    end
    check(distance(frames[1],frames[2])<.001,name..' orbit to free camera starts at displayed pose')
    check(distance(frames[4],frames[5])<.001,name..' entry ends at unmodified placed pose')
    check(distance(frames[5],frames[6])<.001,name..' exit starts at unmodified placed pose')
    check(distance(frames[8],frames[9])<.001,name..' free camera returns to displayed orbit')
    check(distance(frames[1],frames[9])<.001,name..' orbit round trip preserves framing')
    local m1,m2=matrix(frames[1],size[1],size[2]),matrix(frames[2],size[1],size[2])
    local maxError=0
    for _,point in ipairs({{128,0,96},{160,0,96},{128,16,96},{160,16,96}})do
     local a,b=project(m1,point,size[1],size[2]);local c,d=project(m2,point,size[1],size[2])
     if a and c then maxError=math.max(maxError,math.abs(a-c),math.abs(b-d))end
    end
    check(maxError<.01,name..' visible terrain projection is continuous at entry')
    report[#report+1]={case=name,frames=#frames,entryPoseError=distance(frames[1],frames[2]),entryPixelError=maxError}
   end
  end
 end
 -- Exercise the methods actually installed by the sandboxed MOD loader,
 -- not only the direct-module unit fixture. No native input device needed.
 local Input=require('src.core.Input');local Touch=require('src.core.TouchControls')
 Input:init();Touch:init();Touch:ensureImages();Touch.active=true;Touch.enabled=true
 Game.input=Input;Game.stack={top=function()return state end}
 for _,level in ipairs({6,7})do
  Pipelines.setLevel('voxel',level);Voxel.level=level;FP.update(.45)
  local pad=Touch:layout().dpad
  Game:touchpressed('held-pad',pad.cx+pad.w*.45,pad.cy)
  local mx=FP.moveVector();check(mx>0,'installed camera '..level..' receives actual touch-pad deflection')
  Game:mousepressed(300,100,1,false)
  check(Input:isDown('a'),'installed camera '..level..' maps a fresh mouse press to A')
  Game:clearSessionInput()
  local presses,releases=0,0
  Game.sessionMenu={pressed=function()presses=presses+1 end,moved=function()end,
   released=function()releases=releases+1 end,cancelPointers=function()end,cancelTransfers=function()end}
  Game:touchreleased('held-pad',pad.cx+pad.w*.45,pad.cy);Game:mousereleased(300,100,1,false)
  check(releases==0,'installed cancellation quarantines old camera releases')
  local yaw=FP.yaw
  Game:touchpressed('menu-touch',300,100);Game:touchmoved('menu-touch',400,150);Game:touchreleased('menu-touch',400,150)
  Game:mousepressed(300,100,1,false);Game:mousereleased(300,100,1,false)
  check(presses==2 and releases==2 and FP.yaw==yaw,'installed wrappers let menu touch and mouse through without camera motion')
  Game:closeSessionMenu();FP.update(1/60)
  local x,z=FP.moveVector()
  check(x==0 and z==0 and not Input:isDown('a'),'installed camera closes menu with no residual movement or mouse hold')
  Game:clearSessionInput()
 end
 write('free-camera-geometry.json',require('src.link.Json').encode({romUsed=false,cases=report}))
end
