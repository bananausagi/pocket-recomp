-- Actual camera wrappers + actual host cancellation, without ROM data.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Game=require('src.core.Game')
local Input=require('src.core.Input')
local Touch=require('src.core.TouchControls')
Input:init();Touch:init()
Game.input=Input;Game.overworld={player={facing='down'}}
Game.stack={top=function()return Game.overworld end}
Game.save={options=require('src.core.SaveData').defaultOptions()}
Game.mods={releaseModInput=function()end}
local width,height=480,800
love.graphics.getWidth=function()return width end
love.graphics.getHeight=function()return height end
local relative=false
love.mouse={getRelativeMode=function()return relative end,setRelativeMode=function(v)relative=v end}
love.window=love.window or {};love.window.hasFocus=function()return true end
-- Keep the real host event routing and Input reset, with a deterministic pad.
function Touch:hitTest(x,y)return x<100 and 'dpad' or nil end
function Touch:layout()return {dpad={w=80,cx=50,cy=height-80}}end
function Touch:touchpressed(id,x,y)
 if self:hitTest(x,y)=='dpad' then self.dpadTouch=id;return true end
end
function Touch:touchmoved()end
function Touch:touchreleased(id)if self.dpadTouch==id then self.dpadTouch=nil end end
local before=os.getenv('JP_CAMERA_BEFORE')
local base=(before and (before..'/') or '')..'vendor/jp-mods/'..(os.getenv('JP_QA_RENDERER') or 'DRAMALESS_SHAPE')..'/lib/'
local mode='first'
local modules={Mat4=dofile(base..'Mat4.lua'),Voxel3D={available=function()return true end},
 VoxelState={ready=true,level=7,angle=math.rad(75),FOCAL=1,
  isFreeCam=function()return mode=='first' or mode=='third' end,
  isFirstPerson=function()return mode=='first' end,isThirdPerson=function()return mode=='third' end,
  active=function()return mode~='off' end},WorldCurve={k=function()return 0 end},BattleCam={},
 VoxelScene={groundAt=function()return 0 end},
 ModSetting={new=function()return{get=function()return false end}end}}
local V
V={require=function(name)
 if not modules[name] then
  local chunk=assert(loadfile(base..name..'.lua'))
  modules[name]=chunk(V)
 end
 return modules[name]
end}
modules.ThirdPerson=assert(loadfile(base..'ThirdPerson.lua'))(V)
modules.FirstPerson=assert(loadfile(base..'FirstPerson.lua'))(V)
modules.CamControl=assert(loadfile(base..'CamControl.lua'))(V)
local FP,TP,CC=modules.FirstPerson,modules.ThirdPerson,modules.CamControl
FP.install();CC.install()
local counts
local function open()
 Game:clearSessionInput()
 counts={press=0,move=0,release=0,wheel=0}
 Game.sessionMenu={pressed=function()counts.press=counts.press+1 end,
  moved=function()counts.move=counts.move+1 end,released=function()counts.release=counts.release+1 end,
  wheelmoved=function()counts.wheel=counts.wheel+1 end,cancelPointers=function()end,cancelTransfers=function()end,
  gamepadaxis=function()end,gamepadpressed=function()end}
end
local function close()Game:closeSessionMenu()end
local function noMove(label)
 local x,y=FP.moveVector();T.check(x==0 and y==0,label)
end
for _,size in ipairs({{480,800},{800,480}})do
 width,height=size[1],size[2]
 for _,selected in ipairs({'first','third'})do
  mode=selected;Game:focus(true);FP.update(0.45)
  local label=selected..' '..width..'x'..height
  T.check(relative,label..' free look initially captures mouse')
  Game:touchpressed('pad',90,height-80)
  local x=FP.moveVector();T.check(x>0,label..' pad starts camera-relative walking')
  Game:touchpressed('look',250,120)
  Game:mousepressed(300,120,1,false)
  T.check(Input:isDown('a'),label..' free mouse press owns A')
  open()
  T.check(not FP.driving(),label..' independent menu excludes camera input')
  T.check(not relative,label..' pause synchronously releases relative mouse')
  T.check(not Input:isDown('a'),label..' pause releases held mouse A')
  Game:touchreleased('pad',90,height-80)
  Game:touchreleased('look',300,120)
  Game:mousereleased(300,120,1,false)
  T.eq(counts.release,0,label..' old camera releases cannot click the menu')
  local yaw,pitch,zoom=FP.yaw,FP.pitch,TP.zoomGoal
  Game:touchpressed('menu',250,120);Game:touchmoved('menu',350,170);Game:touchreleased('menu',350,170)
  Game:mousepressed(250,120,1,false);Game:mousemoved(280,150,30,30,false);Game:mousereleased(280,150,1,false)
  Game:wheelmoved(0,1)
  T.eq(counts.press,2,label..' new touch and mouse press reach menu')
  T.eq(counts.move,2,label..' new touch and mouse movement reach menu')
  T.eq(counts.release,2,label..' new touch and mouse release reach menu')
  T.eq(counts.wheel,1,label..' wheel scroll reaches menu')
  T.check(FP.yaw==yaw and FP.pitch==pitch,label..' menu gestures do not turn camera')
  T.eq(TP.zoomGoal,zoom,label..' menu wheel does not zoom boom')
  noMove(label..' menu has no movement intent')
  close();FP.update(1/60)
  noMove(label..' closing menu leaves no held analog vector')
  T.check(FP.yaw==yaw and FP.pitch==pitch,label..' closing menu cannot replay mouse delta')
  T.check(relative,label..' resumed free look recaptures mouse')
  Game:touchpressed('new-pad',90,height-80)
  x=FP.moveVector();T.check(x>0,label..' new pad press resumes walking')
  Game:touchreleased('new-pad',90,height-80);noMove(label..' new pad release stops walking')
  Game:touchpressed('new-look',250,120);Game:touchmoved('new-look',275,120);Game:touchreleased('new-look',275,120)
  T.check(FP.yaw~=yaw,label..' new look drag resumes turning')
  -- Cancel a live two-finger pinch, including the finger whose release is lost.
  Game:touchpressed('pinch-a',250,200);Game:touchpressed('pinch-b',350,200)
  Game:touchmoved('pinch-b',400,200)
  open();zoom=TP.zoomGoal;yaw=FP.yaw
  Game:touchreleased('pinch-a',250,200)
  close();FP.update(1/60)
  Game:touchmoved('pinch-b',600,200)
  T.check(TP.zoomGoal==zoom and FP.yaw==yaw,label..' cancelled pinch/look cannot resume from old finger')
  Game:touchreleased('pinch-b',600,200)
  Game:clearSessionInput()
 end
end
-- Normal (non-free-camera) mouse releases still pass through the wrapper.
mode='off';open()
Game:mousepressed(250,120,1,false);Game:mousereleased(250,120,1,false)
T.eq(counts.press,1,'orbit mouse press reaches menu')
T.eq(counts.release,1,'orbit mouse release reaches menu')
close()
-- The fix changes ownership, not the established camera-relative axes,
-- shoulder rail or collision-driven switch to a close first-person view.
mode='third';FP.blend=1;TP.out=1
for _,yaw in ipairs({0,math.pi/2,math.pi,-math.pi/2})do
 FP.yaw=yaw
 local x,z=FP.moveWorld(0,1)
 T.check(math.abs(x-math.sin(yaw))<1e-9 and math.abs(z-math.cos(yaw))<1e-9,'forward follows camera bearing')
 local sx,sz=FP.moveWorld(1,0)
 T.check(math.abs(x*sx+z*sz)<1e-9,'strafe remains perpendicular to camera forward')
end
local world={map={def={outdoor=false},inBounds=function(_,x,z)return x>=0 and x<64 and z>=0 and z<64 end,
 isWalkableCell=function(_,x,z)return z<10 end}}
local reach=TP.reach(world,{128,17,128},0,0,1,48)
T.check(reach>0 and reach<28,'near indoor wall contracts the boom before geometry')
TP.len=reach
T.check(not TP.showsPlayer(),'contracted boom still hides a card that would fill the lens')
TP.len=48
T.check(TP.showsPlayer(),'clear third-person boom still shows the player')
T.finish('JP free camera input ownership')
