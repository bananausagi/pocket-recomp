-- ROM-free: synthetic text/data, real script rows, Commands, ScriptRunner,
-- TextBox, naming/dex screens and party/box mutations. NPC steps are driven
-- by a small deterministic scheduler; this does not claim visual ROM parity.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Japanese starter dialogue")
local Version = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local Runner = require("src.script.ScriptRunner")
local Stack = require("src.core.StateStack")
local Screens = require("src.ui.Screens")
local Font = require("src.render.Font")
local Json = require("src.link.Json")
local Extractor = require("src.import.RomExtractor")
local Collision = require("src.world.Collision")
local script = require("data.scripts.oaks_lab")
local f = assert(io.open("tools/rom_manifest_red_jp.json", "rb"))
local manifest = assert(Json.decode(f:read("*a"))); f:close()

-- Use the actual manifest's RAM token contract with invented bytecode.
local function syntheticROMText(label)
  local bytes = string.char(0,128,0x50,1,0,0,0,129,0x57)
  local m = {language="ja", symbols={[label]={0,0}},
    charmap={["128"]="あ",["129"]="い"},text={lengths={[label]=#bytes}}}
  local ex = Extractor.new(bytes,m)
  return ex:decodeTextCommands(ex:symbol(label),manifest.text.dynamic[label] or {})
end

local function newGame(version)
  Version.set(version); Screens.invalidate()
  local data = require("tests.fixture_data").load()
  data.constants.language = version == "red_jp" and "ja" or nil
  local defs = {CHARMANDER="FIXMON_A",SQUIRTLE="FIXMON_B",BULBASAUR="FIXMON_C"}
  local names = {CHARMANDER="あか",SQUIRTLE="あお",BULBASAUR="みどり"}
  for id, fixture in pairs(defs) do
    data.pokemon[id] = data.pokemon[fixture]
    data.pokemon[id].id, data.pokemon[id].name = id, names[id]
  end
  data.text._OaksLabReceivedMonText = syntheticROMText("_OaksLabReceivedMonText")
  data.text._OaksLabRivalReceivedMonText = syntheticROMText("_OaksLabRivalReceivedMonText")
  data.text._DoYouWantToNicknameText = syntheticROMText("_DoYouWantToNicknameText")
  data.text._GotMonText = syntheticROMText("_GotMonText")
  data.text._SentToBoxText = "はこ {RAM:wStringBuffer} なまえ {RAM:wBoxMonNicks}"
  data.text._OaksLabLastMonText = "のこりの テスト"
  data.text._OaksLabMonEnergeticText = "げんきの テスト"
  data.text._OaksLabRivalIllTakeThisOneText = "えらぶ テスト"
  data.text._OaksLabThoseArePokeBallsText = "ボールの テスト"
  for _, row in pairs(script.talk) do
    if type(row) == "table" then
      for _, cmd in ipairs(row) do
        if cmd[1] == "ask" then data.text[cmd[2]] = "えらびますか" end
      end
    end
  end
  function data:resolveText() return nil end
  data.font.charmap = manifest.fontCharmap
  data.font.composites = manifest.fontComposites
  Font.load(data); Strings.load(data)
  local game = {data=data, options={}, save={version=version,
    player={name="てすと",rival="あいて",id=123},party={},flags={},
    pokedex={seen={},owned={}},inventory={}},stack=setmetatable({states={}},{__index=Stack})}
  local rival = {cellX=4,cellY=3,def={name="RIVAL"}}
  local oak = {cellX=5,cellY=2,def={name="OAK"}}
  local ow = {map={id="OAKS_LAB",def={label="OAKS_LAB"}},
    npcs={rival,oak},entities={rival,oak},scriptMoves={}}
  function ow:npcByIndex(index) return index == 1 and rival or index == 5 and oak end
  function ow.map:inBounds(x,y) return x>=0 and x<12 and y>=0 and y<12 end
  function ow.map:isWalkableCell() return true end
  function ow:scriptMove(npc,dir,tiles,onDone)
    self.scriptMoves[#self.scriptMoves+1] = {npc=npc,dir=dir,onDone=onDone}
  end
  return game,ow
end

local function drive(game,ow,rows,choices,nickname)
  local runner = Runner.new(game,ow)
  local texts,screens,choiceIndex,finished = {},{},0,false
  runner:run(rows,{onDone=function() finished=true end})
  for _=1,200 do
    local top = game.stack:top()
    if top then
      game.stack:pop()
      if top.pages then
        local lines={}
        for _,page in ipairs(top.pages) do for _,line in ipairs(page) do lines[#lines+1]=line end end
        texts[#texts+1] = table.concat(lines,"\n")
        if top.choice then
          choiceIndex=choiceIndex+1
          top.choice(not choices or choices[choiceIndex] ~= false)
        else top.onDone() end
      else
        screens[#screens+1] = top
        if top.screenId == "NamingScreen" then top.onDone(nickname or "なまえ") end
      end
    elseif ow.scriptMoves[1] then
      local step=table.remove(ow.scriptMoves,1)
      step.npc.cellX,step.npc.cellY=Collision.target(step.npc.cellX,step.npc.cellY,step.dir)
      step.onDone()
    end
    runner:update()
    if not runner:isRunning() then break end
  end
  T.check(finished,"script reaches normal completion")
  T.check(not runner:isRunning(),"script coroutine stops")
  T.eq(#game.stack.states,0,"all dialogue/dex/naming screens pop")
  T.eq(#ow.scriptMoves,0,"NPC movement queue drains")
  return texts,screens,runner.ctx
end

local picks={
  {"CHARMANDER","SQUIRTLE",7,"EVENT_CHOSE_CHARMANDER"},
  {"SQUIRTLE","BULBASAUR",8,"EVENT_CHOSE_SQUIRTLE"},
  {"BULBASAUR","CHARMANDER",6,"EVENT_CHOSE_BULBASAUR"},
}
for _,pick in ipairs(picks) do
  local own,rival=pick[1],pick[2]
  local game,ow=newGame("red_jp")
  game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB=true
  local texts,screens=drive(game,ow,script.talk["TEXT_OAKSLAB_"..own.."_POKE_BALL"],{true,true})
  T.eq(texts[3],"あ"..game.data.pokemon[own].name.."い",own.." receive inserts imported name")
  T.eq(texts[4],"あ"..game.data.pokemon[own].name.."い",own.." nickname question uses same imported name")
  T.eq(texts[6],"あ"..game.data.pokemon[rival].name.."い",own.." rival receipt keeps its counterpick")
  T.check(not table.concat(texts):find("[A-Z]"),own.." flow leaks no English species IDs")
  T.eq(screens[1].screenId,"DexEntryMenu","dex preview still precedes the offer")
  T.eq(screens[2].screenId,"NamingScreen","accepted nickname opens naming screen")
  T.eq(screens[2].maxLen,5,"Japanese nickname length remains five")
  T.eq(screens[2].title,"ニックネームは？","nickname heading translated")
  T.eq(game.save.party[1].species,own,"party keeps species ID")
  T.eq(game.save.party[1].nickname,"なまえ","chosen nickname stored")
  T.check(game.save.pokedex.owned[own] and game.save.pokedex.seen[own],"dex marks gifted species")
  T.check(game.save.flags.EVENT_GOT_STARTER and game.save.flags[pick[4]],"starter flags still set")
  T.eq(game.save.objectToggles.OAKS_LAB["OAKSLAB_"..own.."_POKE_BALL"],false,"own ball removed")
  T.eq(game.save.objectToggles.OAKS_LAB["OAKSLAB_"..rival.."_POKE_BALL"],false,"rival ball removed")
  T.eq(ow:npcByIndex(1).cellX,pick[3],"rival reaches correct ball column")
  T.eq(ow:npcByIndex(1).cellY,4,"rival reaches counter row")
  T.eq(ow:npcByIndex(1).facing,"up","rival faces the ball")
  local remaining=drive(game,ow,script.talk["TEXT_OAKSLAB_"..own.."_POKE_BALL"])
  T.eq(remaining[1],game.data.text._OaksLabLastMonText,"remaining ball reads ROM label")
  T.eq(#game.save.party,1,"remaining ball does not give another starter")
end

local game,ow=newGame("red_jp")
game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB=true
drive(game,ow,script.talk.TEXT_OAKSLAB_CHARMANDER_POKE_BALL,{false})
T.eq(#game.save.party,0,"declined starter leaves party empty")
T.eq(game.save.flags.EVENT_GOT_STARTER,nil,"declined starter leaves flag unset")
T.eq(next(game.save.pokedex.owned),nil,"dex preview does not mark ownership")

game,ow=newGame("red_jp")
for i=1,6 do game.save.party[i]={species="FIXMON_A"} end
local texts,_,ctx=drive(game,ow,{{"give_pokemon","CHARMANDER",5,false,true}},{false})
T.eq(texts[1],"ああかい","general gift receipt uses imported name")
T.eq(texts[2],"ああかい","box gift nickname question uses imported name")
T.eq(texts[3],"はこ 1 なまえ あか","box handoff uses correct number and name")
T.eq(game.save.boxes[1][1].species,"CHARMANDER","full party gift lands in box")
T.eq(ctx.lastCheck,true,"declining nickname preserves give success")

-- A transformed gift must not contaminate the later rival name.
game,ow=newGame("red_jp")
game.mods={events={emit=function(_,name,gift) if name=="pokemon.before_give" then gift.species="SQUIRTLE" end end}}
texts=drive(game,ow,{{"give_pokemon","CHARMANDER",5,false,true},
  {"show_text","_OaksLabRivalReceivedMonText",{RAM="BULBASAUR"}}},{false})
T.eq(texts[1],"ああおい","mod replacement uses imported replacement name")
T.eq(texts[3],"あみどりい","replacement does not leak into rival receipt")

game,ow=newGame("red_jp")
game.data.text._DoYouWantToNicknameText=nil
texts=drive(game,ow,{{"give_pokemon","CHARMANDER",5}},{false})
T.check(texts[1]:find("ニックネーム",1,true)~=nil,"incomplete custom dataset fallback is Japanese")

game,ow=newGame("red")
game.save.flags.EVENT_GOT_STARTER=true
texts=drive(game,ow,script.talk.TEXT_OAKSLAB_CHARMANDER_POKE_BALL)
T.eq(texts[1],"That's PROF.OAK's\nlast Pokémon!","overseas leftover-ball literal unchanged")
texts=drive(game,ow,{{"show_text","_OaksLabReceivedMonText",{RAM="CHARMANDER"}}})
T.eq(texts[1],"あCHARMANDERい","overseas RAM substitution unchanged")
Version.set("red"); Strings.load({}); Screens.invalidate()
T.finish()
