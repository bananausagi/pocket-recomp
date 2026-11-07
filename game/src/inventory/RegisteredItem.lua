-- Japanese Red's SELECT shortcut keeps a reusable field tool in the save.
-- Revalidate on use: depositing/removing the tool must not leave a live shortcut.
local RegisteredItem = {}
local TOOLS = { BICYCLE=true, OLD_ROD=true, GOOD_ROD=true, SUPER_ROD=true,
  ITEMFINDER=true, POKE_FLUTE=true, TOWN_MAP=true }

function RegisteredItem.enabled()
  return require("src.core.GameVersion").get() == "red_jp"
end

function RegisteredItem.canRegister(game, id)
  local inventory = game and game.save and game.save.inventory
  return RegisteredItem.enabled() and TOOLS[id] == true
    and type(inventory) == "table" and (tonumber(inventory[id]) or 0) > 0
end

function RegisteredItem.get(game)
  local save = game and game.save
  if not save or not RegisteredItem.enabled() then return nil end
  local id = save.registeredItem
  if type(id) == "string" and RegisteredItem.canRegister(game, id) then return id end
  save.registeredItem = nil
end

function RegisteredItem.toggle(game, id)
  if not RegisteredItem.canRegister(game, id) then return nil end
  local on = RegisteredItem.get(game) ~= id
  game.save.registeredItem = on and id or nil
  return on
end

return RegisteredItem
