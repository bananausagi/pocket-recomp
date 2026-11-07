-- ROM-free behavior/integration checks: real ItemEffects, bag, save codec,
-- overworld step dispatch and TextBox/ChoiceBox input. Only map IO is stubbed.
package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('JP25 repeat repel')
local Repeat = require('src.inventory.JapaneseRepelRepeat')
local Items = require('src.inventory.ItemEffects')
local Bag = require('src.inventory.Bag')
local Stack = require('src.core.StateStack')
local Codec = require('src.core.SaveSerializer')
local Choice = require('src.ui.ChoiceBox')
local OW = require('src.world.OverworldController')
local Game = require('src.core.Game')
local Runtime = require('src.mods.Runtime')
Runtime.install(require('src.mods.Events').new(), require('src.mods.Hooks').new())
require('src.core.GameVersion').set('red_jp')
local data = require('tests.fixture_data').load()
data.constants.language = 'ja'
data.items.REPEL = {name='むしよけスプレー', index=30}
data.items.SUPER_REPEL = {name='シルバースプレー', index=31}
data.items.MAX_REPEL = {name='ゴールドスプレー', index=32}
data.text._RepelWoreOffText = 'スプレーの こうかが\nきれた！{DONE}'
data.text._ItemUseText001 = '{PLAYER}は\n{STRBUF}を つかった！'
local Json = require('src.link.Json')
local mf = assert(io.open('tools/rom_manifest_red_jp.json', 'rb'))
local manifest = assert(Json.decode(mf:read('*a'))); mf:close()
data.font.charmap, data.font.composites = manifest.fontCharmap, manifest.fontComposites
require('src.render.Font').load(data)
require('src.core.Strings').load(data)

local function copy(value) return assert(Codec.decode(Codec.encode(value))) end
local function setup()
  local ow = {isOverworld=true,player={cellX=2,cellY=2,facing='down'},scriptMoves={}}
  Game.data, Game.overworld = data, ow
  Game.save = {version='red_jp',player={name='レッド'},options={jpRepelRepeat=true,textSpeed=1},
    party={},inventory={REPEL=3,SUPER_REPEL=3,MAX_REPEL=3,POTION=2},
    bagOrder={'POTION','SUPER_REPEL','REPEL','MAX_REPEL'},repelSteps=0,
    registeredItem='BICYCLE', flags={}}
  Game.stack = setmetatable({states={ow}}, {__index=Stack})
  Game.input = {wasPressed=function() return false end,isDown=function() return false end}
  Game.linkSession = nil
  return Game, ow
end
local function press(game, key)
  game.input.wasPressed = function(_, button) return button == key end
  game.stack:update(1/60)
  game.input.wasPressed = function() return false end
end
local function reachChoice(game)
  for frame=1,2000 do
    if getmetatable(game.stack:top()) == Choice then return game.stack:top() end
    press(game, frame % 2 == 0 and 'a' or nil)
  end
  error('repeat confirmation never reached its ChoiceBox')
end
local function answer(game, key)
  local choice = reachChoice(game)
  press(game, key)
  for _=1,20 do press(game) end
  T.check(game.stack:top() ~= choice, 'answer exits actual ChoiceBox')
end
local function clear(game, world)
  for frame=1,2000 do
    if game.stack:top() == world then return end
    press(game, frame % 2 == 0 and 'a' or nil)
  end
  error('repel text did not return control to field')
end
local function use(game, id)
  local result = Items.use(game.data, game.save, id)
  T.eq(result,'consumed',id..' follows successful ordinary item-use path')
  Bag.remove(game.save,id,1) -- same consumption owner as BagMenu / favorite use
end

for id,steps in pairs({REPEL=100,SUPER_REPEL=200,MAX_REPEL=250}) do
  local game,ow=setup();use(game,id)
  T.eq(game.save.jpRepelItem,id,'successful use remembers exact '..id)
  T.eq(game.save.repelSteps,steps,id..' initial duration')
  game.save=copy(game.save)
  T.eq(game.save.jpRepelItem,id,'save codec round-trip retains '..id)
  local earlyStops=0
  for _=1,steps-1 do if Repeat.onStep(game,ow) then earlyStops=earlyStops+1 end end
  T.eq(earlyStops,0,'no premature expiry stops across full '..id..' duration')
  T.eq(game.save.repelSteps,1,'entire initial duration counted without shortening')
  local before=copy(game.save)
  T.eq(Repeat.onStep(game,ow),true,'last protected step cannot encounter')
  T.eq(game.save.inventory[id],before.inventory[id],'showing repeat prompt consumes nothing')
  local choice=reachChoice(game)
  T.same(choice.labels,{'はい','いいえ'},'repeat choices explicitly Japanese')
  T.eq(choice.index,1,'routine repeat offers Yes first')
  answer(game,'a')
  T.eq(game.save.repelSteps,steps,'confirmed '..id..' gets full duration')
  T.eq(game.save.inventory[id],before.inventory[id]-1,'Yes consumes exactly one '..id)
  for other,count in pairs(before.inventory) do
    if other~=id then T.eq(game.save.inventory[other],count,'other item untouched: '..other) end
  end
  T.same(game.save.bagOrder,before.bagOrder,'positive remaining stock preserves order')
  T.eq(game.save.registeredItem,before.registeredItem,'favorite unchanged')
  clear(game,ow)
  T.eq(Repeat.onStep(game,ow),false,'accepted prompt does not reappear next step')
  T.eq(game.save.repelSteps,steps-1,'walking resumes after confirmed repeat')
end

for _,key in ipairs({'b','no'}) do
  local game,ow=setup();use(game,'REPEL');game.save.repelSteps=1
  Repeat.onStep(game,ow);local before=copy(game.save.inventory)
  reachChoice(game)
  if key=='no' then press(game,'down');answer(game,'a') else answer(game,'b') end
  T.same(game.save.inventory,before,'decline/cancel never consumes an item')
  T.eq(game.save.repelSteps,0,'decline leaves effect expired')
  T.eq(game.stack:top(),ow,'decline returns to field')
  T.eq(Repeat.onStep(game,ow),false,'declined expiry never prompts again')
  T.eq(game.stack:top(),ow,'no repeat dialog on later ordinary step')
end

for _,kind in ipairs({'none','unknown','out','off','english','missingdef'}) do
  local game,ow=setup();use(game,'SUPER_REPEL');game.save.repelSteps=1
  if kind=='none' then game.save.jpRepelItem=nil
  elseif kind=='unknown' then game.save.jpRepelItem='POTION'
  elseif kind=='out' then game.save.inventory.SUPER_REPEL=nil
  elseif kind=='off' then game.save.options.jpRepelRepeat=false
  elseif kind=='english' then game.data=copy(data);game.data.constants.language='en'
  elseif kind=='missingdef' then game.data=copy(data);game.data.items.SUPER_REPEL=nil end
  local before=copy(game.save.inventory)
  T.eq(Repeat.onStep(game,ow),true,kind..' still protects last step')
  T.eq(game.stack:top().choice,nil,kind..' receives ordinary wore-off text only')
  clear(game,ow)
  T.same(game.save.inventory,before,kind..' never substitutes another repel type')
end

-- Change the context while the modal is open: no stale stock, save or field
-- references may consume an item, and duplicate callbacks are idempotent.
for _,kind in ipairs({'stock','type','option','save','world','script','active','battle'}) do
  local game,ow=setup();use(game,'REPEL');game.save.repelSteps=1
  Repeat.onStep(game,ow);reachChoice(game)
  if kind=='stock' then game.save.inventory.REPEL=nil
  elseif kind=='type' then game.save.jpRepelItem='MAX_REPEL'
  elseif kind=='option' then game.save.options.jpRepelRepeat=false
  elseif kind=='save' then game.save=copy(game.save)
  elseif kind=='world' then game.overworld={}
  elseif kind=='script' then ow.engaging=true
  elseif kind=='active' then game.save.repelSteps=80
  elseif kind=='battle' then game.linkSession={} end
  local before=copy(game.save)
  answer(game,'a')
  T.same(game.save,before,'stale '..kind..' cannot commit repeat')
end
do
  local game,ow=setup();use(game,'REPEL');game.save.repelSteps=1
  Repeat.onStep(game,ow);local callback=game.stack:top().choice
  answer(game,'a');clear(game,ow)
  local before=copy(game.save);callback(true);callback(false)
  T.same(game.save,before,'callback cannot consume same confirmation twice')
end
do
  local game,ow=setup();game.save.inventory.REPEL=2;use(game,'REPEL');game.save.repelSteps=1
  Repeat.onStep(game,ow);answer(game,'a');clear(game,ow)
  T.eq(game.save.inventory.REPEL,nil,'last spare spray removes depleted stack')
  T.same(game.save.bagOrder,{'POTION','SUPER_REPEL','MAX_REPEL'},'last spare removed from bag order only')
  game.save.repelSteps=1;Repeat.onStep(game,ow)
  T.eq(game.stack:top().choice,nil,'no spare left gives ordinary expiry')
end

for _,kind in ipairs({'runner','moves','engaging','emote','teleport','transition','input','stack','argument',
    'pendingScripts','flyAnim','flyArrive','spinArrive','holeFall','holeArrive','playerHidden','cameraPan','healAnim'}) do
  local game,ow=setup();use(game,'MAX_REPEL');game.save.repelSteps=1
  if kind=='runner' then ow.runner={isRunning=function()return true end}
  elseif kind=='moves' then ow.scriptMoves={{}}
  elseif kind=='engaging' then ow.engaging=true
  elseif kind=='emote' then ow.emote={}
  elseif kind=='teleport' then ow.teleportOut={}
  elseif kind=='transition' then ow.transitioning=true
  elseif kind=='input' then ow.player.inputLocked=true
  elseif kind=='stack' then game.stack:push({})
  elseif kind=='pendingScripts' then ow.pendingScripts={{}}
  elseif kind~='argument' then ow[kind]=true end
  local depth=#game.stack.states
  T.eq(Repeat.onStep(game,ow,kind=='argument'),true,'deferred '..kind..' expiry still suppresses encounter')
  T.eq(#game.stack.states,depth,'no intrusive '..kind..' dialog during scripted/locked scene')
  T.eq(game.save.jpRepelExpired,true,'deferred notification is saved')
  game.save=copy(game.save)
  ow.runner=nil;ow.scriptMoves={};ow.engaging=nil;ow.emote=nil;ow.teleportOut=nil
  for _,flag in ipairs({'pendingScripts','flyAnim','flyArrive','spinArrive','holeFall','holeArrive',
      'playerHidden','cameraPan','healAnim'}) do ow[flag]=nil end
  ow.transitioning=nil;ow.player.inputLocked=nil;game.stack.states={ow}
  T.eq(Repeat.onStep(game,ow),true,'pending '..kind..' expiry shown on next safe step')
  T.check(type(game.stack:top().choice)=='function','pending confirmation restored after save/load')
  T.eq(game.save.jpRepelExpired,false,'pending flag cleared exactly once')
  answer(game,'b')
  T.eq(Repeat.onStep(game,ow),false,'deferred expiry not repeated after decline')
end
do
  local game,ow=setup();use(game,'REPEL');game.save.repelSteps=1
  Repeat.onStep(game,ow,true);use(game,'SUPER_REPEL')
  T.eq(game.save.jpRepelExpired,false,'manual new use cancels older deferred notification')
  T.eq(game.save.jpRepelItem,'SUPER_REPEL','new manual spray replaces remembered type')
  T.eq(Repeat.onStep(game,ow),false,'old deferred expiry cannot interrupt fresh spray')
  T.eq(game.save.repelSteps,199,'new manual spray duration remains in effect')
end
do
  local game,ow=setup();use(game,'REPEL');local before=copy(game.save)
  T.eq(Items.use(game.data,game.save,'MAX_REPEL',nil,{}),'failed','mid-battle repel use remains forbidden')
  T.same(game.save,before,'failed mid-battle spray does not change remembered type/counter')
  game.data=copy(data);game.data.constants.language='en';game.save.jpRepelItem=nil
  Items.use(game.data,game.save,'REPEL')
  T.eq(game.save.jpRepelItem,nil,'non-Japanese item use does not write repeat metadata')
  game.save.jpRepelExpired=nil;game.save.repelSteps=1
  Repeat.onStep(game,ow)
  T.eq(game.save.jpRepelExpired,nil,'ordinary non-Japanese expiry does not add repeat metadata')
end

-- Exercise the game's actual persistence API, including options stored in
-- their separate file, migrations and read-time normalization.
do
  local Save=require('src.core.SaveData')
  local game,ow=setup();use(game,'SUPER_REPEL');game.save.repelSteps=17
  T.check(Save.save(game.save),'ordinary save succeeds with active repeat state')
  game.save=assert(Save.load('red_jp'))
  T.eq(game.save.jpRepelItem,'SUPER_REPEL','actual SaveData reload retains spray identity')
  T.eq(game.save.repelSteps,17,'actual SaveData reload retains remaining steps')
  T.eq(game.save.options.jpRepelRepeat,true,'repeat option survives separate options file')
  game.save.repelSteps=1;Repeat.onStep(game,ow,true)
  T.check(Save.save(game.save),'deferred expiry can be saved')
  game.save=assert(Save.load('red_jp'))
  T.eq(game.save.jpRepelExpired,true,'actual SaveData reload retains deferred expiry')
  T.eq(Repeat.onStep(game,ow),true,'reloaded deferred expiry reaches safe field prompt')
  answer(game,'a')
  T.eq(game.save.repelSteps,200,'reloaded confirmation repeats the same silver spray')
  T.eq(game.save.inventory.SUPER_REPEL,1,'reloaded confirmation consumes exactly one item')
end

-- Real onStepComplete reaches the helper before rolling an encounter and
-- resumes encounter checks after No. Authored fixture supplies no warps/events.
do
  local game,ow=setup()
  for _,fn in pairs(OW) do if type(fn)=='function' then
    for i=1,40 do
      local name=debug.getupvalue(fn,i);if not name then break end
      if name=='Game' then debug.setupvalue(fn,i,game)
      elseif name=='mapScripts' then debug.setupvalue(fn,i,{get=function()end}) end
    end
  end end
  ow.map={id='FIX_REPEL',def={index=0,tileset='OVERWORLD'},warpAtCell=function()end,
    isGrassCell=function()return true end,cellTile=function()return 1 end}
  for _,name in ipairs({'syncLastMapRewrite','checkSpinner','checkBadgeGate','checkForcedMovement',
      'checkSeafoamCurrent','safariStep','applyFieldPoison','refreshStandingOnWarp','dirHeld'}) do
    ow[name]=function()return false end
  end
  local rolls=0;ow.rollEncounter=function()rolls=rolls+1 end
  use(game,'REPEL');game.save.repelSteps=1
  OW.onStepComplete(ow)
  T.eq(rolls,0,'real overworld suppresses encounter on last repel step')
  T.check(game.stack:top().choice~=nil,'real overworld opens repeat dialog')
  answer(game,'b');OW.onStepComplete(ow)
  T.eq(rolls,1,'normal encounter checks resume on next step after No')
  T.eq(game.stack:top(),ow,'normal step does not reopen expiry')
end
T.finish()
