-- Actual Player + FreeMove + bundled Running Shoes callbacks, no retail ROM.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP24 dash animation cadence')
local Game=require('src.core.Game')
local Player=require('src.world.Player')
local OW=require('src.world.OverworldController')
local Hooks=require('src.mods.Hooks')
local Runtime=require('src.mods.Runtime')
local Json=require('src.link.Json')
local Data=require('tests.fixture_data').load()
Data.constants.language='ja';Data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
Game.data=Data
require('src.world.Collision').load(Data)
local held,mx,mz=false,1,0
Game.input={isDown=function(_,key)return key=='b' and held end,wasPressed=function()return false end}
Game.save={onBike=false,options={}}
local FP={driving=function()return false end,
  pointTravel=function(x,z)return x>=0 and 'right' or 'left'end,
  moveVector=function()return mx,mz end,releaseBody=function()end}
local FM=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/FreeMove.lua'))({require=function(name)
 assert(name=='FirstPerson');return FP
end})
local opts,defaults={},{}
local hooks=Hooks.new();local originalHooks=Runtime.hooks;Runtime.hooks=hooks
local mod={options={define=function(_,rows)for _,r in ipairs(rows)do defaults[r.key]=r.default end end,
 get=function(_,key)if opts[key]~=nil then return opts[key] end;return defaults[key]end},
 hooks={wrap=function(_,name,fn)return hooks:wrap(name,fn,0,'running_shoes')end},
 events={on=function()end},log={info=function()end},
 find=function(id)if id=='DRAMALESS_SHAPE'then return{id=id,version='test',exports={lib={require=function(name)
 assert(name=='FreeMove');return FM end}}}end end}
assert(loadfile('vendor/jp-mods/running_shoes/main.lua'))()(mod)
opts.fx='off'
local report={authoredAssets=true,physicalAndroid=false,sequences={}}
local function refresh()Runtime.call('input.step',function()end,Game,1/60)end
local function state(bike,b,language)
 FM.drop();held=b;mx,mz=1,0;Game.save.onBike=bike;Data.constants.language=language or 'ja'
 opts.speed='2';opts.bike=true
 local p=Player.new(Data,4,4,'right');p.turnArmed=false
 local s=setmetatable({player=p,isOverworld=true,scriptMoves={},marchers={},runner={isRunning=function()return false end},
 map={id='FIX_TEST',def={tileset='FIX_OUT'},inBounds=function()return true end,
 isWalkableCell=function()return true end,cellTile=function()return 0 end},
 onStepComplete=function()end,onSlopeMap=function()return false end,
 checkEdgeExit=function()return false end,checkLedgeHop=function()return false end,
 checkBoulderPush=function()return false end,canCollisionWarp=function()return false end},{__index=OW})
 s.entities={p};Game.overworld=s;Game.stack={top=function()return s end}
 return s,p
end
local function sample(p)
 local _,x,y,face,phase,flip=p:pose()
 return {x=x,y=y,phase=phase,flip=flip,clock=p.animClock,step=p.stepFramesCur}
end
local function runGrid(s,p,n)
 local out={}
 for i=1,n do refresh();if not p.moving then p:tryMove('right',s.map,s.entities)end;p:update();out[i]=sample(p)end
 return out
end
local function runFree(s,p,n)
 local out={}
 for i=1,n do refresh();FM.tick(s);p:update();out[i]=sample(p)end
 return out
end
local cases={
 {id='walk',bike=false,b=false,distance=16,clock=16},
 {id='run',bike=false,b=true,distance=32,clock=32},
 {id='bike',bike=true,b=false,distance=32,clock=16},
 {id='bike-boost',bike=true,b=true,distance=64,clock=32},
}
for _,mode in ipairs({'grid','free'})do
 for _,case in ipairs(cases)do
  local s,p=state(case.bike,case.b)
  local seq=(mode=='grid' and runGrid or runFree)(s,p,16)
  T.eq(p.px-64,case.distance,mode..' '..case.id..' existing displacement unchanged')
  T.eq(p.animClock,case.clock,mode..' '..case.id..' feet match intended cadence')
  T.eq(p.jpFreeAnimRate,nil,mode..' '..case.id..' no pending free cadence after update')
  for i,frame in ipairs(seq)do
   local expected=i*case.clock/16
   T.eq(frame.phase,expected%16>=4 and expected%16<12 and 1 or 0,mode..' '..case.id..' frame '..i..' continuous native pose')
   T.eq(frame.flip,math.floor(expected/16)%2==1,mode..' '..case.id..' frame '..i..' alternating foot')
  end
  report.sequences[mode..'-'..case.id]=seq
 end
end
-- Actual RUN SPEED choices use rounded/floored durations, not nominal factors.
for _,speed in ipairs({'1.5','2','3','4'})do
 local s,p=state(false,true);opts.speed=speed
 local frames=p:stepLength('right');local expected=math.max(4,math.floor(16/tonumber(speed)+.5))
 T.eq(frames,expected,'grid retains real shoe duration '..speed)
 T.eq(p.jpStepAnimRate,16/expected,'grid cadence uses actual duration '..speed)
 local sf,pf=state(false,true);opts.speed=speed;runFree(sf,pf,1)
 T.eq(pf.animClock,tonumber(speed),'free intent cadence follows shoe option '..speed)
 T.eq(FM.WALK,1,'Running Shoes restores WALK after '..speed)
 T.eq(FM.BIKE,2,'Running Shoes restores BIKE after '..speed)
end
-- Changing B midway through a tile must not change interpolation or pose phase.
do
 local s,p=state(false,true);runGrid(s,p,3);held=false
 for _=1,5 do refresh();p:update()end
 T.eq(p.px,80,'release B mid-run still finishes the original 8-frame tile')
 T.eq(p.animClock,16,'release B keeps current step cadence until its landing')
 T.eq(p.jpStepAnimRate,nil,'landing releases manual cadence ownership')
 runGrid(s,p,1);T.eq(p.animClock,17,'following ordinary step resumes original cadence')
end
-- Free cadence lives for one Player:update, never a release, menu or script.
do
 local s,p=state(false,true);runFree(s,p,1);local clock=p.animClock
 mx=0;runFree(s,p,1)
 T.eq(p.animClock-clock,1,'stopping only drains existing bonk at normal speed')
 clock=p.animClock;runFree(s,p,1);T.eq(p.animClock,clock,'fully stopped free walk no longer animates')
 mx=1;refresh();FM.tick(s);T.eq(p.jpFreeAnimRate,2,'free frame has pending boosted cadence')
 FM.drop();T.eq(p.jpFreeAnimRate,nil,'dropping free camera clears pending intent')
 clock=p.animClock;p:update();T.eq(p.animClock-clock,1,'camera handoff cannot retain boosted cadence')
end
-- Firm wall pushes keep the original in-place gait; count intent not distance.
do
 local s,p=state(false,true);s.map.isWalkableCell=function(_,x)return x==4 end
 runFree(s,p,20);local x,clock=p.px,p.animClock;runFree(s,p,1)
 T.eq(p.px,x,'wall still blocks boosted free movement')
 T.eq(p.animClock-clock,2,'blocked run retains deliberate fast in-place gait')
end
-- A script following manual running always gets native frame count and cadence.
for _,free in ipairs({false,true})do
 local s,p=state(false,true)
 if free then runFree(s,p,2);FM.snap(s)else runGrid(s,p,8)end
 local start=p.animClock
 local completed=false
 s:scriptMove(p,'down',1,function()completed=true end);s:updateScriptMoves()
 T.eq(p.stepFramesCur,16,'escort duration after '..tostring(free)..' free mode stays native')
 T.eq(p.jpStepAnimRate,nil,'escort clears dash cadence after '..tostring(free)..' free mode')
 for _=1,16 do refresh();FM.tick(s);p:update();s:updateScriptMoves()end
 T.eq(p.animClock-start,16,'escort cadence after '..tostring(free)..' free mode stays native')
 T.check(completed and #s.scriptMoves==0,'escort drains normally despite B after '..tostring(free)..' free mode')
end
-- Old ROMs retain prior animation with the same existing speed modifier.
for _,language in ipairs({'en','de'})do for _,mode in ipairs({'grid','free'})do
 local s,p=state(false,true,language);(mode=='grid' and runGrid or runFree)(s,p,16)
 T.eq(p.px-64,32,language..' '..mode..' existing run speed remains')
 T.eq(p.animClock,16,language..' '..mode..' original animation unchanged')
end end
-- Disable bike boost and live locks without affecting the recorded pose rate.
do
 local s,p=state(true,true);opts.bike=false;runFree(s,p,8)
 T.eq(p.animClock,8,'bike boost OFF keeps normal pedal cadence')
 p.inputLocked=true;local x,clock=p.px,p.animClock;runFree(s,p,1)
 T.eq(p.px,p.cellX*16,'input lock snaps only existing free position')
 T.eq(p.jpFreeAnimRate,nil,'input lock has no pending boosted cadence')
 T.check((p.animClock-clock)<=1,'input lock cannot keep boosted footstep rate')
end
Runtime.hooks=originalHooks
local output=os.getenv('JP_QA_RUNNING_OUT')
if output then local f=assert(io.open(output..'/sequences.json','wb'));f:write(assert(Json.encode(report)));f:close()end
T.finish()
