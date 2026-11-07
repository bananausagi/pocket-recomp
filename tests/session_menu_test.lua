-- Session navigation contracts, using real Game entry points and the shared
-- declarative settings model; no ROM, native game data or saved progress.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Japanese session menu")
local Game = require("src.core.Game")
local Input = require("src.core.Input")
local Touch = require("src.core.TouchControls")
local FixedStep = require("src.core.FixedStep")
local Menu = require("src.ui.SessionMenu")
local SaveData = require("src.core.SaveData")
require("src.core.GameVersion").set("red_jp")
Input:init(); Touch:init()
local ow = { player = { moving = false } }
local stack = { states = { ow } }
function stack:top() return self.states[#self.states] end
local counts = { writes = 0, homes = 0, applies = 0, options = 0, modInputs = 0 }
local failSave, failOptions = false, false
local g = setmetatable({ stack = stack, overworld = ow,
  save = { options = SaveData.defaultOptions() }, mods = {
    releaseModInput = function() counts.modInputs = counts.modInputs + 1 end,
  } }, { __index = Game })
g.writeSave = function() counts.writes = counts.writes + 1; return not failSave end
g.returnToLauncher = function() counts.homes = counts.homes + 1 end
g.applyOptions = function(self, options)
  counts.applies = counts.applies + 1
  T.check(options == self.save.options, "settings apply the live game option table")
end
g.writeOptions = function() counts.options = counts.options + 1; return not failOptions end
g.save.options.modOptions = { fixture = { value = 1 } }
Input:keypressed("right")
g:keypressed("acback")
T.check(g.sessionMenu ~= nil, "Android back opens the session menu")
T.eq(#stack.states, 1, "opening keeps original state stack unchanged")
T.check(not Input:isDown("right"), "opening releases held gameplay input")
T.eq(counts.modInputs, 1, "opening releases held MOD input")
local originalUpdate = FixedStep.update
FixedStep.update = function() error("simulation must not run while menu is open") end
T.check(pcall(g.update, g, 10), "long menu frame cannot tick the simulation")
FixedStep.update = originalUpdate
local m = g.sessionMenu
T.check(m:canSave(), "standing overworld remains safe to save during the overlay")
ow.player.moving = true
T.check(not m:canSave(), "moving player cannot quick-save")
T.check(not m:saveProgress(), "unsafe report is rejected")
T.eq(counts.writes, 0, "unsafe report never writes progress")
ow.player.moving = false
stack.states[2] = { screenId = "Battle" }
T.check(not m:canSave(), "battle underneath the overlay cannot save")
stack.states[2] = nil
ow.runner = { isRunning = function() return true end }
T.check(not m:canSave(), "running cutscene cannot save")
ow.runner = nil
stack.states = { { screenId = "PlayerStartMenu" } }
T.check(not m:canSave(), "title cannot overwrite a real save with a new-game skeleton")
stack.states = { ow }
failSave = true
T.check(not m:goHome(true), "failed save blocks return home")
T.eq(counts.homes, 0, "home callback not dispatched after failed write")
T.check(g.sessionMenu == m and not m.leaving, "failed write preserves paused game")
failSave = false
T.check(m:goHome(true), "successful save permits home return")
T.eq(counts.homes, 1, "successful save dispatches home exactly once")
T.check(m.leaving, "return keeps game paused until host teardown")
g:closeSessionMenu()
g:openSessionMenu("home")
m = g.sessionMenu
local before = counts.writes
T.check(m:goHome(false), "explicit discard permits home return")
T.eq(counts.writes, before, "discard never overwrites a report")
g:closeSessionMenu()
g:keypressed("escape")
T.check(g.sessionMenu ~= nil, "Escape opens from gameplay")
g:keypressed("escape", true)
T.check(g.sessionMenu ~= nil, "Escape auto-repeat does not immediately close menu")
g:keyreleased("escape")
g:keypressed("escape")
T.eq(g.sessionMenu, nil, "second Escape closes main menu")
T.eq(FixedStep.accum, 0, "resume clears simulation catch-up debt")
g:gamepadpressed(nil, "guide")
T.check(g.sessionMenu ~= nil, "gamepad guide opens menu")
g:gamepadreleased(nil, "guide")
g:gamepadpressed(nil, "b")
T.eq(g.sessionMenu, nil, "gamepad B resumes from main menu")
g:gamepadreleased(nil, "b")
T.check(not Input:isDown("b"), "menu button does not carry over into gameplay")
g:openSessionMenu("settings")
m = g.sessionMenu
local model = m:settings()
local music
for _, section in ipairs(model.sections) do
  for _, row in ipairs(section.rows) do if row.id == "musicVol" then music = row end end
end
T.check(music ~= nil, "session settings use real shared audio model")
local originalVolume = g.save.options.musicVol
m:change(music, -1)
T.eq(g.save.options.musicVol, originalVolume - 1, "audio changes immediately on live game")
T.eq(counts.options, 1, "one tap persists preferences once")
T.check(g.mods.modOptions == g.save.options.modOptions, "MOD settings share the running loader values")
failOptions = true
m:change(music, -1)
T.eq(g.save.options.musicVol, originalVolume - 1, "failed preference write rolls value back")
T.check(m.warning and m.model == nil, "failure is visible and model closures are rebuilt")
failOptions = false
local pipelines, tilt = require("src.render.Pipelines"), require("src.render.Tilt")
pipelines.install({ render_pipelines = { voxel = { label = "VOXEL", drawWorld = function() end } } })
g.save.options.pipelines, g.save.options.tilt = { voxel = 1 }, 0
pipelines.applyOptions(g.save.options)
local originalApply = g.applyOptions
g.applyOptions = function(self, options)
  originalApply(self, options); tilt.applyOptions(options); pipelines.applyOptions(options)
end
m.model = nil
local tiltRow, voxelRow
for _, section in ipairs(m:settings().sections) do
  for _, row in ipairs(section.rows) do
    if row.id == "tilt" then tiltRow = row end
    if row.id == "pipeline.voxel" then voxelRow = row end
  end
end
T.check(voxelRow ~= nil, "3D renderer can be controlled in the running session")
m:change(tiltRow, 1)
T.eq(pipelines.level("voxel"), 0, "enabling native tilt disables conflicting 3D pipeline")
T.eq(g.save.options.pipelines.voxel, 0, "3D exclusion is persisted with preferences")
T.eq(tilt.level, 1, "native tilt setting is actually applied")
m:change(voxelRow, 1)
T.eq(pipelines.level("voxel"), 1, "3D can be enabled again without going home")
T.eq(tilt.level, 0, "3D re-enable switches native tilt off")
failOptions = true
m:change(tiltRow, 1)
T.eq(pipelines.level("voxel"), 1, "failed setting write restores the running 3D pipeline")
T.eq(tilt.level, 0, "failed setting write restores native tilt too")
failOptions = false
for index in ipairs(m:settings().sections) do
  m:open("settings-detail", index)
  for _, row in ipairs(m:rows()) do
    T.check(row.step and not row.action and row.id ~= "hotbar"
      or (row.id == "importSettings" or row.id == "exportSettings") and row.action,
      "running settings expose safe values and explicit JSON transfer actions only")
  end
end
m:open("settings")
g:keypressed("acback")
T.eq(m.page, "main", "Android back leaves settings without resuming by accident")
g:keyreleased("acback")
g:keypressed("acback")
T.eq(g.sessionMenu, nil, "Android back on main resumes gameplay")
-- No persistent chrome or invisible hotspot: Back / Escape / Guide opens
-- the menu even when gameplay touch buttons are disabled.
Touch.enabled = false
T.check(Menu.buttonRect == nil and Menu.drawButton == nil and Menu.buttonContains == nil,
  "persistent menu chip and hotspot API are removed")
g:touchpressed(7, 600, 25)
T.eq(g.sessionMenu, nil, "former chip location does not open menu on touch")
g:touchreleased(7, 600, 25)
g:mousepressed(600, 25, 1, false)
T.eq(g.sessionMenu, nil, "former chip location does not open menu on mouse click")
g:keypressed("acback")
T.check(g.sessionMenu ~= nil, "Android back opens menu with touch controls disabled")
g:keyreleased("acback")
m = g.sessionMenu
local l = m:layout()
local row = l.hits[1]
local x = l.viewport.x + (row.x + row.w / 2) * l.viewport.sx
local y = l.viewport.y + (row.y + row.h / 2) * l.viewport.sy
g:touchpressed(8, x, y)
g:mousepressed(x, y, 1, true)
T.check(g.sessionMenu == m, "synthesized mouse twin cannot activate touch twice")
g:touchreleased(8, x, y)
T.eq(g.sessionMenu, nil, "direct row touch resumes on release")
g:keypressed("escape")
T.check(g.sessionMenu ~= nil, "desktop Escape opens menu without screen chrome")
m = g.sessionMenu
m:pressed(9, x, y)
T.check(m.pointer ~= nil, "menu owns a touch before a focus interruption")
g:focus(false)
T.eq(m.pointer, nil, "focus interruption cancels menu pointer ownership")
m:pressed(10, x, y)
T.check(m.pointer and m.pointer.id == 10, "next touch works after Android lost a release")
g:visible(false)
T.eq(m.pointer, nil, "visibility interruption also cancels menu pointer")
-- JSON settings commit must retain the same live table and roll back both
-- values and live renderers if persistence fails.
local Json = require("src.link.Json")
local candidate = Json.decode(Json.encode(g.save.options))
candidate.musicVol = 2
T.check(m:applyImportedSettings(candidate), "valid imported settings apply to paused safe overworld")
T.eq(g.save.options.musicVol, 2, "imported preference reaches running game")
T.check(m.model == nil and m.page == "settings", "import rebuilds session setting rows")
T.check(g.mods.modOptions == g.save.options.modOptions, "import refreshes MOD preference table")
candidate.musicVol = 4
failOptions = true
T.check(not m:applyImportedSettings(candidate), "failed import persistence is rejected")
T.eq(g.save.options.musicVol, 2, "failed import restores old preference")
T.eq(pipelines.level("voxel"), 1, "failed import restores active 3D renderer")
failOptions = false
ow.player.moving = true
before = counts.options
T.check(not m:applyImportedSettings(candidate), "JSON import cannot rebuild a moving overworld")
T.check(not m:importSettings(), "unsafe import does not launch native picker")
T.eq(counts.options, before, "unsafe JSON import never writes preferences")
ow.player.moving = false
m.notice = nil
local SettingsFiles = require("src.import.SettingsFiles")
T.check(m:importSettings(), "safe desktop session can start JSON drop import")
T.check(SettingsFiles.pending(), "desktop JSON import records a pending drop")
T.check(m.notice and m.notice:find("ドロップ", 1, true), "drop instruction is not mistaken for completed import")
m:back()
T.check(not SettingsFiles.pending(), "touch-style back cancels pending desktop JSON drop")
T.eq(m.notice, nil, "cancel also closes pending import instructions")
local bootCandidate = Json.decode(Json.encode(g.save.options))
bootCandidate.mods = bootCandidate.mods or {}; bootCandidate.mods.test_restart = false
T.check(m:applyImportedSettings(bootCandidate), "MOD toggle settings persist through JSON import")
T.check(m.importRestartPending, "boot-only MOD toggle difference requests reopen notice")
T.check(m:importSettings(), "second JSON import can start after cancellation")
T.check(not m.importRestartPending, "new picker does not inherit previous success notice state")
m:back()
g.touchControls = { visible = function() return true end,
  hitTest = function() return "b" end }
g:touchpressed(19, -10, -10); g:touchreleased(19, -10, -10)
T.eq(m.page, "main", "visible gamepad B touch returns through session navigation")
g:touchpressed(20, -10, -10); g:touchreleased(20, -10, -10)
T.eq(g.sessionMenu, nil, "visible gamepad B touch closes the session overlay")
g.touchControls = nil
T.check(not m:applyImportedSettings(candidate), "stale picker callback cannot mutate ended session")
g:closeSessionMenu()

-- Test the actual host callback as well as Game:update: MOD core.update
-- wraps Game:update and therefore has to be blocked one level earlier.
assert(loadfile("main.lua"))()
local function upvalue(fn, name, value)
  for i = 1, 80 do
    local key = debug.getupvalue(fn, i)
    if not key then break end
    if key == name then debug.setupvalue(fn, i, value); return end
  end
  error("missing host upvalue " .. name)
end
local hookCount, tickCount, autoCount, driverCount, returned = 0, 0, 0, 0, 0
local hostGame = { sessionMenu = {}, update = function() tickCount = tickCount + 1 end }
upvalue(love.update, "Game", hostGame)
upvalue(love.update, "onlineClientModule", function() return nil end)
upvalue(love.update, "checkEmergencyQuit", function() end)
upvalue(love.update, "HostDisplay", { update = function() end })
upvalue(love.update, "SwitchDiagnostics", { maybeFlush = function() end })
upvalue(love.update, "NxDisplay", { sync = function() end })
upvalue(love.update, "LaunchOptions", { pollURI = function() end })
local Runtime = require("src.mods.Runtime")
local hooks = require("src.mods.Hooks").new()
hooks:wrap("core.update", function(next, game, dt)
  hookCount = hookCount + 1
  return next(game, dt)
end, 0, "pause-contract-fixture")
Runtime.install(Runtime.events, hooks)
love.update(1 / 60)
T.eq(hookCount, 0, "real love.update pauses before MOD core.update middleware")
T.eq(tickCount, 0, "real love.update does not tick paused game")
hostGame.sessionMenu = nil
love.update(1 / 60)
T.eq(hookCount, 1, "real MOD core.update wrapper resumes after close")
T.eq(tickCount, 1, "real host resumes game simulation once")
hostGame.sessionMenu = {}
upvalue(love.update, "autopilot", { update = function() autoCount = autoCount + 1 end })
upvalue(love.update, "driverCo", coroutine.create(function() driverCount = driverCount + 1; coroutine.yield() end))
love.update(1 / 60)
T.eq(autoCount, 0, "paused host also blocks scripted autopilot inputs")
T.eq(driverCount, 0, "paused host also blocks scripted frame driver")
upvalue(love.update, "pendingLauncherReturn", {})
upvalue(love.update, "returnToLauncher", function() returned = returned + 1 end)
love.update(1 / 60)
T.eq(returned, 1, "queued home return runs before pause guard")
Runtime.reset()
-- Native Android Back arrives through SDL/LÖVE as escape + acback; other
-- SDL builds use appback. Exercise the real main callbacks, not just Game.
upvalue(love.keypressed, "Game", g)
upvalue(love.keypressed, "Importer", nil)
love.event = love.event or {}
local quitCount, originalQuit = 0, love.event.quit
love.event.quit = function() quitCount = quitCount + 1 end
for _, event in ipairs({ {"escape", "acback"}, {"appback", "acback"}, {"unknown", "acback"}, {"escape", "escape"} }) do
  g:closeSessionMenu()
  Input:keypressed("right")
  love.keypressed(event[1], event[2], false)
  love.keyreleased(event[1], event[2])
  T.check(g.sessionMenu ~= nil, "real host Back opens paused menu: " .. event[1] .. "/" .. event[2])
  T.check(not Input:isDown("right"), "host Back clears held movement")
  local navigationKey = event[2] == "acback" and "acback" or "escape"
  T.check(not (g.sessionKeyCaptures or {})[navigationKey], "matching native key release clears navigation capture")
  love.keypressed(event[1], event[2], false)
  love.keyreleased(event[1], event[2])
  T.eq(g.sessionMenu, nil, "second host Back resumes without leaving application")
end
T.eq(quitCount, 0, "native Back routed through real main never requests app exit")
love.event.quit = originalQuit
T.finish()
