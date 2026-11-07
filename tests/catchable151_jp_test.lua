-- Actual Loader/Registry integration, with no ROM or extracted game data.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness").suite("Catchable 151 JP integration")
local Json=require("src.link.Json")
local Merge=require("src.mods.Merge")
local Loader=require("src.mods.Loader")
local GameVersion=require("src.core.GameVersion")
local function read(path)
  local f=assert(io.open(path,"rb"));local b=f:read("*a");f:close();return b
end
local jp=assert(Json.decode(read("tools/rom_manifest_red_jp.json")))
local id="all_pokemon_catchable_151_mod"
local dir="vendor/jp-mods/"..id.."/"
local files={
  ["mods/"..id.."/manifest.json"]=read(dir.."manifest.json"),
  ["mods/"..id.."/main.lua"]=read(dir.."main.lua"),
}
local fs={read=function(p)return files[p]end,
  write=function(p,b)files[p]=b;return true end,
  load=function(p)return loadstring(files[p],p)end}
fs.getInfo=function(p)
  if files[p] then return {type="file"} end
  for k in pairs(files) do
    if k:sub(1,#p+1)==p.."/" then return {type="directory"} end
  end
  local f=io.open(p,"rb");if f then f:close();return {type="file"} end
end
fs.getDirectoryItems=function(p)
  local out,seen={},{}
  for k in pairs(files) do
    if k:sub(1,#p+1)==p.."/" then
      local child=k:sub(#p+2):match("^[^/]+")
      if child and not seen[child] then seen[child]=true;out[#out+1]=child end
    end
  end
  table.sort(out);return out
end
local function data()
  local d=require("tests.fixture_data").load()
  require("src.core.Data").seedDefaults(d,"red_jp")
  return require("tests.catchable151_fixture").apply(d,jp)
end
GameVersion.set("red_jp")
local d=data()
local before=Merge.deepCopy(d)
local loader=Loader.new({fs=fs,generation=1})
T.check(loader:load(d),"actual loader completes")
local report=loader.mods[id]
T.eq(report.state,"loaded","adapted author code loads: "..tostring(report.reason))
T.eq(d.items.MOON_STONE.price,2100,"Moon Stone costs the author's 2100")
T.eq(d.items.MOON_STONE.name,"テストのいし","JP item name stays unchanged")
local marts={PewterMart="TEXT_PEWTERMART_CLERK",CeladonMart4F="TEXT_CELADONMART4F_CLERK"}
for map,clerk in pairs(marts) do
  T.check(jp.text.pointers[map] and jp.text.pointers[map][clerk],"JP ROM clerk symbol exists: "..map)
  local old=before.text_pointers[map][clerk].mart
  local current=d.text_pointers[map][clerk].mart
  T.eq(#current,#old+1,"Moon Stone appends without erasing shop inventory: "..map)
  for i,v in ipairs(old) do T.eq(current[i],v,"existing shop item preserved") end
  T.eq(current[#current],"MOON_STONE","Moon Stone is offered")
end
T.same(d.text_pointers.PewterMart.TEST_UNRELATED,before.text_pointers.PewterMart.TEST_UNRELATED,"unrelated text pointer preserved")
for _,v in ipairs({{"KADABRA","ALAKAZAM",42},{"GRAVELER","GOLEM",42},
                  {"HAUNTER","GENGAR",42},{"MACHOKE","MACHAMP",45}}) do
  local evo=d.pokemon[v[1]].evolutions
  T.same(evo,{{method="LEVEL",species=v[2],level=v[3]}},"trade evolution becomes specified level evolution: "..v[1])
  T.eq(d.pokemon[v[1]].name,"テスト","JP species display name is preserved")
  T.same(d.pokemon[v[1]].baseStats,before.pokemon[v[1]].baseStats,"stats are not changed")
end
local count=0
local authorRates={CERULEAN_CAVE_1F=10,CERULEAN_CAVE_2F=15,CERULEAN_CAVE_B1F=25}
for map in pairs(loader.content.encounters.ops) do
  if loader.content.encounters.owners[map]==id then
    count=count+1
    T.check(jp.maps[map],"encounter map exists in JP ROM manifest: "..map)
    local now,old=d.encounters[map],before.encounters[map]
    T.eq(now.grass.rate,authorRates[map] or old.grass.rate,
      authorRates[map] and ("author's cave encounter rate applied: "..map)
        or ("original encounter frequency preserved: "..map))
    T.eq(#now.grass.slots,10,"ten weighted encounter slots retained: "..map)
    T.same(now.water,old.water,"water encounters stay unchanged: "..map)
    for _,slot in ipairs(now.grass.slots) do
      T.check(jp.pokemonAssets[slot.species],"referenced species exists in JP ROM: "..slot.species)
    end
  end
end
T.eq(count,33,"all 33 expanded encounter areas applied")
local function has(map,species)
  for _,slot in ipairs(d.encounters[map].grass.slots) do
    if slot.species==species then return true end
  end
  return false
end
T.check(has("POKEMON_MANSION_B1F","MEW"),"Mew encounter is present")
T.check(has("SAFARI_ZONE_EAST","BULBASAUR"),"renewable Bulbasaur is present")
T.check(has("VICTORY_ROAD_3F","CHARMANDER"),"renewable Charmander is present")
T.check(has("SEAFOAM_ISLANDS_B2F","SQUIRTLE"),"renewable Squirtle is present")
T.check(has("SEAFOAM_ISLANDS_B4F","OMANYTE") and has("SEAFOAM_ISLANDS_B4F","KABUTO"),"both fossils are present")
T.same(d.encounters.ROUTE_1,before.encounters.ROUTE_1,"an untouched route stays unchanged")
T.eq(d.pokemon.FIXMON_A.catchRate,before.pokemon.FIXMON_A.catchRate,"catch probability data is unchanged")
-- A saved OFF choice must disable the content edits on a fresh load.
local SaveData=require("src.core.SaveData")
local options=SaveData.loadOptions(fs)
SaveData.setModEnabled(options,id,false,"red_jp")
assert(SaveData.saveOptions(options,fs))
local disabled=data()
local off=Loader.new({fs=fs,generation=1})
off:load(disabled)
T.eq(off.mods[id].state,"disabled","saved OFF choice is honored")
T.eq(disabled.items.MOON_STONE.price,0,"disabled mod does not change content")
GameVersion.set("red")
T.finish()
