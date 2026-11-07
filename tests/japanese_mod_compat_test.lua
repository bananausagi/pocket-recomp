-- Real loader + manifest/dependency gates; ROM-free, no metadata rewriting.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness").suite("Japanese upstream MOD compatibility")
local GameVersion = require("src.core.GameVersion")
local Version = require("src.core.Version")
local Targets = require("src.mods.ModTargets")
local Manifest = require("src.mods.Manifest")
local Semver = require("src.mods.Semver")
local Json = require("src.link.Json")
local Loader = require("src.mods.Loader")
local ModIndex = require("src.mods.ModIndex")
local function manifest(id, games, range)
  return {id=id,name=id,version="1.0.0",entry="main.lua",api=2,
    games=games,game_version=range or ">=0.2.66 <0.3.0"}
end
T.eq(Version.engine,"0.2.66","original mods see the real upstream engine version")
T.eq(Version.distribution,"0.2.66-jp.65-audit.1","distribution revision stays separately visible")
T.check(Semver.satisfies(Version.engine,">=0.1.86 <2.0.0"),"Dramaless upstream range matches")
T.check(not Semver.satisfies(Version.engine,">=0.2.67"),"newer engine requirements remain enforced")
for _,games in ipairs({{"red"},{"red","blue","yellow"},{"gen1"},{"all"}}) do
  local m=Manifest.validate(manifest("m",games))
  T.check(Targets.supports(m,"red_jp",1),"original target works: "..table.concat(games,","))
end
local red=Manifest.validate(manifest("m",{"red"}))
T.eq(table.concat(red.games,","),"red","author's manifest target is preserved")
local shown=ModIndex.filter({{id="original",games={"red"}},
  {id="blue",games={"blue"}}},{game="red_jp"})
T.eq(#shown,1,"JP catalog shows compatible originals and excludes Blue-only entries")
T.eq(shown[1].id,"original","original Red mod remains discoverable")
T.eq(ModIndex.targetLabel({games={"red","blue","yellow"}}),"GEN 1","Gen 1 chip includes its JP-compatible regional variant")
T.check(not Targets.supports(red,"blue",1),"Red-only mod stays Red-only on international games")
T.check(not Targets.supports(Manifest.validate(manifest("m",{"red_jp"})),"red",1),"JP-only mod stays JP-only")
for _,v in ipairs({"blue","yellow","gold","firered"}) do
  T.check(not Targets.supports(Manifest.validate(manifest("m",{v})),"red_jp",1),v.." is not silently forced onto JP Red")
end
T.check(Targets.specApplies({games={"red"}},"red_jp",1),"Red dependency applies to JP Red")
T.check(not Targets.specApplies({games={"blue"}},"red_jp",1),"Blue dependency does not match by generation alone")
T.check(not Targets.specApplies({game_version=">=0.2.67"},"red_jp",1),"dependency version condition returns its result")
T.check(Targets.specApplies({game_version="=0.2.66"},"red_jp",1),"matching engine dependency applies")
GameVersion.set("red_jp")
T.eq(GameVersion.get(),"red_jp","real game identity is not spoofed")
T.eq(GameVersion.cachePrefix(),"red_jp/","regional cache stays separate")
T.eq(GameVersion.saveSuffix(),"_red_jp","regional saves stay separate")
T.eq(GameVersion.info().romSize,524288,"ROM identity still uses Japanese size")
T.check(not GameVersion.acceptsSha1("red_jp",GameVersion.info("red").sha1),"US ROM does not pass the JP hash gate")

local files={}
local function add(m,code)
  files["mods/"..m.id.."/manifest.json"]=Json.encode(m)
  files["mods/"..m.id.."/main.lua"]=code or "return function(mod) mod.exports.ok = true end"
end
add(manifest("red_original",{"red"}))
add(manifest("wrong_blue",{"blue"}))
add(manifest("future_engine",{"red"},">=0.2.67"))
local dep=manifest("needs_missing_red",{"red"})
dep.dependencies={{id="absent",games={"red"}}};add(dep)
local other=manifest("optional_on_blue",{"red"})
other.dependencies={{id="absent",games={"blue"}}};add(other)
add(manifest("blocked_ffi",{"red"}),"return function() require('ffi') end")
local fs={read=function(p)return files[p]end,write=function(p,b)files[p]=b;return true end}
fs.load=function(p)return loadstring(files[p],p)end
fs.getInfo=function(p)
  if files[p] then return {type="file"} end
  for k in pairs(files) do if k:sub(1,#p+1)==p.."/" then return {type="directory"} end end
end
fs.getDirectoryItems=function(p)
  local out,seen={},{}
  for k in pairs(files) do
    if k:sub(1,#p+1)==p.."/" then
      local child=k:sub(#p+2):match("^[^/]+")
      if child and not seen[child] then out[#out+1]=child;seen[child]=true end
    end
  end
  table.sort(out);return out
end
local loader=Loader.new({fs=fs,generation=1})
loader:load({pokemon={}})
T.eq(loader.mods.red_original.state,"loaded","unmodified Red manifest loads through actual Loader")
T.check(loader.exports.red_original.ok,"original entry code executes")
T.eq(loader.mods.wrong_blue.state,"wrong_generation","other-game target is skipped")
T.eq(loader.mods.future_engine.state,"invalid","future engine mod is blocked")
T.eq(loader.mods.needs_missing_red.state,"blocked_dependency","Red-scoped required dependency remains mandatory")
T.eq(loader.mods.optional_on_blue.state,"loaded","Blue-only dependency does not block JP")
T.check(loader.mods.blocked_ffi.state~="loaded","sandbox restrictions are preserved")
T.eq(files["mods/red_original/manifest.json"],Json.encode(manifest("red_original",{"red"})),"loading never rewrites original manifest")
GameVersion.set("red")
T.finish()
