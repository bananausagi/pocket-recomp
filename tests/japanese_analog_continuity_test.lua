-- Real fractional walking, native interaction selection and script movement;
-- authored map geometry, no ROM. Handoff offsets are visual-only assertions.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP25 analog interaction continuity')
local Game=require('src.core.Game')
local Input=require('src.core.Input')
local Player=require('src.world.Player')
local NPC=require('src.world.NPC')
local OW=require('src.world.OverworldController')
local Stack=require('src.core.StateStack')
local Camera=require('src.render.Camera')
local Handoff=require('src.world.JapaneseAnalogHandoff')
local Text=require('src.render.TextBox')
local Runtime=require('src.mods.Runtime')
Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
local data=require('tests.fixture_data').load();data.constants.language='ja'
data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
require('src.core.GameVersion').set('red_jp')
require('src.core.Strings').load(data);require('src.render.Font').load(data)
require('src.world.Collision').load(data)
local moving=true
local FP={driving=function()return false end,walkingDriving=function()return moving end,
 releaseBody=function()end,pointTravel=function(x,y)
  if math.abs(x)>=math.abs(y)then return x>=0 and 'right' or 'left' end
  return y>=0 and 'down' or 'up'
 end}
function FP.moveVector()
 local a=Input.stickAxis or{x=0,y=0};return a.x,-a.y
end
local FM=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/FreeMove.lua'))({require=function(name)
 assert(name=='FirstPerson');return FP end})
FM.install()
local registry={get=function()end,talkScript=function()end}
for _,fn in pairs(OW)do if type(fn)=='function'then for i=1,40 do
 local n=debug.getupvalue(fn,i);if not n then break end
 if n=='Game'then debug.setupvalue(fn,i,Game)
 elseif n=='mapScripts'then debug.setupvalue(fn,i,registry)end
end end end
local function near(a,b,label)T.check(math.abs(a-b)<1e-7,label..' ('..a..'/'..b..')')end
local function setup()
 FM.drop();Input:init();Game.input=Input;Game.data=data;Game.sessionMenu=nil;moving=true
 Game.save={player={name='RED'},options={jpAnalogWalk=true,jpFieldActions=false,textSpeed=1},party={},inventory={}}
 local p=Player.new(data,8,8,'right');p.turnArmed=false
 local walls={};local s=setmetatable({player=p,scriptMoves={},marchers={},npcs={},ghosts={},
  camera=Camera.new(),runner={isRunning=function()return false end},map={id='FIX_ANALOG',def={tileset='plain'},
  inBounds=function(_,x,y)return x>=0 and y>=0 and x<64 and y<64 end,
  isWalkableCell=function(_,x,y)return not walls[x..','..y]end,isWaterCell=function()return false end,
  cellTile=function()return 1 end,isCounterCell=function()return false end,signAtCell=function()end}}, {__index=OW})
 s.entities={p};s.steps={};s.interactions={}
 function s:onStepComplete()self.steps[#self.steps+1]={p.cellX,p.cellY}end
 for _,name in ipairs({'tryCardKeyDoor','tryHiddenObject','tryBookshelf','checkEdgeExit',
  'checkLedgeHop','checkBoulderPush','canCollisionWarp'})do s[name]=function()return false end end
 function s:talkTo(npc)
  self.interactions[#self.interactions+1]=npc
  Game.stack:push(Text.new(Game,'TEST'))
 end
 Game.overworld=s;Game.stack=setmetatable({states={s}},{__index=Stack})
 return s,p,walls
end
local function stick(x,y)Input:gamepadaxis(nil,'leftx',x);Input:gamepadaxis(nil,'lefty',y)end
local function tick(s,n)
 for _=1,n or 1 do Input:step();s:handleInput();s.player:update()end
end
local function key(s,key)
 Input:sourcePress(key,'qa');tick(s);Input:sourceRelease(key,'qa');Input:step()
end
local function position(p)local _,x,y=p:pose();return x,y end
local function drain(s)
 for frame=1,500 do
  if Game.stack:top()==s then return end
  if frame%2==0 then Input:sourcePress('a','dialogue')else Input:sourceRelease('a','dialogue')end
  Input:step();Game.stack:update(1/60)
 end
 error('dialogue did not return to the field')
end

for _,axis in ipairs({{.5,0},{0,.5},{.3,.4},{-.4,-.3}})do
 local s,p=setup();stick(axis[1],axis[2]);tick(s,3);stick(0,0);tick(s)
 local px,py=position(p);local cx,cy=p.cellX,p.cellY
 key(s,'a') -- native OW.interact resolves no target on authored empty map
 near(p.px,px,'A without a target keeps X');near(p.py,py,'A without a target keeps Y')
 T.eq(p.cellX,cx,'A keeps logical X');T.eq(p.cellY,cy,'A keeps logical Y')
 T.eq(#s.steps,0,'A never invents a step event')
 stick(axis[1],axis[2]);tick(s)
 near(p.px,px+axis[1],'walking resumes directly from pre-A X')
 near(p.py,py+axis[2],'walking resumes directly from pre-A Y')
end

do
 local s,p=setup();stick(.5,0);tick(s,3);stick(0,0);tick(s)
 local npc=NPC.new(data,'FIX_ANALOG',{index=1,name='FIX_NPC',x=9,y=8,sprite='SPRITE_FIX_NPC',
  movement='STAY',range='NONE',text='TEXT_FIX'})
 s.npcs={npc};s.entities={p,npc}
 local px,py=position(p);local nx,ny=npc.px,npc.py
 key(s,'a')
 T.eq(s.interactions[1],npc,'fractional A reaches same logical-cell NPC')
 T.check(Game.stack:top().isTextBox,'native interaction opens actual dialogue')
 near(p.px,px,'opening dialogue preserves player X');near(p.py,py,'opening dialogue preserves player Y')
 drain(s)
 near(p.px,px,'closing dialogue preserves player X');near(p.py,py,'closing dialogue preserves player Y')
 near(npc.px,nx,'interaction never moves NPC X');near(npc.py,ny,'interaction never moves NPC Y')
 stick(.5,0);tick(s)
 near(p.px,px+.5,'walking resumes without tile-centre rewind after talk')
 tick(s,40)
 T.eq(p.cellX,8,'NPC collision still prevents entering occupied cell')
 T.check(p.px+8<9*16-FM.RADIUS,'continuous body still stops outside NPC')
end

do
 local s,p=setup();stick(.5,.5);tick(s,5);stick(0,0)
 local px,py=position(p)
 -- Use the actual START route with just its destination factory observed.
 local Screens=require('src.ui.Screens');local original=Screens.push
 Screens.push=function(game,name)T.eq(name,'StartMenu','START requests actual start menu');game.stack:push({})end
 key(s,'start');Screens.push=original
 near(p.px,px,'START keeps fractional X');near(p.py,py,'START keeps fractional Y')
 Game.stack:pop();stick(.5,.5);tick(s)
 near(p.px,px+.5,'menu resume retains X');near(p.py,py+.5,'menu resume retains Y')
end

do
 local s,p=setup();stick(.5,.5);tick(s,7);stick(0,0)
 local beforeX,beforeY=position(p);local startCellX,startCellY=p.cellX,p.cellY
 local npc=Player.new(data,12,8,'up');npc.turnArmed=false
 s:scriptMove(npc,'up',1)
 near(p.px,beforeX,'NPC-only script enqueue does not move player X')
 near(p.py,beforeY,'NPC-only script enqueue does not move player Y')
 local finished=0;s:scriptMove(p,'up',1,function()finished=finished+1 end)
 near(p.px,startCellX*16,'player script owns exact native grid X')
 near(p.py,startCellY*16,'player script owns exact native grid Y')
 local x,y=position(p);near(x,beforeX,'script handoff retains rendered X');near(y,beforeY,'script handoff retains rendered Y')
 local previousX,previousY=x,y
 s:updateScriptMoves()
 T.eq(p.stepFramesCur,16,'script move retains original duration')
 for frame=1,16 do
  local completed=p:update();npc:update();s:updateScriptMoves()
  near(p.px,128,'native script X interpolation stays original')
  near(p.py,128-frame,'native script Y interpolation stays original')
  T.eq(completed,frame==16,'original completion tick preserved')
  x,y=position(p)
  T.check(math.abs(x-previousX)<=1 and math.abs(y-previousY)<=2,'smooth bounded visual handoff frame '..frame)
  local bx,by=Handoff.position(p);near(x,bx,'sprite and camera agree on X');near(y,by,'sprite and camera agree on ground Y')
  s.camera:follow(bx,by,160,144)
  near(s.camera.x,bx-64,'orbit camera uses same handoff X');near(s.camera.y,by-64,'orbit camera uses same handoff Y')
  near(by-y,0,'ground offset does not become 3D vertical lift')
  previousX,previousY=x,y
 end
 T.eq(finished,1,'script callback fires exactly once')
 T.eq(#s.scriptMoves,0,'NPC and player script queue drains')
 T.eq(p.cellY,startCellY-1,'script ends on correct tile')
 T.eq(#s.steps,0,'visual interpolation emits no extra onStepComplete')
 stick(.5,0);tick(s);near(p.px,128.5,'analog resumes after native script without leftover offset')
end

do
 local s,p=setup();stick(.5,-.5);tick(s,7);stick(0,0)
 local px,py=position(p);moving=false
 s:handleInput() -- native input starts immediately; rendering keeps old point
 local x,y=position(p);near(x,px,'camera-mode switch retains visual X');near(y,py,'camera-mode switch retains visual Y')
 T.eq(FM._pos(),nil,'grid mode owns movement immediately')
 local offX,offY=Handoff.offset(p)
 for _=1,20 do p:pose()end
 local dx,dy=Handoff.offset(p);near(dx,offX,'render frames do not advance handoff');near(dy,offY,'render frames preserve handoff phase')
 p:update();local visibleX,visibleY=position(p)
 moving=true;s:handleInput()
 near(p.px,visibleX,'early analog resume adopts visual X once');near(p.py,visibleY,'early analog resume adopts visual Y once')
 dx,dy=Handoff.offset(p);near(dx,0,'analog resumes without residual X offset');near(dy,0,'analog resumes without residual Y offset')
end
do
  local s,p=setup();stick(.5,.5);tick(s,7);FM.snap(s)
 p.cellX,p.cellY,p.px,p.py=20,21,320,336
 local x,y=Handoff.position(p);near(x,320,'external warp cancels stale X offset');near(y,336,'external warp cancels stale Y offset')
  local _,vx,vy=p:pose();near(vx,320,'warped sprite at new X');near(vy,336,'warped sprite at new Y')
end
do
 local s,p=setup();stick(.5,.5);tick(s,7);FM.snap(s)
 local replacement={player=p,map=s.map};Game.overworld=replacement
 local x,y=Handoff.offset(p);near(x,0,'new world invalidates old-world X offset');near(y,0,'new world invalidates old-world Y offset')
end
do
 local s,p=setup();stick(.5,.5);tick(s,7);FM.snap(s)
 local weak=setmetatable({world=s,player=p,map=s.map},{__mode='v'})
 Game.overworld=nil;Game.stack.states={};s,p=nil,nil
 collectgarbage('collect');collectgarbage('collect')
 T.eq(weak.world,nil,'paused handoff does not retain previous world')
 T.eq(weak.player,nil,'paused handoff does not retain previous player')
 T.eq(weak.map,nil,'paused handoff does not retain previous map/resources')
end
do
 local s,p=setup();stick(.5,.5);tick(s,7);FM.snap(s)
 p.hopFrames,p.hopTotal=16,32
 local _,x,y=p:pose();local bx,by=Handoff.position(p)
 near(x,bx,'hop keeps horizontal handoff');near(by-y,10,'native hop lift remains ten pixels')
end
do
 local s,p=setup();stick(.5,.5);tick(s,7);FM.snap(s);stick(0,0)
 p.inputLocked=true;Game.save.options.jpFollower=false
 Game.renderer={worldViewSize=function()return 160,144 end}
 s.runner.update=function()end
 for _,method in ipairs({'onSlopeMap','checkTrainerSight','applyPendingSpawnResets'})do
  s[method]=function()return false end
 end
 for frame=1,8 do
  Input:step();OW.update(s,1/60)
  local _,px,py=p:pose()
  near(s.camera.x,px-64,'actual world update follows visual sprite X at handoff '..frame)
  near(s.camera.y,py-64,'actual world update follows visual sprite Y at handoff '..frame)
  near(p.px,128,'actual world update leaves logical X native')
  near(p.py,128,'actual world update leaves logical Y native')
 end
end
-- Returning home unloads the renderer while the native overworld module is
-- cached. A second renderer instance must own the existing input seam.
do
 local s,p=setup();stick(.5,0);tick(s,3);stick(0,0)
 local oldX=p.px
 moving=false -- the retired camera no longer drives the current session
 local freshMoving=true
 local nextFP={driving=function()return false end,
  walkingDriving=function()return freshMoving end,
  releaseBody=function()end,pointTravel=FP.pointTravel,moveVector=FP.moveVector}
 local nextFM=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/FreeMove.lua'))({require=function(name)
  assert(name=='FirstPerson');return nextFP end})
 nextFM.install();stick(.5,0);tick(s)
 near(p.px,oldX+.5,'new renderer session resumes fractional walking with its own camera')
 T.eq(FM._pos(),nil,'retired renderer releases its movement owner')
 T.check(nextFM._pos()~=nil,'new renderer owns the continuous position')
 T.eq(Game.save.options.jpAnalogWalk,true,'session reinstallation retains the saved walking choice')
 freshMoving=false;stick(0,0);tick(s)
 T.eq(nextFM._pos(),nil,'new session can still return to native grid when explicitly disabled')
end
T.finish()
