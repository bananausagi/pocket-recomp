-- jp.81: Japanese Gold / Silver / Crystal data normalizer.
--
-- On the Japanese carts charmap byte $54 is the ポケモン text command, but the
-- JP manifests (tools/rom_manifest_*_jp*.json) list it as the English "POKé".
-- RomExtractorGen2:decodeGen2Text already reads it as ポケモン, every other
-- path (item / move descriptions, dex entries, script `getstring` names such
-- as PokegearName = `$54 ギ ア`) went through the plain charmap and came out
-- as POKéを / POKéギア.  The extractor now reads $54 as ポケモン too
-- (RomExtractorGen2.new), but a cart imported by an older build keeps the old
-- data/generated tables, so the same reading is applied here at load time.
--
-- Only string VALUES are rewritten, never keys, and only strings that are
-- Japanese text already (they hold a kana / kanji / full-width byte), so an
-- English label kept in the data for a catalog lookup is never touched.
-- Idempotent: a table walked twice has nothing left to replace.
local JapaneseData = {}

local POKE = "POK\195\169"            -- "POKé" (charmap $54 on the JP manifests)
local POKEMON = "ポケモン"
-- UTF-8 lead bytes of the kana / CJK / full-width blocks (U+3000-U+9FFF,
-- U+FF00-U+FFEF): the cheap test for "this string is Japanese text".
local JAPANESE = "[\227-\233\239]"

JapaneseData.REPLACEMENTS = { { POKE, POKEMON } }

local function fix(s)
  if not s:find(POKE, 1, true) or not s:find(JAPANESE) then return s end
  for _, pair in ipairs(JapaneseData.REPLACEMENTS) do
    local from, to = pair[1], pair[2]
    local out, i = {}, 1
    while true do
      local a, b = s:find(from, i, true)
      if not a then break end
      out[#out + 1] = s:sub(i, a - 1)
      out[#out + 1] = to
      i = b + 1
    end
    out[#out + 1] = s:sub(i)
    s = table.concat(out)
  end
  return s
end
JapaneseData.fixString = fix

local function walk(t, seen, count)
  if seen[t] then return count end
  seen[t] = true
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "string" then
      local nv = fix(v)
      if nv ~= v then
        t[k] = nv
        count = count + 1
      end
    elseif tv == "table" then
      count = walk(v, seen, count)
    end
  end
  return count
end

-- The text-bearing tables Game2:load reads.  Maps, tilesets, sprites, audio
-- and the other binary tables hold no player-visible words and are skipped.
JapaneseData.DATA_KEYS = {
  "pokemon", "items", "moves", "gen2Pokedex", "gen2Landmarks", "gen2Intro",
  "gen2Credits", "gen2Diploma", "gen2Trade", "gen2Trainers", "gen2Marts",
  "gen2Scripts", "gen2StdScripts", "gen2Text", "text", "gen2EventTables",
}

function JapaneseData.isJapanese(data)
  local c = data and data.constants
  return c ~= nil and c.language == "ja"
end

-- Normalize `data` (Game2's self.data) plus any extra tables passed in (the
-- title and Oak-speech tables live on the game object, not on data).  Returns
-- the number of strings rewritten; does nothing for a non-Japanese cart.
function JapaneseData.apply(data, extra)
  if not JapaneseData.isJapanese(data) then return 0 end
  local seen, count = {}, 0
  for _, key in ipairs(JapaneseData.DATA_KEYS) do
    if type(data[key]) == "table" then count = walk(data[key], seen, count) end
  end
  for _, t in ipairs(extra or {}) do
    if type(t) == "table" then count = walk(t, seen, count) end
  end
  return count
end

return JapaneseData
