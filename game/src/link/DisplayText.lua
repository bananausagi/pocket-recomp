-- Presentation boundary for link diagnostics. Session/Protocol/Net retain their
-- machine-readable reasons; callers translate only when showing them to a player.
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local DisplayText = {}

local function formattedParts(text, template)
  local pattern, pos = {}, 1
  while true do
    local first, last = template:find("%%[sd]", pos)
    local literal = template:sub(pos, first and first - 1 or #template)
    pattern[#pattern + 1] = literal:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    if not first then break end
    pattern[#pattern + 1] = template:sub(last, last) == "d" and "(%d+)" or "(.-)"
    pos = last + 1
  end
  return { text:match("^" .. table.concat(pattern) .. "$") }
end

-- Net has historically formatted these presentation templates before returning
-- its error. Recognize the active catalog too, so only their nested reason is
-- localized at the final UI boundary; the transport's stored detail stays raw.
local NESTED = {
  { Strings.source("can't reach relay %s:%d\n(%s)"), 3 },
  { Strings.source("Couldn't join:\n%s"), 1 },
  { Strings.source("no answer from\n%s"), 1 },
}

function DisplayText.reason(raw, depth)
  local text = tostring(raw or "?")
  depth = depth or 0
  if depth >= 8 then return text end
  local translated = Strings.lookup(text, "link.reason")
  if translated ~= text then return translated end
  local port, why = text:match("^can't open UDP port (%d+) %((.*)%)$")
  if port then
    return Strings("can't open UDP port %d (%s)", tonumber(port), DisplayText.reason(why, depth + 1))
  end
  local address = text:match("^bad address (.*)$")
  if address then return Strings("bad address %s", address) end
  why = text:match("^send failed: (.*)$")
  if why then return Strings("send failed: %s", DisplayText.reason(why, depth + 1)) end
  for _, row in ipairs(NESTED) do
    local parts = formattedParts(text, Strings.lookup(row[1]))
    if #parts == 0 then parts = formattedParts(text, row[1]) end
    if #parts > 0 and parts[row[2]] ~= text then
      parts[row[2]] = DisplayText.reason(parts[row[2]], depth + 1)
      return Strings(row[1], unpack(parts))
    end
  end
  -- External transports and MODs may supply arbitrary details. Do not guess at
  -- their meaning or replace useful diagnostics with a generic error.
  return text
end

function DisplayText.species(game, id)
  local data = game and game.data
  local japanese = data and data.constants and data.constants.language == "ja"
  local record = japanese and data.pokemon and data.pokemon[id]
  return record and record.name or tostring(id)
end

function DisplayText.component(id)
  return Strings.lookup(tostring(id), "link.component")
end

function DisplayText.ruleset(id)
  return Strings.lookup(tostring(id):upper(), "link.ruleset")
end

-- Whole font spans, including composed kana and ROM ligatures. The same helpers
-- work before Font.load in handshake tests, using its UTF-8 fallback spans.
local function fitting(text, columns)
  local spans = Font.split(text)
  local count = Font.spansFitting(spans, math.max(1, columns or 19) * 8)
  -- Several spans can share one byte range (the # macro expands to POKé).
  -- Never cut through such an expansion.
  while count > 0 and spans[count + 1]
      and spans[count + 1].from == spans[count].from do count = count - 1 end
  return spans, count
end

function DisplayText.clip(text, columns)
  text = tostring(text or "")
  local spans, count = fitting(text, columns)
  return count > 0 and text:sub(1, spans[count].to) or ""
end

function DisplayText.wrap(text, columns)
  local lines = {}
  for part in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    while part ~= "" do
      local spans, count = fitting(part, columns)
      if count == #spans then lines[#lines + 1] = part; break end
      -- A single oversized custom glyph still has to make progress.
      if count == 0 then count = 1 end
      local last = spans[count].to
      local space = part:sub(1, last + 1):match("^.*()%s")
      if space and space > 1 then
        lines[#lines + 1] = part:sub(1, space - 1)
        part = part:sub(space + 1)
      else
        lines[#lines + 1] = part:sub(1, last)
        part = part:sub(last + 1)
      end
    end
  end
  return lines
end

return DisplayText
