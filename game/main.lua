-- Native LÖVE2D port of Pokemon Red. A packaged build creates its private
-- game-data cache from a user-provided ROM on first boot.
--
-- The save editor (tools/save-editor/) ships inside every build and is
-- reachable two ways:
--   * standalone: POKEPORT_EDITOR=1 or `love . --editor`, its own window
--   * from the launcher: Edit on a save row, which suspends the launcher,
--     opens the editor on that slot's file, and restores the launcher when
--     the editor's Close button is pressed (openEditor / closeEditor below)

if POKEPORT_DISPLAY_COMPANION then
  return require("src.render.DesktopCompanion").install(
    POKEPORT_DISPLAY_COMPANION)
end

local editorMode = os.getenv("POKEPORT_EDITOR") == "1" or POKEPORT_EDITOR_MODE == true

local SwitchDiagnostics = require("src.debug.SwitchDiagnostics")
local LaunchOptions = require("src.core.LaunchOptions")
local NxDisplay = require("src.core.NxDisplay")
local PlatformHooks = require("src.core.PlatformHooks")
local HostDisplay = require("src.core.HostDisplay")
local GameViewport = require("src.render.GameViewport")

local function applySavedOrientation()
  local ok, savedOptions = pcall(function()
    return require("src.core.SaveData").loadOptions()
  end)
  if not ok or type(savedOptions) ~= "table" then savedOptions = {} end
  pcall(function()
    require("src.core.Orientation").applyOptions(savedOptions)
  end)
end

-- Global emergency quit: holding Start + Select for 5 seconds forcefully terminates LOVE.
local emergencyQuitTimer = 0
-- getJoysticks() allocates a fresh table every call; this runs once (twice)
-- per frame, so cache the list and refresh it once a second instead.  The 5s
-- hold requirement makes a 1s hotplug delay irrelevant.
local cachedJoysticks = nil
local joystickCacheAge = 1

local function checkEmergencyQuit(dt)
  local held = false
  joystickCacheAge = joystickCacheAge + (dt or 0.016)
  if love.joystick and love.joystick.getJoysticks then
    if not cachedJoysticks or joystickCacheAge >= 1 then
      cachedJoysticks = love.joystick.getJoysticks()
      joystickCacheAge = 0
    end
    for _, j in ipairs(cachedJoysticks) do
      if j:isGamepad() then
        local start = j:isGamepadDown("start")
        local selectBtn = j:isGamepadDown("back") or j:isGamepadDown("guide")
        if start and selectBtn then
          held = true
          break
        end
      else
        local bCount = j:getButtonCount()
        local s1 = (bCount >= 7 and j:isDown(7)) or (bCount >= 9 and j:isDown(9))
        local s2 = (bCount >= 8 and j:isDown(8)) or (bCount >= 10 and j:isDown(10))
        if s1 and s2 then
          held = true
          break
        end
      end
    end
  end

  if love.keyboard and love.keyboard.isDown then
    if (love.keyboard.isDown("escape") and love.keyboard.isDown("return"))
        or (love.keyboard.isDown("lalt") and love.keyboard.isDown("f4")) then
      held = true
    end
  end

  if held then
    emergencyQuitTimer = emergencyQuitTimer + (dt or 0.016)
    if emergencyQuitTimer >= 5.0 then
      print("[FORCE QUIT] Start + Select held for 5 seconds. Exiting forcefully.")
      pcall(function()
        if love.audio and love.audio.stop then love.audio.stop() end
        if love.window and love.window.close then love.window.close() end
      end)
      local exitFn = os["exit"]
      exitFn(0)
    end
  else
    emergencyQuitTimer = 0
  end
end

-- Lua errors: persist a redacted trace in the save dir and surface a hint.
do
  local defaultErrorHandler = love.errorhandler or love.errhand
  function love.errorhandler(msg)
    local ok, hint = pcall(SwitchDiagnostics.logLuaError, msg)
    if ok and hint and type(msg) == "string" then
      msg = msg .. "\n\n" .. hint
    end

    if love.window and love.window.isOpen and love.window.isOpen() and love.graphics and love.graphics.isActive() then
      -- Ensure no Canvas is left bound (errors during Display.present).
      pcall(function() love.graphics.setCanvas() end)
      pcall(function() love.graphics.origin() end)
      -- jp.69: a touch-only phone could not leave this screen (only a pad or
      -- keyboard quit it), and Android kept the stuck process alive, so tapping
      -- the app icon brought the same error back -- the app looked unable to
      -- start. Now a 2-second press, or sending the app to the background,
      -- ends the process so the next launch is a clean boot. Nothing is saved
      -- or removed here: saves and options.lua are left exactly as they are.
      local isAndroid = love.system and love.system.getOS and love.system.getOS() == "Android"
      local hint = isAndroid and "\n\n[がめんを 2びょう ながおしすると アプリを とじます。セーブデータは きえません]" or ""
      -- jp.72: on Android the screen uses NotoSansJP, so the quit hint is Japanese there too.
      local quitHint = isAndroid and "\n\n[START + SELECT を 5びょう おしつづけると きょうせい しゅうりょう します]" or "\n\n[Hold START + SELECT for 5s to Force Quit]"
      local fullMsg = tostring(msg) .. "\n\n" .. tostring(debug.traceback()) .. hint .. quitHint
      local pressAt = nil
      local shownAt = love.timer and love.timer.getTime() or 0
      local function shownFor() return (love.timer and love.timer.getTime() or 0) - shownAt end
      local errorFont = nil
      if isAndroid then
        local okFont, f = pcall(love.graphics.newFont, "assets/fonts/noto/NotoSansJP-Regular.ttf", 16)
        if okFont then errorFont = f end
      end
      local function leave()
        if isAndroid then
          local exitFn = os["exit"]
          exitFn(1)
        end
        return 1
      end
      return function()
        love.event.pump()
        for e, a in love.event.poll() do
          if e == "quit" or (e == "keypressed" and a == "escape") then
            return leave()
          elseif e == "gamepadpressed" and (a == "start" or a == "back") then
            return leave()
          elseif e == "touchpressed" or e == "mousepressed" then
            pressAt = love.timer and love.timer.getTime() or 0
          elseif e == "touchreleased" or e == "mousereleased" then
            pressAt = nil
          elseif isAndroid and shownFor() > 1.0 and ((e == "visible" and not a) or (e == "focus" and not a) or e == "lowmemory") then
            return leave()
          end
        end
        if pressAt and love.timer and love.timer.getTime() - pressAt >= 2.0 then
          return leave()
        end
        checkEmergencyQuit(0.016)
        love.graphics.origin()
        love.graphics.clear(0.10, 0.10, 0.12)
        love.graphics.setColor(1, 0.4, 0.4, 1)
        if errorFont then pcall(love.graphics.setFont, errorFont) end
        love.graphics.printf(fullMsg, 20, 20, love.graphics.getWidth() - 40)
        love.graphics.present()
        love.timer.sleep(0.016)
      end
    end

    if defaultErrorHandler then
      return defaultErrorHandler(msg)
    end
  end
  love.errhand = love.errorhandler
end

local Game, EditorApp, Importer, TouchEditor, Studio, Prelaunch, PersonalUpdate

-- #887: quit-to-launcher state, shared by love.load and love.quit (both need
-- it, so it is declared here rather than next to love.quit).
--   * launchedIntoGame -- a --game / POKEPORT_GAME shortcut booted this
--     session straight into a game, so there is no launcher behind it and a
--     window close must exit.  Restarting instead re-read the same shortcut
--     and came right back into the game, and the next close did it again:
--     the app could not be closed at all (macOS feels this worst, where the
--     red X, Cmd+Q and the Dock's Quit are all the same quit event).
--   * RELAUNCH_MARKER -- written in the save dir just before the #785
--     restart, so the fresh boot ignores any boot-straight-into-a-game
--     option exactly once and keeps #785's promise of landing in the
--     launcher, whatever put the game on screen this time.
local launchedIntoGame = false
local RELAUNCH_MARKER = "relaunch_to_launcher.txt"
local launchOptionsSuppressed = false

local onlineClient, onlineClientResolved
local function onlineClientModule()
  if onlineClientResolved then return onlineClient end
  onlineClientResolved = true
  local ok, mod = pcall(require, "src.online.Client")
  if ok and type(mod) == "table" and type(mod.update) == "function" then
    onlineClient = mod
  end
  return onlineClient
end

local autopilot -- optional scripted-input dev tool (tests/autopilot.lua)
local driverCo  -- optional frame-driver (POKEPORT_DRIVER=file.lua): a
                -- coroutine that receives `Game` and yields once per
                -- frame; used headless (xvfb) for scripted screenshots

-- --speed N / POKEPORT_SPEED=N: run the logic clock N times faster without
-- touching audio (src/core/GameSpeed.lua).  Overrides the saved option so a
-- bot or screenshot run is not at the mercy of the player's last choice.
local speedOverride = tonumber(os.getenv("POKEPORT_SPEED"))

-- POKEPORT_TOUCH=1 forces the mobile on-screen controls on and lets the
-- mouse stand in for a finger, so the overlay can be exercised on desktop
-- (see src/core/TouchControls.lua).
local mouseTouch = os.getenv("POKEPORT_TOUCH") == "1"

-- How many times to run a scripted act+step loop per rendered frame.  Only
-- scripted runs use this; interactive play fast-forwards through
-- Game.speedOverride / the GAME SPEED option instead.
local function scriptedIterations()
  if not (autopilot or driverCo) then return 1 end
  return math.max(1, math.floor(require("src.core.GameSpeed").clamp(speedOverride)))
end

-- ------------------------------------------------------------ save editor
-- The launcher instance parked while the editor is up, plus the version whose
-- cache the editor mounted (so closing can put the read path back).
local editorHost, editorVersion, editorWindow
local closeEditor  -- forward declaration: openEditor hands it to the editor

-- Drop CacheFs / Data / mod Runtime / Assets / LegacyCompat for one mounted
-- version session (save editor or game).  closeEditor and returnToLauncher
-- both go through SessionLifecycle so neither path forgets a singleton.
local SessionLifecycle = require("src.core.SessionLifecycle")

-- The editor's modules use flat names (require("Kit"), require("Party")), so
-- their directories have to be on the require path.  It must be
-- love.filesystem's path, not package.path: in a packaged build these files
-- live inside the .love archive, which the stock Lua searcher cannot open.
local function addEditorRequirePath()
  local fs = love.filesystem
  if not (fs.setRequirePath and fs.getRequirePath) then
    -- very old LOVE: a source checkout still resolves through package.path
    package.path = fs.getSource() .. "/tools/save-editor/?.lua;"
                .. fs.getSource() .. "/tools/save-editor/panels/?.lua;"
                .. package.path
    return
  end
  local current = fs.getRequirePath()
  if current:find("tools/save%-editor") then return end
  fs.setRequirePath("tools/save-editor/?.lua;tools/save-editor/panels/?.lua;"
    .. current)
end

-- Desktop only: the launcher window (1024x768) is tighter than the editor's
-- design size, so grow it while editing and put it back on Close.  Never
-- shrinks, never touches a fullscreen or mobile window.
local function resizeForEditor()
  if not (love.window and love.window.getMode and love.window.setMode) then return end
  local osName = love.system.getOS()
  if osName ~= "OS X" and osName ~= "Windows" and osName ~= "Linux" then return end
  local w, h, flags = love.window.getMode()
  if flags.fullscreen then return end
  local dw, dh = love.window.getDesktopDimensions()
  local wantW = math.max(w, math.min(1360, math.floor((dw or w) * 0.92)))
  local wantH = math.max(h, math.min(860, math.floor((dh or h) * 0.88)))
  if wantW <= w and wantH <= h then return end
  editorWindow = { w = w, h = h }
  love.window.setMode(wantW, wantH, flags)
end

local function restoreWindow()
  if not editorWindow then return end
  local _, _, flags = love.window.getMode()
  love.window.setMode(editorWindow.w, editorWindow.h, flags)
  editorWindow = nil
end

-- Open the editor on a launcher save row.  The version's cache has to be
-- mounted before the editor's Data:load runs, or a Blue save would be edited
-- against Red's species/item tables.
local function openEditor(version, slotId)
  local function refuse(text)
    if not Importer then return end
    Importer.saveNotice = Importer.saveNotice or {}
    Importer.saveNotice[version] = { ok = false, text = text }
  end
  local SaveData = require("src.core.SaveData")
  local path = SaveData.slotDiskPath(version, slotId)
  if not path then
    refuse("Could not resolve that save slot on disk.")
    return
  end
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version)
  require("src.import.CacheFs").mountVersion(version)
  editorVersion = version
  editorHost = Importer
  -- Drop launcher pad/FlexLove so the save editor owns input (NX shim +
  -- virtual cursor + system hand cursor). Desktop park is a light no-op.
  if Importer and Importer.prepareOverlayHandoff then
    Importer:prepareOverlayHandoff()
  end
  Importer = nil
  editorMode = true
  resizeForEditor()
  addEditorRequirePath()
  local okReq, appOrErr = pcall(require, "App")
  if not okReq then
    editorMode = false
    SessionLifecycle.endEditorSession({ version = version, app = nil })
    restoreWindow()
    Importer = editorHost
    editorHost = nil
    editorVersion = nil
    if Importer and Importer.resumeAfterOverlay then
      Importer:resumeAfterOverlay()
    end
    refuse("Could not open the save editor (" .. tostring(appOrErr) .. ").")
    return
  end
  EditorApp = appOrErr
  local okLoad, loadErr = pcall(EditorApp.load, path, {
    version = version, slotId = slotId, embedded = true,
    onClose = function() closeEditor() end,
  })
  if not okLoad then
    editorMode = false
    if EditorApp.unload then pcall(EditorApp.unload) end
    EditorApp = nil
    SessionLifecycle.endEditorSession({ version = version, app = nil })
    restoreWindow()
    Importer = editorHost
    editorHost = nil
    editorVersion = nil
    if Importer and Importer.resumeAfterOverlay then
      Importer:resumeAfterOverlay()
    end
    refuse("Could not open the save editor (" .. tostring(loadErr) .. ").")
  end
end

-- Back to the launcher.  Everything the editor mounted or cached has to come
-- back out: the version overlay (CacheFs) and the generated modules require
-- cached behind it (Data), or pressing Play on the OTHER game would boot it
-- with this one's data.  Also reset Runtime / Assets / LegacyCompat so the
-- next Edit or Play does not inherit the editor's dead mod loader.
function closeEditor()
  local version = editorVersion
  local app = EditorApp
  editorMode = false
  EditorApp = nil
  SessionLifecycle.endEditorSession({ version = version, app = app })
  editorVersion = nil
  restoreWindow()
  Importer = editorHost
  editorHost = nil
  if Importer and Importer.resumeAfterOverlay then
    Importer:resumeAfterOverlay()
  end
  if Importer and version and Importer.savesChanged then
    Importer:savesChanged(version)
  end
end

-- ------------------------------------------------------------ touch controls editor
-- Suspends the launcher while the player drags on-screen buttons / toggles
-- the overlay off (#327).  No ROM cache needed -- options.lua only.
local touchEditorHost, touchEditorGame
local closeTouchControlsEditor  -- forward declaration

-- The same editor overlays either the launcher or a paused game menu. Keep
-- the game stack intact, and merge only the editor-owned options on return.
local function prepareGameEditor()
  if Importer or not Game then return end
  local touch = require("src.core.TouchControls")
  local host = { game=Game, active=touch.active, sessionMenuActive=touch.sessionMenuActive }
  if Game.clearSessionInput then Game:clearSessionInput() end
  return host
end

local function resumeGameEditor(host)
  if not host or host.game ~= Game then return end
  local options = Game.save and Game.save.options
  if options then
    local saved = require("src.core.SaveData").loadOptions()
    options.touchControls = saved.touchControls
    options.jpTouchAreas = saved.jpTouchAreas
    local touch = require("src.core.TouchControls")
    touch.active, touch.sessionMenuActive = host.active, host.sessionMenuActive
    touch:applyOptions(options)
    touch:ensureImages()
  end
  if Game.clearSessionInput then Game:clearSessionInput() end
end

-- `version` determines the option block used by TouchControlsEditor.persist.
local function openTouchControlsEditor(version, mode)
  touchEditorHost = Importer
  touchEditorGame = prepareGameEditor()
  if Importer and Importer.prepareOverlayHandoff then
    Importer:prepareOverlayHandoff()
  end
  Importer = nil
  TouchEditor = require(mode == "areas" and "src.ui.JapaneseTouchAreaEditor" or "src.ui.TouchControlsEditor")
  TouchEditor.load({
    version = version,
    onClose = function() closeTouchControlsEditor() end,
  })
end

function closeTouchControlsEditor()
  -- Editor.close already unloads before invoking its onClose callback.
  if TouchEditor and TouchEditor.onClose and TouchEditor.unload then TouchEditor.unload() end
  TouchEditor = nil
  Importer = touchEditorHost
  touchEditorHost = nil
  if Importer and Importer.resumeAfterOverlay then
    Importer:resumeAfterOverlay()
  end
  resumeGameEditor(touchEditorGame)
  touchEditorGame = nil
end

-- ------------------------------------------------------------ skin studio
local studioHost, studioGame
local closeSkinStudio
local bootGame

local function openSkinStudio(version, skinId)
  local SkinStudio = require("src.ui.SkinStudio")
  if not SkinStudio.available_desktop() then return end
  studioHost = Importer
  studioGame = prepareGameEditor()
  if Importer and Importer.prepareOverlayHandoff then
    Importer:prepareOverlayHandoff()
  end
  Importer = nil
  Studio = SkinStudio
  Studio.load({
    version = version,
    skinId = skinId,
    onClose = function() closeSkinStudio() end,
    onPlay = function(v)
      local existingGame = studioGame ~= nil
      closeSkinStudio()
      if existingGame then return end
      Importer = nil
      bootGame(v or version)
    end,
  })
end

function closeSkinStudio()
  if Studio and Studio.unload then Studio.unload() end
  Studio = nil
  Importer = studioHost
  studioHost = nil
  if Importer and Importer.resumeAfterOverlay then
    Importer:resumeAfterOverlay()
  end
  resumeGameEditor(studioGame)
  studioGame = nil
end

local function makeLauncher(launcherOpts)
  local RomImporter = require("src.import.RomImporter")
  local forceImport = os.getenv("POKEPORT_FORCE_IMPORT") == "1"
  return RomImporter.new(function(version, cartId, opts)
    Importer = nil
    bootGame(version, cartId, opts)
  end, {
    launcher = true,
    forceImport = forceImport,
    initialTab = launcherOpts and launcherOpts.initialTab or nil,
    onEditSave = openEditor,
    onEditTouchControls = openTouchControlsEditor,
    onEditTouchAreas = function(version) openTouchControlsEditor(version, "areas") end,
    -- Skin Studio owns a touch-first layout as well as the desktop workspace.
    -- Keep the compatibility predicate so external hosts using it still work.
    onOpenSkinStudio = require("src.ui.SkinStudio").available_desktop()
      and openSkinStudio or nil,
  })
end

local function returnToLauncher(opts)
  if not Game then return end

  if require("src.core.RequireGuard").repair() then
    print("boot: restored love.filesystem searcher (see #2001)")
  end

  local GameVersion = require("src.core.GameVersion")
  local currentVersion = GameVersion.get()
  SessionLifecycle.endGameSession(Game)
  Game = nil
  pcall(function() require("src.online.Trade").hostIsLive = nil end)
  local syncEngine = package.loaded["src.sync.SyncEngine"]
  if type(syncEngine) == "table" and type(syncEngine._shared) == "table" then
    pcall(syncEngine._shared.protectPlaythrough, syncEngine._shared, nil, nil)
  end
  autopilot = nil
  driverCo = nil
  -- Leave the cart's scope behind: the launcher's own settings and slots are
  -- the base game's, not the cart's.  The speed ladder is cart state too, so
  -- a 1x/2x cart must not pin the launcher or the next game.
  local SaveData = require("src.core.SaveData")
  local cartId = SaveData.getCart()
  SaveData.setCart(nil)
  require("src.core.GameSpeed").setAllowed(nil)

  SessionLifecycle.endMountedSession(currentVersion)

  -- Slot lists are resolved once per process.  Invalidate only the game
  -- (and cart, if any) we just left so the new launcher can migrate a flat
  -- in-game SAVE into a visible slot -- nothing else is rewritten.
  SaveData.refreshSlotResolution(currentVersion)
  if cartId then SaveData.refreshSlotResolution("cart_" .. cartId) end

  applySavedOrientation()

  local preload = require("src.mods.LauncherMods").translationStrings()
  if preload then require("src.core.Strings").load({ strings = preload }) end

  if love.window and love.window.setTitle then
    local Version = require("src.core.Version")
    love.window.setTitle(Version.title())
  end

  Importer = makeLauncher({ initialTab = opts and opts.tab or nil })
  -- Finger that confirmed EXIT GAME is often still down over Import Save.
  if Importer.ignoreReturningPointer then
    Importer:ignoreReturningPointer()
  end
end

local pendingLauncherReturn

function bootGame(version, cartId, opts)
  opts = opts or {}
  if require("src.core.RequireGuard").repair() then
    print("boot: restored love.filesystem searcher (see #2001)")
  end
  pcall(function()
    require("src.online.Trade").hostIsLive = function() return true end
  end)
  -- The launcher hands us the chosen game (Red / Blue / Yellow / Gold);
  -- scripted and headless runs fall back to POKEPORT_VERSION, then Red.
  -- Set the active version and overlay its extracted cache BEFORE anything
  -- requires generated data, so data/generated + assets/generated resolve
  -- to that version's files.
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version or os.getenv("POKEPORT_VERSION") or "red")
  local CacheFs = require("src.import.CacheFs")
  -- Keep CacheFs.prefix aligned for any CacheFs.read fallback during Data:load
  -- (Blue/Yellow/Gold caches live under blue/ / yellow/ / gold/).
  CacheFs.prefix = GameVersion.cachePrefix()
  CacheFs.mountVersion(GameVersion.get())
  local cartHash, cartSpeeds, cartOptions
  if cartId then
    local ok, cart, hash = pcall(function()
      return require("src.carts.CartStore").get(cartId)
    end)
    if ok and cart then
      cartHash, cartSpeeds, cartOptions = hash, cart.speeds, cart.options
    else
      cartId = nil
    end
  end
  local SaveData = require("src.core.SaveData")
  SaveData.setCart(cartId, cartHash)
  -- The author's settings land in the cart's own scope the first time only;
  -- after that the player owns them.
  if cartOptions then SaveData.seedCartOptions(cartOptions) end
  -- A cart may narrow or pin the speed ladder; nil restores the full one.
  require("src.core.GameSpeed").setAllowed(cartSpeeds)
  if cartId then SaveData.adoptCartSeal(cartId) end
  -- NX: always write nx-asset-probe.log so Yellow/Blue art failures are
  -- diagnosable from the SD without enabling switch-debug.txt.
  pcall(function()
    require("src.debug.SwitchDiagnostics").probeAssets(GameVersion.get())
  end)
  if love.window and love.window.setTitle then
    local Version = require("src.core.Version")
    love.window.setTitle(Version.title())
  end
  -- Gen 2: Gen 1 Game:load cannot consume a Gen 2 cache -- different generated
  -- tables, save shape and screen registry -- so Gold and Silver boot their
  -- own service owner, which mounts src/world/gen2 (walk / warps /
  -- connections) and the Gen 2 screens instead of src/core/Game.lua's Gen 1
  -- wiring.
  local arena = opts.arena
  local loadOpts = { arena = arena, cartId = cartId, onExit = opts.onExit,
    jpContinue = opts.jpContinue, jpNewGame = opts.jpNewGame }
  if GameVersion.generation() == 3 then
    Game = require("src.core.Game3").new()
    Game.returnToLauncher = function(o) pendingLauncherReturn = o or {} end
    Game:load(loadOpts)
  elseif GameVersion.generation() == 2 then
    Game = require("src.core.Game2").new()
    Game.returnToLauncher = function(o) pendingLauncherReturn = o or {} end
    Game:load(loadOpts)
  else
    -- Gen1 Game is a module singleton.  Always re-require after in-process
    -- EXIT GAME so a prior session cannot leave a table whose rawget(load)
    -- is nil (release Android: bootGame then dies with load-a-nil-value).
    -- rawget: type(mod.load) can lie via __index and skip a rebuild.
    package.loaded["src.core.Game"] = nil
    local gameMod = require("src.core.Game")
    if type(rawget(gameMod, "load")) ~= "function" then
      error("src.core.Game missing load after reload")
    end
    Game = gameMod
    Game.returnToLauncher = function(o) pendingLauncherReturn = o or {} end
    Game:load(loadOpts)
    if Game.data and Game.data.constants and Game.data.constants.language == "ja" then
      Game.openTouchControlsEditor = function() openTouchControlsEditor(GameVersion.get()) end
      Game.openTouchAreasEditor = function() openTouchControlsEditor(GameVersion.get(), "areas") end
      Game.openSkinStudio = function() openSkinStudio(GameVersion.get()) end
    end
    if os.getenv("POKEPORT_AUTOPILOT") then
      autopilot = require("tests.autopilot")
    end
  end
  local driverPath = os.getenv("POKEPORT_DRIVER")
  if driverPath then
    local fn = assert(loadfile(driverPath))()
    driverCo = coroutine.create(fn)
  end
  -- After the two above are known: a scripted run drives the multiplier
  -- from love.update's loop, so the in-engine one must stay at 1 or the
  -- two would compound (10x10 = 100 steps per observation).
  Game.speedOverride = (autopilot or driverCo) and 1 or speedOverride
end

local function showLauncher(version)
  LaunchOptions.pendingTab = version
  if not Importer then
    Importer = makeLauncher({ initialTab = version })
  end
end

local function startLaunchRequest(request)
  if type(request) ~= "table" then return false end

  local version = request.game
  if request.launcher or not version then
    if Game then
      returnToLauncher({ tab = version })
    else
      showLauncher(version)
    end
    return true
  end

  local RomImporter = require("src.import.RomImporter")
  if Game then returnToLauncher() end
  Importer = nil
  if Prelaunch then return true end

  local cartId
  if request.cartSpecified then
    local ok, cart = pcall(function()
      return require("src.carts.CartStore").get(request.cart)
    end)
    if not ok or type(cart) ~= "table" or cart.base ~= version then
      showLauncher(version)
      return true
    end
    cartId = request.cart
  end

  if not RomImporter.isReady(version) then
    showLauncher(version)
    return true
  end

  local function bootShortcut()
    if request.slot then LaunchOptions.selectSlot(version, request.slot) end
    launchedIntoGame = true
    bootGame(version, cartId)
  end

  Prelaunch = require("src.core.Prelaunch").new({
    version = version,
    tasks = request.tasks or {},
    done = function(outcome)
      if outcome == "restart" then return end
      Prelaunch = nil
      if outcome == "launcher" then
        showLauncher(version)
        return
      end
      bootShortcut()
    end,
  })
  if not Prelaunch then bootShortcut() end
  return true
end

function love.load(args)
  -- Before anything can shell out (update check, mod index, ROM picker),
  -- claim one hidden console on Windows so those children inherit it instead
  -- of each flashing their own cmd.exe window (#606).  No-op elsewhere.
  require("src.core.HostShell").hideHostConsole()

  require("src.core.RequireGuard").capture()

  -- Hang gen1tls on love.system before mods boot.  Android already has tls*
  -- from JNI; this is the desktop half.  No DLL / no FFI is fine -- ws://
  -- rooms still work, wss:// just won't.
  pcall(function() require("src.net.Gen1Tls").install() end)

  -- NX fused mounts are unreliable for the blue|yellow cache overlay: wrap
  -- the love loaders once so every generated-asset read falls back to the
  -- versioned save-dir copy.  Never installed on desktop/Android/iOS.
  if require("src.core.Platform").isNX() then
    require("src.core.NxAssetOverlay").install()
  end

  -- Self-updater boot shell: a fused build may mount and chainload a newer
  -- downloaded payload here.  True means it took over, so we must stop.  A
  -- dev / source checkout no-ops (see src/update/Boot.lua).
  local Boot = require("src.update.Boot")
  if Boot.run(args) then return end

  local packOK, packResult, packError = pcall(function()
    return require("src.mods.JapaneseStarterPack").install()
  end)
  if not packOK or packResult == nil then
    print("Japanese starter mods: " .. tostring(packError or packResult))
  end

  local savePath
  for i, a in ipairs(args or {}) do
    if a == "--editor" then
      editorMode = true
    elseif a == "--developer" then
      _G.POKEPORT_DEV_MODE = true
    elseif a == "--save" and args[i + 1] and args[i + 1] ~= "" then
      savePath = args[i + 1]
    elseif a == "--speed" and tonumber(args[i + 1]) then
      speedOverride = tonumber(args[i + 1])
    end
  end
  love.graphics.setDefaultFilter("nearest", "nearest")
  -- NX: handheld 720p / docked 1080p. Runs for every boot path (launcher,
  -- editor, scripted); no-op on desktop/mobile.
  NxDisplay.sync()

  -- Apply the persisted Android orientation lock (#592) before the launcher
  -- shows: SDL created the window with no orientation hint, so without this
  -- the launcher would rotate freely until options are applied at boot.
  -- No-op on desktop / iOS / when options.lua does not exist yet.
  applySavedOrientation()

  -- Standalone editor.  A bare `--editor` run has no launcher behind it, so
  -- Close quits; --save points it at a specific file, otherwise it opens the
  -- default save path for POKEPORT_VERSION (Red unless overridden), whose
  -- cache has to be mounted before the editor's Data:load.
  if editorMode then
    local version = os.getenv("POKEPORT_VERSION") or "red"
    require("src.core.GameVersion").set(version)
    require("src.import.CacheFs").mountVersion(version)
    addEditorRequirePath()
    EditorApp = require("App")
    EditorApp.load(savePath, { version = version })
    return
  end

  local RomImporter = require("src.import.RomImporter")
  local resolvedLaunch = LaunchOptions.resolveRequest(arg, args)
  local forceImport = os.getenv("POKEPORT_FORCE_IMPORT") == "1"
  local importPath = os.getenv("POKEPORT_IMPORT_ROM")
  -- Scripted / headless runs pick their game from POKEPORT_VERSION, then
  -- POKEPORT_GAME / --game= (LaunchOptions), then Red.  Drivers for Gold
  -- must honor POKEPORT_GAME=gold the same way a desktop shortcut does.
  local scriptedVersion = os.getenv("POKEPORT_VERSION")
    or resolvedLaunch.game
    or "red"
  local ready = RomImporter.isReady(scriptedVersion)
  -- Scripted / headless runs have to reach the game with no human pressing
  -- Play: an autopilot, a frame driver, an import-only build step, or an
  -- explicit ROM path all bypass the interactive launcher and keep today's
  -- import-then-boot (or boot-straight-in) behavior.
  local scripted = os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER")
    or os.getenv("POKEPORT_IMPORT_ONLY") == "1" or importPath ~= nil

  local scriptedOpts = nil
  local specPath = os.getenv("POKEPORT_ARENA_SPEC")
  if specPath and os.getenv("POKEPORT_DRIVER") then
    local chunk, chunkErr = loadfile(specPath)
    if not chunk then error("POKEPORT_ARENA_SPEC: " .. tostring(chunkErr)) end
    local spec = chunk()
    if type(spec) ~= "table" then
      error("POKEPORT_ARENA_SPEC must return an ArenaSpec table")
    end
    scriptedOpts = { arena = spec }
  end

  if scripted then
    if forceImport or not ready then
      -- The importer detects the dropped/loaded ROM's version by SHA-1 and
      -- passes it to onComplete; boot that version.
      Importer = RomImporter.new(function(version)
        if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
          love.event.quit()
          return
        end
        Importer = nil
        bootGame(version or scriptedVersion, nil, scriptedOpts)
      end)
      if importPath then Importer:startPath(importPath) end
      return
    end
    bootGame(scriptedVersion, nil, scriptedOpts)
    return
  end

  -- The launcher draws before any game boots, so the mod loader has not run
  -- and Strings has no catalog.  Routing the launcher's text through Strings
  -- (#767) only pays off if something fills that catalog this early, and no
  -- restart could: the ordering is the same on every launch.  Read the
  -- enabled mods' string catalogs -- data only, no entry chunk -- so a
  -- translation reaches the launcher too.  The active game's loader replaces
  -- this with the real merged catalog once a version boots.
  do
    local preload = require("src.mods.LauncherMods").translationStrings()
    if preload then require("src.core.Strings").load({ strings = preload }) end
  end

  -- LAUNCH OPTIONS: skip the launcher and boot a game directly.
  --   --game red|blue|yellow|gold  (or POKEPORT_GAME / POKEPORT_LAUNCH)
  --   --slot <id>             optional; picks the save slot to load
  --   --launcher              force the launcher even if a game is set
  -- This is what a desktop shortcut, a Steam entry, or a frontend like
  -- EmulationStation needs: one click into the game the player wants, with no
  -- menu in between.  A game that is not imported falls through to the
  -- launcher on its tab rather than booting into nothing.
  -- A window close that restarted us into the launcher (#785) leaves the
  -- marker behind: consume it and stay on the launcher, or the shortcut below
  -- would boot the same game again and that close would restart again,
  -- forever (#887).  Consumed on read, so the very next launch is normal.
  local relaunched = love.filesystem.getInfo(RELAUNCH_MARKER) ~= nil
  if relaunched then
    launchOptionsSuppressed = true
    pcall(love.filesystem.remove, RELAUNCH_MARKER)
  end

  if not relaunched and resolvedLaunch.game and not resolvedLaunch.launcher
      and startLaunchRequest(resolvedLaunch) then
    return
  end
  if not relaunched and resolvedLaunch.launcher and resolvedLaunch.game then
    LaunchOptions.pendingTab = resolvedLaunch.game
  end

  -- Interactive: the launcher owns game selection. Red, Blue, Yellow, and Gold are
  -- each live: a column shows Play when that game's ROM is already imported,
  -- or Choose ROM / drag-drop when it is not.  Any dropped .gb/.gbc is routed
  -- by its SHA-1 (GameVersion.forSha1); pressing Play boots that game (Gold
  -- goes to its own service owner, src/core/Game2.lua -- docs/gold-phase1.md).
  -- Edit on a save row opens the bundled editor on that slot (openEditor).
  Importer = makeLauncher()
  -- Personal line: one-shot GitHub release check behind a launcher
  -- banner (src/jp/PersonalUpdate.lua).  Fully optional -- any failure
  -- just means no banner -- so boot must never depend on it.
  do
    local okPU, modPU = pcall(require, "src.jp.PersonalUpdate")
    if okPU and type(modPU) == "table" then
      PersonalUpdate = modPU
      pcall(modPU.start)
    end
  end
  local request = require('src.import.JapaneseHome').startupRequest(
    require('src.core.SaveData').loadOptions(), {
      version=Importer.tab, ready=Importer.ready[Importer.tab],
      relaunched=relaunched, launcher=resolvedLaunch.launcher, forceImport=forceImport,
    })
  if request then Importer:play(Importer.tab, request) end
end

-- Host overlays bypass Game:update (and MOD/script simulation) entirely.
-- Service only the active game's real-time audio so chip music keeps its
-- streaming queue filled while settings, file pickers or touch layout are open.
local function updatePausedGameAudio(game, dt)
  if game and type(game.updateAudio) == "function" then game:updateAudio(dt) end
end

function love.update(dt)
  checkEmergencyQuit(dt)
  if PersonalUpdate then PersonalUpdate.tick() end
  HostDisplay.update(dt)
  SwitchDiagnostics.maybeFlush(false)
  -- NX only (no-op elsewhere): follow dock/undock without waiting for SDL.
  NxDisplay.sync()
  if editorMode then return EditorApp.update(dt) end
  if TouchEditor then
    updatePausedGameAudio(touchEditorGame and touchEditorGame.game, dt)
    return TouchEditor.update(dt)
  end
  if Studio then
    updatePausedGameAudio(studioGame and studioGame.game, dt)
    return Studio.update(dt)
  end
  local launchURI = LaunchOptions.pollURI()
  if launchURI then love.handlers.intent_uri(launchURI) end
  if Prelaunch then return Prelaunch:update(dt) end
  local client = onlineClientModule()
  if client then pcall(client.update, dt) end
  if pendingLauncherReturn then
    local opts = pendingLauncherReturn
    pendingLauncherReturn = nil
    returnToLauncher(opts)
    return
  end
  -- Document pickers must finish while the session (including MODs) is paused,
  -- and before the ROM importer's independent native-picker polling.
  if require("src.import.SettingsFiles").update(dt) then
    if not Importer then updatePausedGameAudio(Game, dt) end
    return
  end
  if Importer then return Importer:update(dt) end
  if not Game then return end
  -- jp.91-preview2: rebuild canvas-backed bakes after the GPU dropped them
  require("src.render.ContextGuard").update(Game)
  -- Pause before MOD core.update wrappers and scripted drivers can act.
  -- pendingLauncherReturn is processed above so a paused game can exit.
  if Game.sessionMenu then updatePausedGameAudio(Game, dt); return end

  -- Scripted runs (autopilot / POKEPORT_DRIVER) observe and act exactly
  -- once per Game:update, so they must keep a 1:1 relationship with the
  -- logic step.  Fast-forwarding them by scaling the step inside
  -- Game:update would run N steps per observation: a held direction walks
  -- through all N, the player slides past the waypoint, and the script
  -- re-plans from an overshot cell.  So iterate the whole act+step loop
  -- instead -- same script, just more of it per rendered frame.
  local iterations = scriptedIterations()

  if autopilot then
    for _ = 1, iterations do
      autopilot.update()
      Game:update(1 / 60) -- deterministic stepping for the autopilot
    end
    return
  end
  if driverCo then
    for _ = 1, iterations do
      local ok, err = coroutine.resume(driverCo, Game)
      if not ok then
        print("driver error: " .. tostring(err))
        love.event.quit(1)
        return
      end
      if coroutine.status(driverCo) == "dead" then
        love.event.quit()
        return
      end
      Game:update(1 / 60)
    end
    return
  end
  -- Mods may wrap or veto the per-frame simulation step (pause it, react
  -- to external platform state, etc.) -- see docs/modding.md's core.update
  -- entry. Vanilla behavior (used when no mod claims the hook) is just
  -- Game:update(dt), unconditionally, exactly as before this hook existed.
  PlatformHooks.update(Game, dt)
end

function love.draw()
  if editorMode then
    GameViewport.reset()
    HostDisplay.beginFrame("editor", EditorApp)
    local result = EditorApp.draw()
    HostDisplay.endFrame("editor", EditorApp)
    return result
  end
  if TouchEditor then
    GameViewport.reset()
    HostDisplay.beginFrame("touch_editor", TouchEditor)
    local result = TouchEditor.draw()
    HostDisplay.endFrame("touch_editor", TouchEditor)
    return result
  end
  if Studio then
    HostDisplay.beginFrame("skin_studio", Studio)
    local result = Studio.draw()
    HostDisplay.endFrame("skin_studio", Studio)
    return result
  end
  if Prelaunch then
    GameViewport.reset()
    return Prelaunch:draw()
  end
  if Importer then
    GameViewport.reset()
    HostDisplay.beginFrame("launcher", Importer)
    local result = Importer:draw()
    HostDisplay.endFrame("launcher", Importer)
    if PersonalUpdate then PersonalUpdate.draw() end
    return result
  end
  if not Game then
    GameViewport.reset()
    return
  end

  HostDisplay.beginFrame("game", Game)
  Game:draw()
  -- frame capture requested by a driver
  if Game.capturePath then
    local path = Game.capturePath
    Game.capturePath = nil
    love.graphics.captureScreenshot(function(imagedata)
      local fd = imagedata:encode("png")
      local f = io.open(path, "wb")
      if f then
        f:write(fd:getString())
        f:close()
      end
    end)
  end
  HostDisplay.endFrame("game", Game)
end

function love.keypressed(key, scancode, isrepeat)
  -- Android LÖVE reports system Back as escape/acback, while other SDL
  -- builds use appback. Normalize the physical navigation scancode too.
  if scancode == "acback" or key == "appback" then key = "acback" end
  if key == "escape" or key == "acback" or key == "backspace" then
    require("src.import.SettingsFiles").cancel()
  end
  if editorMode then return EditorApp.keypressed(key) end
  if TouchEditor then return TouchEditor.keypressed(key == "acback" and "escape" or key) end
  if Studio then return Studio.keypressed(key == "acback" and "escape" or key) end
  if Prelaunch then return Prelaunch:cancel() end
  if Importer then return Importer:keypressed(key) end
  if not Game then return end
  Game:keypressed(key, isrepeat)
end

function love.keyreleased(key, scancode)
  if scancode == "acback" or key == "appback" then key = "acback" end
  if editorMode or TouchEditor or Studio then return end
  if Importer then return end
  if not Game then return end
  Game:keyreleased(key)
end

function love.gamepadpressed(joystick, button)
  if button == "b" or button == "back" or button == "guide" then
    require("src.import.SettingsFiles").cancel()
  end
  SwitchDiagnostics.onJoystickEvent("gamepadpressed", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.gamepadpressed then
      return EditorApp.gamepadpressed(joystick, button)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.gamepadpressed then
      return TouchEditor.gamepadpressed(joystick, button)
    end
    return
  end
  if Studio then return Studio.gamepadpressed(joystick, button) end
  if Prelaunch then return Prelaunch:cancel() end
  if Importer then return Importer:gamepadpressed(joystick, button) end
  if not Game then return end
  Game:gamepadpressed(joystick, button)
end

function love.gamepadreleased(joystick, button)
  SwitchDiagnostics.onJoystickEvent("gamepadreleased", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.gamepadreleased then
      return EditorApp.gamepadreleased(joystick, button)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.gamepadreleased then
      return TouchEditor.gamepadreleased(joystick, button)
    end
    return
  end
  if Studio then return Studio.gamepadreleased(joystick, button) end
  if Importer then return Importer:gamepadreleased(joystick, button) end
  if not Game then return end
  Game:gamepadreleased(joystick, button)
end

function love.gamepadaxis(joystick, axis, value)
  SwitchDiagnostics.onJoystickEvent("gamepadaxis", joystick, axis, { value = value })
  if editorMode then
    if EditorApp and EditorApp.gamepadaxis then
      return EditorApp.gamepadaxis(joystick, axis, value)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.gamepadaxis then
      return TouchEditor.gamepadaxis(joystick, axis, value)
    end
    return
  end
  if Studio then return Studio.gamepadaxis(joystick, axis, value) end
  if Importer then return Importer:gamepadaxis(joystick, axis, value) end
  if not Game then return end
  Game:gamepadaxis(joystick, axis, value)
end

function love.joystickpressed(joystick, button)
  SwitchDiagnostics.onJoystickEvent("joystickpressed", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.joystickpressed then
      return EditorApp.joystickpressed(joystick, button)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickpressed then
      return TouchEditor.joystickpressed(joystick, button)
    end
    return
  end
  if Studio then return Studio.joystickpressed(joystick, button) end
  if Importer then return Importer:joystickpressed(joystick, button) end
  if not Game then return end
  Game:joystickpressed(joystick, button)
end

function love.joystickreleased(joystick, button)
  SwitchDiagnostics.onJoystickEvent("joystickreleased", joystick, button)
  if editorMode then
    if EditorApp and EditorApp.joystickreleased then
      return EditorApp.joystickreleased(joystick, button)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickreleased then
      return TouchEditor.joystickreleased(joystick, button)
    end
    return
  end
  if Studio then return Studio.joystickreleased(joystick, button) end
  if Importer then return Importer:joystickreleased(joystick, button) end
  if not Game then return end
  Game:joystickreleased(joystick, button)
end

function love.joystickaxis(joystick, axis, value)
  SwitchDiagnostics.onJoystickEvent("joystickaxis", joystick, axis, { value = value })
  if editorMode then
    if EditorApp and EditorApp.joystickaxis then
      return EditorApp.joystickaxis(joystick, axis, value)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickaxis then
      return TouchEditor.joystickaxis(joystick, axis, value)
    end
    return
  end
  if Studio then return Studio.joystickaxis(joystick, axis, value) end
  if Importer then return Importer:joystickaxis(joystick, axis, value) end
  if not Game then return end
  Game:joystickaxis(joystick, axis, value)
end

function love.joystickhat(joystick, hat, direction)
  SwitchDiagnostics.onJoystickEvent("joystickhat", joystick, hat, { direction = direction })
  if editorMode then
    if EditorApp and EditorApp.joystickhat then
      return EditorApp.joystickhat(joystick, hat, direction)
    end
    return
  end
  if TouchEditor then
    if TouchEditor.joystickhat then
      return TouchEditor.joystickhat(joystick, hat, direction)
    end
    return
  end
  if Studio then return Studio.joystickhat(joystick, hat, direction) end
  if Importer then return Importer:joystickhat(joystick, hat, direction) end
  if not Game then return end
  Game:joystickhat(joystick, hat, direction)
end

function love.joystickadded(joystick)
  SwitchDiagnostics.onJoystickEvent("joystickadded", joystick)
  if editorMode or TouchEditor or Studio then return end
  if Importer then return end
  if not Game then return end
  Game:joystickadded(joystick)
end

function love.joystickremoved(joystick)
  SwitchDiagnostics.onJoystickEvent("joystickremoved", joystick)
  if editorMode or TouchEditor or Studio then return end
  if Importer then return end
  if not Game then return end
  Game:joystickremoved(joystick)
end

-- jp.91-preview2: a window re-creation (fold, rotation, resume) can empty every
-- Canvas; ContextGuard checks a sentinel on the next update and rebuilds.
function love.resize(w, h)
  require("src.render.ContextGuard").request("resize")
end

function love.displayrotated()
  require("src.render.ContextGuard").request("rotated")
end

-- f is true on focus gained, false on focus lost (e.g. alt-tab). A held
-- direction's key-up can be delivered to the OS instead of the game while
-- unfocused, so reset input on either transition rather than trust it.
function love.focus(f)
  if f then require("src.render.ContextGuard").request("focus") end
  if editorMode then return end
  if TouchEditor then if TouchEditor.focus then TouchEditor.focus(f) end;return end
  if Studio then
    if Studio.focus then Studio.focus(f) end
    return
  end
  local settingsFiles = require("src.import.SettingsFiles")
  local settingsPick = settingsFiles.pending()
  settingsFiles.focus(f)
  if f then settingsFiles.update(0) end
  if Importer then
    require("src.core.Input"):reset()
    if not settingsPick and Importer.focus then Importer:focus(f) end
    return
  end
  if not Game then return end
  Game:focus(f)
end

-- v is true when the window becomes visible again, false on minimize.
function love.visible(v)
  if v then require("src.render.ContextGuard").request("visible") end
  if editorMode then return end
  if TouchEditor then if TouchEditor.visible then TouchEditor.visible(v) end;return end
  require("src.import.SettingsFiles").focus(v)
  if Studio then
    if Studio.visible then Studio.visible(v) end
    return
  end
  if Importer then
    require("src.core.Input"):reset()
    return
  end
  if not Game then return end
  Game:visible(v)
end

function love.lowmemory()
  if editorMode or TouchEditor or Studio or Importer then return end
  if Game then Game:onResume() end
end

love.handlers = love.handlers or {}

function love.handlers.audiosuspend()
  local ChipAudio = package.loaded["src.core.ChipAudio"]
  if ChipAudio then pcall(ChipAudio.setSuspended, true) end
  local Sound = package.loaded["src.core.Sound"]
  if Sound then pcall(Sound.onDeviceReset) end
  local Game3Audio = package.loaded["src.core.game3.audio"]
  if Game3Audio then pcall(Game3Audio.setSuspended, true) end
end

function love.handlers.audioreset()
  local ChipAudio = package.loaded["src.core.ChipAudio"]
  if ChipAudio then
    pcall(ChipAudio.setSuspended, false)
    pcall(ChipAudio.rebuildPlayback)
  end
  local Music = package.loaded["src.core.Music"]
  if Music then pcall(Music.onDeviceReset) end
  local Sound = package.loaded["src.core.Sound"]
  if Sound then pcall(Sound.onDeviceReset) end
  local Game3Audio = package.loaded["src.core.game3.audio"]
  if Game3Audio then
    pcall(Game3Audio.setSuspended, false)
    pcall(Game3Audio.rebuildPlayback)
  end
end

function love.handlers.intent_game(version)
  local request = LaunchOptions.fromGame(version)
  if request then startLaunchRequest(request) end
end

function love.handlers.intent_uri(uri)
  local request = LaunchOptions.parseURI(uri)
  if request then
    startLaunchRequest(request)
  elseif LaunchOptions.isLaunchURI(uri) then
    startLaunchRequest({})
  end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  if editorMode then
    -- iOS synthesizes mousepressed for the primary touch; forwarding here
    -- would double-fire.  Android / NX need the explicit touch → click path
    -- (love-nx does not synthesize mouse for the editor the way desktop does).
    if love.system.getOS() == "iOS" then return end
    if EditorApp and EditorApp.mousepressed then
      return EditorApp.mousepressed(x, y, 1)
    end
    return
  end
  if TouchEditor then
    -- iOS synthesizes mousepressed for the primary touch (same as the
    -- launcher); Android drives the editor through love.touch directly.
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchpressed(id, x, y)
  end
  if Studio then return Studio.touchpressed(id, x, y) end
  if Prelaunch then return Prelaunch:cancel() end
  if PersonalUpdate and Importer and PersonalUpdate.press(x, y) then return end
  if Importer then
    -- Both mobiles: FlexLove scroll needs the real touch stream. Clicks are
    -- polled inside the view; the istouch filter on mousepressed still drops
    -- Android's synthesized mouse twin so Import cannot double-fire (#553).
    return Importer:touchpressed(id, x, y, dx, dy, pressure)
  end
  if not Game then return end
  Game:touchpressed(id, x, y, dx, dy, pressure)
end

function love.touchmoved(id, x, y, dx, dy, pressure)
  if editorMode then return end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchmoved(id, x, y)
  end
  if Studio then return Studio.touchmoved(id, x, y) end
  if Importer then
    return Importer:touchmoved(id, x, y, dx, dy, pressure)
  end
  if not Game then return end
  Game:touchmoved(id, x, y, dx, dy, pressure)
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  -- The Android surface tags an aborted stream with negative pressure while
  -- still releasing SDL/LÖVE's finger. Never pass it to a UI's release action.
  if pressure and pressure < 0 then
    if TouchEditor and TouchEditor.touchcancelled then return TouchEditor.touchcancelled(id) end
    if Importer then
      if Importer.touchcancelled then return Importer:touchcancelled(id) end
      return
    end
    if not editorMode and not Studio and Game then
      -- jp.69: Game2/Game3 lacked this method, so an Android ACTION_CANCEL in
      -- Gold/Silver/Crystal crashed the app. Fall back to the input reset.
      if Game.touchcancelled then return Game:touchcancelled(id) end
      if Game.clearSessionInput then return Game:clearSessionInput() end
      return
    end
    return
  end
  if editorMode then return end
  if TouchEditor then
    if love.system.getOS() == "iOS" then return end
    return TouchEditor.touchreleased(id, x, y)
  end
  if Studio then return Studio.touchreleased(id, x, y) end
  if Importer then
    return Importer:touchreleased(id, x, y, dx, dy, pressure)
  end
  if not Game then return end
  Game:touchreleased(id, x, y, dx, dy, pressure)
end

function love.wheelmoved(x, y)
  if editorMode then
    if EditorApp.wheelmoved then return EditorApp.wheelmoved(x, y) end
    return
  end
  if TouchEditor then return end
  if Studio then return Studio.wheelmoved(x, y) end
  if Importer then return end
  if not Game then return end
  Game:wheelmoved(x, y)
end

-- #781: Linux X11 multi-monitor with the primary display away from desktop
-- (0,0): SDL's polled mouse state can come back in desktop-virtual
-- coordinates while the event stream stays window-relative, which strands
-- every polled consumer (launcher Kit rising-edge clicks, the pad-cursor
-- motion yield, PadCursor) on coordinates no hit test can match.  Sanitize
-- the poll once here: remember the last window-relative event coordinates
-- and substitute them whenever the polled value falls outside the window.
-- Linux only -- macOS / Windows / mobile keep the stock function, and the
-- NX launcher shim still composes because it captures whatever
-- love.mouse.getPosition is at bridge time (_ensureNxPointerBridge).
local eventMouseX, eventMouseY
if love.system and love.system.getOS() == "Linux"
    and love.mouse and love.mouse.getPosition then
  local polledGetPosition = love.mouse.getPosition
  love.mouse.getPosition = function()
    local x, y = polledGetPosition()
    local w, h = love.graphics.getDimensions()
    if x < 0 or y < 0 or x > w or y > h then
      if eventMouseX then return eventMouseX, eventMouseY end
      return math.max(0, math.min(x, w)), math.max(0, math.min(y, h))
    end
    return x, y
  end
end

function love.mousepressed(x, y, button, istouch)
  if not istouch then eventMouseX, eventMouseY = x, y end
  if TouchEditor then
    -- Android primary touch already arrived via love.touchpressed; a second
    -- mouse path would double-fire Done / begin a second drag.
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousepressed(x, y, button)
  end
  if Studio then
    -- Mobile LÖVE sends both a touch event and an `istouch` mouse twin.
    -- Studio consumes the real finger stream above, so discard the twin.
    if istouch and (love.system.getOS() == "Android" or love.system.getOS() == "iOS") then return end
    return Studio.mousepressed(x, y, button)
  end
  if Prelaunch then
    if istouch then return end
    return Prelaunch:cancel()
  end
  if PersonalUpdate and Importer and not istouch
      and PersonalUpdate.press(x, y) then return end
  if Importer then
    -- love.touchpressed already forwards the primary touch into FlexLove for
    -- scroll. LÖVE ALSO synthesizes a mouse press for that same touch; if both
    -- reached a press handler, one tap ran every launcher button twice and
    -- stacked two SAF pickers (#553). Clicks are polled inside FlexLove from
    -- love.touch / mouse.isDown, so dropping the synthesized istouch press is
    -- safe. A real mouse (DeX, Chromebook, USB) still reaches mousepressed.
    if istouch and (love.system.getOS() == "Android"
        or love.system.getOS() == "iOS") then return end
    return Importer:mousepressed(x, y, button)
  end
  if editorMode and EditorApp.mousepressed then
    -- Same Android double-fire guard: touchpressed already clicked for the
    -- save editor; a synthesized mouse press must not fire again.
    if istouch and love.system.getOS() == "Android" then return end
    return EditorApp.mousepressed(x, y, button)
  end
  if mouseTouch then
    -- the mouse is standing in for a finger: the touch path owns it, and
    -- feeding the same press back in as a mouse pointer would double it
    if Game and button == 1 then Game:touchpressed("mouse", x, y) end
    return
  end
  -- #807: a real mouse reaches gameplay as a pointer event for mods; Game
  -- drops synthesized istouch twins so a mobile touch that already arrived
  -- through love.touchpressed cannot fire twice
  if Game then Game:mousepressed(x, y, button, istouch) end
end

function love.mousereleased(x, y, button, istouch)
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousereleased(x, y, button)
  end
  if Studio then
    if istouch and (love.system.getOS() == "Android" or love.system.getOS() == "iOS") then return end
    return Studio.mousereleased(x, y, button)
  end
  if Importer then return end
  if editorMode and EditorApp.mousereleased then
    return EditorApp.mousereleased(x, y, button)
  end
  if mouseTouch then
    if Game and button == 1 then Game:touchreleased("mouse", x, y) end
    return
  end
  if Game then Game:mousereleased(x, y, button, istouch) end
end

function love.mousemoved(x, y, dx, dy, istouch)
  if not istouch then eventMouseX, eventMouseY = x, y end
  if TouchEditor then
    if love.system.getOS() == "Android" then return end
    return TouchEditor.mousemoved(x, y)
  end
  if Studio then
    if istouch and (love.system.getOS() == "Android" or love.system.getOS() == "iOS") then return end
    return Studio.mousemoved(x, y)
  end
  if editorMode or Importer then return end
  if mouseTouch then
    if Game and love.mouse.isDown(1) then Game:touchmoved("mouse", x, y) end
    return
  end
  if Game then Game:mousemoved(x, y, dx, dy, istouch) end
end

function love.textinput(text)
  if TouchEditor then return end
  if Studio then return Studio.textinput(text) end
  if Importer then return Importer:textinput(text) end
  if editorMode and EditorApp.textinput then
    return EditorApp.textinput(text)
  end
end

-- #785: set once love.quit has routed a window close into HostShell.restart,
-- so the follow-up quit event the restart itself raises (quit("restart") on
-- desktop; AppImage and Android relaunch the process instead, #575) falls
-- through to the normal shutdown below instead of restarting forever.
local quitToLauncher = false

function love.quit()
  if editorMode and EditorApp.quit then
    -- true blocks the quit (unsaved-changes prompt).  A quit that proceeds
    -- must fall through to the worker shutdowns below instead of returning:
    -- the bundled editor opens from a live launcher whose update-check and
    -- fetch-pool workers are still parked in Channel:demand(), and returning
    -- here skipped their "quit" push, so the process outlived the closed
    -- window and kept the install folder locked on Windows (#727).
    if EditorApp.quit() then return true end
  end
  -- Closing the window of a running game returns to the launcher instead of
  -- exiting the app, so testing a mod does not need a relaunch every time
  -- (#785).  Game is only non-nil once bootGame ran; Importer non-nil means
  -- the launcher (or its import) owns the window and its close still quits.
  -- Scripted and headless runs (autopilot, frame driver, import-only, ROM
  -- path import) keep the plain exit so they terminate as before.  Nothing
  -- is saved here on purpose: a window close never wrote the save, and the
  -- restart path must be no worse than that, not quietly better.
  local scripted = os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER")
    or os.getenv("POKEPORT_IMPORT_ONLY") == "1" or os.getenv("POKEPORT_IMPORT_ROM")
  -- #887: a shortcut session (--game / POKEPORT_GAME) has no launcher to go
  -- back to and the restart would re-read the shortcut, so it exits instead.
  --
  -- A platform launcher that owns "return to launcher" itself (see
  -- docs/modding.md's core.quit_to_launcher entry) may veto returning to
  -- this Lua launcher via that hook. Vanilla behavior (used when no mod
  -- claims the hook) is exactly the condition below.
  --
  -- Android and iOS both tear down LOVE in-process rather than
  -- love.event.quit("restart"): Android's vendored love.cpp PHYSFS-crashes
  -- on a second init (#575), and iOS's love.cpp forces DONE_RESTART for
  -- every quit while warning that leftover threads make that unreliable.
  -- SessionLifecycle workers (ChipAudio / Fetch / Check) make that warning
  -- real -- endProcess joins them, then the native restart still blows up.
  local osName = love.system and love.system.getOS and love.system.getOS()
  local inProcessReturn = (osName == "Android" or osName == "iOS")
  local wouldReturnToLauncher = PlatformHooks.quitToLauncher(function()
    return Game and not Importer and not quitToLauncher and not scripted
      and (inProcessReturn or not launchedIntoGame)
  end)
  if wouldReturnToLauncher then
    if inProcessReturn then
      returnToLauncher()
      return true -- abort this quit; stay in the same LOVE run
    end
    quitToLauncher = true
    -- Tell the fresh boot to ignore any boot-straight-into-a-game option this
    -- once, so the restart really does land in the launcher (#887).  A failed
    -- write only costs that suppression, so it must never block the restart.
    pcall(love.filesystem.write, RELAUNCH_MARKER, "1")
    require("src.core.HostShell").restart()
    return true -- abort this quit; the restart lands back in the launcher
  end
  pcall(function()
    require("src.core.DiscordPresence").shutdown()
  end)
  SessionLifecycle.endProcess()
end

function love.filedropped(file)
  if require("src.import.SettingsFiles").filedropped(file) then return end
  local filename = file and file.getFilename and file:getFilename()
  if LaunchOptions.isLaunchURI(filename) then
    local request = LaunchOptions.parseURI(filename)
    if launchOptionsSuppressed then return end
    startLaunchRequest(request or {})
    return
  end
  if editorMode and EditorApp and EditorApp.filedropped then
    return EditorApp.filedropped(file)
  end
  if Studio then return Studio.filedropped(file) end
  if Importer then Importer:filedropped(file) end
end

local function pacingEnabled()
  if os.getenv("POKEPORT_AUTOPILOT") then return false end
  if os.getenv("POKEPORT_DRIVER") then return false end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  return true
end

-- Shane #1830 idle render governor (POKEPORT_IDLE_*): drop presentation rate
-- on static in-game screens; game logic and audio stay at full speed.
local function idlePresentationCap(idleFor)
  local after = tonumber(os.getenv("POKEPORT_IDLE_AFTER"))
  local fps = tonumber(os.getenv("POKEPORT_IDLE_FPS"))
  if not after or after <= 0 or not fps or fps <= 0 then return nil end
  if idleFor < after then return nil end
  if Importer or Prelaunch or editorMode or not Game then return nil end
  return fps
end

function love.run()
  if love.load then love.load(love.arg.parseGameArguments(arg), arg) end

  -- don't let love.load's cost land in the first frame's dt
  if love.timer then love.timer.step() end

  local FrameCap = require("src.core.FrameCap")
  _G.POKEPORT_LOOP_PANEL_SYNC = true
  FrameCap.bootPanelSync()
  local RefreshRate = require("src.core.RefreshRate")
  local FixedStep = require("src.core.FixedStep")
  local VSync = require("src.core.VSync")
  local PresentSync = require("src.core.PresentSync")
  local paced = pacingEnabled()
  -- The deadline the next present() should not beat.  Carried forward one
  -- budget per frame so pacing stays even instead of drifting with the
  -- per-frame sleep-granularity jitter.
  local nextFrame = love.timer and love.timer.getTime() or 0
  local dt = 0
  local idleFor = 0
  local SLEEP_FLOOR = 0.001
  -- Sleep until deadline with one or two kernel waits, not 1 ms polling.
  local function sleepUntilFrame(deadline)
    while true do
      local remaining = deadline - love.timer.getTime()
      if remaining <= SLEEP_FLOOR then break end
      if remaining > 0.004 then
        love.timer.sleep(remaining - 0.002)
      else
        love.timer.sleep(remaining)
      end
    end
  end
  local WAKE = {
    keypressed = true, keyreleased = true, textinput = true,
    mousepressed = true, mousereleased = true, mousemoved = true,
    wheelmoved = true, touchpressed = true, touchreleased = true,
    touchmoved = true, joystickpressed = true, joystickreleased = true,
    joystickhat = true, gamepadpressed = true, gamepadreleased = true,
    joystickadded = true, joystickremoved = true, filedropped = true,
    directorydropped = true, focus = true, visible = true, resize = true,
  }

  return function()
    -- process events
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        if name == "quit" then
          if not love.quit or not love.quit() then
            -- Android keeps the process and its task alive after LOVE's own
            -- teardown, so the relaunched task re-enters an activity whose
            -- native main already returned; end the process outright once the
            -- love.quit hook has run (#339)
            if love.system and love.system.getOS() == "Android" then
              os.exit(a or 0)
            end
            return a or 0
          end
        end
        if WAKE[name] then
          idleFor = 0
        elseif name == "joystickaxis" and type(c) == "number" and math.abs(c) > 0.5 then
          idleFor = 0
        end
        if name == "focus" and a then
          PresentSync.onDisplayChange()
        elseif name == "resize" then
          PresentSync.onDisplayChange()
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end

    -- update dt
    if love.timer then dt = love.timer.step() end
    idleFor = idleFor + dt
    RefreshRate.sample(dt)

    checkEmergencyQuit(dt)

    -- call update and draw
    if love.update then love.update(dt) end

    local visible = not (love.window and love.window.isVisible)
      or love.window.isVisible()
    local focused = not (love.window and love.window.hasFocus)
      or love.window.hasFocus()
    local cap = FrameCap.current
    if not visible then
      cap = 10
    elseif Importer and (not focused or idleFor > 30) then
      cap = 15
    else
      local idleCap = idlePresentationCap(idleFor)
      if idleCap then cap = idleCap end
    end
    if cap == FrameCap.DISPLAY and not VSync.isOn() then
      cap = FrameCap.DEFAULT
    elseif cap == FrameCap.DISPLAY and PresentSync.needsSoftwareCap() then
      -- Fallback cascade: probe failed / wait abandoned / sync non-
      -- deterministic → FrameCap is the live pacing path on every OS.
      -- (During an active probe we intentionally leave DISPLAY uncapped so
      -- calibration is not grading our own limiter.)
      cap = FrameCap.DEFAULT
    end

    if visible and love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then love.draw() end
      PresentSync.waitBeforePresent()
      love.graphics.present()
      PresentSync.notePresent()
    end

    PresentSync.applyFixedStepPeriod()

    if love.timer then
      if paced and cap ~= FrameCap.DISPLAY and not PresentSync.hardwarePacesCap(cap) then
        -- Sleep out the remainder of the frame budget, measured from the
        -- carried deadline.  When vsync already gates at or above the cap,
        -- hardwarePacesCap skips this entirely.  Otherwise one kernel sleep
        -- covers the bulk; only the last couple ms re-check for overshoot.
        local budget = 1 / cap
        nextFrame = nextFrame + budget
        local now = love.timer.getTime()
        -- A stall (alt-tab, a GC pause, a blocked import) can leave the
        -- deadline more than a full budget in the past; re-anchor to now so
        -- we pace the next frame rather than burst uncapped to catch up.
        if now - nextFrame > budget then
          nextFrame = now
        end
        sleepUntilFrame(nextFrame)
      else
        love.timer.sleep(0.001)
      end
    end
  end
end
