-- Real save serialization/backup/load and native map transition entry points.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP40 autosave and area continuity')
local Game=require('src.core.Game');local Save=require('src.core.SaveData')
local Version=require('src.core.GameVersion');Version.set('red_jp')
local Auto=require('src.core.JapaneseAutoSave');local Stack=require('src.core.StateStack')
local OW=require('src.world.OverworldController');local Player=require('src.world.Player')
local Transition=require('src.render.Transition');local Pipelines=require('src.render.Pipelines')
local Handoff=require('src.world.JapaneseAnalogHandoff')
local Runtime=require('src.mods.Runtime');Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
for _,fn in pairs(OW)do if type(fn)=='function'then for i=1,40 do
 local n=debug.getupvalue(fn,i);if not n then break end;if n=='Game'then debug.setupvalue(fn,i,Game)end
end end end
local files={};local fail=false;local writes=0
love.filesystem={read=function(p)return files[p]end,write=function(p,s)
 if fail and p:find('saves/',1,true)==1 then return false,'injected write failure' end
 files[p]=s;return true end,remove=function(p)files[p]=nil;return true end,
 getInfo=function(p)return files[p] and {type='file',size=#files[p]}end,createDirectory=function()return true end}
Save.resetSlotState();Save.invalidateOptions()
local slot=assert(Save.createSlot('red_jp'));assert(Save.setActiveSlot('red_jp',slot))
Game.save=Save.newGame({version='red_jp'});Game.save.options=Save.defaultOptions()
Game.syncEngine=function()return nil end
local p=setmetatable({cellX=5,cellY=5,px=80,py=80,facing='down',moving=false,stepFrames=16,turnTimer=0,animClock=0},Player)
local ow=setmetatable({player=p,map={id='ROOM',def={tileset='POKECENTER'}},scriptMoves={},npcs={},entities={p}}, {__index=OW})
function ow:captureSave(s)writes=writes+1;s.player.x=p.cellX;s.player.y=p.cellY;s.player.map=self.map.id end
Game.overworld=ow;Game.stack=setmetatable({states={ow}},{__index=Stack})
Game.data={constants={language='ja'},field={},maps={}}
local function tick(n)for _=1,n do Auto.update(Game,.25)end end
local path='saves/red_jp/'..slot..'.lua'
tick(239);T.check(not files[path],'no save before one-minute interval')
tick(2);T.check(files[path]~=nil and writes==1,'one-minute autosave writes actual active slot')
T.eq(Save.load('red_jp').player.map,'ROOM','Continue reads the autosaved location')
local before=files[path]
p.px=80.25;for _=1,250 do p.px=p.px+.1;Auto.update(Game,.25)end
T.eq(files[path],before,'fractional walking cannot trigger a save in motion')
for _,flag in ipairs({'transitioning','healAnim','fishing','cutAnim','engaging'})do
 ow[flag]=true;tick(8);T.eq(files[path],before,flag..' blocks a pending save');ow[flag]=nil
end
p.moving=true;tick(8);T.eq(files[path],before,'native walking blocks save');p.moving=false
ow.runner={isRunning=function()return true end};tick(8);T.eq(files[path],before,'script blocks save');ow.runner=nil
local battle={};Game.stack.states={ow,battle};Game.save.money=4200;tick(8)
T.eq(files[path],before,'battle snapshot never reaches current slot')
Game.stack.states={ow};tick(4);T.eq(Save.load('red_jp').money,4200,'battle return saves rewards after field settles')
Game.save.options.jpAutoSave=false;Auto.update(Game,.25);local count=writes;tick(300)
T.eq(writes,count,'explicit OFF prevents all automatic writes')
Game.save.options.jpAutoSave=true;tick(10);assert(Game:writeSave());count=writes;tick(239)
T.eq(writes,count,'manual report resets the autosave interval')
Game.save.money=5000;fail=true;tick(4);T.eq(Save.load('red_jp').money,4200,'failed autosave preserves prior readable bytes')
count=writes;tick(20);T.eq(writes,count,'failed storage retries with a cooldown')
fail=false;tick(60);T.eq(Save.load('red_jp').money,5000,'autosave recovers after storage becomes writable')
local savedFirst=files[path];local slot2=assert(Save.createSlot('red_jp'));assert(Save.setActiveSlot('red_jp',slot2))
Game.save=Save.newGame({version='red_jp'});Game.save.options=Save.defaultOptions();Game.save.money=777
Auto.update(Game,.25);tick(240)
T.eq(files[path],savedFirst,'another playthrough keeps the first slot byte-identical')
T.eq(Save.load('red_jp').money,777,'new active slot receives its own autosave')
Game.save.money=888;tick(10);T.check(Auto.flush(Game),'background flush saves an idle field')
T.eq(Save.load('red_jp').money,888,'background save uses the real load path')
-- Ordinary JP 3D door/stair warps retain the old map/palettes until ready.
Game.data.render_pipelines={voxel={drawWorld=function()end},_owners={voxel='DRAMALESS_SHAPE'}}
Pipelines.install(Game.data);Pipelines.setLevel('voxel',1)
local ready=false;local prepared;local entries=0;local finished=0
Game.mods={exports={DRAMALESS_SHAPE={prepareMapTransition=function(id)prepared=id;return function()return ready end end}}}
function ow:setMap(id,x,y,facing)entries=entries+1;self.map={id=id,def={tileset='POKECENTER'}};p.cellX,p.cellY=x,y;p.px,p.py=x*16,y*16;p.facing=facing end
ow:startWarpTo('NEXT',3,4,'down',function()finished=finished+1 end)
local tr=Game.stack:top();T.eq(prepared,'NEXT','native warp invokes installed renderer preparation')
for _=1,40 do tr:update(1/60);T.check(tr:alpha()==0 and tr:bgp()==0xE4 and tr:obp0()==0xD0,'loading never darkens world or sprites')end
T.eq(entries,0,'destination scripts/map entry do not run during preparation')
T.check(ow.transitioning and Game.stack:top()==tr,'input remains gated on old scenery')
ready=true;tr:update(1/60);tr:update(1/60)
T.check(entries==1 and finished==1 and Game.stack:top()==ow and not ow.transitioning,'ready area enters once and releases transition')
local failed=Transition.new(Game,function()entries=entries+1 end,nil,true,{noFade=true,ready=function()error('renderer failed')end})
Game.stack:push(failed);failed:update(1/60);T.eq(Game.stack:top(),ow,'renderer error releases loading without black fade')
Pipelines.setLevel('voxel',0);ow:startWarpTo('FLAT',1,1);T.check(not Game.stack:top().noFade,'original 2D warp timing is unchanged');Game.stack:pop();ow.transitioning=false
-- Actual seam routine rebases a fractional visible point into the new map.
local Map=require('src.world.Map');local originalPassable=Map.defPassable;Map.defPassable=function()return true end
function ow:connectionLanding()return {},{},8,0 end
function ow:stopSurfingOntoLand()end
ow.camera=require('src.render.Camera').new()
p.cellX,p.cellY,p.px,p.py=8,63,131.25,1012.5;p.facing='down'
local oldX,oldY=Handoff.position(p)
T.check(ow:crossConnection('down',{map='SEAM'}),'native connection accepts destination')
local vx,vy=Handoff.position(p)
T.check(math.abs(vx-(oldX+(p.cellX-8)*16))<1e-7 and math.abs(vy-(oldY+(p.cellY-63)*16))<1e-7,'seam preserves sub-cell position across coordinate rebasing')
local lastX,lastY=vx,vy
for _=1,16 do p:update();vx,vy=Handoff.position(p);T.check(math.abs(vx-lastX)<1 and math.abs(vy-lastY)<2,'native seam step settles without a snap');lastX,lastY=vx,vy end
Map.defPassable=originalPassable
T.finish()
