-- Repeat the same spray only after an explicit field confirmation. Progress
-- fields live in the save, so an active spray survives saving/reloading.
local Rules = require("src.core.JapaneseRules")
local Bag = require("src.inventory.Bag")
local ItemNames = require("src.inventory.ItemNames")
local TextBox = require("src.render.TextBox")
local romText = require("src.core.RomText")
local Repeat = {}
local STEPS = { REPEL = 100, SUPER_REPEL = 200, MAX_REPEL = 250 }

local function japanese(data)
  return data and data.constants and data.constants.language == "ja"
end

function Repeat.remember(data, save, id)
  if japanese(data) and STEPS[id] then
    save.jpRepelItem = id
    save.jpRepelExpired = false
  end
end

local function fieldReady(game, world, scripted)
  if scripted or not world or game.overworld ~= world or game.linkSession then return false end
  if not game.stack or game.stack:top() ~= world then return false end
  local runner = world.runner
  return not ((runner and runner.isRunning and runner:isRunning())
    or #(world.scriptMoves or {}) > 0 or #(world.pendingScripts or {}) > 0
    or world.engaging or world.emote or world.teleportOut or world.transitioning
    or world.flyAnim or world.flyArrive or world.spinArrive
    or world.holeFall or world.holeArrive or world.playerHidden
    or world.cameraPan or world.healAnim
    or (world.player and world.player.inputLocked))
end

local function canRepeat(game, save, id)
  return game.save == save and Rules.enabled(game, "jpRepelRepeat")
    and STEPS[id] ~= nil and save.jpRepelItem == id
    and (save.repelSteps or 0) == 0
    and game.data.items and game.data.items[id] ~= nil
    and type(save.inventory and save.inventory[id]) == "number"
    and save.inventory[id] >= 1
end

local function woreOff(game, world)
  local save, id = game.save, game.save.jpRepelItem
  -- Clear before pushing the modal: its callback or a subsequent step must
  -- never offer this same expiry twice, including when the player says No.
  if japanese(game.data) then save.jpRepelExpired = false end
  local text = romText(game.data, "_RepelWoreOffText", "REPEL's effect\nwore off.")
  if not canRepeat(game, save, id) then
    game.stack:push(TextBox.new(game, text))
    return
  end
  local name = ItemNames.get(game.data, id)
  -- Remove ROM text terminators before adding the next page and choice.
  text = TextBox.strip(text) .. "\f" .. name .. "を\nつづけて つかいますか？"
  local answered = false
  game.stack:push(TextBox.new(game, text, nil, {
    choiceLabels = { "はい", "いいえ" },
    choice = function(yes)
      if answered then return end
      answered = true
      if not yes or not fieldReady(game, world) or not canRepeat(game, save, id) then return end
      -- This is one synchronous transaction after the stock/context recheck;
      -- other spray types, bag order, registration and party data stay intact.
      Bag.remove(save, id, 1)
      save.repelSteps = STEPS[id]
      Repeat.remember(game.data, save, id)
      local used = require("src.inventory.ItemEffects").itemUseLine(game.data, save, name)
      game.stack:push(TextBox.new(game, used, nil, TextBox.soundOpts(game, "Heal_Ailment")))
    end,
  }))
end

-- Return true when this step must not roll a wild encounter. Even without
-- repeat enabled, the final protected step keeps the original Gen 1 rule.
function Repeat.onStep(game, world, scripted)
  local save = game.save
  local active = type(save.repelSteps) == "number" and save.repelSteps > 0
  if active then
    save.repelSteps = save.repelSteps - 1
    if save.repelSteps ~= 0 then return false end
    if japanese(game.data) and not fieldReady(game, world, scripted) then
      save.jpRepelExpired = true
    else
      woreOff(game, world)
    end
    return true
  end
  if japanese(game.data) and save.jpRepelExpired and fieldReady(game, world, scripted) then
    woreOff(game, world)
    return true
  end
  return false
end

return Repeat
