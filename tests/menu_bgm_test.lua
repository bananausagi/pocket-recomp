-- Real Game/main.lua pause paths with a counted audio transport. The companion
-- LÖVE fixture exercises actual threaded PCM/Source playback past queue depth.
package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('Paused-menu music transport')
local Game = require('src.core.Game')
local Fixed = require('src.core.FixedStep')
local Input = require('src.core.Input'); Input:init()
local Runtime = require('src.mods.Runtime')
local Music = require('src.core.Music')
local Chip = require('src.core.ChipAudio')
local audioTicks, logicFrames, inputTicks, pipelineTicks, worldTicks = 0, 0, 0, 0, 0
local wrongDataset = false
local data = { constants = { language = 'ja' } }
local g = setmetatable({ data = data, input = Input,
  save = { playTime = 123, options = {} },
  stack = { states = {} }, updateSync = function() end,
  logicSpeed = function() return 4 end,
}, { __index = Game })
Music.update = function(d)
  if d ~= data then wrongDataset = true end
  audioTicks = audioTicks + 1
end
Input.step = function() inputTicks = inputTicks + 1 end
Fixed.update = function() logicFrames = logicFrames + 1 end
require('src.render.Tilt').update = function() pipelineTicks = pipelineTicks + 1 end
require('src.render.Pipelines').update = function() pipelineTicks = pipelineTicks + 1 end
package.loaded['src.core.DiscordPresence'] = { update = function() end }
local world = { update = function() worldTicks = worldTicks + 1 end }
local menuTicks = 0
local menu = { systemMenuPause = true, floatingPanel = true,
  update = function() menuTicks = menuTicks + 1 end }

-- Exactly one real-time clock independent of 30/60/120 Hz or 4x game speed.
for _, rate in ipairs({ 30, 60, 120 }) do
  g.stack.states = { world, menu }; g.sessionMenu = nil
  g.audioAccum = 0; g.systemMenuAccum = 0
  local before = audioTicks
  for _ = 1, rate * 12 do g:update(1 / rate) end
  T.check(math.abs(audioTicks - before - 720) <= 1,
    'native settings/MOD menu services 12 seconds at ' .. rate .. ' Hz')
end
T.eq(logicFrames, 0, 'native menus never advance fixed world simulation')
T.eq(worldTicks, 0, 'world state remains frozen')
T.eq(g.save.playTime, 123, 'menu dwell does not advance saved playtime')
T.eq(pipelineTicks, 0, 'render MOD simulation/tweens remain paused')
T.check(menuTicks > 2000 and inputTicks == menuTicks,
  'only menu input and its own update advance')

g.sessionMenu = {}; local before = audioTicks
for _ = 1, 720 do g:update(1 / 60) end
T.eq(audioTicks - before, 720, 'direct session overlay retains music for 12 seconds')
T.eq(inputTicks, menuTicks, 'session overlay cannot consume game input')
Chip.setSuspended(true); before = audioTicks
for _ = 1, 600 do g:update(1 / 60) end
T.eq(audioTicks, before, 'platform audio suspension gates menu music transport')
T.eq(g.audioAccum, 0, 'suspended time is discarded rather than caught up')
Chip.setSuspended(false); g:update(1 / 60)
T.eq(audioTicks - before, 1, 'resume advances only the current frame')
g.sessionMenu = nil; g.stack.states = { world }; before = audioTicks
g:update(1 / 60)
T.eq(logicFrames, 1, 'closing menus resumes one normal game update')
T.eq(audioTicks - before, 1, 'closing menus does not double-service audio')
g.stack.states = { world, menu }; before = audioTicks
g:update(1 / 120); g:update(1 / 120)
T.eq(audioTicks - before, 1, 'reopening keeps fractional real-time audio phase')
g.audioAccum = 1 / 120
g.sessionMenu = { cancelTransfers = function() end }
g.clearSessionInput = function() end
g:closeSessionMenu()
T.eq(g.audioAccum, 1 / 120, 'actual session close preserves fractional audio phase')
g.stack.states = { { isSystemMenuRoot = true } }
g.stack.top = function(self) return self.states[#self.states] end
g.stack.pop = function(self) table.remove(self.states) end
g:navigateSystemMenu()
T.eq(g.audioAccum, 1 / 120, 'actual START close preserves fractional audio phase')
g.audioAccum = 0

-- Actual host love.update paths, including its early return before MOD hooks.
assert(loadfile('main.lua'))()
local function set(fn, name, value)
  for i = 1, 100 do
    local key = debug.getupvalue(fn, i)
    if not key then break end
    if key == name then debug.setupvalue(fn, i, value); return end
  end
  error('missing host upvalue ' .. name)
end
set(love.update, 'Game', g)
set(love.update, 'onlineClientModule', function() return nil end)
set(love.update, 'checkEmergencyQuit', function() end)
set(love.update, 'HostDisplay', { update = function() end })
set(love.update, 'SwitchDiagnostics', { maybeFlush = function() end })
set(love.update, 'NxDisplay', { sync = function() end })
set(love.update, 'LaunchOptions', { pollURI = function() end })
local pending = false
require('src.import.SettingsFiles').update = function() return pending end
local modFrames, autoFrames, driverFrames, editorFrames = 0, 0, 0, 0
local hooks = require('src.mods.Hooks').new()
hooks:wrap('core.update', function(next, game, dt)
  modFrames = modFrames + 1; return next(game, dt)
end, 0, 'menu-bgm-test')
Runtime.install(Runtime.events, hooks)
set(love.update, 'autopilot', { update = function() autoFrames = autoFrames + 1 end })
set(love.update, 'driverCo', coroutine.create(function() driverFrames = driverFrames + 1 end))
g.sessionMenu = {}; before = audioTicks
love.update(1 / 60)
T.eq(audioTicks - before, 1, 'host session pause pumps audio once')
T.eq(modFrames + autoFrames + driverFrames, 0, 'host session keeps MODs and scripted drivers paused')
pending = true; before = audioTicks; love.update(1 / 60)
T.eq(audioTicks - before, 1, 'native settings file picker pumps audio once')
pending = false
local editor = { update = function() editorFrames = editorFrames + 1 end }
for _, mode in ipairs({ { 'TouchEditor', 'touchEditorGame' }, { 'Studio', 'studioGame' } }) do
  set(love.update, mode[1], editor); set(love.update, mode[2], { game = g })
  before = audioTicks; love.update(1 / 60)
  T.eq(audioTicks - before, 1, mode[1] .. ' opened over game pumps audio once')
  set(love.update, mode[2], nil); before = audioTicks; love.update(1 / 60)
  T.eq(audioTicks, before, mode[1] .. ' opened over launcher does not resurrect game audio')
  set(love.update, mode[1], nil)
end
T.eq(editorFrames, 4, 'host editors continue their own UI updates')
T.eq(modFrames + autoFrames + driverFrames, 0, 'all host overlays keep underlying simulation paused')
Runtime.reset()
T.check(not wrongDataset, 'transport retains the active session dataset')
T.finish()
