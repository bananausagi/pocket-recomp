-- ROM-free interaction fixture: real overworld HM methods, TextBox,
-- ChoiceBox, StateStack and palette transition. Only map/art/audio are fake.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("JP contextual field actions")
local sounds = {}
package.loaded["src.core.Sound"] = {
  play = function(_, id) sounds[#sounds + 1] = id end,
  playPress = function() end, playCry = function() end,
}
local musicCalls = 0
package.loaded["src.core.Music"] = { playMap = function() musicCalls = musicCalls + 1 end }
local TextBox = require("src.render.TextBox")
local createText = TextBox.new
TextBox.new = function(game, text, done, opts)
  local box = createText(game, text, done, opts)
  box.fixtureText = text
  return box
end
local ChoiceBox = require("src.ui.ChoiceBox")
local Game = require("src.core.Game")
local OW = require("src.world.OverworldController")
local Actions = require("src.world.JapaneseFieldActions")
local Stack = require("src.core.StateStack")
local Input = require("src.core.Input")
local Save = require("src.core.SaveData")
local Data = require("tests.modkit.fixtures").fresh()
local Version = require("src.core.GameVersion")
Data.constants.language = "ja"
Data.field.cutTreeSwaps = { { before = 7, after = 8 } }
Data.text._NewBadgeRequiredText = "まだ あたらしい バッジが\nひつようです！"
Data.text._UsedCutText = "{RAM:wNameBuffer}は\nいあいぎりを つかった！"
Data.text._SurfingGotOnText = "{RAM:wNameBuffer}に\nのった！"
Data.text._UsedStrengthText = "{RAM:wNameBuffer}は\nかいりきを つかった！"
Data.text._CanMoveBouldersText = "いわを うごかせます！"
Data.text._FlashLightsAreaText = "フラッシュで あかるくなった！"
Data.text._CyclingIsFunText = "ここでは じてんしゃ！"
Data.text._CurrentTooFastText = "ながれが はやすぎる！"
Data.pokemon.FIXMON_A.name = "テスト"
local manifestFile = assert(io.open("tools/rom_manifest_red_jp.json", "rb"))
local manifest = require("src.link.Json").decode(manifestFile:read("*a")); manifestFile:close()
Data.font.charmap, Data.font.composites = manifest.fontCharmap, manifest.fontComposites
Version.set("red_jp")
require("src.core.Strings").load(Data)
require("src.render.Font").load(Data)
Game.data, Game.stack, Game.input = Data, Stack, Input
Input:init()
local scriptOwnsNpc, mapHook
local scripts = {
  get = function() return { onInteract = function(...)
    return mapHook and mapHook(...) or false end } end,
  talkScript = function() return scriptOwnsNpc end,
}
for _, fn in ipairs({ OW.interact, OW.tryCut }) do
  for i = 1, 50 do
    local name = debug.getupvalue(fn, i)
    if not name then break end
    if name == "Game" then debug.setupvalue(fn, i, Game) end
    if name == "mapScripts" then debug.setupvalue(fn, i, scripts) end
  end
end
local function fresh(kind)
  Stack:init(); Input:reset(); sounds = {}; musicCalls = 0
  scriptOwnsNpc, mapHook = nil, nil
  Game.save = { player = { name = "レッド" }, flags = {}, inventory = {
    CASCADEBADGE = true, SOULBADGE = true, RAINBOWBADGE = true, BOULDERBADGE = true },
    party = { { species = "FIXMON_A", nickname = "テスト", hp = 0, moves = {
      { id = "CUT" }, { id = "SURF" }, { id = "STRENGTH" }, { id = "FLASH" } } } },
    options = Save.defaultOptions() }
  Game.save.options.jpFieldActions = true
  Game.save.options.textSpeed = "fast"
  local p = { cellX = 2, cellY = 2, facing = "right", surfing = false }
  function p:facingCell()
    local d = ({ right = { 1, 0 }, left = { -1, 0 }, up = { 0, -1 }, down = { 0, 1 } })[self.facing]
    return self.cellX + d[1], self.cellY + d[2]
  end
  local map = { id = "FIX_TOWN", def = { tileset = "OVERWORLD" },
    tile = kind == "tree" and 0x3d or 0x01, block = 7, changes = 0, rebuilds = 0 }
  function map:inBounds(x, y) return x >= 0 and x < 20 and y >= 0 and y < 20 end
  function map:cellTile(x, y) return x == 3 and y == 2 and self.tile or 0x01 end
  function map:isWalkableCell(x, y) return self:cellTile(x, y) ~= 0x3d end
  function map:blockAt() return self.block end
  function map:setBlock(_, _, b) self.block = b; self.tile = 0x01; self.changes = self.changes + 1 end
  function map:isCounterCell() return false end
  function map:signAtCell() return self.sign end
  map.renderer = { rebuild = function() map.rebuilds = map.rebuilds + 1 end }
  local ow = setmetatable({ map = map, player = p, npcs = {}, scriptMoves = {},
    pendingScripts = {}, runner = { isRunning = function() return false end },
    dark = kind == "dark", steps = 0, talks = 0, dust = 0 }, { __index = OW })
  ow.tryCardKeyDoor = function() return false end
  ow.tryHiddenObject = function() return false end
  ow.tryBookshelf = function() return false end
  ow.facingIsShoreOrWater = function() return kind == "water" end
  ow.surfBlockedHere = function(self) return self.blockedCurrent end
  ow.talkTo = function(self) self.talks = self.talks + 1 end
  ow.showMapText = function(self) self.talks = self.talks + 1 end
  ow.startDustAnim = function(self, _, _, done) self.dust = self.dust + 1; if done then done() end end
  ow.stepForwardOrCrossEdge = function(self) self.steps = self.steps + 1 end
  ow.setDark = function(self, dark) self.dark = dark end
  if kind == "boulder" then
    ow.npcs = { { cellX = 3, cellY = 2, def = { sprite = "SPRITE_BOULDER" } } }
  end
  Stack.states = { ow }; Game.overworld = ow
  return ow
end
local function frame(button)
  Input.pressed = button and { [button] = true } or {}
  Stack:update(1 / 60)
end
local function awaitChoice()
  for _ = 1, 1500 do
    if getmetatable(Stack:top()) == ChoiceBox then return Stack:top() end
    assert(getmetatable(Stack:top()) == TextBox, "expected a native question")
    frame("a")
  end
  error("choice did not appear")
end
local function answer(button)
  local choice = awaitChoice()
  frame(button or "a")
  for _ = 1, 50 do
    if Stack:top() ~= choice then return end
    frame()
  end
  error("choice did not dismiss")
end
local function drain(ow)
  for _ = 1, 3000 do
    if Stack:top() == ow then return end
    frame("a")
  end
  error("field action failed to settle")
end

local ow = fresh("tree")
ow:interact()
T.eq(getmetatable(Stack:top()), TextBox, "A at tree opens actual dialogue")
T.eq(Stack:top().fixtureText, "いあいぎりを\nつかいますか？", "Cut question is Japanese")
T.eq(ow.map.changes, 0, "question has no world mutation")
local originalQuestion = Stack:top()
ow:interact()
T.eq(Stack:top(), originalQuestion, "repeated A cannot stack a second question")
answer("b")
T.eq(Stack:top(), ow, "B dismisses both native choice and question")
T.eq(ow.map.changes, 0, "B does not cut")
ow:interact(); awaitChoice(); frame("down"); answer("a")
T.eq(ow.map.changes, 0, "explicit NO also cancels Cut")
T.eq(Stack:top(), ow, "explicit NO returns to the field")
ow:interact(); local callback = Stack:top().choice; answer("a")
T.eq(ow.map.changes, 0, "confirmed cut still waits for native used-move text")
drain(ow)
T.eq(ow.map.changes, 1, "confirmed Cut replaces tree exactly once")
T.eq(ow.map.rebuilds, 1, "same tree gets one renderer rebuild")
T.eq(ow.dust, 1, "existing Cut animation runs once")
T.eq(sounds[#sounds], "Cut", "existing Cut sound preserved")
T.eq(#ow.cutBlocks.FIX_TOWN, 1, "one restore-on-map-reload record")
callback(true); ow:interact()
T.eq(ow.map.changes, 1, "double callback and repeated A never duplicate Cut")
T.eq(Stack:top(), ow, "removed tree no longer prompts")
T.eq(Game.save.party[1].hp, 0, "Gen1 fainted-party HM eligibility retained")

for _, mode in ipairs({ "no_badge", "missing_move" }) do
  ow = fresh("tree")
  if mode == "no_badge" then Game.save.inventory.CASCADEBADGE = nil
  else Game.save.party[1].moves = {} end
  ow:interact()
  T.eq(Stack:top().choice, nil, mode .. " refuses rather than offering an unusable confirmation")
  T.check(Stack:top().fixtureText:find(mode == "no_badge" and "バッジ" or "おぼえた", 1, true) ~= nil,
    mode .. " has a Japanese requirement explanation")
  drain(ow); T.eq(ow.map.changes, 0, mode .. " never alters tree")
end
for _, gate in ipairs({ "moving", "inputLocked", "script", "queued", "scriptMoves", "transitioning",
    "engaging", "emote", "flyAnim", "holeFall", "cutAnim", "dustAnim", "menu" }) do
  ow = fresh("tree")
  if gate == "moving" or gate == "inputLocked" then ow.player[gate] = true
  elseif gate == "script" then ow.runner.isRunning = function() return true end
  elseif gate == "queued" then ow.pendingScripts = { {} }
  elseif gate == "scriptMoves" then ow.scriptMoves = { {} }
  elseif gate == "menu" then Stack:push({})
  else ow[gate] = {} end
  local top = Stack:top(); ow:interact()
  T.eq(Stack:top(), top, gate .. " prevents prompt")
  T.eq(ow.map.changes, 0, gate .. " prevents field side effect")
end
for _, change in ipairs({ "facing", "position", "map", "block", "badge", "option", "script", "occupied" }) do
  ow = fresh("tree"); ow:interact()
  if change == "facing" then ow.player.facing = "up"
  elseif change == "position" then ow.player.cellX = 1
  elseif change == "map" then local changed = {}; for k,v in pairs(ow.map) do changed[k] = v end; ow.map = changed
  elseif change == "block" then ow.map.block = 9
  elseif change == "badge" then Game.save.inventory.CASCADEBADGE = nil
  elseif change == "option" then Game.save.options.jpFieldActions = false
  elseif change == "script" then ow.runner.isRunning = function() return true end
  elseif change == "occupied" then ow.npcs = { { cellX = 3, cellY = 2, def = {} } } end
  answer("a"); drain(ow)
  T.eq(ow.map.changes, 0, "stale " .. change .. " invalidates pending action")
end
for _, place in ipairs({ "wrong_tile", "wrong_tileset", "grass", "sign", "npc", "script" }) do
  ow = fresh("tree")
  if place == "wrong_tile" then ow.map.tile = 0x01
  elseif place == "wrong_tileset" then ow.map.def.tileset = "PLATEAU"
  elseif place == "grass" then ow.map.tile = 0x52
  elseif place == "sign" then ow.map.sign = { text = "FIX_SIGN" }
  elseif place == "npc" then ow.npcs = { { cellX = 3, cellY = 2, def = { sprite = "SPRITE_FIX_NPC" } } }
  elseif place == "script" then mapHook = function() return true end end
  ow:interact(); T.eq(Stack:top(), ow, place .. " is not hijacked by CUT")
  T.eq(ow.map.changes, 0, place .. " has no Cut mutation")
end
ow = fresh("tree"); Game.save.options.jpFieldActions = false; ow:interact()
T.eq(Stack:top(), ow, "disabled contextual action restores original A behavior")
T.eq(ow:useCutFieldMove(), "ok", "manual party-menu field eligibility still works when disabled")
ow:tryCut(3, 2); drain(ow); T.eq(ow.map.changes, 1, "manual Cut still runs while shortcut disabled")
ow = fresh("tree"); Data.constants.language = "en"; ow:interact()
T.eq(Stack:top(), ow, "non-Japanese original A interactions unchanged")
Data.constants.language = "ja"

ow = fresh("water"); Game.save.onBike = true; ow:interact()
T.eq(Stack:top().fixtureText, "なみのりを\nつかいますか？", "shore opens Surf question")
answer("b"); T.eq(Game.save.onBike, true, "cancel Surf does not dismount bicycle")
T.eq(musicCalls, 0, "cancel Surf does not change BGM")
ow:interact(); answer("a")
T.eq(ow.player.surfing, false, "Surf still waits for got-on message")
drain(ow)
T.eq(ow.player.surfing, true, "Surf sets native riding state")
T.eq(Game.save.onBike, false, "native Surf ends bicycle mode")
T.eq(ow.steps, 1, "Surf steps into water exactly once after flash")
T.eq(musicCalls, 1, "native Surf changes BGM once")
ow:interact(); T.eq(Stack:top(), ow, "already surfing does not offer remount")
for _, gate in ipairs({ "forced_bike", "current", "no_badge" }) do
  ow = fresh("water")
  if gate == "forced_bike" then Game.save.forcedBike = true
  elseif gate == "current" then ow.blockedCurrent = true
  else Game.save.inventory.SOULBADGE = nil end
  ow:interact(); T.eq(Stack:top().choice, nil, gate .. " preserves Surf refusal")
  drain(ow); T.eq(ow.steps, 0, gate .. " cannot cross water")
end

ow = fresh("boulder"); ow:interact()
T.eq(Stack:top().fixtureText, "かいりきを\nつかいますか？", "boulder opens Strength question")
answer("b"); T.eq(ow.strengthActive, nil, "cancel leaves Strength inactive")
ow:interact(); answer("a"); drain(ow)
T.eq(ow.strengthActive, true, "native Strength activates after confirmation")
T.eq(ow.npcs[1].cellX, 3, "confirmation never pushes boulder through collision")
ow:interact(); T.eq(Stack:top().choice, nil, "active Strength only explains push, no repeated confirmation")
drain(ow)
ow = fresh("boulder"); scriptOwnsNpc = true; ow:interact()
T.eq(ow.talks, 1, "script-owned boulder dialogue retains priority")
T.eq(Stack:top(), ow, "script-owned object does not open HM prompt")
ow = fresh("boulder"); ow:interact(); ow.npcs = {}; answer("a")
T.eq(ow.strengthActive, nil, "removed boulder invalidates pending Strength")

ow = fresh("dark"); ow:interact()
T.eq(Stack:top().fixtureText, "フラッシュを\nつかいますか？", "empty A in dark cave offers Flash")
answer("b"); T.eq(ow.dark, true, "Flash cancellation retains darkness")
ow:interact(); answer("a"); drain(ow)
T.eq(ow.dark, false, "native Flash lights cave")
T.eq(Game.save.flashLit, true, "Flash retains original save flag")
ow:interact(); T.eq(Stack:top(), ow, "lit cave does not repeatedly offer Flash")
T.finish()
