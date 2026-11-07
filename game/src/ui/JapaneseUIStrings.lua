-- Launcher pages also need translations before a game loads Strings.data.
-- Look up presentation text only; never translate stored IDs or user input.
local UIStrings = {}
local catalogs = {
  require("src.core.JapaneseStringsKit"),
  require("src.core.JapaneseStringsTouchEditor"),
  require("src.core.JapaneseStringsEditors"),
  require("src.core.JapaneseStringsSettings"),
  require("src.core.JapaneseStringsExtra"),
  require("src.core.JapaneseStrings"),
}

function UIStrings.lookup(source, language)
  source = tostring(source or "")
  if language == "en" then return source end
  -- A running Japanese game's explicit MOD translations still take priority.
  local game = package.loaded["src.core.Game"]
  local data = game and game.data
  if data and data.constants and data.constants.language == "ja"
      and type(data.strings) == "table" and type(data.strings[source]) == "string" then
    return data.strings[source]
  end
  for _, catalog in ipairs(catalogs) do
    if type(catalog[source]) == "string" then return catalog[source] end
  end
  return source
end

function UIStrings.format(source, language, ...)
  local text = UIStrings.lookup(source, language)
  local ok, value = pcall(string.format, text, ...)
  if ok then return value end
  return string.format(source, ...)
end

return UIStrings
