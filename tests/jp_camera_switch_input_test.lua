-- Reproduce a paused settings camera change before the next pipeline tick.
-- Use real host event routing/Input/TouchControls and real camera wrappers.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Game=require('src.core.Game')
local Input=require('src.core.Input')
local Touch=require('src.core.TouchControls')
Input:init();Touch:init()
Game.input=Input;Game.save={options=require('src.core.SaveData').defaultOptions()}
Game.data={field={tilePairs={land={},water={}}}}
Game.mods={releaseModInput=function()end}
Game.overworld={player={facing='down',px=64,py=64,cellX=4,cellY=4}}
Game.stack={top=function()return Game.overworld end}
local relative=false
love.mouse={getRelativeMode=function()return relative end,setRelativeMode=function(v)relative=v end}
love.window=love.window or {};love.window.hasFocus=function()return true end
love.graphics.getWidth=function()return 480 end
love.graphics.getHeight=function()return 800 end
Touch.active=true;Touch.enabled=true;Touch.img={};Touch.hotbarEnabled=false
function Touch:layout()
 return {dpad={w=80,cx=50,cy=720},a={cx=420,cy=600,w=60,h=60},b={cx=360,cy=720,w=60,h=60},
  start={cx=250,cy=750,w=30,h=30},select={cx=200,cy=750,w=30,h=30}}
end
local old=os.getenv('JP_CAMERA_BEFORE')
local base=(old and old..'/' or '')..'vendor/jp-mods/DRAMALESS_SHAPE/lib/'
local selected=7
local Voxel={ready=true,level=7,angle=math.rad(75),FOCAL=1,
 isFreeCam=function(level)return level==6 or level==7 end,
 isFirstPerson=function(level)return level==6 end,isThirdPerson=function(level)return level==7 end,
 active=function()return true end}
package.loaded['src.render.Pipelines']={get=function(id)return id=='voxel' and {} end,
 level=function()return selected end}
local modules={Mat4=dofile(base..'Mat4.lua'),Voxel3D={available=function()return true end},
 VoxelState=Voxel,WorldCurve={k=function()return 0 end},BattleCam={},
 VoxelScene={groundAt=function()return 0 end},
 ModSetting={new=function()return{get=function()return false end}end}}
local V
V={require=function(name)
 if not modules[name]then modules[name]=assert(loadfile(base..name..'.lua'))(V)end
 return modules[name]
end}
local FP,TP,CC=V.require('FirstPerson'),V.require('ThirdPerson'),V.require('CamControl')
FP.install();CC.install()
local function enter()
 Game:clearSessionInput();Touch.active=true;Touch.enabled=true;Touch.img={}
 selected=7;Voxel.level=7;FP.update(0.45)
 T.check(FP.driving() and relative,'third person starts with live free-look owner')
end
local function isMoving()
 local x,z=FP.moveVector();return x~=0 or z~=0
end
local zoomSteps=0
function Game:zoomStep()zoomSteps=zoomSteps+1 end
for _,level in ipairs({0,3,6})do
 enter()
 Game:touchpressed('pad',90,720)
 T.check(Input:isDown('right') and isMoving(),'live touch pad owns movement before switch '..level)
 Game:touchpressed('look',230,150)
 Game:touchpressed('pinch',350,150)
 Game:touchmoved('pinch',390,150)
 Game:mousepressed(200,150,1,false)
 local yaw,pitch,zoom=FP.yaw,FP.pitch,TP.zoomGoal
 -- In the real options menu Voxel.level is not updated until the paused
 -- pipeline resumes; routing must use the new stored selection now.
 selected=level
 T.eq(FP.engaged(),level==6,'selected camera is live before delayed visual tick '..level)
 T.check(not relative,'old relative capture is retired immediately '..level)
 T.check(not Input:isDown('a'),'old mouse button does not survive camera handoff '..level)
 T.check(Input:isDown('right'),'camera handoff keeps actual dpad hold '..level)
 local steps=zoomSteps
 Game:touchmoved('pinch',450,150)
 Game:touchmoved('look',350,180)
 Game:touchreleased('pinch',450,150)
 Game:touchreleased('look',350,180)
 Game:mousereleased(200,150,1,false)
 T.eq(zoomSteps,steps,'old pinch cannot zoom a newly selected camera '..level)
 T.eq(TP.zoomGoal,zoom,'old pinch cannot alter shoulder zoom '..level)
 T.check(FP.yaw==yaw and FP.pitch==pitch,'old look cannot steer new camera '..level)
 Game:touchreleased('pad',90,720)
 T.check(not Input:isDown('right') and Touch.dpadTouch==nil,'real dpad release reaches its owner '..level)
 -- A new press after the switch must never be eaten by delayed cleanup.
 Game:touchpressed('fresh-pad',10,720)
 T.check(Input:isDown('left'),'fresh direction survives switch '..level)
 Game:touchreleased('fresh-pad',10,720)
 T.check(not Input:isDown('left'),'fresh direction release works '..level)
 Voxel.level=level;FP.update(1/60)
 T.check(not isMoving(),'no orphan analog movement after switch '..level)
end
-- Mouse and touchscreen may both hold A; their owners must be distinct.
enter()
Input:overlayPressed('a');Game:mousepressed(200,150,1,false)
Game:mousereleased(200,150,1,false)
T.check(Input:isDown('a'),'mouse release cannot clear a real touch A hold')
Input:overlayReleased('a');T.check(not Input:isDown('a'),'touch releases its own A')
Game:mousepressed(200,150,1,false);Input:overlayPressed('a')
Input:overlayReleased('a')
T.check(Input:isDown('a'),'touch release cannot clear a real mouse A hold')
Game:mousereleased(200,150,1,false);T.check(not Input:isDown('a'),'mouse releases its own A')
-- Controller movement is hardware state, not a private camera gesture.
enter();Input:gamepadaxis(nil,'leftx',0.9)
Game:gamepadaxis(nil,'rightx',0.8)
selected=3;FP.engaged()
T.check(Input:isDown('right') and Input.stickAxis.x==0.9,'left stick survives view switch without repress')
Input:gamepadaxis(nil,'leftx',0)
T.check(not Input:isDown('right'),'center event stops grid direction')
selected=7;Voxel.level=7;FP.update(1/60)
local yaw=FP.yaw;FP.update(1/60)
T.eq(FP.yaw,yaw,'discarded old right-stick look is not replayed after reentry')
selected=6;Voxel.level=6
Game:gamepadaxis(nil,'rightx',0.8);FP.update(1/60)
T.check(FP.yaw~=yaw,'fresh right-stick event after mode selection is not discarded')
Game:gamepadaxis(nil,'rightx',0)
local menuCounts={pressed=0,released=0}
Game:clearSessionInput()
Game.sessionMenu={pressed=function()menuCounts.pressed=menuCounts.pressed+1 end,
 released=function()menuCounts.released=menuCounts.released+1 end,cancelPointers=function()end}
selected=3 -- changed while the menu has paused all pipeline updates
Game:touchpressed('new-menu',250,120);Game:touchreleased('new-menu',250,120)
Game:mousepressed(250,120,1,false);Game:mousereleased(250,120,1,false)
T.eq(menuCounts.pressed,2,'fresh menu mouse and touch presses survive delayed mode cleanup')
T.eq(menuCounts.released,2,'fresh menu mouse and touch releases reach the menu')
Game.sessionMenu=nil
-- FreeMove must return to the native grid on the first resumed logic tick,
-- even though the visual VoxelState still holds the previous third person.
local Overworld=require('src.world.OverworldController')
local nativeCalls=0
Overworld.handleInput=function()nativeCalls=nativeCalls+1 end
Overworld.dramaticShapeFreeMoveHook=nil
local FreeMove=V.require('FreeMove');FreeMove.install()
local p=Game.overworld.player
p.px,p.py,p.cellX,p.cellY=64,64,4,4;p.moving=false;p.inputLocked=false
Game.overworld.map={def={tileset='OVERWORLD'},inBounds=function()return true end,
 isWalkableCell=function()return true end,cellTile=function()return 0 end}
Game.overworld.entities={};Game.overworld.onStepComplete=function()end
Game.overworld.interact=function()end
Input:reset();selected=7;Voxel.level=7;FP.update(1/60)
Input:overlayPressed('up')
Overworld.handleInput(Game.overworld)
T.check(FreeMove._pos()~=nil,'free movement owns position in third person')
selected=3
Overworld.handleInput(Game.overworld)
T.eq(nativeCalls,1,'first resumed logic tick already returns to native grid')
T.check(FreeMove._pos()==nil and p.px==p.cellX*16 and p.py==p.cellY*16,'fractional position snaps exactly once at grid handoff')
T.check(Input:isDown('up'),'grid handoff preserves physical held direction')
Input:overlayReleased('up')
T.finish('JP camera-switch input handoff')
