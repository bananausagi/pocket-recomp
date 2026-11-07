-- Read-only habitat catalogue from the active (already MOD-merged) Gen 1
-- encounter tables. Only the separate visited-map set is written here.
local H = {}
local Names = require("src.core.JapaneseStringsMenus")
local Defaults = require("src.world.FieldDefaults")

function H.enabled(game)
  local c = game and game.data and game.data.constants
  return c and c.language == "ja" and (not c.generation or c.generation == 1)
    and game.save ~= nil
end

function H.observe(game)
  if not H.enabled(game) then return false end
  local ow = game.overworld
  local id = ow and ow.map and ow.map.id
  if not (id and ow.player and (game.data.maps or {})[id]) or ow.transitioning then return false end
  -- A stale world retained behind the opening/title is not an arrival.
  local present = false
  for _, state in ipairs(game.stack and game.stack.states or {}) do
    if state == ow then present = true end
    if state.isTitleScreen or state.isOpeningMovie then return false end
  end
  if not present then return false end
  local visited = game.save.jpHabitatVisited
  if type(visited) ~= "table" then visited = {}; game.save.jpHabitatVisited = visited end
  if visited[id] == true then return false end
  visited[id] = true
  return true
end

local function japanese(game, source)
  if type(source) ~= "string" then return nil end
  local name = (game.data.strings or {})[source] or Names[source] or source
  if name:find("[\227-\233]") then return name:gsub("[\r\n]", " ") end
end

function H.region(game, id)
  local tm = (game.data.field or {}).townMap or {}
  local entry = (tm.locations or tm)[id]
  local def = (game.data.maps or {})[id] or {}
  local source = type(entry) == "table" and (entry.name or entry.label)
  local name = japanese(game, source) or japanese(game, def.name)
    or japanese(game, id:gsub("_", " ")) or "なまえの ない ばしょ"
  -- Shared town-map records are the canonical floor/room grouping. Do not
  -- merge adjacent routes merely because their terrain is streamed together.
  local key = id
  if source then
    local p = entry.coords or entry
    key = source .. ":" .. tostring(p.x or p.col or "") .. ":" .. tostring(p.y or p.row or "")
  end
  return key, name
end

-- Inspect collision-foot tiles in the map's real blocks, not a tileset-wide
-- water possibility. Old/Good Rod otherwise incorrectly appear everywhere.
function H.hasWater(data, id)
  local def = (data.maps or {})[id]
  local ts = def and (data.tilesets or {})[def.tileset]
  if not (def and ts and ts.blocks and def.blocks) then return false end
  local eligible = false
  for _, name in ipairs((data.field or {}).waterTilesets or {}) do
    if name == def.tileset then eligible = true; break end
  end
  if not eligible then return false end
  local water = {}
  for _, tile in ipairs(ts.waterTiles or {0x14}) do water[tile] = true end
  local shore = ts.shoreTiles
  if shore == nil then shore = def.tileset == "SHIP_PORT" and {} or {0x32, 0x48} end
  for _, tile in ipairs(shore) do water[tile] = true end
  local checked = {}
  for _, blockId in ipairs(def.blocks) do
    if not checked[blockId] then
      checked[blockId] = true
      local block = ts.blocks[blockId + 1]
      if block then
        for _, at in ipairs({5, 7, 13, 15}) do if water[block[at]] then return true end end
      end
    end
  end
  return false
end

local function append(game, species, level, kind, rows, byId)
  local def = (game.data.pokemon or {})[species]
  if not (def and type(species) == "string") then return end
  local row = byId[species]
  if not row then
    row = {species=species, dex=def.dex or 9999, methods={}}
    byId[species] = row; rows[#rows+1] = row
  end
  row.methods[kind] = true
  level = tonumber(level)
  if level and level >= 1 and level <= 100 then
    row.minLevel = math.min(row.minLevel or level, level)
    row.maxLevel = math.max(row.maxLevel or level, level)
  end
end

function H.entries(game, mapIds, method)
  local rows, byId = {}, {}
  for _, id in ipairs(mapIds or {}) do
    local enc = (game.data.encounters or {})[id] or {}
    for _, spec in ipairs({{"grass", "land"}, {"water", "water"}}) do
      local pool, kind = enc[spec[1]], spec[2]
      if (not method or method == "all" or method == kind) and pool
          and (tonumber(pool.rate) or 0) > 0 then
        local buckets=pool.buckets or Defaults.constant(game.data,"encounterBuckets")
        local previous=0
        for i, threshold in ipairs(buckets or {}) do
          local slot=(pool.slots or {})[i]
          if slot and threshold>previous and previous<256 then
            append(game, slot.species, slot.level, kind, rows, byId)
          end
          previous=math.max(previous,threshold)
        end
      end
    end
    if (not method or method == "all" or method == "fish") and H.hasWater(game.data, id) then
      for _, rod in pairs(Defaults.field(game.data, "fishing") or {}) do
        local pool = rod.pool or rod.perMap and (game.data.field[rod.perMap] or {})[id]
        if pool then
          -- Native Gen 1 fishing samples only indices 1..4.
          for i, slot in ipairs(pool) do
            if i<=4 then append(game, slot.species, slot.level, "fish", rows, byId) end
          end
        elseif rod.always then append(game, rod.always.species, rod.always.level, "fish", rows, byId) end
      end
    end
  end
  table.sort(rows, function(a,b) if a.dex ~= b.dex then return a.dex < b.dex end return a.species < b.species end)
  local dex = game.save.pokedex or {}
  local seen, owned = 0, 0
  for _, row in ipairs(rows) do
    row.owned = (dex.owned or {})[row.species] == true
    row.seen = row.owned or (dex.seen or {})[row.species] == true
    row.name = row.seen and ((game.data.pokemon[row.species] or {}).name or "？？？") or "？？？"
    if row.seen then seen = seen + 1 else row.minLevel, row.maxLevel = nil, nil end
    if row.owned then owned = owned + 1 end
  end
  return rows, {total=#rows, seen=seen, owned=owned}
end

function H.areas(game)
  local ids, included = {}, {}
  local current = game.overworld and game.overworld.map and game.overworld.map.id
  local function add(id)
    if type(id) == "string" and (game.data.maps or {})[id] and not included[id] then
      ids[#ids+1] = id; included[id] = true
    end
  end
  -- Earlier saves know towns through the genuine Fly visited flags. Routes
  -- are recorded from this version onwards; never invent old travel history.
  for id, yes in pairs(game.save.visited or {}) do if yes == true then add(id) end end
  for id, yes in pairs(game.save.jpHabitatVisited or {}) do if yes == true then add(id) end end
  if current then add(current) end
  table.sort(ids)
  local areas, byKey, currentArea = {}, {}, nil
  for _, id in ipairs(ids) do
    local key, name = H.region(game, id)
    local area = byKey[key]
    if not area then area={key=key, name=name, maps={}}; areas[#areas+1]=area; byKey[key]=area end
    area.maps[#area.maps+1] = id
    if id == current then currentArea = area end
  end
  local ranks = {}
  for i,id in ipairs(((game.data.field or {}).townMap or {}).cursorOrder or {}) do
    local key=H.region(game,id); ranks[key]=ranks[key] or i
  end
  table.sort(areas,function(a,b)
    if (ranks[a.key] or 9999) ~= (ranks[b.key] or 9999) then return (ranks[a.key] or 9999)<(ranks[b.key] or 9999) end
    return a.key<b.key
  end)
  local index = 1
  for i,area in ipairs(areas) do if area == currentArea then index=i end end
  return areas, index
end

return H
