-- ROM-free regression: invented command streams at the manifest's real alias
-- addresses; real import decoding, cache seeding, script runner and TextBox.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Japanese dialogue segments")
local Split = require("src.core.JapaneseText")
local Json = require("src.link.Json")
local Extractor = require("src.import.RomExtractor")
local Data = require("src.core.Data")
local Version = require("src.core.GameVersion")
local Runner = require("src.script.ScriptRunner")
local Stack = require("src.core.StateStack")
local Font = require("src.render.Font")
local f = assert(io.open("tools/rom_manifest_red_jp.json", "rb"))
local manifest = assert(Json.decode(f:read("*a"))); f:close()
local function clone(x)
  if type(x) ~= "table" then return x end
  local y = {}; for k,v in pairs(x) do y[k] = clone(v) end; return y
end
local banks = {}; for i=0,31 do banks[i] = string.rep("\0",0x4000) end
local function put(bank,address,bytes)
  local at=address%0x4000
  banks[bank]=banks[bank]:sub(1,at)..bytes..banks[bank]:sub(at+#bytes+1)
end
local m=clone(manifest)
m.text.labels={};m.text.dynamic={}
local fulls, expected = {}, {}
for index,rule in ipairs(Split.segments) do
  local first,second,delimiter,ordinal=unpack(rule)
  local a,b=manifest.symbols[first],manifest.symbols[second]
  T.eq(a[1],b[1],first.." shares the JP bank")
  T.eq(a[2],b[2],first.." shares the JP address")
  T.eq(manifest.jpTextSymbols[first],manifest.jpTextSymbols[second],
    first.." is a verified disassembly alias")
  local sep=delimiter=="\f" and 0x51 or 0x4e
  local before=string.rep("あ"..delimiter,ordinal-1).."あ{RAM:wStringBuffer}"
  local after=delimiter.."い"..delimiter.."い{PROMPT}"
  local bytes=string.char(0)..string.rep(string.char(0x80,sep),ordinal-1)
    ..string.char(0x80,0x50,1,0,0,0x10,0,sep,0x81,sep,0x81,0x58)
  T.check(#bytes<=m.text.lengths[first],first.." synthetic stream fits its boundary")
  put(a[1],a[2],bytes)
  for _,label in ipairs({first,second}) do
    m.text.labels[#m.text.labels+1]=label
    m.text.dynamic[label]={{1,"{RAM:wStringBuffer}"}}
  end
  fulls[first]=before..after
  expected[first],expected[second]=before.."{DONE}",after
end
m.charmap["128"],m.charmap["129"]="あ","い"
local rom=table.concat(banks,"",0,31)
local ex=Extractor.new(rom,m)
local old={}
for _,rule in ipairs(Split.segments) do
  for _,label in ipairs({rule[1],rule[2]}) do
    old[label]=ex:decodeTextCommands(ex:symbol(label),m.text.dynamic[label])
  end
  T.eq(old[rule[1]],fulls[rule[1]],rule[1].." decoder has the full JP stream")
  T.eq(old[rule[1]],old[rule[2]],rule[1].." reproduces duplicated old-cache aliases")
end
-- The import pipeline must write the repaired cache, not only change a return.
local writes={}
function ex:write(kind,value) writes[kind]=clone(value) end
function ex:beginStage() end
function ex:tick() end
local extracted=ex:extractText().texts
for _,rule in ipairs(Split.segments) do
  for _,label in ipairs({rule[1],rule[2]}) do
    T.eq(extracted[label],expected[label],label.." split during ROM import")
    T.eq(writes.text[label],expected[label],label.." saved in imported cache")
  end
  T.eq(extracted[rule[1]]:gsub("{DONE}$","")..extracted[rule[2]],fulls[rule[1]],
    rule[1].." reconstruction preserves every token and repeated page")
end
Version.set("red_jp")
local cached={constants={language="ja"},text=clone(old)}
Data.seedDefaults(cached,"red_jp")
for label,value in pairs(expected) do T.eq(cached.text[label],value,label.." old cache repaired") end
T.eq(Split.seed(cached,"red_jp"),0,"cache repair is idempotent")
local first,second=unpack(Split.segments[1])
local foreign={constants={language="ja"},text=clone(old)}
T.eq(Split.seed(foreign,"red"),0,"foreign version untouched")
T.eq(foreign.text[first],old[first],"foreign dialogue preserved")
foreign.constants.language="en"
T.eq(Split.seed(foreign,"red_jp"),0,"language must also match")
local custom={[first]="custom\nfirst",[second]="custom\nsecond",unrelated="same",other="same"}
T.eq(Split.normalize(custom),0,"distinct MOD translations untouched")
T.eq(custom[second],"custom\nsecond","MOD second fragment retained")
T.eq(custom.unrelated,custom.other,"unrelated identical messages retained")
local incomplete={[first]="no boundary",[second]="no boundary"}
T.eq(Split.normalize(incomplete),0,"missing boundary is never guessed")
T.eq(Split.normalize({[first]="missing second"}),0,"missing alias is never synthesized")

-- Feed the old and repaired aliases through real Commands/Runner/TextBox.
local function gameWith(texts)
  local d=require("tests.fixture_data").load()
  d.constants.language="ja";d.text=clone(texts)
  d.font.charmap=m.fontCharmap;d.font.composites=m.fontComposites
  Font.load(d)
  local game={data=d,options={},save={version="red_jp",player={name="あ",rival="い",id=1},
    party={},flags={},inventory={},pokedex={seen={},owned={}}},
    stack=setmetatable({states={}},{__index=Stack}),stringBuffer="あ"}
  return game
end
local function drive(game,rows)
  local runner=Runner.new(game,{map={id="TEST",def={label="TEST"}}})
  local boxes,done={},false
  runner:run(rows,{onDone=function() done=true end})
  for _=1,100 do
    local top=game.stack:top()
    if top then
      game.stack:pop()
      local lines={}
      for _,page in ipairs(top.pages) do for _,line in ipairs(page) do lines[#lines+1]=line end end
      boxes[#boxes+1]=table.concat(lines,"\n")
      if top.choice then top.choice(true) else top.onDone() end
    end
    runner:update()
    if not runner:isRunning() then break end
  end
  T.check(done,"real script completes")
  T.eq(#game.stack.states,0,"real dialogue stack drains")
  return boxes
end
local pair={"_OaksLabOak1DeliverParcelText","_OaksLabOak1ParcelThanksText"}
local rows={{"show_text",pair[1]},{"show_text",pair[2]}}
local baseline=drive(gameWith(old),rows)
T.eq(baseline[1],baseline[2],"old-cache Oak parcel visibly repeats the entire message")
local repaired=drive(gameWith(cached.text),rows)
T.check(repaired[1]~=repaired[2],"Oak parcel now shows handover then thanks")
T.check(not repaired[1]:find("い",1,true),"handover no longer includes later thanks")
T.check(not repaired[2]:find("あ",1,true),"thanks no longer repeats handover")
local repeatBoxes=drive(gameWith(cached.text),{{"show_text",pair[1]},{"show_text",pair[1]}})
T.eq(#repeatBoxes,2,"intentional repeated same-label dialogue is not suppressed")
T.eq(repeatBoxes[1],repeatBoxes[2],"intentional repeated content is unchanged")

-- An actual event keeps its offer, inventory mutation, flag and later talk.
for _,case in ipairs({
  {"VERMILION_OLD_ROD_HOUSE","TEXT_VERMILIONOLDRODHOUSE_FISHING_GURU","OLD_ROD","EVENT_GOT_OLD_ROD",
    "_VermilionOldRodHouseFishingGuruDoYouLikeToFishText","_VermilionOldRodHouseFishingGuruHowAreTheFishBitingText"},
  {"ROUTE_12_SUPER_ROD_HOUSE","TEXT_ROUTE12SUPERRODHOUSE_FISHING_GURU","SUPER_ROD","EVENT_GOT_SUPER_ROD",
    "_Route12SuperRodHouseFishingGuruDoYouLikeToFishText","_Route12SuperRodHouseFishingGuruTryFishingText"},
}) do
  local game=gameWith(cached.text)
  game.data.items[case[3]]={id=case[3],name="あ",index=1,price=0}
  game.data.text[case[5]],game.data.text[case[6]]="あ？","い！"
  local script=require("data.scripts.story3")[case[1]].talk[case[2]]
  local boxes=drive(game,script)
  T.eq(#boxes,3,case[3].." offer, received, explanation run once each")
  T.check(boxes[2]~=boxes[3],case[3].." received/explanation no longer duplicate")
  T.eq(game.save.inventory[case[3]],1,case[3].." given once")
  T.eq(game.save.flags[case[4]],true,case[3].." event flag set")
  local later=drive(game,script)
  T.eq(#later,1,case[3].." later talk still executes")
  T.eq(later[1],"い！",case[3].." later dialogue intact")
  T.eq(game.save.inventory[case[3]],1,case[3].." later talk gives no extra item")
end
T.finish()
