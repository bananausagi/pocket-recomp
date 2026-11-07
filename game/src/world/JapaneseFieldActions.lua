-- Optional GBA-style A interactions. These only choose/confirm the existing
-- field-move entry points; badge rules, map changes and animations stay in
-- OverworldController so the party menu and the shortcut cannot diverge.
local FieldDefaults = require("src.world.FieldDefaults")
local Map = require("src.world.Map")
local TextBox = require("src.render.TextBox")

local Actions = {}
local NAMES = { CUT = "いあいぎり", SURF = "なみのり",
  STRENGTH = "かいりき", FLASH = "フラッシュ" }

function Actions.enabled(game)
  return game and game.save and game.data and game.data.constants
    and game.data.constants.language == "ja" and
    (not game.save.options or game.save.options.jpFieldActions ~= false)
end

function Actions.ready(game, world)
  local p = world and world.player
  return Actions.enabled(game) and p and not p.moving and not p.inputLocked
    and game.stack and game.stack:top() == world
    and not (world.runner and world.runner:isRunning())
    and #(world.scriptMoves or {}) == 0 and #(world.pendingScripts or {}) == 0
    and not world.transitioning and not world.engaging and not world.emote
    and not world.teleportOut and not world.flyAnim and not world.flyArrive
    and not world.spinArrive and not world.holeFall and not world.holeArrive
    and not world.cutAnim and not world.dustAnim and not world.healAnim
    and not world.pikaHop and not world.fishPose and (world.hopLand or 0) <= 0
end

local function japanese(game)
  return game.data and game.data.constants and game.data.constants.language == "ja"
end

-- Use both the collision tile and block swap, never the block id alone:
-- decorative shrubs/fences may share a block with a real cuttable tree.
local function treeAt(game, world, x, y)
  local map = world.map
  if not map:inBounds(x, y) then return nil end
  local ts, tile = map.def.tileset, map:cellTile(x, y)
  if not ((ts == "OVERWORLD" and tile == 0x3d)
      or (ts == "GYM" and tile == 0x50)) or map:isWalkableCell(x, y) then
    return nil
  end
  local block = map:blockAt(math.floor(x / 2), math.floor(y / 2))
  for _, swap in ipairs((game.data.field or {}).cutTreeSwaps or {}) do
    if swap.before == block then return block end
  end
end

local function candidate(game, world, x, y, npc)
  if npc then
    if npc.def and Map.isPushable(npc.def) and not npc.moving
      and npc.cellX == x and npc.cellY == y then
      return "STRENGTH", npc
    end
    return nil
  end
  local tree = treeAt(game, world, x, y)
  if tree then return "CUT", tree end
  if not world.player.surfing and world:facingIsShoreOrWater() then
    return "SURF"
  end
  -- A on an otherwise unclaimed spot in a dark cave offers FLASH, but
  -- ordinary NPC/sign/hidden-object/script/bookshelf interactions win first.
  if world.dark and world:partyKnows("FLASH") then return "FLASH" end
end

local function message(game, ja, en)
  game.stack:push(TextBox.new(game, japanese(game) and ja or en))
end

local function refuse(game, move)
  local badge = (FieldDefaults.constant(game.data, "hmBadges") or {})[move]
  local knows = false
  for _, mon in ipairs(game.save.party or {}) do
    for _, known in ipairs(mon.moves or {}) do
      if known.id == move then knows = true end
    end
  end
  if knows and badge and badge.badge and not (game.save.inventory or {})[badge.badge] then
    game.stack:push(TextBox.new(game, (game.data.text or {})._NewBadgeRequiredText
      or (japanese(game) and "まだ あたらしい バッジが\nひつようです！"
        or "A new BADGE is\nrequired.")))
  else
    message(game, NAMES[move] .. "を おぼえた\nポケモンが ひつようです！",
      "A POKéMON that knows\n" .. move .. " is needed.")
  end
end

local function surfFailure(game, reason)
  local key = ({ forced_bike = "_CyclingIsFunText", current = "_CurrentTooFastText" })[reason]
  local text = key and (game.data.text or {})[key]
  if text then game.stack:push(TextBox.new(game, text))
  else message(game, "ここでは なみのりを\nつかえません！", "No SURFing here!") end
end

function Actions.interact(game, world, x, y, npc)
  if not Actions.ready(game, world) then return false end
  local move, target = candidate(game, world, x, y, npc)
  if not move then return false end
  if move == "STRENGTH" and world.strengthActive then
    message(game, "いわを おして\nうごかせます！", "You can push\nthis boulder!")
    return true, move
  end
  if not world:partyKnows(move) then refuse(game, move); return true, move end
  if move == "SURF" then
    local reason = world:useSurfFieldMove()
    if reason ~= "ok" then surfFailure(game, reason); return true, move end
  end

  local p, map = world.player, world.map
  local cx, cy, facing = p.cellX, p.cellY, p.facing
  local answered = false
  local prompt = japanese(game) and (NAMES[move] .. "を\nつかいますか？")
    or ("Would you like to\nuse " .. move .. "?")
  game.stack:push(TextBox.new(game, prompt, nil, { choice = function(yes)
    -- TextBox has removed both the YES/NO and its question before calling
    -- us. A stale/double callback cannot cut a new target or enter water.
    if answered then return end
    answered = true
    if not yes or not Actions.ready(game, world) or world.map ~= map
      or world.player ~= p or p.cellX ~= cx or p.cellY ~= cy
      or p.facing ~= facing then return end
    local fx, fy = p:facingCell()
    if fx ~= x or fy ~= y then return end
    local currentNpc = world:npcAtCell(fx, fy)
    if currentNpc ~= npc then return end
    local currentMove, currentTarget = candidate(game, world, fx, fy, currentNpc)
    if currentMove ~= move or currentTarget ~= target then return end
    local mon = world:partyKnows(move)
    if not mon then refuse(game, move); return end
    if move == "CUT" then
      if world:useCutFieldMove() == "ok" then world:tryCut(fx, fy) end
    elseif move == "SURF" then
      local reason = world:useSurfFieldMove()
      if reason == "ok" then world:trySurf(fx, fy) else surfFailure(game, reason) end
    elseif move == "STRENGTH" then
      if not world.strengthActive then world:useStrengthFieldMove(mon) end
    elseif move == "FLASH" then
      if world.dark then world:useFlashFieldMove() end
    end
  end }))
  return true, move
end

return Actions
