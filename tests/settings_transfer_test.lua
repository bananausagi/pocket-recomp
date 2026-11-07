package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness").suite("Portable settings JSON")
local Transfer=require("src.import.SettingsTransfer")
local Json=require("src.link.Json")
local function document(options)
  return Json.encode({format=Transfer.FORMAT,version=1,options=options})
end
local original={
  musicVol=2,sfxVol=6,colors="classic",palette="CUSTOM_GB",jpDialogScale=0.75,vsync="off",
  jpOriginalIntro=false,orientation="portrait",jpBattleSpacing="wider",jpBattleBlur="strong",pipelines={voxel=3,tiltshift=5},
  touchControls={enabled=false,layouts={portrait={scale=1.2,positions={a={x=0.8,y=0.7}}}}},
  bindings={a={key="z",pad="a"},b=false,select={key=";"},speedUp={pad="rightshoulder"}},
  mods={DRAMALESS_SHAPE=true},modsByVersion={red_jp={quality_of_life=false}},
  modOptions={DRAMALESS_SHAPE={daytime="dusk",renderScale=2},
    CUSTOM_MOD={text="ゆうがた",levels={1,2,3},nested={enabled=true},
      apiToken="DO_NOT_EXPORT",secret="DO_NOT_EXPORT",assetsPath="private/asset",
      userFile="secret.json",url="https://private.example",texture="assets/picture.png"}},
  saveSync={token="DO_NOT_EXPORT"},auth={password="DO_NOT_EXPORT"},
  lastGame="red_jp",activeSlot="slot-private",romPath="private/game.gb",
  jpStarterPackV1={DRAMALESS_SHAPE="keep-version"},privateFuture={keep=99},
}
local encoded,err=Transfer.export(original)
T.check(type(encoded)=="string" and err==nil,"exports selected user settings")
local parsed=assert(Json.decode(encoded))
T.eq(parsed.format,Transfer.FORMAT,"versioned format marker")
T.eq(parsed.version,1,"format version is one")
T.eq(parsed.options.modOptions.DRAMALESS_SHAPE.daytime,"dusk","evening is exported as chosen")
T.eq(parsed.options.colors,"classic","color mode is not reset")
T.eq(parsed.options.palette,"CUSTOM_GB","custom palette is not reset")
T.check(not encoded:find("DO_NOT_EXPORT",1,true),"private secrets absent from exported JSON")
for _,key in ipairs({"saveSync","auth","lastGame","activeSlot","romPath","jpStarterPackV1","privateFuture"}) do
  T.eq(parsed.options[key],nil,"excludes private/internal top-level "..key)
end
for _,key in ipairs({"apiToken","secret","assetsPath","userFile","url","texture"}) do
  T.eq(parsed.options.modOptions.CUSTOM_MOD[key],nil,"excludes private/path MOD option "..key)
end
T.eq(original.modOptions.CUSTOM_MOD.secret,"DO_NOT_EXPORT","export does not modify source")

local current={musicVol=7,sfxVol=1,zoom=3,colors="gbc",saveSync={token="LOCAL"},
  activeSlot="LOCAL_SLOT",jpStarterPackV1={DRAMALESS_SHAPE="LOCAL_VERSION"},
  unknownFuture={nested={answer=42}},modOptions={DRAMALESS_SHAPE={daytime="night",custom=17},
    CUSTOM_MOD={secret="LOCAL_SECRET",levels={4,5,6,7},nested={other="kept"}}}}
local candidate,reason=Transfer.import(encoded,current)
T.check(candidate~=nil and reason==nil,"imports valid settings into a new candidate")
T.eq(current.musicVol,7,"input current table stays unchanged")
T.eq(current.modOptions.DRAMALESS_SHAPE.daytime,"night","input nested table stays unchanged")
T.eq(candidate.musicVol,2,"audio restored")
T.eq(candidate.sfxVol,6,"effects volume restored")
T.eq(candidate.vsync,"off","VSync uses the engine's persisted string values")
T.eq(candidate.jpBattleSpacing,"wider","battle spacing survives export and import")
T.eq(candidate.jpBattleBlur,"strong","battle background blur survives export/import")
T.eq(candidate.pipelines.tiltshift,5,"strongest world blur survives export/import")
T.eq(candidate.zoom,3,"missing settings are not reset to defaults")
T.eq(candidate.modOptions.DRAMALESS_SHAPE.daytime,"dusk","evening option restored")
T.eq(candidate.modOptions.DRAMALESS_SHAPE.custom,17,"unrelated MOD value remains")
T.eq(candidate.modOptions.CUSTOM_MOD.secret,"LOCAL_SECRET","local MOD credential remains private and unchanged")
T.eq(candidate.modOptions.CUSTOM_MOD.nested.other,"kept","nested safe merge preserves unspecified values")
T.eq(#candidate.modOptions.CUSTOM_MOD.levels,3,"arrays replace atomically rather than retaining stale tail")
T.eq(candidate.saveSync.token,"LOCAL","sync credential is not overwritten")
T.eq(candidate.activeSlot,"LOCAL_SLOT","save selection is not overwritten")
T.eq(candidate.jpStarterPackV1.DRAMALESS_SHAPE,"LOCAL_VERSION","starter pack identity is not overwritten")
candidate.unknownFuture.nested.answer=0
T.eq(current.unknownFuture.nested.answer,42,"candidate has no nested alias into current")
T.eq(candidate.touchControls.enabled,false,"false options survive")
T.eq(candidate.touchControls.layouts.portrait.positions.a.x,0.8,"touch position restored")
T.eq(candidate.modsByVersion.red_jp.quality_of_life,false,"per-game disabled MOD survives")
T.eq(candidate.bindings.speedUp.pad,"rightshoulder","controller binding restored")
T.eq(candidate.bindings.b,false,"explicitly cleared binding remains false")
T.eq(candidate.bindings.select.key,";","punctuation keyboard binding is accepted")
for _,key in ipairs({"[","]","/",".","'","=","-"}) do
  T.eq(assert(Transfer.import(document({bindings={a={key=key}}}),{})).bindings.a.key,key,
    "SDL punctuation key survives: "..key)
end

local function invalid(text,label)
  local before=Json.encode(current)
  local result,why=Transfer.import(text,current)
  T.check(result==nil and type(why)=="string",label.." rejected")
  T.eq(Json.encode(current),before,label.." leaves current intact")
end
for _,case in ipairs({
  {{musicVol=8},"volume above range"},{{musicVol=-1},"volume below range"},
  {{musicVol=1.5},"fractional volume"},{{musicVol="2"},"string volume"},
  {{jpDialogScale=0.1},"invalid UI size"},{{colors="new_unknown_mode"},"invalid color mode"},
  {{jpBattleSpacing="unknown"},"invalid battle spacing"},
  {{jpBattleBlur="unknown"},"invalid battle blur"},
  {{vsync=1},"VSync driver interval instead of persisted mode"},
  {{touchControls={layouts={portrait={positions={a={x=2,y=0.5}}}}}},"off-screen touch position"},
  {{touchControls={layouts={portrait={scale=20}}}},"touch scale above range"},
  {{bindings={a={key="a\n"}}},"control character binding"},
  {{modOptions={CUSTOM_MOD={token="x"}}},"MOD credential import"},
  {{modOptions={CUSTOM_MOD={foo="/private/path"}}},"MOD path import"},
  {{modOptions={CUSTOM_MOD={gain=1000001}}},"unbounded MOD number"},
  {{saveSync={enabled=true}},"sync settings import"},{{activeSlot="overwrite"},"save slot import"},
  {{musicVol=1,auth={token="attack"}},"mixed valid and private settings"},
}) do invalid(document(case[1]),case[2]) end

local prefix='{"format":"'..Transfer.FORMAT..'","version":1,"options":'
for _,case in ipairs({
  {encoded..' trailing',"trailing content"},
  {prefix..'{"musicVol":1,"musicVol":2}}',"duplicate settings key"},
  {prefix..'{"musicVol":01}}',"leading zero number"},
  {prefix..'{"musicVol":1.}}',"incomplete fraction"},
  {prefix..'{"musicVol":1e}}',"incomplete exponent"},
  {prefix..'{"musicVol":1e999}}',"infinite exponent"},
  {prefix..'{"musicVol":null}}',"null deletion attempt"},
  {prefix..'{"musicVol":1,}}',"trailing object comma"},
  {prefix..'{musicVol:1}}',"unquoted key"},
  {prefix..'{"modOptions":{"CUSTOM_MOD":{"text":"\\q"}}}}',"invalid string escape"},
  {prefix..'{"modOptions":{"CUSTOM_MOD":{"text":"\\ud800"}}}}',"isolated surrogate"},
  {prefix..'{"modOptions":{"CUSTOM_MOD":{"text":"'..string.char(255)..'"}}}}',"invalid UTF-8"},
  {prefix..'{"modOptions":{"CUSTOM_MOD":{"text":"line\nbreak"}}}}',"literal control character"},
  {'return os.execute("side effect")',"Lua source"},
  {string.rep(' ',Transfer.MAX_BYTES+1),"oversized file"},
  {'{"format":"'..Transfer.FORMAT..'","version":2,"options":{}}',"future format version"},
  {'{"format":"other-app","version":1,"options":{}}',"wrong format"},
  {prefix..'{},"save":{"party":[1]}}',"unexpected envelope field"},
}) do invalid(case[1],case[2]) end

local unicode=assert(Transfer.import(prefix..'{"modOptions":{"CUSTOM_MOD":{"text":"\\u3086\\u3046\\u304c\\u305f \\ud83c\\udf07"}}}}',{}))
T.eq(unicode.modOptions.CUSTOM_MOD.text,"ゆうがた 🌇","valid Unicode and surrogate pair decode")
local depth={};local at=depth
for _=1,20 do at.child={};at=at.child end
invalid(document({modOptions={CUSTOM_MOD=depth}}),"excessive nesting")
local cycle={};cycle.self=cycle
local text,errorText=Transfer.export({modOptions={CUSTOM_MOD=cycle}})
T.check(text==nil and type(errorText)=="string","cyclic export rejected")
text,errorText=Transfer.export({modOptions={CUSTOM_MOD={run=function()error("must not run")end}}})
T.check(text==nil and type(errorText)=="string","executable values rejected without execution")
text,errorText=Transfer.export({musicVol=0/0})
T.check(text==nil and type(errorText)=="string","non-finite export rejected")
text,errorText=Transfer.export({modOptions={CUSTOM_MOD={mixed={[1]=1,name=true}}}})
T.check(text==nil and type(errorText)=="string","mixed array/map export rejected")
local defaults=require("src.core.SaveData").defaultOptions()
T.check(Transfer.export(defaults)~=nil,"standard default settings can be exported")
T.eq(Transfer.import(assert(Transfer.export({})),{musicVol=5}).musicVol,5,"empty snapshot keeps current settings")
T.finish()
