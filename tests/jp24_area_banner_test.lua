package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Japanese area arrivals')
local Banner=require('src.ui.JapaneseAreaBanner')
local Json=require('src.link.Json')
local data={constants={language='ja'},field={townMap={locations={
  PALLET_TOWN={name='PALLET TOWN'},REDS_HOUSE={name='PALLET TOWN'},
  VIRIDIAN_CITY={name='VIRIDIAN CITY'},POKECENTER={name='VIRIDIAN CITY'},
  MT_MOON_1F={name='MT.MOON'},MT_MOON_B1F={name='MT.MOON'},
  FIX_JP={name='みどりの ひろば'},FIX_EN={name='ENGLISH MOD AREA'},
}}},maps={},strings={}}
local ow={isOverworld=true,player={moving=true},map={id='PALLET_TOWN',def={tileset='OVERWORLD'}}}
local stack={states={ow}};function stack:top()return self.states[#self.states]end
local game={data=data,save={options={jpDialogScale=.75},party={}},overworld=ow,stack=stack}
local before=Json.encode(game.save)
local function update(n,dt)for _=1,n or 1 do Banner.update(game,dt or 1/60)end end
local function visit(id,tileset)
  ow.map={id=id,def={tileset=tileset or 'OVERWORLD'}};update()
end
local function active()return game._jpAreaBanner and game._jpAreaBanner.active end
local function displayed()
  update(20);local a=active();T.check(a~=nil,'new named destination queues a notice')
  if a then a.presented=true;game._jpAreaBanner.lastShown=a.name end
  return a
end
update()
T.eq(active(),nil,'first entry waits for a stable world frame')
local a=displayed();T.eq(a.name,'マサラタウン','town metadata uses established Japanese location name')
update(190);T.eq(active(),nil,'notice expires after visible real time')
update(30);T.eq(active(),nil,'walking and remaining on same map never repeats notice')
visit('REDS_HOUSE','HOUSE');update(20);T.eq(active(),nil,'entering a house never shows town again')
visit('PALLET_TOWN');update(20);T.eq(active(),nil,'leaving same town house never repeats arrival')
visit('ROUTE_1');a=displayed();T.eq(a.name,'1ばんどうろ','known route ID localizes with existing catalog fallback')
visit('VIRIDIAN_CITY');a=displayed();T.eq(a.name,'トキワシティ','crossing into new city shows its name')
visit('ROUTE_1');a=displayed();T.eq(a.name,'1ばんどうろ','a genuine return boundary shows destination again')
visit('MT_MOON_1F','CAVERN');a=displayed();T.eq(a.name,'おつきみやま','named dungeon entry is recognized')
local old=a;visit('MT_MOON_B1F','CAVERN');update(20)
T.eq(active(),old,'changing dungeon floor retains one regional notice')
update(190);visit('MT_MOON_1F','CAVERN');update(20)
T.eq(active(),nil,'return floor transition does not repeat dungeon name')
visit('FIX_EN');update(20);T.eq(active(),nil,'unknown English MOD names do not leak into Japanese UI')
visit('FIX_JP');a=displayed();T.eq(a.name,'みどりの ひろば','authored Japanese town-map name takes precedence')
data.strings['VIRIDIAN CITY']='トキワの ひろば'
visit('VIRIDIAN_CITY');a=displayed();T.eq(a.name,'トキワの ひろば','explicit Japanese MOD translation stays authoritative')
data.strings['VIRIDIAN CITY']=nil
-- No initial notification while a title/intro/fade/dialogue owns the stack.
for _,label in ipairs({'title','dialogue','battle','options','loading'})do
  game._jpAreaBanner=nil;stack.states={ow,{kind=label}};visit('PALLET_TOWN');update(30)
  T.eq(active(),nil,label..' defers first arrival')
  T.eq(Banner.available(game),false,label..' excludes banner drawing')
  stack.states={ow};a=displayed();T.eq(a.name,'マサラタウン',label..' settles after world becomes interactive')
end
for _,key in ipairs({'transitioning','engaging','emote','flyAnim','flyArrive','spinArrive','teleportOut','holeFall','holeArrive'})do
  game._jpAreaBanner=nil;ow[key]=true;visit('ROUTE_2');update(30)
  T.eq(active(),nil,key..' defers arrival');T.eq(Banner.available(game),false,key..' suppresses drawing')
  ow[key]=nil;a=displayed();T.eq(a.name,'2ばんどうろ',key..' deferred destination appears after completion')
end
for _,blocker in ipairs({
  {key='scriptMoves',value={{}}},{key='pendingScripts',value={{}}},
  {key='runner',value={isRunning=function()return true end}},
})do
  game._jpAreaBanner=nil;ow[blocker.key]=blocker.value;visit('ROUTE_3');update(30)
  T.eq(active(),nil,blocker.key..' suppresses scripted scene')
  ow[blocker.key]=nil;displayed()
end
ow.player.inputLocked=true;T.eq(Banner.available(game),false,'script input lock suppresses notice');ow.player.inputLocked=nil
game.sessionMenu={};T.eq(Banner.available(game),false,'paused session menu suppresses notice');game.sessionMenu=nil
-- Offscreen streaming does not change the actual current-map identity.
game._jpAreaBanner=nil;visit('PALLET_TOWN');displayed();update(190)
for n=1,5 do ow.neighbors={{map={id='ROUTE_'..n}}};update(20)end
T.eq(active(),nil,'neighbor streaming/preload never creates an area arrival')
-- Only the destination that remains after scripts/fades is announced.
game._jpAreaBanner=nil;ow.transitioning=true
visit('PALLET_TOWN');visit('ROUTE_1');visit('VIRIDIAN_CITY')
ow.transitioning=nil;a=displayed();T.eq(a.name,'トキワシティ','intermediate blocked maps never enqueue stale notices')
-- A menu pauses a visible notice instead of letting its remaining time expire.
local t=a.time;stack.states={ow,{}};update(300)
T.eq(a.time,t,'covered notice does not consume its visible duration')
stack.states={ow};update(190);T.eq(active(),nil,'resumed notice finishes normally')
-- The real-frame clock has no dependency on the gameplay speed multiplier.
game._jpAreaBanner=nil;visit('PALLET_TOWN');update(20)
a=active();update(300);T.eq(a.time,0,'no countdown before the first actual draw')
a.presented=true;game._jpAreaBanner.lastShown=a.name
update(60);T.check(math.abs(a.time-1)<1e-9,'duration advances by real elapsed seconds')
T.eq(Json.encode(game.save),before,'notices never write preferences, party or save data')
local oldSave=game.save;game.save={options={}}
update(20);T.check(active()~=nil,'new save/session gets an independent first arrival')
game.save=oldSave;data.constants.language='en';update()
T.eq(game._jpAreaBanner,nil,'non-Japanese games stay outside the feature')
T.eq(Banner.available(game),false,'non-Japanese draw is gated')
T.finish()
