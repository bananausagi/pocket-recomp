-- Optional convenience rules. An absent option keeps the original Gen 1
-- behavior, including the original EXP.ALL arithmetic. Presets deliberately
-- touch only these options, never a player's graphics, controls or MOD setup.
local Rules = {}

Rules.keys = { "jpPartyExp", "jpForgetHM", "jpReusableTM" }

local function options(subject)
  if type(subject) ~= "table" then return {} end
  if subject.save then return subject.save.options or {} end
  return subject.options or subject
end

function Rules.enabled(subject, key)
  -- Gen 1 saves share launcher options across cartridges. These controls
  -- are exposed only for Japanese games, so carrying a true flag into an
  -- English cartridge must not silently change rules the menu cannot edit.
  -- Plain options/save records remain usable by the preset helpers.
  if type(subject) == "table" and subject.save then
    local data = subject.data
    if not (data and data.constants and data.constants.language == "ja") then
      return false
    end
  end
  return options(subject)[key] == true
end

function Rules.preset(subject)
  local opts, count = options(subject), 0
  for _, key in ipairs(Rules.keys) do
    if opts[key] == true then count = count + 1 end
  end
  if count == 0 then return "classic" end
  if count == #Rules.keys then return "convenient" end
  return "custom"
end

function Rules.applyPreset(subject, preset)
  if preset ~= "classic" and preset ~= "convenient" then return false end
  local opts = options(subject)
  for _, key in ipairs(Rules.keys) do opts[key] = preset == "convenient" end
  return true
end

return Rules
