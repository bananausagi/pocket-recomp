-- TM/HM names are synthesized by the importer rather than read from the ROM.
-- Localize only that generated display spelling, including old import caches.
-- Item ids, machine metadata and MOD-authored names remain unchanged.
local ItemNames = {}

function ItemNames.get(data, id, fallback)
  local def = data and data.items and data.items[id]
  local name = def and def.name or fallback or id
  local machine = def and def.machine
  if not (data and data.constants and data.constants.language == "ja"
      and type(machine) == "table") then return name end
  local kind, number = machine.kind, machine.number
  if (kind ~= "TM" and kind ~= "HM") or type(number) ~= "number"
      or number < 1 or number > 99 or number % 1 ~= 0 then return name end
  if name ~= (kind .. "%02d"):format(number) then return name end
  return ((kind == "HM" and "ひでんマシン" or "わざマシン") .. "%02d"):format(number)
end

return ItemNames
