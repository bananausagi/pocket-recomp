-- Actual host timing + native Player/3D walker + bundled Running Shoes.
-- Synthetic open map: no ROM, graphics or hardware timing claims.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP28 real-time 3D walking')
local Game=require('src.core.Game')
local Input=require('src.core.Input')
local Touch=require('src.core.TouchControls')
local Player=require('src.world.Player')
local OW=require('src.world.OverworldController')
local Fixed=require('src.core.FixedStep')
local Hooks=require('src.mods.Hooks')
local Runtime=require('src.mods.Runtime')
local Json=require('src.link.Json')
local Data=require('tests.fixture_data').load()
Data.constants.language='ja';Data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
Game.data=Data;Game.input=Input;Input:init();Touch:init()
require('src.world.Collision').load(Data)
-- Only presentation/audio services are isolated; Game:update is the real host.
require('src.world.JapaneseHabitats').observe=function()end
require('src.ui.JapaneseAreaBanner').update=function()end
require('src.render.Tilt').update=function()end
require('src.render.Pipelines').update=function()end
package.loaded['src.core.DiscordPresence']={update=function()end}
Game.updateAudio=function()end
local speed=1
Game.logicSpeed=function()return speed end
local base=(os.getenv('JP28_MOVEMENT_BASE') or '.')..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/'
local mods={VoxelState=dofile(base..'VoxelState.lua'),Mat4=dofile(base..'Mat4.lua'),
 Voxel3D={available=function()return true end},WorldCurve={k=function()return 0 end},
 ModSetting={new=function()return {get=function()return false end}end}}
local V
V={require=function(name)
 if not mods[name] then mods[name]=assert(loadfile(base..name..'.lua'))(V)end
 return mods[name]
end}
local FP,FM=V.require('FirstPerson'),V.require('FreeMove')
FM.install()
-- Fixed fixture pad dimensions; actual Game touch wrapper and Input used.
function Touch:hitTest(x,y)return x>=60 and x<=140 and y>=660 and y<=740 and 'dpad' or nil end
function Touch:layout()return {dpad={w=80,cx=100,cy=700}}end
function Touch:touchpressed(id,x,y)if self:hitTest(x,y)=='dpad'then self.dpadTouch=id;return true end end
function Touch:touchmoved()end
function Touch:touchreleased(id)if self.dpadTouch==id then self.dpadTouch=nil end end
FP.install()
local hooks=Hooks.new();Runtime.hooks=hooks
local opts,defaults={},{}
local mod={options={define=function(_,rows)for _,r in ipairs(rows)do defaults[r.key]=r.default end end,
 get=function(_,key)if opts[key]~=nil then return opts[key] end;return defaults[key]end},
 hooks={wrap=function(_,name,fn)return hooks:wrap(name,fn,0,'running_shoes')end},
 events={on=function()end},log={info=function()end},
 find=function(id)if id=='DRAMALESS_SHAPE'then return{id=id,version='test',exports={lib={require=function(name)
 assert(name=='FreeMove');return FM end}}}end end}
assert(loadfile('vendor/jp-mods/running_shoes/main.lua'))()(mod)
opts.fx='off';opts.speed='2';opts.bike=true
local report={rom=false,physicalAndroid=false,durationSeconds=2,cases={},limits={}}
local function near(a,b,msg)T.check(math.abs(a-b)<1e-6,msg..' ('..a..' vs '..b..')')end
local function reset(mode,bike,b,source)
 FM.drop();Input:reset();Game.sessionMenu=nil
 Game.save={onBike=bike,options={jpAnalogWalk=mode~='grid'}}
 mods.VoxelState.level=mode=='first' and 6 or mode=='third' and 7 or 3
 FP.yaw=math.pi
 local p=Player.new(Data,64,64,'right');p.turnArmed=false
 local s=setmetatable({player=p,isOverworld=true,scriptMoves={},marchers={},runner={isRunning=function()return false end},
 map={id='FIX_TEST',def={tileset='FIX_OUT'},inBounds=function()return true end,
 isWalkableCell=function()return true end,cellTile=function()return 0 end},
 onStepComplete=function(self)self.landings=(self.landings or 0)+1 end,onSlopeMap=function()return false end,
 checkEdgeExit=function()return false end,checkLedgeHop=function()return false end,
 checkBoulderPush=function()return false end,canCollisionWarp=function()return false end,
 interact=function()end},{__index=OW})
 s.entities={p};Game.overworld=s;Game.stack={states={s},top=function()return s end}
 if b then Input:sourcePress('b','keyboard')end
 if source=='touch' then Game:touchpressed('pad',100+80/3,700)
 elseif source=='stick' then Input:gamepadaxis(nil,'leftx',1)
 else Input:sourcePress('right','keyboard')end
 Fixed.refreshPeriod=nil
 local steps=0
 Fixed:init(function(dt)
  steps=steps+1;Runtime.call('input.step',function()end,Game,dt);Input:step()
  if mode=='grid'then
   if not p.moving then p:tryMove('right',s.map,s.entities)end
  else s:handleInput()end
  p:update()
 end)
 return s,p,function()return steps end
end
local cases={
 {id='walk',bike=false,b=false,pxPerTick=1},
 {id='run',bike=false,b=true,pxPerTick=2},
 {id='bike',bike=true,b=false,pxPerTick=2},
 {id='bike-boost',bike=true,b=true,pxPerTick=4},
}
for _,hz in ipairs({60,Fixed.GB_HZ})do
 Fixed.setHz(hz)
 for _,fps in ipairs({20,30,60,120})do for _,rate in ipairs({1,4})do
  speed=rate
  for _,mode in ipairs({'grid','orbit','first','third'})do for _,case in ipairs(cases)do
   local s,p,count=reset(mode,case.bike,case.b,'keyboard')
   for _=1,fps*2 do Game:update(1/fps)end
   local frames=math.floor(hz*2*rate+0.02)
   local distance=math.sqrt((p.px-1024)^2+(p.py-1024)^2)
   local label=('%s %s %gHz %dfps %dx'):format(mode,case.id,hz,fps,rate)
   T.eq(count(),frames,label..' elapsed time supplies full native tick count')
   near(distance,frames*case.pxPerTick,label..' distance matches original walk/run/bike')
   report.cases[#report.cases+1]={mode=mode,action=case.id,logicHz=hz,fps=fps,speed=rate,ticks=count(),distance=distance}
  end end
 end end
end
Fixed.setHz(60);speed=1
-- The visible arrow centre must give full speed in every continuous view.
for _,mode in ipairs({'orbit','first','third'})do
 for _,source in ipairs({'touch','stick'})do
  local s,p,count=reset(mode,false,false,source)
  for _=1,120 do Game:update(1/60)end
  near(math.sqrt((p.px-1024)^2+(p.py-1024)^2),120,mode..' '..source..' arrow/full-stick speed equals grid')
  if source=='touch'then Game:touchreleased('pad',100+80/3,700)end
 end
end
-- Centre micro-adjustment and physical analog range remain available.
do
 local s,p=reset('third',false,false,'touch')
 Game:touchmoved('pad',100+80/6,700)
 local x,z=FP.moveVector();near(math.sqrt(x*x+z*z),.5,'inner half-radius remains half-speed')
 Game:touchmoved('pad',100,700);x,z=FP.moveVector();near(x*x+z*z,0,'pad centre remains stopped')
 Game:touchreleased('pad',100,700)
 Input:gamepadaxis(nil,'leftx',.625);x,z=FP.moveVector();near(math.sqrt(x*x+z*z),.5,'physical stick response unchanged')
 Input:gamepadaxis(nil,'leftx',.2);x,z=FP.moveVector();near(x*x+z*z,0,'physical stick deadzone unchanged')
end
-- Catch-up is bounded even during long stalls; explicit seam suppression wins.
for _,rate in ipairs({1,4,200})do
 speed=rate;local s,p,count=reset('third',false,true,'keyboard')
 Game:update(10)
 local cap=rate==1 and 4 or 15
 T.check(count()<=cap,'ten-second hitch capped at '..cap..' ticks at '..rate..'x')
 report.limits[#report.limits+1]={speed=rate,longHitchTicks=count()}
 local start=count();Fixed:discardCatchup();Game:update(.25)
 T.eq(count()-start,1,'map-seam suppressCatchup stays one tick at '..rate..'x')
 T.check(Fixed.accum>=0 and Fixed.accum<Fixed.STEP,'seam clears old timing debt')
end
-- Frame variations around 20/30fps must not discard the fractional clock.
for _,periods in ipairs({{1/20-.001,1/20+.001},{1/30-.001,1/30+.001},{1/60,1/20}})do
 speed=1;local s,p,count=reset('third',false,false,'keyboard')
 local time=0
 for n=1,120 do local dt=periods[(n-1)%2+1];time=time+dt;Game:update(dt)end
 local expected=time*60
 T.check(math.abs(count()-expected)<=1.01,'jitter retains elapsed tick count at '..1/((periods[1]+periods[2])*.5)..'fps ('..count()..' vs '..expected..')')
end
local out=os.getenv('JP28_MOVEMENT_OUT')
if out then local f=assert(io.open(out..'/rates.json','wb'));f:write(assert(Json.encode(report)));f:close()end
T.finish()
