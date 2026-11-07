-- ROM-free world localization: actual script callbacks, Commands/ScriptRunner,
-- TextBox/Menu/Font, economy, gift flags and boot/cache defaults. Synthetic
-- imported text is deliberately distinct from the engine fallback catalog.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Japanese world fallback text")
local Version = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Font = require("src.render.Font")
local Data = require("src.core.Data")
local Stack = require("src.core.StateStack")
local Runner = require("src.script.ScriptRunner")
local Commands = require("src.script.Commands")
local TextBox = require("src.render.TextBox")
local Json = require("src.link.Json")
local f = assert(io.open("tools/rom_manifest_red_jp.json", "rb"))
local manifest = assert(Json.decode(f:read("*a"))); f:close()

-- Require the authored templates BEFORE loading any Japanese catalog.
Strings.load({})
local gyms = require("data.scripts.gyms")
local story2 = require("data.scripts.story2")
local story4 = require("data.scripts.story4")
local story5 = require("data.scripts.story5")
local safari = require("data.scripts.safari")
local corner = require("data.scripts.flavor.game_corner")
local roof = require("data.scripts.celadon_eevee")
local school = require("data.scripts.flavor.viridian_school_house")
local observed = {}
local actualNew = TextBox.new
TextBox.new = function(game, text, done, opts)
  observed[#observed + 1] = text
  return actualNew(game, text, done, opts)
end

local function newGame(version)
  version = version or "red_jp"
  Version.set(version)
  local data = require("tests.fixture_data").load()
  data.constants.language = version == "red_jp" and "ja" or nil
  data.text = {}
  data.font.language = "ja"
  data.font.charmap = manifest.fontCharmap
  data.font.composites = manifest.fontComposites
  data.items.HM_FLASH = {name="ひでんマシン05",keyItem=true}
  data.items.COIN_CASE = {name="コインケース",keyItem=true}
  function data:resolveText() return nil end
  Font.load(data); Strings.load(data)
  observed = {}
  return {data=data, options={},save={version=version,
    player={name="てすと",rival="あいて",id=123},party={},flags={},
    pokedex={seen={},owned={}},inventory={},money=2000,coins=0},
    stack=setmetatable({states={}},{__index=Stack})}
end

local function drive(game, answers)
  local answer=0
  for _=1,80 do
    local top=game.stack:top()
    if not top then return end
    game.stack:pop()
    if top.choice then
      answer=answer+1
      top.choice(not answers or answers[answer]~=false)
    elseif top.onDone then top.onDone() end
  end
  error("world script did not settle")
end
local function said(fragment)
  for _,text in ipairs(observed) do
    if text:find(fragment,1,true) then return true end
  end
  return false
end
local function noEnglish(label)
  for _,text in ipairs(observed) do
    local visible=text:gsub("%b{}", ""):gsub("<[^<>]*>", "")
    T.check(not visible:find("[A-Za-z]"),label.." has no English fallback: "..text)
  end
end

-- Item gift guard and bag-full behavior, including runtime template lookup.
do
  local game=newGame()
  local talk=story5.CELADON_DINER.talk.TEXT_CELADONDINER_GYM_GUIDE
  local done=0
  talk(game,{},nil,function()done=done+1 end);drive(game)
  T.eq(game.save.inventory.COIN_CASE,1,"gift added once")
  T.check(game.save.flags.EVENT_GOT_COIN_CASE,"gift event set")
  T.check(said("コインケースを もらった"),"gift's named RAM uses imported item name")
  T.eq(done,1,"gift completes once")
  talk(game,{},nil,function()done=done+1 end);drive(game)
  T.eq(game.save.inventory.COIN_CASE,1,"repeat talk does not duplicate gift")
  T.eq(done,2,"repeat conversation completes")
  noEnglish("gift")

  game=newGame()
  for i=1,20 do game.save.inventory["TEST_ITEM_"..i]=1 end
  talk(game,{},nil,function()end);drive(game)
  T.check(not game.save.flags.EVENT_GOT_COIN_CASE,"full bag keeps gift event unset")
  T.check(not game.save.inventory.COIN_CASE,"full bag gives no item")
  T.check(said("どうぐを もてない"),"full bag failure is Japanese")
end

-- Oak's aide counter formatting and one-time reward flags stay intact.
do
  local game=newGame()
  for i=1,10 do game.save.pokedex.owned[i]=true end
  local done=false
  story4.ROUTE_2_GATE.talk.TEXT_ROUTE2GATE_OAKS_AIDE(game,{},nil,function()done=true end)
  drive(game)
  T.check(done,"aide reward flow completes")
  T.eq(game.save.inventory.HM_FLASH,1,"aide gives Flash")
  T.check(game.save.flags.EVENT_GOT_HM05,"aide flag unchanged")
  T.check(said("10しゅるい"),"aide numeric placeholder survives")
  T.check(said("ひでんマシン05"),"aide localized item placeholder survives")
  noEnglish("aide")
end

-- Coins and flags still match the real authored NPC callbacks.
do
  local game=newGame();game.save.inventory.COIN_CASE=1
  local talk=corner.GAME_CORNER.talk.TEXT_GAMECORNER_FISHING_GURU
  talk(game,{},nil,function()end);drive(game)
  T.eq(game.save.coins,10,"coin giver awards ten")
  T.check(game.save.flags.EVENT_GOT_10_COINS,"coin giver sets original flag")
  T.check(said("10まい"),"coin count formatted after catalog lookup")
  talk(game,{},nil,function()end);drive(game)
  T.eq(game.save.coins,10,"coin giver cannot repeat reward")
  noEnglish("coin giver")
end

-- Safari admission still charges 500 and gives exactly 30 balls / 502 steps.
do
  local game=newGame()
  local ow={player={cellX=0,cellY=0},map={}}
  function ow:scriptMove(_,_,_,done) if done then done() end end
  local talk=safari.SAFARI_ZONE_GATE.talk.TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1
  talk(game,ow,nil,function()end);drive(game)
  T.eq(game.save.money,1500,"Safari charges original fee")
  T.eq(game.save.safari.balls,30,"Safari ball count unchanged")
  T.eq(game.save.safari.steps,502,"Safari initial steps unchanged")
  T.check(said("500えん"),"Safari price Japanese")
  noEnglish("Safari")
  game=newGame();talk(game,ow,nil,function()end);drive(game,{false})
  T.eq(game.save.money,2000,"declining admission costs nothing")
  T.check(not game.save.safari,"declining admission starts no Safari game")
end

-- Fixed table templates resolve at use time and explicit ROM/MOD text wins.
do
  local game=newGame();game.save.flags.EVENT_BEAT_MISTY=true
  game.save.flags.EVENT_GOT_TM11=true
  local talk=gyms.CERULEAN_GYM.talk.TEXT_CERULEANGYM_MISTY
  talk(game,{},nil,function()end);drive(game)
  T.eq(observed[1],"わざマシン11は\nバブルこうせん よ！","gym advice translated after module load")
  game.data.text._CeruleanGymMistyTM11ExplanationText="CUSTOM ROM LINE"
  talk(game,{},nil,function()end);drive(game)
  T.eq(observed[#observed],"CUSTOM ROM LINE","imported/custom advice remains verbatim")
  game.data.text._CeruleanGymMistyTM11ExplanationText=nil
  game.data.strings={["TM11 teaches\nBUBBLEBEAM!"]="カスタム せつめい"}
  Strings.load(game.data);talk(game,{},nil,function()end);drive(game)
  T.eq(observed[#observed],"カスタム せつめい","MOD engine catalog overrides Japanese default")
  game=newGame("red");game.save.flags.EVENT_BEAT_MISTY=true;game.save.flags.EVENT_GOT_TM11=true
  talk(game,{},nil,function()end);drive(game)
  T.eq(observed[1],"TM11 teaches\nBUBBLEBEAM!","overseas advice unchanged")
end

-- Actual Commands/ScriptRunner: literal text and menu labels are display-only.
do
  local game=newGame()
  T.eq(Strings("RED", "world.player"),"レッド","player default has a display context")
  T.eq(Strings("RED"),"RED","plain RED is not translated into a player name")
  local runner=Runner.new(game,nil)
  local finished=0
  local rows={{"show_text","Return to\nPALLET TOWN?"},{"show_text","Return to\nPALLET TOWN?"},{"set_flag","WORLD_TEST_DONE"}}
  runner:run(rows,{onDone=function()finished=finished+1 end})
  for _=1,8 do drive(game);runner:update() end
  T.eq(finished,1,"literal script completes exactly once")
  T.eq(#observed,2,"intentional repeated literal dialogue is retained")
  T.eq(observed[1],"マサラタウンに\nもどりますか？","literal fallback translated")
  T.eq(observed[2],observed[1],"second identical dialogue still shown")
  T.check(game.save.flags.WORLD_TEST_DONE,"script advances through next event")

  local fakeRunner={yield=function()end,resume=function()end}
  local ctx={game=game,save=game.save,runner=fakeRunner,source={modId="CUSTOM"}}
  Commands.show_text(ctx,"Return to\nPALLET TOWN?")
  T.eq(observed[#observed],"Return to\nPALLET TOWN?","MOD literal never auto-translated")
  drive(game)
  ctx.source=nil;game.data.text.KEY="ROM CUSTOM"
  Commands.show_text(ctx,"KEY")
  T.eq(observed[#observed],"ROM CUSTOM","resolved ROM label remains verbatim")
  drive(game)
  Commands.choice(ctx,{"CANCEL","Return to\nPALLET TOWN?"})
  local menu=game.stack:top()
  T.eq(menu.items[1].label,Strings("CANCEL"),"engine choice label localized")
  menu.items[1].onSelect()
  T.eq(ctx.lastChoice.label,"CANCEL","choice logical label stays original")
  game.stack:pop();ctx.source={modId="CUSTOM"}
  Commands.choice(ctx,{"CANCEL"})
  T.eq(game.stack:top().items[1].label,"CANCEL","MOD menu labels preserved")
end

-- Books/blackboard use localized headings, including direct Font draw calls.
do
  local game=newGame()
  T.check(roof.onInteract(game,{},3,4),"TM notebook interact handled")
  T.check(said("わざマシンは"),"static notebook fallback translated at runtime")
  T.check(said("シルフカンパニー"),"notebook supplier line localized")
  noEnglish("notebook")
  game=newGame();roof.onInteract(game,{},3,0)
  local first=game.stack:top();game.stack:pop();first.onDone()
  local prompt=game.stack:top();prompt.stay.onShown()
  local menu=game.stack:top()
  T.eq(menu.items[1].label,"つなぎかた","cable heading localized")
  T.eq(menu.items[4].label,"よむのを やめる","cable menu exit localized")

  game=newGame();school.VIRIDIAN_SCHOOL_HOUSE.onInteract(game,{},3,0)
  first=game.stack:top();game.stack:pop();first.onDone()
  prompt=game.stack:top();prompt.stay.onShown()
  local board=game.stack:top()
  local drawn,ys,realDraw={},{},Font.draw
  Font.draw=function(text,_,y)drawn[#drawn+1]=text;ys[#ys+1]=y end
  board:draw();Font.draw=realDraw
  T.same(drawn,{" ねむり"," どく"," まひ"," やけど"," こおり"," やめる"},"native blackboard headings Japanese")
  T.same(ys,{16,32,48,16,32,48},"blackboard leaves dakuten row between headings")
end

-- Gym statue embeds localized names in genuine named-ROM slots and fallback.
do
  local game=newGame()
  local OW=require("src.world.OverworldController")
  for i=1,100 do
    local name=debug.getupvalue(OW.tryHiddenObject,i)
    if not name then break end
    if name=="Game" then debug.setupvalue(OW.tryHiddenObject,i,game) end
  end
  game.data.field.hiddenExtras={pcTiles={},benchGuys={},gymStatues={PEWTER_GYM={{x=1,y=2}}}}
  local ow=setmetatable({map={id="PEWTER_GYM"},player={facing="up"}},{__index=OW})
  game.data.text._GymStatueText1="{RAM:wGymCityName}\n{RAM:wGymLeaderName}"
  T.check(ow:tryHiddenObject(1,2),"gym statue interaction handled")
  T.eq(observed[#observed],"ニビシティ\nタケシ","Japanese ROM statue slots use Japanese names")
  game.data.text._GymStatueText1=nil
  ow:tryHiddenObject(1,2)
  T.check(said("リーダー タケシ"),"fallback statue fills positional leader slot")
  T.check(not observed[#observed]:find("{RAM}",1,true),"fallback statue has no unresolved RAM")
end

-- Boot defaults fill only absent values: no loaded save or explicit name edits.
do
  Version.set("red_jp")
  local data={constants={language="ja"},field={presetNames={player={"あか"},rival={"みどり"}}}}
  Data.seedDefaults(data,"red_jp")
  T.eq(data.field.boot.playerName,"あか","JP boot chooses actual imported player preset")
  T.eq(data.field.boot.rivalName,"みどり","JP boot chooses actual imported rival preset")
  Data.seedDefaults(data,"red_jp")
  T.eq(data.field.boot.playerName,"あか","cache seed is idempotent")
  data={constants={language="ja"},field={boot={playerName="MY NAME",rivalName="BLUE"},presetNames={player={"あか"},rival={"みどり"}}}}
  Data.seedDefaults(data,"red_jp")
  T.eq(data.field.boot.playerName,"MY NAME","explicit boot player name retained")
  T.eq(data.field.boot.rivalName,"BLUE","explicit English rival name retained")
  data={constants={language="ja"},field={boot={namePresets={player={"MOD NAME"},rival={"MOD RIVAL"}}}}}
  Data.seedDefaults(data,"red_jp")
  T.eq(data.field.boot.playerName,"MOD NAME","explicit preset override respected")
  T.eq(data.field.boot.rivalName,"MOD RIVAL","explicit rival preset override respected")
  data={constants={language="ja"}};Data.seedDefaults(data,"red")
  T.eq(data.field.boot.playerName,"RED","other ROM version retains default")
  T.eq(data.field.boot.rivalName,"BLUE","other ROM rival default retained")
end

-- Every authored fallback preserves named substitution keys and format arity.
for source,translation in pairs(require("src.core.JapaneseStringsWorld")) do
  local function slots(text)
    local out={}
    for token in text:gmatch("%b{}") do out[token]=(out[token] or 0)+1 end
    return out
  end
  T.same(slots(translation),slots(source),"world token contract: "..source)
end
TextBox.new=actualNew
T.finish()
