-- Real unmodified Dramaless card and orbit matrices, no ROM or GPU needed.
package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness")
local Framing=require("src.render.JapaneseCameraFraming")
local Camera=require("src.render.Camera")
local Version=require("src.core.GameVersion")
local Pipelines=require("src.render.Pipelines")
local Game=require("src.core.Game")
local mat=dofile("vendor/jp-mods/DRAMALESS_SHAPE/lib/Mat4.lua")
local voxel={angle=0,FOCAL=1}
local camera3d=assert(loadfile("vendor/jp-mods/DRAMALESS_SHAPE/lib/Voxel3D.lua"))({
  require=function(name)
    if name=="Mat4" then return mat elseif name=="VoxelState" then return voxel end
    return {}
  end,
})
local function point(m,x,y,z)
  return m[1]*x+m[2]*y+m[3]*z+m[4],m[5]*x+m[6]*y+m[7]*z+m[8],
    m[9]*x+m[10]*y+m[11]*z+m[12],m[13]*x+m[14]*y+m[15]*z+m[16]
end
for _,size in ipairs({{160,144},{320,480},{478,266}}) do
 for _,angle in ipairs({0,15,45,75}) do
  for _,ground in ipairs({0,8}) do
   for _,phase in ipairs({0,0.25,0.5,0.75,1}) do
    for _,k in ipairs({0,0.18/size[2]}) do
      voxel.angle=math.rad(angle)
      local px,py=128+16*phase,160-16*phase
      local camera=Camera.new();camera:follow(px,py,size[1],size[2])
      local dx,dy=Framing.offset(voxel.angle,8,ground,k)
      local cx,cy=camera.x+size[1]/2+dx,camera.y+size[2]/2+dy
      local model=mat.billboard(px,py,ground,0,voxel.angle-math.pi/2,false)
      local x,y,z=point(model,8,8,0)
      y=y-k*((x-cx)^2+(z-cy)^2)
      local clipX,clipY,_,clipW=point(camera3d.viewProjection(cx,cy,size[1],size[2]),x,y,z)
      local label=table.concat({size[1],size[2],angle,ground,phase,k},"/")
      T.check(math.abs(clipX/clipW)<0.000001,label.." actual billboard centre is horizontally centred")
      T.check(math.abs(clipY/clipW)<0.000001,label.." actual billboard centre is vertically centred")
    end
   end
  end
 end
end

local fp={blend=0,engaged=function()return false end}
local modules={VoxelState=voxel,FirstPerson=fp,WorldCurve={k=function()return 0 end},
  VoxelScene={groundAt=function()return 0 end}}
Game.mods={exports={DRAMALESS_SHAPE={lib={require=function(name)return modules[name]end}}}}
local camera=Camera.new();camera:follow(128,160,320,480)
local x,y=camera.x,camera.y
local state={camera=camera,player={px=128,py=160,cellX=8,cellY=10},map={}}
local ctx={state=state,cam=camera,vw=320,vh=480}
local result=love.graphics.newCanvas(32,32)
Version.set("red_jp")
Pipelines.install({render_pipelines={_owners={voxel="DRAMALESS_SHAPE"},voxel={drawWorld=function(render)
  T.check(render.cam~=camera and render.state.camera==render.cam,"pipeline alone sees the drawing camera")
  T.check(camera.x==x and camera.y==y,"original camera coordinates remain unchanged during draw")
  return result
end}}})
T.eq(Pipelines.drawWorld("voxel",ctx),result,"corrected pipeline returns its canvas")
T.eq(state.camera,camera,"normal return restores the original camera object")
T.eq(ctx.cam,camera,"normal return restores the context camera")
for _,version in ipairs({"red","gold"}) do
  Version.set(version)
  T.eq(Framing.begin("voxel","DRAMALESS_SHAPE",ctx),nil,"other game unchanged: "..version)
end
Version.set("red_jp")
T.eq(Framing.begin("voxel","another-mod",ctx),nil,"another renderer is not modified")
T.eq(Framing.begin("other-pipeline","DRAMALESS_SHAPE",ctx),nil,"postprocess pipeline is not modified")
fp.blend=0.5
local transition=Framing.begin("voxel","DRAMALESS_SHAPE",ctx)
T.check(transition~=nil,"first/third-person transition retains corrected orbit endpoint")
Framing.finish(transition)
fp.blend=1;fp.engaged=function()return true end
T.eq(Framing.begin("voxel","DRAMALESS_SHAPE",ctx),nil,"first/third-person camera remains untouched")
fp.blend=0;fp.engaged=function()return false end
Pipelines.install({render_pipelines={_owners={voxel="DRAMALESS_SHAPE"},voxel={drawWorld=function()
  error("fixture render failure")
end}}})
T.eq(Pipelines.drawWorld("voxel",ctx),nil,"failed renderer retains fallback behavior")
T.eq(state.camera,camera,"failed renderer restores original camera")
T.eq(ctx.cam,camera,"failed renderer restores context camera")
T.check(camera.x==x and camera.y==y,"camera coordinates are untouched after all calls")
Version.set("red")
T.finish("Japanese player centre")
