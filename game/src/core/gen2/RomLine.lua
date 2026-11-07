-- A line of dialogue read from the player's own cartridge, filled in.
--
-- jp.71: the Gen 2 specials (Buena, the Seer, Mom, the Name Rater, ...)
-- used to carry their sentences as Lua literals, which meant an English
-- line over a Japanese import.  They now print the label the importer
-- extracted from the ROM, in whatever language that ROM is.  There is no
-- dialogue fallback here on purpose: a cache without the label shows a
-- neutral placeholder instead of somebody's rewrite of the game's text.
--
-- Filling.  The extractor stores, next to each label that splices runtime
-- text, "<label>@slots": the WRAM buffer behind every {STRBUF}, in order
-- (RomExtractorGen2 extractText).  A Japanese sentence often names its
-- buffers in a different order from the English one, so callers pass
-- values BY BUFFER NAME and each lands where that ROM put it.  Values a
-- caller only knows by position (values[1], values[2], ...) are taken by
-- the ordinal of the slot -- {STRBUF} and {NUM} both count -- which is
-- also how a cache built before "@slots" existed gets filled.
--
-- A slot nobody supplies stays a token: {STRBUF} is then filled by
-- Vm:showRaw from vm.stringBuffer, and {PLAYER}/{RIVAL} by the text box's
-- own registry, exactly as before.

local RomLine = {}

RomLine.MISSING = "……"

local FILLABLE = {
  ["{STRBUF}"] = true, ["{NUM}"] = true,
  ["{USER}"] = true, ["{TARGET}"] = true, ["{ENEMY}"] = true,
}

function RomLine.raw(data, label)
  local text = data and data.text
  return text and text[label] or nil
end

function RomLine.has(data, label)
  return RomLine.raw(data, label) ~= nil
end

function RomLine.slots(data, label)
  local list = {}
  local joined = RomLine.raw(data, label .. "@slots")
  if type(joined) == "string" then
    for name in joined:gmatch("[^,]+") do list[#list + 1] = name end
  end
  return list
end

-- Trailing {DONE}/{PROMPT} and the paragraph/line breaks before them are
-- box timing the Lua caller already decides (TextBox treats {PROMPT} as
-- "no button wait"), so they come off unless opts.keepEnding.
local function stripEnding(text)
  local prev
  repeat
    prev = text
    text = text:gsub("{DONE}$", ""):gsub("{PROMPT}$", ""):gsub("[\n\f\v]+$", "")
  until text == prev
  return text
end
RomLine.stripEnding = stripEnding

function RomLine.get(data, label, values, opts)
  local text = RomLine.raw(data, label)
  if type(text) ~= "string" then return RomLine.MISSING end
  if not (opts and opts.keepEnding) then text = stripEnding(text) end
  -- Lines that continue an earlier box open with a break; a caller that
  -- prints them as a box of their own asks for it to go.
  if opts and opts.trimStart then text = text:gsub("^[\n\f\v]+", "") end
  if text == "" then return text end
  values = values or {}
  local slots = RomLine.slots(data, label)
  local strbuf, ordinal = 0, 0
  return (text:gsub("%b{}", function(token)
    local name = token:sub(2, -2)
    if token == "{PLAYER}" or token == "{RIVAL}" then
      local v = values[name]
      return v ~= nil and tostring(v) or token
    end
    if not FILLABLE[token] then return token end
    ordinal = ordinal + 1
    local v
    if token == "{STRBUF}" then
      strbuf = strbuf + 1
      local slot = slots[strbuf]
      if slot then v = values[slot] end
    else
      v = values[name]
    end
    if v == nil then v = values[ordinal] end
    if v == nil then return token end
    return tostring(v)
  end))
end

-- Convenience for call sites that print several labels as one box.
function RomLine.join(data, labels, sep)
  local out = {}
  for i, label in ipairs(labels) do out[i] = RomLine.get(data, label) end
  return table.concat(out, sep or "\n")
end

return RomLine
