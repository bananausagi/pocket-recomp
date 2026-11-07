-- ROM-free integration: actual analog reader, collision walker, Player,
-- native input/script queue, and Input source tracking.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Game=require('src.core.Game')
local Input=require('src.core.Input')
local Player=require('src.world.Player')
local Controller=require('src.world.OverworldController')
local Collision=require('src.world.Collision')
-- Seed the shared host reference normally populated by enter(), without ROM loading.
for _,fn in pairs(Controller) do if type(fn)=='function' then
 for i=1,40 do local name=debug.getupvalue(fn,i);if not name then break end
  if name=='Game' then debug.setupvalue(fn,i,Game) end
 end
end end
Input:init();Game.input=Input
Game.save={options={jpAnalogWalk=true},onBike=false}
Game.data={constants={language="ja"},field={tilePairs={land={},water={}},forcedMovement={slopeMaps={}}}}
Collision.load(Game.data)
local base=(os.getenv('JP_ANALOG_BEFORE') or '.')..'/vendor/jp-mods/'..(os.getenv('JP_QA_RENDERER') or 'DRAMALESS_SHAPE')..'/lib/'
local mods={VoxelState=dofile(base..'VoxelState.lua'),Mat4=dofile(base..'Mat4.lua'),
 Voxel3D={available=function()return true end},WorldCurve={k=function()return 0 end},
 ModSetting={new=function()return {get=function()return false end} end}}
local V
V={require=function(name)
 if not mods[name] then mods[name]=assert(loadfile(base..name..'.lua'))(V) end
 return mods[name]
end}
local FP=V.require('FirstPerson')
local FM=V.require('FreeMove')
FM.install()
local entered, interactions, walls, waters, lastInteraction
local function reset(cx,cy)
 FM.drop();Input:reset();Game.save.onBike=false;Game.sessionMenu=nil
 Game.save.options.jpAnalogWalk=true;mods.VoxelState.level=3
 Game.data.constants.language="ja"
 entered,interactions,walls,waters,lastInteraction={},0,{},{},nil
 local p=setmetatable({cellX=cx or 8,cellY=cy or 8,px=(cx or 8)*16,py=(cy or 8)*16,
  facing='up',moving=false,inputLocked=false,progress=0,stepFrames=16,bikeStepFrames=8,
  turnFrames=4,turnTimer=0,turnArmed=false},Player)
 local state=setmetatable({player=p,map={id='test',def={tileset='plain'},
   inBounds=function(_,x,y)return x>=0 and x<64 and y>=0 and y<64 end,
   isWalkableCell=function(_,x,y)return not walls[x..','..y] and not waters[x..','..y] end,
   isWaterCell=function(_,x,y)return waters[x..','..y] end,
   cellTile=function(_,x,y)return x==9 and 2 or 1 end},
  scriptMoves={},marchers={},runner={isRunning=function()return false end},bumpCooldown=0},{__index=Controller})
 state.entities={p}
 function state:onStepComplete()entered[#entered+1]={self.player.cellX,self.player.cellY} end
 function state:interact()interactions=interactions+1;lastInteraction={p.px,p.py,p.facing} end
 function state:checkEdgeExit(dir)self.edge=dir;return false end
 function state:checkLedgeHop(dir)self.ledge=dir;return false end
 function state:checkBoulderPush(dir)self.boulder=dir;return false end
 function state:canCollisionWarp()return false end
 Game.overworld=state;Game.stack={top=function()return state end}
 return state,p
end
local function stick(x,y)
 Input:gamepadaxis(nil,'leftx',x);Input:gamepadaxis(nil,'lefty',y)
end
local function tick(state,n)for i=1,n or 1 do Input:step();state:handleInput();state.player:update() end end
local function near(a,b,msg)T.check(math.abs(a-b)<1e-7,msg..' ('..a..' vs '..b..')')end
-- Arbitrary directions keep equal speed (including non-45-degree travel).
for deg=0,345,15 do
 local s,p=reset();local a=math.rad(deg)
 local x,y=math.cos(a),math.sin(a);stick(x,y);tick(s)
 near(p.px,128+x,'orbit analog X '..deg);near(p.py,128+y,'orbit analog Y '..deg)
 near(math.sqrt((p.px-128)^2+(p.py-128)^2),1,'unit speed '..deg)
end
local s,p=reset();stick(.625,0);tick(s)
near(p.px,128.5,'partial stick ramps from radial dead zone')
local start=p.px;stick(.2,.1);tick(s);near(p.px,start,'inside radial dead zone holds position')
stick(1,1);start=p.px;local py=p.py;tick(s)
near(math.sqrt((p.px-start)^2+(p.py-py)^2),1,'diagonal input cannot exceed walk speed')
-- Keyboard/touch-style directions also normalize and respect the new gate.
s,p=reset();Input:sourcePress('right','keyboard');Input:sourcePress('up','keyboard');tick(s)
near(p.px-128,1/math.sqrt(2),'digital right contributes diagonal X')
near(p.py-128,-1/math.sqrt(2),'digital up contributes diagonal Y')
-- A stationary facing is retained in orbit views, not reset to an old 3rd yaw.
s,p=reset();FP.yaw=0;stick(1,0);tick(s,3);stick(0,0);tick(s)
T.eq(p.facing,'right','stopping preserves latest travel-facing')
Input:sourcePress('a','keyboard');tick(s)
T.eq(interactions,1,'A reaches native interact once')
T.check(lastInteraction and lastInteraction[1]==131 and lastInteraction[2]==128,'interaction retains the fractional position without snapping')
T.eq(lastInteraction and lastInteraction[3],'right','interaction faces last travel direction')
-- Crossing and idle frames emit a single landing per logical cell.
s,p=reset();stick(1,0);tick(s,40)
T.eq(#entered,3,'40 pixels crosses exactly three cell boundaries from cell centre')
for i=1,#entered do T.eq(entered[i][1],8+i,'cells arrive in order '..i) end
stick(0,0);tick(s,30);T.eq(#entered,3,'standing emits no extra step events')
-- Wall sliding and entity occupancy share native map verdicts.
s,p=reset();for y=0,63 do walls['9,'..y]=true end
stick(1,1);tick(s,30)
T.check(p.px+8<=9*16-FM.RADIUS,'body stops outside solid wall')
T.check(p.py>145,'free axis continues sliding along wall')
s,p=reset();s.entities[2]={cellX=9,cellY=8,targetX=9,targetY=9}
stick(1,0);tick(s,30)
T.check(p.px+8<9*16-FM.RADIUS,'NPC destination blocks continuous walk')
-- Water and tile-pair checks are not bypassed by an analog diagonal.
s,p=reset();waters['9,8']=true;stick(1,0);tick(s,20)
T.eq(p.cellX,8,'non-surfer cannot enter water')
p.surfing=true;tick(s,20);T.eq(p.cellX,9,'surfer can enter water')
s,p=reset();Game.data.field.tilePairs.land={{tileset='plain',a=1,b=2}}
stick(1,0);tick(s,20);T.eq(p.cellX,8,'tile-pair ledge collision remains solid')
Game.data.field.tilePairs.land={}
T.eq(s.ledge,'right','blocked push reaches native ledge handler')
T.eq(s.boulder,'right','blocked push reaches native boulder handler')
s,p=reset(0,8);stick(-1,0);tick(s,20);T.eq(s.edge,'left','map edge reaches native connection handler')
-- The running companion temporarily scales these same constants.
s,p=reset();Game.save.onBike=true;stick(1,0);tick(s);near(p.px,130,'bicycle retains double walking speed')
s,p=reset();FM.WALK=4;stick(1,0);tick(s);near(p.px,132,'running wrapper speed remains effective');FM.WALK=1
-- Forced movement always wins, including an Oak-style NPC escort queue.
s,p=reset();stick(1,0);tick(s,3)
local npc=setmetatable({cellX=12,cellY=8,px=192,py=128,facing='up',moving=false,
 progress=0,stepFrames=16,bikeStepFrames=8,turnTimer=0},Player)
s:scriptMove(npc,'up',1)
T.check(p.px==131 and p.py==128,'NPC-only escort enqueue does not move the player')
s:scriptMove(p,'up',1);s:updateScriptMoves()
T.eq(p.stepFramesCur,16,'escort keeps native script duration')
local before=p.px;s:handleInput();T.eq(p.px,before,'held stick cannot override queued script')
for i=1,16 do p:update();npc:update() end
s:updateScriptMoves();T.eq(#s.scriptMoves,0,'native escort queue drains')
T.eq(p.cellY,7,'native forced move completes on expected tile')
stick(1,0);tick(s);near(p.px,129,'analog resumes after escort from native landing')
s,p=reset();stick(1,0);tick(s,3);p.inputLocked=true;tick(s)
T.eq(p.px,128,'input lock safely seats fractional position')
s,p=reset();s.runner.isRunning=function()return true end;stick(1,0);tick(s)
T.eq(p.px,128,'active script owns player despite held analog')
-- Turning the switch off and selecting 2D restore the native grid route.
s,p=reset();stick(.625,0);tick(s);Game.save.options.jpAnalogWalk=false;stick(0,0);tick(s)
T.eq(p.px,128,'switch off snaps only owned fractional position')
Input:sourcePress('right','keyboard');tick(s);T.check(p.moving,'switch off starts normal native grid step')
local progress=p.progress;tick(s);T.eq(p.progress,progress+1,'native grid animation keeps progressing')
s,p=reset();mods.VoxelState.level=0;stick(1,0);tick(s)
T.check(p.moving and p.cellX==8 and p.targetX==9,'2D keeps native grid movement from physical stick')
-- A held real source survives camera switches; orbit ignores stale free yaw.
s,p=reset();mods.VoxelState.level=7;FP.yaw=0;Input:sourcePress('right','keyboard');tick(s)
near(p.px,127,'third-person right follows camera frame')
mods.VoxelState.level=3;local x=p.px;tick(s)
near(p.px,x+1,'orbit right follows screen after third-person switch')
T.check(Input:isDown('right'),'camera switch does not clear independent physical source')
Input:sourceRelease('right','keyboard');x=p.px;tick(s);near(p.px,x,'release after mode switch stops movement')
s,p=reset();stick(1,0);Game.sessionMenu={}
local mx,mz=FP.moveVector();T.check(mx==0 and mz==0,'system menu excludes analog movement intent')
-- External warps own the new pixel position; dropping old state cannot rewind it.
s,p=reset();stick(1,0);tick(s,3);p.cellX,p.cellY,p.px,p.py=20,21,320,336
Game.save.options.jpAnalogWalk=false;stick(0,0);tick(s)
T.check(p.px==320 and p.py==336,'external warp survives analog handoff')
-- Actual host touch events preserve a pad's analog deflection across mode changes.
local Touch=require('src.core.TouchControls');Touch:init()
-- The new visible stick also works when the physical-stick preference is OFF.
local P=require('src.render.Pipelines')
s,p=reset();Game.data.render_pipelines={voxel={drawWorld=function()end,levels={'OFF','1','2','3','4','5','6','7'}}}
P.install(Game.data);P.setLevel('voxel',3);Touch.active=true;Touch:ensureImages();Touch:applyOptions({jpTouchStick=true,hotbar=false})
Game.save.options.jpAnalogWalk=false;FP.install()
T.check(Touch:stickEnabled(),'visible stick offered on the Japanese 3D field')
local z=Touch:layout().dpad;local radius=z.w/3
Game:touchpressed('real-pad',z.cx+radius*.5,z.cy+radius*.2)
local rx,rz=FP.moveVector();near(rx,.5,'actual touch supplies half-speed X');near(rz,-.2,'actual touch keeps arbitrary angle')
local a=Touch:layout().a;Game:touchpressed('real-a',a.cx,a.cy)
T.check(Input:isDown('a') and Touch.dpadTouch=='real-pad','A and analog stick have independent fingers')
Game:touchmoved('real-pad',z.cx+radius*3,z.cy+radius)
rx,rz=FP.moveVector();near(rx,3/math.sqrt(10),'overshoot preserves radial angle');near(rz,-1/math.sqrt(10),'overshoot stays within unit speed')
local visual=Touch:stickPosition(z);near(visual.x,rx,'thumb graphic matches analog X');near(visual.y,-rz,'thumb graphic matches analog Y')
Game:touchreleased('real-pad',-100,-100);rx,rz=FP.moveVector()
T.check(rx==0 and rz==0 and Input:isDown('a'),'off-control release stops movement while A remains held')
Game:touchreleased('real-a',a.cx,a.cy)
Game:touchpressed('cancel',z.cx+radius,z.cy);Game:focus(false)
T.check(not Touch.dpadTouch and not Input:isDown('right'),'focus loss releases actual stick ownership')
rx,rz=FP.moveVector();T.check(rx==0 and rz==0,'focus loss clears analog vector')
Game:touchreleased('cancel',0,0)
Game.sessionMenu={};T.check(not Touch:stickEnabled(),'system menu returns to directional controls');Game.sessionMenu=nil
Touch:applyOptions({jpTouchStick=false});T.check(not Touch:stickEnabled(),'explicit stick OFF restores the original pad')
P.install({});Touch:reset()
function Touch:hitTest(x,y)return x<100 and 'dpad' or nil end
function Touch:layout()return {dpad={w=80,cx=50,cy=700}} end
function Touch:touchpressed(id,x,y)
 if self:hitTest(x,y)=='dpad' then self.dpadTouch=id;return true end
end
function Touch:touchmoved()end
function Touch:touchreleased(id)if self.dpadTouch==id then self.dpadTouch=nil end end
FP.install()
s,p=reset();Game:touchpressed('pad',90,700)
local tx,tz=FP.moveVector();T.check(tx>0 and tz==0,'orbit touch pad supplies continuous vector')
mods.VoxelState.level=7;FP.syncInputMode()
local sx,sz=FP.moveVector();near(sx,tx,'entering third-person keeps pad magnitude')
mods.VoxelState.level=3;FP.syncInputMode()
sx,sz=FP.moveVector();near(sx,tx,'leaving third-person keeps pad magnitude')
Game:touchreleased('pad',90,700);sx,sz=FP.moveVector()
T.check(sx==0 and sz==0,'release of pad that crossed modes removes analog intent')
local yaw=FP.yaw
Game:touchpressed('plain',250,200);Game:touchmoved('plain',300,240);Game:touchreleased('plain',300,240)
T.eq(FP.yaw,yaw,'orbit free walking does not claim touch look')
Game:touchpressed('cancel-pad',90,700);Game:cancelPointers()
sx,sz=FP.moveVector();T.check(sx==0 and sz==0,'host pointer cancellation clears analog pad')
Game:touchreleased('cancel-pad',90,700)
-- Stored JP-only flags must not alter cartridges whose menus hide them.
for _,language in ipairs({'en',false}) do
 s,p=reset();Game.data.constants.language=language or nil
 stick(.625,0);tick(s)
 T.check(p.moving and p.px==129,'non-JP flagged analog walk retains native grid step')
 for _,level in ipairs({6,7}) do
  s,p=reset();Game.data.constants.language=language or nil;mods.VoxelState.level=level
  FP.yaw=0;stick(.625,0);tick(s)
  T.check(not p.moving and p.px==127.5,'non-JP existing free camera '..level..' keeps continuous walk')
 end
end
T.finish('JP22 analog walking integration')
