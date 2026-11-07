-- Handwritten test data for the catchable-151 mod. The JP manifest is used
-- only as a symbol allow-list; no cartridge bytes, sprites or game stats.
local Merge = require("src.mods.Merge")
local M = {}

function M.apply(data, jpManifest)
  assert(type(jpManifest.pokemonAssets) == "table", "JP species symbols required")
  assert(type(jpManifest.maps) == "table", "JP map symbols required")
  local template = assert(data.pokemon.FIXMON_A, "start with tests.fixture_data")
  local count = 0
  for id in pairs(jpManifest.pokemonAssets) do
    count = count + 1
    if not data.pokemon[id] then
      local mon = Merge.deepCopy(template)
      mon.id, mon.index, mon.dex = id, nil, count
      mon.name = "テスト"
      mon.evolutions = {}
      data.pokemon[id] = mon
    end
  end
  for _, pair in ipairs({{"KADABRA","ALAKAZAM"}, {"GRAVELER","GOLEM"},
                         {"HAUNTER","GENGAR"}, {"MACHOKE","MACHAMP"}}) do
    data.pokemon[pair[1]].evolutions = {{method="TRADE", species=pair[2]}}
  end
  data.items.MOON_STONE = {id="MOON_STONE", name="テストのいし", price=0}
  data.text_pointers.PewterMart = {
    TEXT_PEWTERMART_CLERK={mart={"FIX_POTION", "FIX_BALL"}},
    TEST_UNRELATED={text="FIX_SIGN"},
  }
  data.text_pointers.CeladonMart4F = {
    TEXT_CELADONMART4F_CLERK={mart={"FIX_POTION"}},
  }
  for id in pairs(jpManifest.maps) do
    if not data.encounters[id] then
      local slots={}
      for i=1,10 do slots[i]={level=2, species="FIXMON_A"} end
      data.encounters[id]={
        grass={rate=31, slots=slots},
        water={rate=17, slots={{level=4, species="FIXMON_C"}}},
      }
    end
  end
  return data
end

return M
