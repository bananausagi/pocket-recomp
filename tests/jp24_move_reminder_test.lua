package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP24 optional move reminder')
local R=require('src.pokemon.JapaneseMoveReminder')
local Menu=require('src.ui.JapaneseMoveReminderMenu')
local Party=require('src.ui.PartyMenu')
local Stack=require('src.core.StateStack')
local Rules=require('src.core.JapaneseRules')
local Json=require('src.link.Json')
local Save=require('src.core.SaveData')
local Transfer=require('src.import.SettingsTransfer')
local Runtime=require('src.mods.Runtime')
Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
local data=require('tests.fixture_data').load();data.constants.language='ja'
data.pokemon.FIXMON_A.level1Moves={'TACKLE','GROWL','TACKLE','STRUGGLE'}
data.pokemon.FIXMON_A.learnset={{level=1,move='TACKLE'},{level=7,move='BUBBLE'},
  {level=20,move='BITE'},{level=10,move='GROWL'},{level=10,move='MISSING'}}
data.pokemon.FIXMON_A.tmhm={'SURF'}
for id,pp in pairs({TACKLE=35,GROWL=40,BUBBLE=30,BITE=25,SURF=15,CUT=30,FLY=15,STRENGTH=15,FLASH=20,STRUGGLE=1})do
  data.moves[id]={id=id,name=id,pp=pp}
end
require('src.render.Font').load(data);require('src.core.Strings').load(data)
local function copy(v)if type(v)~='table'then return v end local out={}for k,x in pairs(v)do out[k]=copy(x)end return out end
local function newGame(moves)
  local ow={isOverworld=true,player={}}
  local s=setmetatable({states={ow}},{__index=Stack})
  local mon={species='FIXMON_A',nickname='テスト',level=10,hp=20,stats={hp=30},moves=moves or {{id='TACKLE',pp=12,ppUps=2}},
    dvs={attack=12},statExp={hp=30},exp=1000,status='PSN',otId=5}
  local game={data=data,save={options={jpMoveReminder=true,jpForgetHM=false},party={mon},money=100,inventory={POTION=2}},
    overworld=ow,stack=s,input={wasPressed=function(_,key)return false end}}
  return game,mon
end
local function press(game,screen,key)game.input.wasPressed=function(_,k)return k==key end;screen:update(1/60);game.input.wasPressed=function()return false end end
local function menu(game,mon)local m=Menu.new(game,mon);game.stack:push(m);return m end
local function answer(game,yes)
  local text=game.stack:top();T.check(text.isTextBox and type(text.choice)=='function','real confirmation TextBox carries choice callback')
  game.stack:pop();text.choice(yes)
end
local function clearMessages(game,m)while game.stack:top()~=m do game.stack:pop()end end

do
  local game,mon=newGame()
  T.same(R.candidates(game,mon),{'GROWL','BUBBLE'},'only unknown level-one and reached level-up moves, deduped')
  mon.level=6;T.same(R.candidates(game,mon),{'GROWL'},'future-level moves excluded')
  mon.level=20;T.same(R.candidates(game,mon),{'GROWL','BUBBLE','BITE'},'exact reached level becomes eligible')
  mon.species='FIXMON_B';T.same(R.candidates(game,mon),{'FIX_SCRATCH'},'current species only; no arbitrary pre-evolution or TM moves')
end

for _,block in ipairs({'option','english','link','battle','partyBattle','world','member','script','transition','inputLock'})do
  local game,mon=newGame();local states=game.stack.states
  if block=='option'then game.save.options.jpMoveReminder=false
  elseif block=='english'then game.data=copy(data);game.data.constants.language='en'
  elseif block=='link'then game.linkSession={}
  elseif block=='battle'then states[#states+1]={isBattleState=true}
  elseif block=='partyBattle'then states[#states+1]={battle={}}
  elseif block=='world'then game.stack.states={}
  elseif block=='member'then game.save.party={copy(mon)}
  elseif block=='script'then game.overworld.runner={isRunning=function()return true end}
  elseif block=='transition'then game.overworld.transitioning=true
  elseif block=='inputLock'then game.overworld.player.inputLocked=true end
  local before=Json.encode(game.save)
  T.eq(R.available(game,mon),false,block..' gates the feature')
  T.same(R.candidates(game,mon),{},block..' has no candidates')
  T.eq(R.apply(game,mon,'GROWL',1),false,block..' cannot commit')
  T.eq(Json.encode(game.save),before,block..' leaves every save field intact')
end

for _,bad in ipairs({'SURF','STRUGGLE','TACKLE','BITE','MISSING'})do
  local game,mon=newGame();local before=Json.encode(mon)
  T.eq(R.apply(game,mon,bad,1),false,bad..' is not an eligible reminder move')
  T.eq(Json.encode(mon),before,'invalid candidate never changes mon')
end
for _,index in ipairs({0,3,5,1.5})do
  local game,mon=newGame();T.eq(R.apply(game,mon,'GROWL',index),false,'invalid replacement slot '..index..' rejected')
end

do
  local game,mon=newGame();local before=copy(mon);local opts=Json.encode(game.save.options)
  T.check(R.apply(game,mon,'GROWL',2,R.snapshot(mon,2)),'fills one empty slot')
  T.same(mon.moves[2],{id='GROWL',pp=40},'new finite empty slot starts at ordinary full PP')
  T.same(mon.moves[1],before.moves[1],'empty-slot addition preserves existing PP/PPUP')
  local after=copy(mon);after.moves=before.moves
  T.same(after,before,'move addition changes no HP/status/EXP/stats/OT fields')
  T.eq(Json.encode(game.save.options),opts,'learning never changes settings')
end
do
  local game,mon=newGame({{id='TACKLE',pp=12,ppUps=3},{id='CUT',pp=8},{id='FLY',pp=7},{id='FLASH',pp=6}})
  local untouched=copy({mon.moves[2],mon.moves[3],mon.moves[4]})
  T.check(R.apply(game,mon,'GROWL',1,R.snapshot(mon,1)),'four-slot replacement succeeds')
  T.same(mon.moves[1],{id='GROWL',pp=12},'replacement carries remaining PP with no PPUP transfer')
  T.same({mon.moves[2],mon.moves[3],mon.moves[4]},untouched,'all unselected slots retain exact metadata')
  for i=1,12 do
    local id=i%2==1 and 'TACKLE' or 'GROWL'
    T.check(R.apply(game,mon,id,1,R.snapshot(mon,1)),'repeated swap '..i..' succeeds')
    T.eq(mon.moves[1].pp,12,'repeated swapping never refills PP')
  end
  mon.moves[1].pp=0;T.check(R.apply(game,mon,'BUBBLE',1,R.snapshot(mon,1)),'zero-PP slot can change move')
  T.eq(mon.moves[1].pp,0,'zero-PP remains zero until ordinary healing')
end
do
  local game,mon=newGame({{id='GROWL',pp=60,ppUps=3}})
  T.check(R.apply(game,mon,'BUBBLE',1,R.snapshot(mon,1)),'high-PP replaced move is capped')
  T.eq(mon.moves[1].pp,30,'PP never exceeds new ordinary base maximum')
end
for _,id in ipairs({'CUT','FLY','SURF','STRENGTH','FLASH'})do
  local game,mon=newGame({{id=id,pp=4}});local before=Json.encode(mon)
  local ok,why=R.apply(game,mon,'GROWL',1,R.snapshot(mon,1))
  T.eq(ok,false,id..' retains default HM protection');T.eq(why,'hm','HM refusal reason')
  T.eq(Json.encode(mon),before,'protected HM unchanged')
  game.save.options.jpForgetHM=true
  T.check(R.apply(game,mon,'GROWL',1,R.snapshot(mon,1)),id..' removable with existing independent option')
end
for _,change in ipairs({'slot','pp','ppUps','known','level','option','party','battle'})do
  local game,mon=newGame();local expected=R.snapshot(mon,1)
  if change=='slot'then mon.moves[1]=copy(mon.moves[1])
  elseif change=='pp'then mon.moves[1].pp=3
  elseif change=='ppUps'then mon.moves[1].ppUps=3
  elseif change=='known'then mon.moves[2]={id='BUBBLE',pp=1}
  elseif change=='level'then mon.level=1
  elseif change=='option'then game.save.options.jpMoveReminder=false
  elseif change=='party'then game.save.party={}
  elseif change=='battle'then game.stack:push({isBattleState=true})end
  local before=Json.encode(mon)
  T.eq(R.apply(game,mon,'BUBBLE',1,expected),false,change..' changed during confirmation is rejected')
  T.eq(Json.encode(mon),before,'stale '..change..' does not mutate moves')
end

-- Drive the actual party submenu callback and reminder UI with the real stack.
do
  local game,mon=newGame();local p=Party.new(game);game.stack:push(p);press(game,p,'a')
  local at
  for i,e in ipairs(p.subItems)do if e.id=='jpMoveReminder'then at=i end end
  T.check(at~=nil,'party submenu exposes one optional reminder entry')
  p.subIndex=at;press(game,p,'a');local m=game.stack:top()
  T.eq(getmetatable(m),Menu,'party action opens actual reminder state')
  T.eq(p.submenu,nil,'party submenu closes cleanly under reminder')
  local before=Json.encode(mon);press(game,m,'a')
  T.eq(game.stack:top().defaultNo,true,'move mutation confirmation defaults to No')
  answer(game,false);T.eq(Json.encode(mon),before,'No cancels without mutation')
  press(game,m,'a');answer(game,true)
  T.eq(mon.moves[2].id,'GROWL','Yes actually learns selected move in empty slot')
  clearMessages(game,m);press(game,m,'b');T.eq(game.stack:top(),p,'B returns to same party menu')
end
do
  local game,mon=newGame({{id='TACKLE',pp=8},{id='CUT',pp=9},{id='FLY',pp=10},{id='FLASH',pp=11}})
  local m=menu(game,mon);local before=Json.encode(mon)
  press(game,m,'a');T.eq(m.phase,'replace','full moveset opens replacement selection')
  press(game,m,'b');T.eq(m.phase,'learn','B backs out of replacement selection');T.eq(Json.encode(mon),before,'back preserves all moves')
  press(game,m,'a');press(game,m,'down');press(game,m,'a')
  T.check(game.stack:top().isTextBox and not game.stack:top().choice,'protected HM shows refusal, not mutation prompt')
  clearMessages(game,m);T.eq(Json.encode(mon),before,'HM refusal preserves save')
  press(game,m,'up');press(game,m,'a');answer(game,true)
  T.eq(mon.moves[1].id,'GROWL','confirmed selected replacement commits')
  T.eq(mon.moves[1].pp,8,'menu commit obeys non-refill PP rule')
  T.eq(m.phase,'learn','successful change returns to refreshed candidate list')
end
do
  local game,mon=newGame();local items={{id='custom',action='relearn',label='MOD reminder'}}
  R.addEntry({game=game},items,mon);T.eq(#items,1,'existing MOD relearn action is not duplicated')
  items={};R.addEntry({game=game,battle=true},items,mon);T.eq(#items,0,'battle party submenu never adds entry')
  local m=menu(game,mon);game.save.options.jpMoveReminder=false;press(game,m,'a')
  T.eq(game.stack:top(),game.overworld,'revoked option closes stale reminder safely')
end

-- Shared home/game setting, portable JSON and unchanged existing presets.
do
  local defaults=Save.defaultOptions();T.eq(defaults.jpMoveReminder,false,'default preserves original Gen1 behavior')
  local Home=require('src.import.LauncherSettings');local Options=require('src.ui.OptionsMenu')
  require('src.core.GameVersion').set('red_jp')
  local options=Save.defaultOptions();local game={data=data,save={options=options}}
  local home=Home.open({options=options,save=function()return true end},'red_jp')
  local ingame=Options.new(game)
  local function rows(sections,result)result=result or{}for _,s in ipairs(sections or{})do for _,r in ipairs(s.rows or{})do result[#result+1]=r end;rows(s.children,result)end;return result end
  local function find(list)local out,n;for _,r in ipairs(list)do if r.id=='jpMoveReminder'then out=r;n=(n or 0)+1 end end;return out,n end
  local hr,hn=find(rows(home.sections));local gr,gn=find(ingame.rows)
  T.eq(hn,1,'home contains exactly one reminder setting');T.eq(gn,1,'game contains exactly one reminder setting')
  T.eq(hr.value(),'オフ','home starts Off');T.eq(gr.value(game),'オフ','game starts Off')
  hr.step(1);T.eq(options.jpMoveReminder,true,'home enables feature');T.eq(gr.value(game),'オン','in-game shows same live value')
  gr.step(game,-1);T.eq(options.jpMoveReminder,false,'game disables feature')
  options.jpMoveReminder=true;options.modOptions={keep={x=3}};options.jpAtmosphere='off'
  Rules.applyPreset(options,'classic');T.eq(options.jpMoveReminder,true,'classic three-rule preset preserves independent reminder')
  Rules.applyPreset(options,'convenient');T.eq(options.jpMoveReminder,true,'convenient preset preserves independent reminder')
  T.eq(#Rules.keys,3,'existing presets still control exactly three options')
  for _,value in ipairs({true,false})do
    options.jpMoveReminder=value
    local exported=assert(Transfer.export(options));local restored=assert(Transfer.import(exported,{}))
    T.eq(restored.jpMoveReminder,value,'JSON round-trip boolean '..tostring(value))
    T.same(restored.modOptions,options.modOptions,'JSON retains unrelated MOD options')
    T.eq(restored.jpAtmosphere,'off','JSON retains atmosphere choice')
  end
  local bad=Json.encode({format=Transfer.FORMAT,version=1,options={jpMoveReminder='true'}})
  T.eq(Transfer.import(bad,{}),nil,'portable import rejects non-boolean reminder flag')
end
T.finish()
