-- jp.74 わざの おもいだし (jpMoveReminder) for Gold / Silver / Crystal.
--
-- The Gen 1 port's party-menu move reminder (src/pokemon/JapaneseMoveReminder.lua
-- and src/ui/JapaneseMoveReminderMenu.lua), rebuilt over Gold's own data:
-- the candidates are the species' `levelMoves` at or under the mon's level
-- that it does not know, and the learning itself goes through
-- Game2:learnMoveOn -- the same LearnMove / ForgetMove flow a level-up uses,
-- so the HM refusal (and jpForgetHM lifting it) is the vanilla one.
--
-- The Gen 1 PP rule is kept: a move that REPLACES another keeps the old move's
-- PP (capped at the new move's max), so swapping back and forth never refills
-- PP.  A move written into an empty slot starts full, as a level-up would.
--
-- Off by default; only the field party submenu offers the row, never a battle.

local Chrome = require("src.ui.gen2.Chrome")
local Sound = require("src.core.Sound")
local TextBox = require("src.render.TextBox")

local Reminder = {}
Reminder.__index = Reminder
Reminder.isOpaque = false

local VISIBLE_ROWS = 5
local BOX_X, BOX_Y, BOX_INTERIOR_W, BOX_INTERIOR_H = 0, 0, 18, 11
local LIST_X, LIST_Y, ROW_STEP = 2, 3, 2

local TEXT = {
  ja = {
    title = "おもいだす わざ",
    ask = "%sを\nおもいだしますか？",
    none = "おもいだせる わざは\nありません。",
    label = "おもいだす",
  },
  en = {
    title = "REMEMBER MOVE",
    ask = "Remember\n%s?",
    none = "There are no\nmoves to remember.",
    label = "REMIND",
  },
}

local function lang(game)
  local constants = game and game.data and game.data.constants
  return (constants and constants.language == "ja") and "ja" or "en"
end

function Reminder.text(game, key)
  return TEXT[lang(game)][key]
end

function Reminder.enabled(game)
  local options = game and game.options
  return options ~= nil and options.jpMoveReminder == true
end

-- Level-up moves at or under the mon's level that it does not know, in the
-- species' own learnset order, each listed once.
function Reminder.candidates(mon, data)
  if type(mon) ~= "table" or mon.isEgg or mon.egg then return {} end
  local pokemon = data and data.pokemon
  local def = pokemon and pokemon[mon.species]
  local moves = data and data.moves or {}
  local known = {}
  for _, entry in ipairs(mon.moves or {}) do
    if entry and entry.id then known[entry.id] = true end
  end
  local out, seen = {}, {}
  local level = tonumber(mon.level) or 0
  for _, entry in ipairs((def and def.levelMoves) or {}) do
    local id = entry.move
    if id and (entry.level or 0) <= level and not known[id] and not seen[id]
        and id ~= "STRUGGLE" then
      local moveDef = moves[id]
      if moveDef and (moveDef.pp or 0) > 0 then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  end
  return out
end

-- The party submenu row (src/ui/gen2/PartyMenu.lua buildSubmenuItems).
function Reminder.open(game, mon)
  if not (game and game.stack) then return nil end
  local list = Reminder.candidates(mon, game.data)
  if #list == 0 then
    if game.say then game:say(Reminder.text(game, "none")) end
    return nil
  end
  local screen = Reminder.new(game, { mon = mon, list = list })
  game.stack:push(screen)
  return screen
end

function Reminder.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Reminder)
  self.game = game
  self.screenId = "Gen2JapaneseMoveReminder"
  self.mon = opts.mon
  self.moves = (game and game.data and game.data.moves) or {}
  self.list = opts.list or Reminder.candidates(self.mon, game and game.data)
  self.row = 1
  self.top = 1
  return self
end

function Reminder:wantsFillScale() return true end

function Reminder:moveName(id)
  local def = self.moves[id]
  return (def and def.name) or id or "-"
end

function Reminder:playSfx(name)
  local data = self.game and self.game.data
  local sfx = data and data.audio and data.audio.sfx
  if sfx and sfx[Sound.resolve(data, name)] then Sound.play(data, name) end
end

function Reminder:close()
  if self.closed then return end
  self.closed = true
  local stack = self.game and self.game.stack
  if stack and stack:top() == self then stack:pop() end
end

-- After Game2:learnMoveOn: a replaced slot keeps min(new max PP, old PP).
function Reminder.applyPpRule(mon, moveId, before)
  for slot, entry in ipairs(mon.moves or {}) do
    if entry.id == moveId then
      local old = before[slot]
      if old and old.id and old.id ~= moveId then
        local cap = entry.maxPp or entry.pp or 0
        entry.pp = math.min(cap, old.pp or 0)
      end
      return slot
    end
  end
  return nil
end

function Reminder:learn(id)
  local game = self.game
  local mon = self.mon
  if not (game and game.learnMoveOn and mon) then return end
  local before = {}
  for slot, entry in ipairs(mon.moves or {}) do
    before[slot] = { id = entry.id, pp = entry.pp }
  end
  self.busy = true
  game:learnMoveOn(mon, id, function(learned)
    self.busy = false
    if learned then
      Reminder.applyPpRule(mon, id, before)
      self.finished = true
    end
  end)
end

function Reminder:confirm(id)
  local game = self.game
  self.busy = true
  game.stack:push(TextBox.new(game,
    string.format(Reminder.text(game, "ask"), self:moveName(id)), nil,
    { choice = function(yes)
      self.busy = false
      if yes then self:learn(id) end
    end }))
end

function Reminder:update(_dt)
  if self.closed then return end
  if self.finished then return self:close() end
  if self.busy then return end
  local input = self.game and self.game.input
  if not input then return end
  local n = #self.list
  if n == 0 then return self:close() end
  if input:wasPressed("up") then
    self.row = self.row > 1 and self.row - 1 or n
  elseif input:wasPressed("down") then
    self.row = self.row < n and self.row + 1 or 1
  elseif input:wasPressed("a") then
    self:playSfx("Sfx_ReadText2")
    self:confirm(self.list[self.row])
  elseif input:wasPressed("b") then
    self:playSfx("Sfx_ReadText2")
    self:close()
  end
  if self.row < self.top then self.top = self.row end
  if self.row > self.top + VISIBLE_ROWS - 1 then
    self.top = self.row - VISIBLE_ROWS + 1
  end
end

function Reminder:draw()
  Chrome.textbox(BOX_X, BOX_Y, BOX_INTERIOR_W, BOX_INTERIOR_H)
  Chrome.print(Reminder.text(self.game, "title"), 1, 1)
  for i = 0, VISIBLE_ROWS - 1 do
    local index = self.top + i
    local id = self.list[index]
    if not id then break end
    local y = LIST_Y + i * ROW_STEP
    Chrome.print(self:moveName(id), LIST_X, y)
    local def = self.moves[id]
    if def and def.pp then
      -- Same row as the name: a PP figure on the line below read as the
      -- next move's on a 2-row step.
      Chrome.printRight(tostring(def.pp), 18, y)
    end
    if index == self.row then Chrome.cursor(LIST_X - 1, y) end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Reminder
