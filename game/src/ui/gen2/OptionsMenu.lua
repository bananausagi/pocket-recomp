-- Gold's OPTION screen (engine/menus/options_menu.asm _Option).
--
-- Layout is transcribed from the ASM: one full-screen textbox, StringOptions
-- placed at (2,2) as label / "        :" pairs, each option's value printed at
-- (11, labelRow + 1) -- except FRAME, whose number goes at (16,15) after the
-- literal "TYPE".  The cursor is a ▶ in column 1 at row 2 + index * 2.
--
-- Up/down move between rows, left/right change the value under the cursor, and
-- START or B leaves.  BACK is a row like any other that simply exits.
--
-- Values are stored on the save's options table by name (see
-- src/core/gen2/Save.lua DEFAULT_OPTIONS) rather than as the packed wOptions
-- byte, so a save stays readable and reordering an enum cannot silently
-- repoint a setting.
--
-- The row list a screen opens with runs through the ui.options.rows hook, the
-- same name and the same (game, rows) payload the Gen 1 screen uses
-- (src/ui/OptionsMenu.lua), so one mod source can add or drop a row on both
-- generations.

local Chrome = require("src.ui.gen2.Chrome")
local Logger = require("src.core.Logger")
local Marquee = require("src.ui.Marquee")
local Palette = require("src.render.Palette")
local Performance = require("src.core.Performance")
local Runtime = require("src.mods.Runtime")
local Save = require("src.core.gen2.Save")
local Strings = require("src.core.Strings")

local OptionsMenu = {}
OptionsMenu.__index = OptionsMenu
OptionsMenu.isOpaque = true

-- Music.setFilterLevel's ladder.
local FILTERS = {
  Strings.source("OFF"), Strings.source("1X"), Strings.source("2X"),
  Strings.source("3X"),
}

-- Values returned by shared helper modules are dynamic at this callsite, so
-- declare their finite labels explicitly for tools/modkit.py's catalog
-- harvester.  Player palette names and shader filenames are deliberately not
-- in this list: those are user content and stay verbatim.
local FINITE_VALUE_SOURCES = {
  Strings.source("AUTO"), Strings.source("HIGH"),
  Strings.source("BALANCED"), Strings.source("LOW"),
  Strings.source("NORMAL"), Strings.source("FIT"),
  Strings.source("OUT%d"), Strings.source("IN%d"),
  Strings.source("WATER"), Strings.source("TREES"), Strings.source("FADE "),
  Strings.source("GEN 2"), Strings.source("DMG"), Strings.source("CLASSIC"),
  Strings.source("GREEN"), Strings.source("LIME"), Strings.source("OLIVE"),
  Strings.source("AMBER"), Strings.source("ORANGE"), Strings.source("RED"),
  Strings.source("ROSE"), Strings.source("MAGENTA"),
  Strings.source("PURPLE"), Strings.source("INDIGO"), Strings.source("BLUE"),
  Strings.source("CYAN"), Strings.source("TEAL"), Strings.source("MINT"),
  Strings.source("SAND"), Strings.source("BROWN"), Strings.source("SILVER"),
  Strings.source("MONO"),
  Strings.source("PALETTE"), Strings.source("FULL"),
  Strings.source("WINDOWED"), Strings.source("CENTER"),
  Strings.source("UPPER"), Strings.source("TOP"), Strings.source("SKIN"),
  Strings.source("LIGHT"), Strings.source("STRONG"),
  Strings.source("ADAPTIVE"), Strings.source("UNAVAILABLE"),
  Strings.source("DISPLAY"), Strings.source("DISPLAY (%dHZ)"),
}

local function volLabel(v)
  v = v or 7
  return v == 0 and Strings("OFF") or tostring(v)
end

local function stepVolume(v, delta)
  return math.max(0, math.min(7, (v or 7) + delta))
end

local function dropClassic(options)
  local GbcPalette = require("src.render.GbcPalette")
  if GbcPalette.mode ~= "classic" then return end
  local target = (options.palette and options.palette ~= "")
    and GbcPalette.CUSTOM_MODE or "gbc"
  options.color = target
  GbcPalette.setMode(target)
end

local function colorPickerOpts(game)
  local GbcPalette = require("src.render.GbcPalette")
  local options = game.options
  dropClassic(options)
  local labels = GbcPalette.MODE_LABELS or {}
  local modes = {}
  for i, id in ipairs(GbcPalette.MODES) do
    modes[i] = { labels[id] or id:upper(), id }
  end
  return {
    palette = Palette,
    get = function() return options.palette or "" end,
    set = function(v)
      options.palette = v
      local target = (v ~= "") and GbcPalette.CUSTOM_MODE or "gbc"
      options.color = target
      GbcPalette.setMode(target)
      GbcPalette.setCustomRamp(v ~= "" and Palette.ramp(v) or nil)
      if game.persistOptions then pcall(game.persistOptions, game) end
    end,
    modes = modes,
    getMode = function() return options.color or "gbc" end,
    setMode = function(v)
      options.color = v
      GbcPalette.setMode(v)
      if game.persistOptions then pcall(game.persistOptions, game) end
    end,
  }
end

-- jp.70: true for the Japanese carts (crystal_jp and the JP Gold/Silver).
local function isJapanese()
  local ok, GV = pcall(require, "src.core.GameVersion")
  if not ok or type(GV) ~= "table" then return false end
  local okI, info = pcall(function() return GV.info(GV.get()) end)
  return okI and type(info) == "table" and info.language == "ja"
end

local ORIENT_JA = {
  auto = "じどう", portrait = "たて", landscape = "よこ",
  reverseLandscape = "ぎゃくむきの よこ",
}

-- jp.70: one of the Gen 1 JP top-screen rows (JapaneseConvenienceSettings),
-- shown only on the Japanese carts.  Steps write the shared option key and
-- re-apply the viewport at once.
local function topScreenRow(id)
  local function desc()
    local ok, S = pcall(require, "src.ui.JapaneseConvenienceSettings")
    if not ok then return nil end
    for _, row in ipairs(S.rows or {}) do
      if row.id == id then return row, S end
    end
  end
  return {
    id = id, label = id, port = true, jpOnly = true,
    value = function(g)
      local row, S = desc()
      if not row then return "?" end
      return S.value(row, g.options, not isJapanese())
    end,
    step = function(g, dir)
      local row, S = desc()
      if not row then return true end
      S.step(row, g.options, dir)
      if g.applyOptions then g:applyOptions() end
      return true
    end,
  }
end

-- jp.75: a plain on/off row for one boolean key (absent counts as off).
local function jp75OnOff(id, label)
  return { id = id, label = label, port = true, jpOnly = true,
    value = function(g)
      local on = g.options and g.options[id] == true
      if isJapanese() then return on and "オン" or "オフ" end
      return on and "ON " or "OFF"
    end,
    step = function(g)
      g.options[id] = g.options[id] ~= true
      return true
    end }
end

-- Each row: the label, the option key it edits, and the cycle of values with
-- the exact strings the cart prints (trailing spaces included -- they are what
-- blank the longer previous value, e.g. "MID " over "SLOW").
-- Labels and cart-original display strings are wrapped in Strings.source so
-- the catalog generator harvests them even though this table is built once
-- at require time, before any mod's Strings.load has a catalog to answer
-- from (src/core/Strings.lua's own note on this).  The lookup itself happens
-- live, in drawPanel, through plain Strings(...) calls.
local ROWS = {
  {
    label = Strings.source("TEXT SPEED"), key = "textSpeed",
    values = { "FAST", "MID", "SLOW" },
    display = {
      FAST = Strings.source("FAST"), MID = Strings.source("MID "),
      SLOW = Strings.source("SLOW"),
    },
  },
  {
    label = Strings.source("BATTLE SCENE"), key = "battleScene",
    values = { true, false },
    display = {
      [true] = Strings.source("ON "), [false] = Strings.source("OFF"),
    },
  },
  {
    label = Strings.source("BATTLE STYLE"), key = "battleStyle",
    values = { "SHIFT", "SET" },
    display = {
      SHIFT = Strings.source("SHIFT"), SET = Strings.source("SET  "),
    },
  },
  {
    label = Strings.source("SOUND"), key = "sound",
    values = { "MONO", "STEREO" },
    display = {
      MONO = Strings.source("MONO  "), STEREO = Strings.source("STEREO"),
    },
  },
  {
    label = Strings.source("PRINT"), key = "print",
    values = { "LIGHTEST", "LIGHTER", "NORMAL", "DARKER", "DARKEST" },
    display = {
      LIGHTEST = Strings.source("LIGHTEST"), LIGHTER = Strings.source("LIGHTER "),
      NORMAL = Strings.source("NORMAL  "), DARKER = Strings.source("DARKER  "),
      DARKEST = Strings.source("DARKEST "),
    },
  },
  {
    label = Strings.source("MENU ACCOUNT"), key = "menuAccount",
    values = { false, true },
    display = {
      [false] = Strings.source("OFF"), [true] = Strings.source("ON "),
    },
  },
  -- FRAME is the textbox border style, 1-8, and prints its number after the
  -- word TYPE rather than in the shared value column.
  { label = Strings.source("FRAME"), key = "frame", frame = true },
  -- Everything from here down is the port's, not the cart's.  They are the
  -- same settings the Gen 1 OPTION screen carries and they drive the same
  -- shared modules, so a player who learns them in Red knows them here.  The
  -- cart's screen has no room for them, which is why this one scrolls.
  --
  -- The two volume rows clamp at the ends rather than wrapping, the way
  -- pokered's text-speed cursor does, so holding left reaches OFF and stays.
  { id = "controls", label = Strings.source("CONTROLS"), port = true,
    activate = function(game)
      require("src.ui.Screens").push(game, "BindingsMenu")
    end },
  { label = Strings.source("MUSIC VOL"), key = "musicVol", port = true,
    cycle = function(options, delta)
      options.musicVol = stepVolume(options.musicVol, delta)
      require("src.core.Music").setVolumeLevel(options.musicVol)
    end,
    text = function(options) return volLabel(options.musicVol) end },
  { label = Strings.source("SFX VOL"), key = "sfxVol", port = true,
    cycle = function(options, delta)
      options.sfxVol = stepVolume(options.sfxVol, delta)
      require("src.core.Sound").setVolumeLevel(options.sfxVol)
    end,
    text = function(options) return volLabel(options.sfxVol) end },
  -- Each filter step keeps 40% of the previous step's treble, so 2X and 3X
  -- are the 1X low-pass applied twice and three times over.
  { label = Strings.source("MUSIC FILTER"), key = "musicFilter", port = true,
    cycle = function(options, delta)
      options.musicFilter = ((options.musicFilter or 0) + delta) % #FILTERS
      require("src.core.Music").setFilterLevel(options.musicFilter)
    end,
    text = function(options)
      return Strings(FILTERS[(options.musicFilter or 0) + 1])
    end },
  -- Heads the port's display group, same spot src/ui/OptionsMenu.lua's own
  -- PERFORMANCE row occupies relative to ZOOM/VOID FILL/TILT/SHADER FX below
  -- (the extras this tier scales).  Gen 1 row shape (`value`/`step`, not this
  -- file's own `text`/`cycle`) works here unmodified: OptionsMenu:cycle
  -- answers `row.step` first, and drawPanel already reads a function
  -- `row.value` -- both written for exactly this kind of shared mod row.
  { id = "performance", label = Strings.source("PERFORMANCE"), port = true,
    value = function(g)
      return Strings(Performance.label(g.options and g.options.performance))
    end,
    step = function(g, dir)
      local o = g.options
      o.performance = Performance.cycle(o.performance, dir)
      g:applyOptions()
      return true
    end },
  { label = Strings.source("GAME SPEED"), key = "speed", port = true,
    cycle = function(options, delta)
      local GameSpeed = require("src.core.GameSpeed")
      options.speed = GameSpeed.cycle(options.speed, delta)
    end,
    text = function(options)
      local speed = tonumber(options.speed) or 1
      if speed == 1 then return Strings("NORMAL") end
      return Strings("%dX", speed)
    end },
  { label = Strings.source("ZOOM"), key = "zoom", port = true,
    cycle = function(options, delta, game)
      local Zoom = require("src.render.Zoom")
      local scale = Zoom.windowFitScale()
      if game and game.world and game.world.fitScale then
        scale = game.world:fitScale()
      end
      Zoom.nudgeOptions(options, delta, scale)
    end,
    text = function(options)
      local offset = math.floor(tonumber(options.zoom) or 0)
      if offset == 0 then return Strings("FIT") end
      return offset < 0 and Strings("OUT%d", -offset)
        or Strings("IN%d", offset)
    end },
  -- VOID FILL: FADE is each map's own border block with the dissolve across
  -- a boundary; WATER / TREES force one outdoor block; BLACK is a flat void.
  -- #1418.  Same key the Gen 1 OPTION screen uses, different ladder (FADE
  -- is Gold's default because that is already what the maps call for).
  { label = Strings.source("VOID FILL"), key = "voidFill", port = true,
    cycle = function(options, delta)
      local BorderFill = require("src.world.gen2.BorderFill")
      BorderFill.setVoidFill(options.voidFill or "fade")
      options.voidFill = BorderFill.cycle(delta)
    end,
    text = function(options)
      return Strings(require("src.world.gen2.BorderFill").voidFillLabel(options.voidFill))
    end },
  { label = Strings.source("TILT"), key = "tilt", port = true,
    cycle = function(options, delta)
      local Tilt = require("src.render.Tilt")
      -- Four levels (OFF, 15, 35, 50); left steps back through them.
      local caps = Performance.caps(options.performance)
      local shown = options.tilt or 0
      if not caps.tilt then shown = 0 end
      local level = (shown + delta) % 4
      options.tilt = level
      Tilt.setLevel(level)
      if level > 0 and not caps.tilt then
        options.performance = "high"
      end
    end,
    text = function(options)
      local Tilt = require("src.render.Tilt")
      local saved = options.tilt or 0
      local live = Tilt.level or 0
      if not Performance.caps(options.performance).tilt then
        return Strings(Tilt.levelLabel(0))
      end
      if live ~= saved then
        return Strings(Tilt.levelLabel(live))
      end
      return Strings(Tilt.levelLabel(saved))
    end },
  { label = Strings.source("COLOR"), key = "color", port = true,
    text = function(options)
      local palette = options.palette
      local name = Palette.label(palette)
      if name then
        -- m: is the engine's finite monochrome ladder; p: is a named user
        -- palette pack and its filename is user content.
        return type(palette) == "string" and palette:sub(1, 2) == "m:"
          and Strings(name) or name
      end
      return Strings(require("src.render.GbcPalette").modeLabel(options.color or "gbc"))
    end,
    activate = function(game)
      require("src.ui.Screens").push(game, "PaletteScreen", colorPickerOpts(game))
    end },
  -- SHADER FX reaches Gen 2 too, not just Gen 1. Same "activate" shape as
  -- CONTROLS/TOUCH LAYOUT below (a pushed screen, not a `cycle` ladder) --
  -- ShaderFXScreen is the shared list screen both generations push, `id`
  -- matching the Gen 1 row's so a mod filtering "shaderfx" on Red also
  -- reaches Gold.
  { id = "uiLetterbox", label = Strings.source("UI LETTERBOX"), port = true,
    cycle = function(options, delta)
      local Letterbox = require("src.render.Letterbox")
      options.uiLetterbox = Letterbox.cycle(options.uiLetterbox, delta)
      Letterbox.setMode(options.uiLetterbox)
    end,
    text = function(options)
      local Letterbox = require("src.render.Letterbox")
      return Strings(Letterbox.label(options.uiLetterbox))
    end },
  { id = "shaderfx", label = Strings.source("SHADER FX"), port = true,
    text = function(options)
      local ShaderFX = require("src.render.ShaderFX")
      local entry = ShaderFX.activeEntry("main")
      if not entry then return Strings("OFF") end
      return (entry.name:gsub("%.slangp$", "")):upper()
    end,
    activate = function(game)
      require("src.ui.Screens").push(game, "ShaderFXScreen", "main")
    end },
  -- Dual-shader secondary slot, same shared ShaderFXScreen as the row
  -- above, opened on "secondary" instead -- see src/ui/OptionsMenu.lua's
  -- mirror of this row for the full rationale.
  { id = "shaderfx2", label = Strings.source("SHADER FX 2"), port = true,
    text = function(options)
      local ShaderFX = require("src.render.ShaderFX")
      local entry = ShaderFX.activeEntry("secondary")
      if not entry then return Strings("OFF") end
      return (entry.name:gsub("%.slangp$", "")):upper()
    end,
    activate = function(game)
      require("src.ui.Screens").push(game, "ShaderFXScreen", "secondary")
    end },
  { label = Strings.source("VIDEO MODE"), key = "videoMode", port = true,
    cycle = function(options, delta)
      local VideoMode = require("src.core.VideoMode")
      options.videoMode = VideoMode.cycle(options.videoMode, delta)
      VideoMode.apply(options.videoMode)
    end,
    text = function(options)
      local VideoMode = require("src.core.VideoMode")
      return VideoMode.normalize(options.videoMode) == "borderless"
        and Strings("FULL") or Strings("WINDOWED")
    end },
  { label = Strings.source("SCREEN POS"), key = "screenPos", port = true,
    cycle = function(options, delta)
      local ScreenPosition = require("src.core.ScreenPosition")
      options.screenPos = ScreenPosition.cycle(options.screenPos, delta)
      ScreenPosition.setMode(options.screenPos)
    end,
    text = function(options)
      return Strings(require("src.core.ScreenPosition").label(options.screenPos))
    end },
  -- jp.70: the Gen 1 Japanese build's display rows, carried over so Crystal /
  -- Gold / Silver get the same screen-orientation lock and top-screen-only
  -- layout.  Same option keys as Gen 1 (shared via Save.SHARED_KEYS), so a
  -- player's choice is one setting across generations.
  { id = "orientation", label = Strings.source("ORIENTATION"), port = true,
    mobileOnly = true,
    value = function(g)
      local O = require("src.core.Orientation")
      local mode = O.normalize(g.options and g.options.orientation)
      if isJapanese() then return ORIENT_JA[mode] or mode end
      return Strings(O.modeLabel(mode))
    end,
    step = function(g, dir)
      local O = require("src.core.Orientation")
      g.options.orientation = O.cycle(g.options.orientation, dir)
      O.apply(g.options.orientation)
      return true
    end },
  topScreenRow("jpTopScreen"),
  topScreenRow("jpTopScreenSize"),
  topScreenRow("jpTopScreenY"),
  topScreenRow("jpTopScreenX"),
  { id = "touchControls", label = Strings.source("TOUCH PAD"), port = true,
    text = function(options)
      local tc = options.touchControls
      local on = not (type(tc) == "table" and tc.enabled == false)
      return on and Strings("ON") or Strings("OFF")
    end,
    cycle = function(options, _delta, game)
      local tc = type(options.touchControls) == "table" and options.touchControls or {}
      tc.enabled = tc.enabled == false
      options.touchControls = tc
      require("src.core.TouchControls"):applyOptions(options)
      if game and game.persistOptions then game:persistOptions() end
    end },
  { id = "touchLayout", label = Strings.source("TOUCH LAYOUT"), port = true,
    activate = function(game)
      game.stack:push(require("src.ui.TouchControlsEditor").new(game))
    end },
  { id = "haptics", label = Strings.source("VIBRATION"), port = true,
    text = function(options)
      return Strings(require("src.core.TouchControls").hapticLabel(options.haptics))
    end,
    cycle = function(options, delta, game)
      local TC = require("src.core.TouchControls")
      options.haptics = TC.cycleHaptics(options.haptics, delta)
      TC:applyOptions(options)
      TC.buzz(options.haptics)
      if game and game.persistOptions then game:persistOptions() end
    end },
  { id = "hotbar", label = Strings.source("KEY BAR"), port = true,
    text = function(options)
      return options.hotbar == false and Strings("OFF") or Strings("ON")
    end,
    cycle = function(options, _delta, game)
      options.hotbar = options.hotbar == false
      require("src.core.TouchControls"):applyOptions(options)
      if game and game.persistOptions then game:persistOptions() end
    end },
  { label = Strings.source("MAX FPS"), key = "fpsCap", port = true,
    cycle = function(options, delta)
      local FrameCap = require("src.core.FrameCap")
      options.fpsCap = FrameCap.cycle(options.fpsCap, delta)
      FrameCap.apply(options.fpsCap)
    end,
    text = function(options)
      local FrameCap = require("src.core.FrameCap")
      local value = FrameCap.normalize(options.fpsCap)
      if value == FrameCap.DISPLAY then
        local label = FrameCap.label(value)
        local hz = tonumber(label:match("^DISPLAY %((%d+)HZ%)$"))
        return hz and Strings("DISPLAY (%dHZ)", hz) or Strings("DISPLAY")
      end
      return FrameCap.label(value)
    end },
  { label = Strings.source("VSYNC"), key = "vsync", port = true,
    cycle = function(options, delta)
      local ok, PS = pcall(require, "src.core.PresentSync")
      if ok and PS.vsyncStepAllowed
         and not PS.vsyncStepAllowed(options.vsync, delta) then
        return
      end
      local VSync = require("src.core.VSync")
      options.vsync = VSync.cycle(options.vsync, delta)
      VSync.apply(options.vsync)
    end,
    text = function(options)
      local ok, PS = pcall(require, "src.core.PresentSync")
      if ok and PS.vsyncEnableBlocked and PS.vsyncEnableBlocked() then
        return Strings("UNAVAILABLE")
      end
      return Strings(require("src.core.VSync").label(options.vsync))
    end },
  { label = Strings.source("LOGIC CLOCK"), key = "logicClock", port = true,
    cycle = function(options, delta)
      local LogicClock = require("src.core.LogicClock")
      options.logicClock = LogicClock.cycle(options.logicClock, delta)
      LogicClock.apply(options.logicClock)
    end,
    text = function(options)
      return Strings(require("src.core.LogicClock").label(options.logicClock))
    end },
  { label = Strings.source("BATTLE LAYOUT"), key = "battleLayout", port = true,
    values = { "og", "wide" },
    display = {
      og = Strings.source("OG  "), wide = Strings.source("WIDE"),
    },
    cycle = function(o, delta)
      local at = o.battleLayout == "wide" and 2 or 1
      local next_ = (at - 1 + (delta or 1)) % 2 + 1
      o.battleLayout = next_ == 2 and "wide" or "og"
      if o.battleLayout ~= "wide" then o.battleHud = "standard" end
    end },
  { label = Strings.source("BATTLE HUD"), key = "battleHud", port = true,
    text = function(o)
      return o.battleLayout == "wide" and o.battleHud == "extended"
        and Strings("EXTENDED") or Strings("STANDARD")
    end,
    cycle = function(o)
      if o.battleLayout ~= "wide" then
        o.battleHud = "standard"
        return
      end
      o.battleHud = o.battleHud == "extended" and "standard" or "extended"
    end },
  { label = Strings.source("BATTLE SIZE"), key = "battleFit", port = true,
    values = { "fixed", "fill" },
    display = {
      fixed = Strings.source("FIXED"), fill = Strings.source("FILL "),
    } },
  -- BATTLE BG (#1709): the void around the battle screen.
  { label = Strings.source("BATTLE BG"), key = "battleBg", port = true,
    values = { "white", "black", "world" },
    display = {
      white = Strings.source("WHITE"), black = Strings.source("BLACK"),
      world = Strings.source("WORLD"),
    } },
  -- jp.88: せんとうを フィールドで.  On (the default) shows the field the
  -- player stands on behind the battle panel instead of the white page
  -- (rilim's request); off is jp.87's white background exactly.
  { id = "jpBattleSeamless", label = Strings.source("BATTLE ON FIELD"), port = true,
    jpOnly = true,
    value = function(g)
      local on = g.options and g.options.jpBattleSeamless ~= false
      if isJapanese() then return on and "フィールド" or "しろ" end
      return on and Strings("FIELD") or Strings("WHITE")
    end,
    step = function(g)
      g.options.jpBattleSeamless = g.options.jpBattleSeamless == false
      return true
    end },
  -- jp.73: Gen 1 JP settings carried over (rilim's request).  Each row is
  -- live: B DASH and its three switches drive src/world/gen2/World.lua
  -- bDashActive / rollEncounter; DOT MATRIX the shared LCD grid pass
  -- (src/render/DotMatrix.lua) that Game2:draw now runs; the split speeds
  -- Game2:logicSpeed; SKIP OPENING Game2's boot branch; REUSABLE TM
  -- PackMenu's TM use; RESET KEYS the bindings and touch layout.
  { id = "bDash", label = Strings.source("B DASH"), port = true,
    value = function(g)
      local f = tonumber(g.options and g.options.bDash)
      if not f or f <= 1 then return isJapanese() and "オフ" or Strings("OFF") end
      return tostring(f) .. (isJapanese() and "ばい" or "X")
    end,
    step = function(g, dir)
      local list = { "off", "1.5", "2", "3" }
      local cur = tostring(g.options.bDash or "off")
      local at = 1
      for i, v in ipairs(list) do if v == cur then at = i end end
      g.options.bDash = list[(at - 1 + (dir or 1)) % #list + 1]
      return true
    end },
  { id = "bDashBike", label = Strings.source("B DASH BIKE"), port = true,
    value = function(g)
      local on = not (g.options and g.options.bDashBike == false)
      if isJapanese() then return on and "オン" or "オフ" end
      return on and Strings("ON") or Strings("OFF")
    end,
    step = function(g)
      g.options.bDashBike = g.options.bDashBike == false
      return true
    end },
  { id = "bDashSurf", label = Strings.source("B DASH SURF"), port = true,
    value = function(g)
      local on = g.options and g.options.bDashSurf == true
      if isJapanese() then return on and "オン" or "オフ" end
      return on and Strings("ON") or Strings("OFF")
    end,
    step = function(g)
      g.options.bDashSurf = g.options.bDashSurf ~= true
      return true
    end },
  { id = "bDashSafe", label = Strings.source("B DASH SAFE"), port = true,
    value = function(g)
      local on = g.options and g.options.bDashSafe == true
      if isJapanese() then return on and "オン" or "オフ" end
      return on and Strings("ON") or Strings("OFF")
    end,
    step = function(g)
      g.options.bDashSafe = g.options.bDashSafe ~= true
      return true
    end },
  topScreenRow("jpSkipIntro"),
  { id = "jpDotMatrix", label = Strings.source("DOT MATRIX"), port = true,
    value = function(g)
      local lv = math.floor(tonumber(g.options and g.options.jpDotMatrix) or 0)
      if isJapanese() then
        return ({ [0] = "オフ", "よわい", "ふつう", "つよい" })[lv] or "オフ"
      end
      return lv == 0 and Strings("OFF") or tostring(lv)
    end,
    step = function(g, dir)
      local lv = math.floor(tonumber(g.options.jpDotMatrix) or 0)
      lv = (lv + (dir or 1)) % 4
      g.options.jpDotMatrix = lv
      require("src.render.DotMatrix").setLevel(lv)
      return true
    end },
  -- jp.74: the Gen 1 JP OVERWORLD SPEED row (src/ui/OptionsMenu.lua:577).
  -- nil (the default, and every older save) follows GAME SPEED.
  { id = "speedOverworld", label = Strings.source("OVERWORLD SPEED"), port = true,
    value = function(g)
      local v = tonumber(g.options and g.options.speedOverworld)
      if not v then return isJapanese() and "ぜんたいと おなじ" or Strings("SAME") end
      if v == 1 then return isJapanese() and "ふつう" or Strings("NORMAL") end
      return isJapanese() and (v .. "ばい") or Strings("%dX", v)
    end,
    step = function(g, dir)
      local GameSpeed = require("src.core.GameSpeed")
      local levels = GameSpeed.allowed()
      local list = { false }
      for _, l in ipairs(levels) do if l <= 10 then list[#list + 1] = l end end
      local cur = tonumber(g.options.speedOverworld) or false
      local at = 1
      for i, v in ipairs(list) do if v == cur then at = i end end
      local nx = list[(at - 1 + (dir or 1)) % #list + 1]
      g.options.speedOverworld = nx or nil
      return true
    end },
  { id = "speedBattle", label = Strings.source("BATTLE SPEED"), port = true,
    value = function(g)
      local v = tonumber(g.options and g.options.speedBattle)
      if not v then return isJapanese() and "ぜんたいと おなじ" or Strings("SAME") end
      if v == 1 then return isJapanese() and "ふつう" or Strings("NORMAL") end
      return isJapanese() and (v .. "ばい") or Strings("%dX", v)
    end,
    step = function(g, dir)
      local GameSpeed = require("src.core.GameSpeed")
      local levels = GameSpeed.allowed()
      local list = { false }
      for _, l in ipairs(levels) do if l <= 10 then list[#list + 1] = l end end
      local cur = tonumber(g.options.speedBattle) or false
      local at = 1
      for i, v in ipairs(list) do if v == cur then at = i end end
      local nx = list[(at - 1 + (dir or 1)) % #list + 1]
      g.options.speedBattle = nx or nil
      return true
    end },
  { id = "speedMenu", label = Strings.source("MENU SPEED"), port = true,
    value = function(g)
      local v = tonumber(g.options and g.options.speedMenu)
      if not v then return isJapanese() and "ぜんたいと おなじ" or Strings("SAME") end
      if v == 1 then return isJapanese() and "ふつう" or Strings("NORMAL") end
      return isJapanese() and (v .. "ばい") or Strings("%dX", v)
    end,
    step = function(g, dir)
      local GameSpeed = require("src.core.GameSpeed")
      local levels = GameSpeed.allowed()
      local list = { false }
      for _, l in ipairs(levels) do if l <= 10 then list[#list + 1] = l end end
      local cur = tonumber(g.options.speedMenu) or false
      local at = 1
      for i, v in ipairs(list) do if v == cur then at = i end end
      local nx = list[(at - 1 + (dir or 1)) % #list + 1]
      g.options.speedMenu = nx or nil
      return true
    end },
  -- jp.74: the rest of the Gen 1 JP GAME RULES page, in its order, plus
  -- Gold's own ひでんわざ なしで つかう (jpFieldNoMove).  All off by default.
  -- ルールの まとめ has no key of its own: it reads and writes the three
  -- Gen 1 preset keys (src/core/JapaneseRules.lua Rules.keys).
  topScreenRow("jpRulesPreset"),
  topScreenRow("jpPartyExp"),
  topScreenRow("jpForgetHM"),
  topScreenRow("jpReusableTM"),
  topScreenRow("jpMoveReminder"),
  { id = "jpFieldNoMove", label = Strings.source("FIELD MOVE W/O"), port = true,
    jpOnly = true,
    value = function(g)
      local on = g.options and g.options.jpFieldNoMove == true
      if isJapanese() then return on and "オン" or "オフ" end
      return on and Strings("ON ") or Strings("OFF")
    end,
    step = function(g)
      g.options.jpFieldNoMove = g.options.jpFieldNoMove ~= true
      return true
    end },
  -- jp.75: メニューの はいけい.  On (the default) keeps the live field behind
  -- the START menu's pages; off is the cart's white page and fade.
  { id = "jpSeamlessMenu", label = Strings.source("MENU BACKDROP"), port = true,
    jpOnly = true,
    value = function(g)
      local on = g.options and g.options.jpSeamlessMenu == true
      if isJapanese() then return on and "フィールド" or "げんさくどおり" end
      return on and Strings("FIELD") or Strings("ORIGINAL")
    end,
    step = function(g)
      g.options.jpSeamlessMenu = g.options.jpSeamlessMenu ~= true
      return true
    end },
  -- jp.75: the Gen 1 parity rows (C-H).  Every one is off by default and
  -- only shown on the Japanese carts.
  jp75OnOff("jpRepelRepeat", Strings.source("REPEL AGAIN")),
  jp75OnOff("jpBagSort", Strings.source("PACK SORT")),
  jp75OnOff("jpPcAnywhere", Strings.source("PC ANYWHERE")),
  jp75OnOff("jpFieldActions", Strings.source("INSPECT HM")),
  -- jp.77: how often a wild mon rolls the shiny DVs (Mon.wildDVs).  The DV
  -- rule and the look stay the cart's; "gen2" is the original 1/8192.
  { id = "jpShinyRate", label = Strings.source("SHINY RATE"), port = true,
    jpOnly = true,
    value = function(g)
      local Mon = require("src.battle.gen2.Mon")
      local key = g.options and g.options.jpShinyRate
      if Mon.SHINY_RATES[key] == nil then key = "gen2" end
      local denom = Mon.SHINY_RATES[key]
      if denom == 0 then
        return isJapanese() and "かならず" or "ALWAYS"
      end
      local text = "1/" .. tostring(denom)
      if key == "gen2" and isJapanese() then text = text .. " げんさく" end
      return text
    end,
    step = function(g, dir)
      local Mon = require("src.battle.gen2.Mon")
      local cycle = Mon.SHINY_RATE_ORDER
      local cur = 1
      for i, k in ipairs(cycle) do
        if g.options.jpShinyRate == k then cur = i end
      end
      cur = (cur - 1 + ((dir or 1) < 0 and -1 or 1)) % #cycle + 1
      g.options.jpShinyRate = cycle[cur]
      return true
    end },
  { id = "jpStartupScreen", label = Strings.source("APP STARTUP"), port = true,
    jpOnly = true,
    value = function(g)
      local on = g.options and g.options.jpStartupScreen == "continue"
      if isJapanese() then return on and "つづきから すぐに" or "いつもどおり" end
      return on and "CONTINUE" or "NORMAL"
    end,
    step = function(g)
      local on = g.options.jpStartupScreen == "continue"
      g.options.jpStartupScreen = on and "home" or "continue"
      return true
    end },
  { id = "faithfulRes", label = Strings.source("FAITHFUL RATIO"), port = true,
    jpOnly = true,
    value = function(g)
      local FaithfulRes = require("src.core.FaithfulRes")
      local label = FaithfulRes.label(g.options and g.options.faithfulRes)
      if isJapanese() then
        if label == "OFF" then return "オフ" end
        if label == "ON" then return "オン" end
        return (label:gsub("X$", "ばい"))
      end
      return label
    end,
    step = function(g, dir)
      local FaithfulRes = require("src.core.FaithfulRes")
      local o = g.options
      o.faithfulRes = FaithfulRes.cycle(o.faithfulRes, dir)
      pcall(FaithfulRes.apply, o.faithfulRes)
      return true
    end },
  -- jp.75: the experimental 3D field (src/world/gen2/Field3D.lua), all off.
  jp75OnOff("jp3D", Strings.source("3D FIELD")),
  { id = "jp3DCamera", label = Strings.source("3D CAMERA"), port = true,
    jpOnly = true,
    value = function(g)
      local m = g.options and g.options.jp3DCamera
      if m ~= "third" and m ~= "first" then m = "above" end
      if isJapanese() then
        return ({ above = "うえから", third = "うしろから", first = "いちにんしょう" })[m]
      end
      return ({ above = "ABOVE", third = "BEHIND", first = "1ST PERSON" })[m]
    end,
    step = function(g, dir)
      local cycle = { "above", "third", "first" }
      local cur = 1
      for i, m in ipairs(cycle) do
        if g.options.jp3DCamera == m then cur = i end
      end
      cur = (cur - 1 + ((dir or 1) < 0 and -1 or 1)) % #cycle + 1
      g.options.jp3DCamera = cycle[cur]
      return true
    end },
  -- jp.81: the tilt of the view from above and the zoom (Gen 1's ladder)
  { id = "jp3DAngle", label = Strings.source("3D ANGLE"), port = true,
    jpOnly = true,
    value = function(g)
      local a = g.options and g.options.jp3DAngle
      a = a ~= nil and tostring(a) or "35"
      if a ~= "diorama" and a ~= "15" and a ~= "50" and a ~= "75" then a = "35" end
      if a == "diorama" then return isJapanese() and "ジオラマ" or "DIORAMA" end
      return isJapanese() and (a .. "ど") or (a .. " DEG")
    end,
    step = function(g, dir)
      local cycle = { "diorama", "15", "35", "50", "75" }
      local cur = 3
      for i, a in ipairs(cycle) do
        if tostring(g.options.jp3DAngle) == a then cur = i end
      end
      cur = (cur - 1 + ((dir or 1) < 0 and -1 or 1)) % #cycle + 1
      g.options.jp3DAngle = cycle[cur]
      return true
    end },
  { id = "jp3DZoom", label = Strings.source("3D ZOOM"), port = true,
    jpOnly = true,
    value = function(g)
      local z = math.floor(tonumber(g.options and g.options.jp3DZoom) or 3)
      z = math.max(1, math.min(5, z))
      return z .. "/5"
    end,
    step = function(g, dir)
      local z = math.floor(tonumber(g.options.jp3DZoom) or 3)
      z = math.max(1, math.min(5, z))
      z = (z - 1 + ((dir or 1) < 0 and -1 or 1)) % 5 + 1
      g.options.jp3DZoom = z
      return true
    end },
  jp75OnOff("jp3DInvert", Strings.source("3D INVERT LOOK")),
  -- jp.86: とおくの ぼかし, the Gen 1 distance blur level 0 (none) .. 5
  -- (src/world/gen2/Field3D.lua BLUR_PRESETS); the field and the battle
  -- backdrop share it
  { id = "jp3DBlur", label = Strings.source("3D DISTANCE BLUR"), port = true, jpOnly = true,
    value = function(g)
      local v = math.floor(tonumber(g.options and g.options.jp3DBlur) or 1)
      v = math.max(0, math.min(5, v))
      if v == 0 then return isJapanese() and "なし" or "OFF" end
      return v .. "/5"
    end,
    step = function(g, dir)
      local v = math.floor(tonumber(g.options.jp3DBlur) or 1)
      v = math.max(0, math.min(5, v))
      v = (v + ((dir or 1) < 0 and -1 or 1)) % 6
      g.options.jp3DBlur = v
      return true
    end },
  -- jp.82: the camera buttons along the top of the 3D field (absent = on).
  -- jp.86: the small tab that flipped this from the field is gone.
  { id = "jp3DButtons", label = Strings.source("3D CAMERA BUTTONS"), port = true, jpOnly = true,
    value = function(g)
      local on = not (g.options and g.options.jp3DButtons == false)
      if isJapanese() then return on and "オン" or "オフ" end
      return on and "ON " or "OFF"
    end,
    step = function(g)
      g.options.jp3DButtons = g.options.jp3DButtons == false
      return true
    end },
  jp75OnOff("jp3DMove", Strings.source("3D TURN MOVE")),
  jp75OnOff("jp3DFree", Strings.source("3D FREE MOVE")),
  jp75OnOff("jp3DAtmos", Strings.source("3D SKY")),
  -- Two presses: the first arms it, the second puts the keys and the touch
  -- layout back (the Gen 1 launcher's resetBindings, LauncherSettings.lua).
  { id = "resetBindings", label = Strings.source("RESET KEYS"), port = true,
    value = function(g)
      if g.resetArmed then return isJapanese() and "もういちど A" or Strings("A AGAIN") end
      if g.resetDone then return isJapanese() and "もどしました" or Strings("DONE") end
      return isJapanese() and "A で もどす" or Strings("PRESS A")
    end,
    activate = function(g)
      if not g.resetArmed then
        g.resetArmed, g.resetDone = true, nil
        return
      end
      g.resetArmed = nil
      local o = g.options
      o.bindings = nil
      if type(o.touchControls) == "table" then
        o.touchControls.layouts = nil
        o.touchControls.positions = nil
      end
      o.jpTouchAreas = nil
      require("src.core.Input"):applyBindings(nil)
      pcall(function()
        require("src.core.TouchControls"):applyOptions({
          touchControls = o.touchControls, haptics = o.haptics, hotbar = o.hotbar })
      end)
      if g.persistOptions then pcall(g.persistOptions, g) end
      g.resetDone = true
    end },
  { label = Strings.source("BACK"), cancel = true },
}

-- The cart's screen is one full-height textbox with every row on it.  This one
-- carries four more, so it shows a window of rows and scrolls: labels start at
-- (2,2) and step two rows, exactly as _Option lays them, and the window moves
-- only when the cursor would leave it.
local VISIBLE_ROWS = 7

-- The same grouping the Gen 1 screen uses (src/ui/OptionsMenu.lua GROUPS),
-- with Gold's own rows in it: FRAME is a graphics setting here and SOUND is
-- an audio one.  Runs after the ui.options.rows hook and only builds
-- self.view, so self.rows stays the flat list a mod reads and edits.
local GROUPS = {
  { id = "group.speed", label = Strings.source("SPEED"),
    members = { "textSpeed", "speed", "speedOverworld", "speedBattle", "speedMenu" } },
  { id = "group.video", label = Strings.source("VIDEO"),
    members = { "videoMode", "orientation", "faithfulRes", "screenPos", "jpSeamlessMenu", "jpTopScreen",
      "jpTopScreenSize", "jpTopScreenY", "jpTopScreenX",
      "fpsCap", "vsync", "logicClock" } },
  { id = "group.graphics", label = Strings.source("GRAPHICS"),
    members = { "color", "uiLetterbox", "shaderfx", "shaderfx2", "frame",
      "jpDotMatrix" } },
  { id = "group.audio", label = Strings.source("AUDIO"),
    members = { "sound", "musicVol", "sfxVol", "musicFilter" } },
  { id = "group.battle", label = Strings.source("BATTLE OPTIONS"),
    members = { "battleScene", "battleStyle", "battleLayout", "battleHud",
      "battleFit", "battleBg", "jpBattleSeamless" } },
  { id = "group.extras", label = Strings.source("EXTRAS"),
    members = { "zoom", "voidFill", "tilt" } },
  { id = "group.jp3d", label = Strings.source("3D"),
    members = { "jp3D", "jp3DCamera", "jp3DAngle", "jp3DZoom", "jp3DBlur", "jp3DInvert",
      "jp3DButtons", "jp3DMove", "jp3DFree", "jp3DAtmos" } },
  -- jp.73: the Gen 1 JP screen's own pages (src/ui/JapaneseSettingsCatalog.lua
  -- own("startup"/"touch"/"controls"/"game")).
  { id = "group.startup", label = Strings.source("STARTUP"),
    members = { "jpSkipIntro", "jpStartupScreen" } },
  { id = "group.movement", label = Strings.source("B DASH"),
    members = { "bDash", "bDashBike", "bDashSurf", "bDashSafe" } },
  { id = "group.rules", label = Strings.source("GAME RULES"),
    members = { "jpRulesPreset", "jpPartyExp", "jpForgetHM", "jpReusableTM", "jpMoveReminder",
      "jpFieldNoMove", "jpFieldActions", "jpRepelRepeat", "jpBagSort", "jpPcAnywhere", "jpShinyRate" } },
  { id = "group.touch", label = Strings.source("TOUCH"),
    members = { "touchControls", "touchLayout", "haptics", "hotbar" } },
  { id = "group.controls", label = Strings.source("CONTROLS"),
    members = { "controls", "resetBindings" } },
}

local ORDER = {
  "group.speed", "group.video", "group.graphics", "group.audio",
  "performance", "group.battle", "group.extras", "group.jp3d",
  "group.startup", "group.movement", "group.rules", "group.touch",
  "group.controls",
}

-- A group's page is this same screen driving the rows it was handed, with
-- its own BACK on the bottom.
local function groupView(rows, open)
  local owner, picked = {}, {}
  for _, group in ipairs(GROUPS) do
    for _, id in ipairs(group.members) do owner[id] = group end
    picked[group.id] = {}
  end
  for _, row in ipairs(rows) do
    if row.id and owner[row.id] then
      local into = picked[owner[row.id].id]
      into[#into + 1] = row
    end
  end
  local made, byId = {}, {}
  for _, group in ipairs(GROUPS) do
    local members = picked[group.id]
    if #members > 0 then
      -- No value line: the value column is eight characters wide here, and a
      -- group has no setting of its own to show in it anyway.
      made[group.id] = { id = group.id, label = group.label, group = true,
                         activate = function(game) open(game, members, group) end }
    end
  end
  for _, row in ipairs(rows) do
    if row.id and not owner[row.id] then byId[row.id] = row end
  end
  local view, taken = {}, {}
  for _, id in ipairs(ORDER) do
    local row = made[id] or byId[id]
    if row then view[#view + 1] = row; taken[id] = true end
  end
  for _, row in ipairs(rows) do
    local id = row.id
    if not (id and (owner[id] or taken[id])) then view[#view + 1] = row end
  end
  return view
end

-- ui.options.rows identity: an unhooked build hands its own rows back.
local function sameRows(_, rows) return rows end

-- The descriptors one opening of the screen works from.  They are shallow
-- copies of ROWS, so a mod that edits a row inside the hook cannot leak that
-- edit into the next opening -- the Gen 1 site rebuilds its descriptors for the
-- same reason (src/ui/OptionsMenu.lua buildRows).
--
-- `id` is the key a Gen 1 mod filters a row on ("shaderfx", "speed", "musicVol")
-- and is added ALONGSIDE this file's own `key`, never in place of it: a mod
-- written against Red's OPTION screen finds the shared rows where it expects
-- them, and the rows Gold has that Red does not (PRINT, MENU ACCOUNT, FRAME,
-- COLOR) simply appear in the list the hook receives.
local function buildRows()
  local rows = {}
  local env = os.getenv("POKEPORT_TOUCH")
  local osName = love.system and love.system.getOS and love.system.getOS()
  local showTouch = env == "1"
    or (env ~= "0" and (osName == "Android" or osName == "iOS"))
  local isNX = require("src.core.Platform").isNX()
  local mobile = osName == "Android" or osName == "iOS" or env == "1"
  local japanese = isJapanese()
  for i, row in ipairs(ROWS) do
    -- PRINT is wGBPrinterBrightness, how dark the Game Boy Printer prints
    -- (GBPRINTER_LIGHTEST..DARKEST, constants/ram_constants.asm:67-70).
    -- There is no printer here (src/script/gen2/Specials.lua answers the
    -- print specials with "no Game Boy Printer"), so nothing reads the
    -- value and the row is hidden rather than offering a dead setting.
    -- The descriptor and the save key stay, so a build that grows a printer
    -- only has to drop this test.
    local hidden = row.key == "print"
      or (isNX and row.key == "videoMode")
      or (row.mobileOnly and not mobile)
      or (row.jpOnly and not japanese)
      or (not showTouch and (row.id == "touchControls"
          or row.id == "touchLayout" or row.id == "haptics"
          or row.id == "hotbar"))
    if not hidden then
      local copy = {}
      for key, value in pairs(row) do copy[key] = value end
      copy.id = copy.id or copy.key or (copy.cancel and "cancel") or nil
      rows[#rows + 1] = copy
    end
  end
  return rows
end

function OptionsMenu:wantsFillScale() return true end
function OptionsMenu:drawsWidescreen() return true end

-- opts: options (the table to edit in place), onDone(options)
-- The page edits the SAME options table the parent screen does, so a value
-- changed on it lands where the caller's onDone will read it.
local function pushGroup(parent, members, group)
  local page = setmetatable({}, OptionsMenu)
  page.game = parent.game
  page.groupId = group and group.id
  page.rows = members
  page.options = parent.options
  page.index, page.scroll, page.sub = 1, 0, true
  page.view = {}
  for i, row in ipairs(members) do page.view[i] = row end
  page.view[#page.view + 1] = { label = Strings.source("BACK"), cancel = true,
                                id = "cancel" }
  parent.game.stack:push(page)
  return page
end

function OptionsMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, OptionsMenu)
  self.game = game
  -- Unguarded, like the Gen 1 site: the screen is built once per opening.  A
  -- hook that answers with anything but a table is degraded to the vanilla
  -- rows rather than leaving the player with an empty OPTION screen.
  local rows = buildRows()
  local hooked = Runtime.call("ui.options.rows", sameRows, game, rows)
  if type(hooked) == "table" then
    rows = hooked
  else
    Logger.error("ui.options.rows returned %s; keeping the vanilla rows",
                 type(hooked))
  end
  self.rows = rows
  self.options = opts.options or Save.defaultOptions()
  -- Fill in anything missing so a row can never read nil and lose the
  -- player's other settings when it writes back.
  for key, value in pairs(Save.DEFAULT_OPTIONS) do
    if self.options[key] == nil then self.options[key] = value end
  end
  self.onDone = opts.onDone
  if game then game.resetArmed, game.resetDone = nil, nil end
  self.index = 1
  self.scroll = 0
  self.view = groupView(rows, function(_, members, group)
    return pushGroup(self, members, group)
  end)
  return self
end

function OptionsMenu:visible()
  return self.view or self.rows
end

function OptionsMenu:ensureVisible()
  local rows = self:visible()
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + VISIBLE_ROWS then
    self.scroll = self.index - VISIBLE_ROWS
  end
  self.scroll = math.max(0,
    math.min(self.scroll, math.max(0, #rows - VISIBLE_ROWS)))
end

function OptionsMenu:row()
  return self:visible()[self.index]
end

-- Cursor onto a row by id, opening its group page first if it lives in one.
-- Returns the screen the row ended up on, so a caller can keep driving it.
function OptionsMenu:focusRow(id)
  local rows = self:visible()
  for i, row in ipairs(rows) do
    if row.id == id then
      self.index = i
      self:ensureVisible()
      return self
    end
  end
  for i, row in ipairs(rows) do
    if row.group and row.activate then
      local group
      for _, g in ipairs(GROUPS) do if g.id == row.id then group = g end end
      for _, member in ipairs(group and group.members or {}) do
        if member == id then
          self.index = i
          row.activate(self.game)
          local page = self.game.stack:top()
          return page.focusRow and page:focusRow(id) or page
        end
      end
    end
  end
  return nil
end

function OptionsMenu:cycle(row, delta)
  -- The Gen 1 row vocabulary (src/ui/OptionRows.lua:3-7), answered first so a
  -- mod's row written against Red's OPTION screen steps here too.  `step` takes
  -- the game, not the options table, because that is the handle it is given on
  -- the other generation.
  if row.step then
    row.step(self.game, delta)
    return
  end
  -- A port row owns its own ladder (and its own live module), so it steps
  -- itself rather than walking a `values` list.
  if row.cycle then
    row.cycle(self.options, delta, self.game)
    return
  end
  if row.frame then
    -- Eight frames, wrapping (UpdateFrame masks to 3 bits).
    local frame = ((self.options.frame or 1) - 1 + delta) % 8 + 1
    self.options.frame = frame
    -- options_menu.asm:475 UpdateFrame reloads the tiles as the value changes,
    -- so this screen's own border restyles under the cursor.
    require("src.render.Font").setFrame(frame)
    return
  end
  if not row.values then return end
  local current = self.options[row.key]
  local at = 1
  for i, value in ipairs(row.values) do
    if value == current then at = i break end
  end
  local next_ = at + delta
  -- Left at the first entry wraps to the last and vice versa, matching
  -- Options_TextSpeed's .LeftPressed / .Increase clamps.
  if next_ < 1 then next_ = #row.values end
  if next_ > #row.values then next_ = 1 end
  self.options[row.key] = row.values[next_]
  -- MUSIC VOL applies itself as it steps; SOUND has to as well, or the
  -- pan sits on the current song until the next map change (#1471)
  if row.key == "sound" then
    require("src.core.Music").applyOptions(self.options)
  end
end

function OptionsMenu:leave_()
  if self.onDone then self.onDone(self.options) end
  if self.game and self.game.stack and self.game.stack:top() == self then
    self.game.stack:pop()
  end
end

function OptionsMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("start") or input:wasPressed("b") then
    self:leave_()
    return
  end
  local rows = self:visible()
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #rows
    self:ensureVisible()
    return
  elseif input:wasPressed("down") then
    self.index = self.index < #rows and self.index + 1 or 1
    self:ensureVisible()
    return
  end
  local row = self:row()
  if not row then return end
  if input:wasPressed("a") then
    if row.cancel then
      self:leave_()
    elseif row.activate then
      -- the A-press action for a row that opens something instead of cycling
      -- a value (src/ui/OptionsMenu.lua:556)
      row.activate(self.game)
    else
      -- A on a value row advances it, which is what the ASM's shared
      -- right-press path does when A is held on a non-CANCEL row.
      self:cycle(row, 1)
    end
    return
  end
  if input:wasPressed("left") then
    self:cycle(row, -1)
  elseif input:wasPressed("right") then
    self:cycle(row, 1)
  end
end

function OptionsMenu:drawPanel()
  Chrome.clear()
  -- hlcoord 0,0 with b = SCREEN_HEIGHT - 2, c = SCREEN_WIDTH - 2.
  Chrome.textbox(0, 0, Chrome.SCREEN_W - 2, Chrome.SCREEN_H - 2)
  -- The textbox spends column 19 on its frame, so a line drawn past column
  -- 18 prints over the border: 17 characters from the label's column 2,
  -- 8 from the value's column 11.  Anything longer scrolls under the cursor.
  local rows = self:visible()
  for slot = 1, math.min(VISIBLE_ROWS, #rows) do
    local i = slot + self.scroll
    local row = rows[i]
    if row then
      local labelY = 2 + (slot - 1) * 2
      local hot = i == self.index
      local key = tostring(row.id or row.label)
      local function fit(text, col)
        local room = 19 - col
        if hot then return Marquee.scroll(text, room, key) end
        return Marquee.clip(text, room)
      end
      Chrome.print(fit(Strings(row.label), 2), 2, labelY)
      if row.frame then
        Chrome.print(Strings(":TYPE"), 10, labelY + 1)
        Chrome.print(tostring(self.options.frame or 1), 16, labelY + 1)
      elseif row.text then
        Chrome.print(":", 10, labelY + 1)
        Chrome.print(fit(row.text(self.options), 11), 11, labelY + 1)
      elseif row.values then
        Chrome.print(":", 10, labelY + 1)
        local value = self.options[row.key]
        local text = row.display and Strings(row.display[value]) or tostring(value)
        Chrome.print(fit(text, 11), 11, labelY + 1)
      elseif type(row.value) == "function" then
        -- the Gen 1 row's value reader (src/ui/OptionRows.lua:4), so a mod row
        -- shows its setting here instead of drawing a bare label
        local ok, text = pcall(row.value, self.game)
        Chrome.print(":", 10, labelY + 1)
        Chrome.print(fit(ok and tostring(text) or "?", 11), 11, labelY + 1)
      end
    end
  end
  Chrome.cursor(1, 2 + (self.index - self.scroll - 1) * 2)
  -- The ▼ hint every scrolling Gen 2 list shows when there is more below.
  if self.scroll + VISIBLE_ROWS < #rows then
    local Font = require("src.render.Font")
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawCode(Chrome.DOWN_ARROW, 1 * 8, (2 + VISIBLE_ROWS * 2 - 1) * 8)
  end
end

function OptionsMenu:draw()
  self:drawPanel()
end

-- jp.70: the Japanese carts draw this screen the way the Gen 1 Japanese
-- settings window does (src/ui/SessionMenu.lua layout/draw): one framed
-- panel sized to the usable playfield in whole 8px tiles, a title and rule,
-- label / < value > rows paged to fit, a one-line help strip for the row
-- under the cursor, and a もどる footer with the page count.  The row data,
-- the input handling and the onDone -> persistOptions path stay the ones
-- above; only the presentation differs.  All of the wording below is the
-- port's own.
local JP_GROUPS = {
  ["group.speed"] = { "はやさ", "もじと ゲームの すすむ はやさです。" },
  ["group.video"] = { "がめん", "がめんの むきや うえがめんだけ などの せってい。" },
  ["group.graphics"] = { "いろと こうか", "ゲームの いろや まどの わく がめんの こうか。" },
  ["group.audio"] = { "おと", "おんがくと こうかおんの せってい。" },
  ["group.battle"] = { "せんとう", "せんとうの うごきと がめんの せってい。" },
  ["group.extras"] = { "そのほか", "ちかくと とおく そとの ちけい かたむき。" },
  ["group.jp3d"] = { "3D しけんちゅう", "フィールドを 3Dで みる しけんちゅうの せってい。" },
  ["group.startup"] = { "きどう", "ゲームを はじめるときの せってい。" },
  ["group.movement"] = { "Bダッシュ", "Bボタンを おして はしる せってい。" },
  ["group.rules"] = { "ゲームの ルール", "わざマシンなど あそびかたの せってい。" },
  ["group.touch"] = { "タッチそうさ", "がめんの ボタンと しんどうの せってい。" },
  ["group.controls"] = { "ボタン・キー", "キーの わりあてと もとに もどす せってい。" },
}
local JP_ROWS = {
  speed = { "ゲームの はやさ", "ゲームぜんたいが すすむ はやさです。" },
  battleScene = { "わざの うごき", "せんとうで わざの うごきを みせるか えらびます。" },
  sound = { "おとの だしかた", "モノラルか ステレオかを えらびます。" },
  menuAccount = { "メニューの せつめい", "メニューで えらんだ こうもくの せつめいを だします。" },
  frame = { "まどの わく", "まどの わくの もようを 8しゅるいから えらびます。" },
  touchLayout = { "ボタンの はいち", "がめんの ボタンの いちと おおきさを かえます。" },
  battleLayout = { "せんとうの はいち", "もとの がめんか ワイドかを えらびます。" },
  battleHud = { "せんとうの じょうほう", "ワイドの ときに だす じょうほうの りょうです。" },
  battleFit = { "せんとうの おおきさ", "せんとうがめんを こていか ぜんがめんに するか えらびます。" },
  battleBg = { "せんとうの はいけい", "せんとうがめんの まわりを うめる いろです。" },
  jpBattleSeamless = { "せんとうを フィールドで", "せんとうの うしろに いま いる ばしょの けしきを みせます。しろ で もとの しろい はいけいに もどります。" },
  bDash = { "Bで はしる はやさ", "Bを おしながら あるくと はやく すすみます。オフで つかいません。" },
  bDashBike = { "Bで じてんしゃを かそく", "じてんしゃでも Bを おして はやく いどうできます。" },
  bDashSurf = { "Bで なみのりを かそく", "なみのりでも Bを おして はやく いどうできます。" },
  bDashSafe = { "はしるとき そうぐうしない", "Bで はしっている ときは くさむらで やせいの ポケモンに あいません。" },
  speedBattle = { "せんとうの はやさ", "せんとうが すすむ はやさです。おなじ で ゲームの はやさに あわせます。" },
  speedOverworld = { "フィールドの はやさ", "フィールドを あるく ときの はやさです。おなじ で ゲームの はやさに あわせます。" },
  speedMenu = { "メニューの はやさ", "メニューや かいわの すすむ はやさです。おなじ で ゲームの はやさに あわせます。" },
  jpFieldNoMove = { "ひでんわざ なしで つかう", "わざを おぼえて いなくても バッジが あれば フィールドで ひでんわざを つかえます。" },
  jpSeamlessMenu = { "メニューの はいけい", "メニューを ひらいても いま いる ばしょの けしきを うしろに みせます。げんさくどおり で しろい がめんに もどります。" },
  jpRepelRepeat = { "スプレーの つづけてしよう", "むしよけスプレーの こうかが きれたとき おなじ スプレーを つづけて つかうか ききます。" },
  jpBagSort = { "リュックの ならべかえ", "リュックで STARTを おすと いまの ポケットの どうぐを なまえじゅんに ならべます。わざマシンは そのままです。" },
  jpPcAnywhere = { "どこでも パソコン", "メニューに パソコンを だして どこからでも ボックスや どうぐを あずけられます。" },
  jpShinyRate = { "いろちがいの でやすさ", "やせいの ポケモンが いろちがいで でる かくりつを えらびます。いろちがいの きまりと みためは げんさくの ままです。1/8192 が げんさくどおりです。" },
  jpFieldActions = { "しらべて ひでんわざ", "なみのりが つかえない みずべを しらべたとき なにが たりないかを おしえます。" },
  jpStartupScreen = { "アプリの きどうじ", "つづきから すぐに で アプリを ひらくと レポートの つづきから はじめます。" },
  faithfulRes = { "げんさくの ひりつ", "ゲームがめんを もとの たてよこの おおきさの まま うつします。まわりは くろく なります。" },
  jp3D = { "3Dフィールド しけん", "まちと どうろを 3Dで みせる しけんちゅうの きのうです。ふだんは オフ（もとの 2D）です。へやの なかと どうくつ・せんとうは いつも 2Dです。うごかない ときは じどうで 2Dに もどります。" },
  jp3DCamera = { "3Dの カメラ", "うえから・うしろから・いちにんしょうを えらびます。フィールドで Vキー・みぎスティックおしこみ・がめん みぎうえの めのボタンでも きりかえられます。Qと Eの キー・Lと Rの ボタン・みぎスティック・ひだりうえの まわすボタンで まわせます。" },
  jp3DAngle = { "3Dの みおろす かくど", "うえからの カメラの かたむきです。15どは まうえに ちかく 75どは よこに ちかく なります。ジオラマは とおくから ちいさく みおろします。" },
  jp3DZoom = { "3Dの ズーム", "カメラの ちかさです。フィールドで マウスホイール・マイナスと イコールの キー・がめん みぎうえの ＋と －・うえからの ときは みぎスティックの うえしたでも かえられます。" },
  jp3DInvert = { "3Dの うえした はんてん", "うしろからと いちにんしょうで みぎスティックや ゆびの うえしたで みあげる むきを ぎゃくに します。Rと Fの キーでも みあげ・みおろし できます。" },
  jp3DBlur = { "とおくの ぼかし", "3Dの フィールドと せんとうで とおくの けしきを ぼかす つよさです。なしで きれます。" },
  jp3DButtons = { "3Dの カメラボタン", "がめん うえの まわす・めの・＋－の ボタンを だすか けします。けしても キーや スティックや ゆびで なぞる そうさは つかえます。" },
  jp3DMove = { "カメラの むきで あるく", "まわした カメラの むきに あわせて じゅうじキーの むきを かえます。カメラを まわして いる ときは オフでも がめんの うえが うえに なります。" },
  jp3DFree = { "3Dで じゆうに あるく", "3Dの とき マスめに とらわれず スティックや ゆびの むきに なめらかに あるきます。こおりや ながれの うえでは もとの うごきに もどります。" },
  jp3DAtmos = { "3Dの そらと てんき", "じかんたいで そらの いろと きりを かえ ひによって あめや ゆきを ふらせます。" },
  jp3DBattle = { "3Dの せんとう", "せんとうを いまの ばしょの 3Dの なかで みせます。ポケモンは たてふだの ように たちます。わざの えんしゅつは 2Dの ままです。" },
}

local raisedKana = {}
for ch in ("がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポヴ")
    :gmatch("[%z\1-\127\194-\244][\128-\191]*") do raisedKana[ch] = true end
local function raised(text)
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if raisedKana[ch] then return true end
  end
  return false
end
local function trim(text)
  return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
local function tileCeil(value) return math.ceil(value / 8) * 8 end
local function helpWrap(Classic, text, width)
  local out = {}
  for para in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      local cand = line == "" and word or (line .. " " .. word)
      if Classic.width(cand) <= width then
        line = cand
      else
        if line ~= "" then out[#out + 1] = line end
        if Classic.width(word) > width then
          local parts = Classic.wrap(word, width)
          for k = 1, #parts - 1 do out[#out + 1] = parts[k] end
          line = parts[#parts] or ""
        else
          line = word
        end
      end
    end
    if line ~= "" then out[#out + 1] = line end
  end
  if #out == 0 then out[1] = "" end
  return out
end

function OptionsMenu:jpInfo(row)
  if not row then return "", nil end
  if row.cancel then return "もどる", nil end
  if row.group then
    local g = JP_GROUPS[row.id]
    if g then return g[1], g[2] end
  end
  local own = row.id and JP_ROWS[row.id]
  if own then return own[1], own[2] end
  local ok, C = pcall(require, "src.ui.JapaneseSettingsCatalog")
  if ok and row.id and C.entry then
    local entry = C.entry(row.id)
    if entry then return entry[1], entry[2] end
  end
  return trim(Strings(row.label)), nil
end

-- The value text a row shows, or nil for a row with no value of its own.
function OptionsMenu:jpValue(row)
  if not row or row.cancel or row.group then return nil end
  local text
  if row.frame then
    text = tostring(self.options.frame or 1)
  elseif row.text then
    local ok, v = pcall(row.text, self.options)
    text = ok and v or "?"
  elseif row.values then
    local value = self.options[row.key]
    text = row.display and row.display[value] ~= nil and Strings(row.display[value])
      or tostring(value)
  elseif type(row.value) == "function" then
    local ok, v = pcall(row.value, self.game)
    text = ok and v or "?"
  else
    return nil
  end
  return self:jpValueText(row, trim(text))
end

-- jp.91: mod rows (CONTROLLER_RUMBLE, ACCESS_PC_ANYWHERE, ...) hand back their
-- own English value words; show them in the same Japanese as the port's rows
-- (オン/オフ, よわい/ふつう/つよい).  Unknown words fall through Strings().
local JP_VALUE_WORDS = {
  ON = "オン", OFF = "オフ", LOW = "よわい", MED = "ふつう", MEDIUM = "ふつう",
  HIGH = "つよい", OPEN = "ひらく", AUTO = "じどう", YES = "はい", NO = "いいえ",
  OUTDOORS = "そとだけ", ANYWHERE = "どこでも",
}
function OptionsMenu:jpValueText(row, text)
  local key = tostring(text or ""):upper()
  local id = tostring(row and row.id or "")
  -- どこでもPCを そとだけにする: the help text speaks of オン / オフ.
  if id:find("overworld_only", 1, true) then
    if key == "OUTDOORS" then return "オン" end
    if key == "ANYWHERE" then return "オフ" end
  end
  -- Row-specific words first (HOUSE HEIGHT TALL -> たかめ, ...), the same
  -- table Red's OPTION screen uses.
  local okC, C = pcall(require, "src.ui.JapaneseSettingsCatalog")
  if okC and C.value and row and row.id then
    local okV, v = pcall(C.value, row.id, text)
    if okV and type(v) == "string" and v ~= text then return v end
  end
  local jp = JP_VALUE_WORDS[key]
  if jp then return jp end
  if text ~= "" and not text:find("[\128-\255]") and text:find("%a") then
    local s = trim(Strings(text))
    if s ~= "" and s ~= text then return s end
  end
  return text
end

local function steps(row)
  return row.step or row.cycle or row.values or row.frame
end

function OptionsMenu:jpLayout(winW, winH)
  local Classic = require("src.ui.ClassicUI")
  local GameUILayout = require("src.ui.GameUILayout")
  local rect = { x = 0, y = 0, w = winW, h = winH }
  local okU, usable = pcall(GameUILayout.usable, true, rect)
  if okU and type(usable) == "table" and usable.w and usable.w > 0 then
    rect = usable
  end
  local shim = { data = self.game and self.game.data }
  local m = GameUILayout.panelMetrics(shim, { minHeight = 128, rect = rect })
  local width = m.width
  local tap, line = 12, 12
  local native = shim.data and shim.data.font and shim.data.font.composites
  local footerH = tap + 16
  local all = self:visible()
  -- The list draws every row but BACK; BACK is the もどる footer.
  local rows, listIndex = {}, {}
  for i, row in ipairs(all) do
    if not row.cancel then rows[#rows + 1] = row; listIndex[#rows] = i end
  end
  local selected = all[self.index]
  local _, helpText = self:jpInfo(selected)
  local help, helpHeight
  if helpText and not selected.cancel then
    -- jp.91: break at the spaces between Japanese words (and at the catalog's
    -- own line breaks) instead of mid-word, and give long help a third line
    -- so it is not cut off.
    help = helpWrap(Classic, helpText, width - 32)
    local lines = m.height < 240 and 2 or 3
    if #help > lines then
      help[lines] = Classic.clip(table.concat(help, " ", lines), width - 32)
      while #help > lines do table.remove(help) end
    end
    helpHeight = lines * 16 + 8
    footerH = footerH + helpHeight
  end
  local title = "せってい"
  if self.groupId and JP_GROUPS[self.groupId] then title = JP_GROUPS[self.groupId][1] end
  local titleLines = Classic.wrap(title, width - 32)
  local bodyY = 20 + math.min(2, #titleLines) * 16
  local capacity = math.max(tap, m.height - bodyY - footerH)
  local wide = width >= 192
  local baseLabelW = wide and math.floor((width - 64) * 0.58 / 8) * 8 or width - 40
  local baseValueX = wide and 24 + baseLabelW + 8 or 24
  local entries, pages = {}, { { first = 1, last = 0, height = 0 } }
  for i, row in ipairs(rows) do
    local label, _ = self:jpInfo(row)
    local valueText = self:jpValue(row)
    local stepper = valueText ~= nil and steps(row) ~= nil
    local labelWidth, valueX = baseLabelW, baseValueX
    local valueWidth = width - 16 - valueX
    local sameLine = wide
    if valueText == nil then
      labelWidth = width - 40
    else
      local need = math.max(24, Classic.width(valueText) + (stepper and 2 * tap or 0))
      if Classic.width(label) + need <= width - 48 then
        sameLine = true
        labelWidth = width - 48 - need
        valueX = 24 + labelWidth + 8
        valueWidth = need
      end
    end
    local pad = native and (raised(label) or raised(valueText)) and 4 or 0
    local rowLine = pad > 0 and 16 or line
    local labelLines = Classic.wrap(label, labelWidth)
    local valueLines = valueText and Classic.wrap(valueText,
      valueWidth - (stepper and 2 * tap or 0)) or nil
    local function height()
      local n = valueLines and (sameLine and math.max(#labelLines, #valueLines)
        or #labelLines + #valueLines) or #labelLines
      return math.max(tap, pad + (n - 1) * rowLine + line)
    end
    while height() > capacity and (#labelLines > 1 or valueLines and #valueLines > 1) do
      local list = (valueLines and #valueLines > #labelLines) and valueLines or labelLines
      local removed = table.remove(list)
      list[#list] = Classic.clip(list[#list] .. removed, list == labelLines and labelWidth
        or valueWidth - (stepper and 2 * tap or 0))
    end
    local rh = height()
    local page = pages[#pages]
    if page.height + rh > capacity and page.last >= page.first then
      page = { first = i, last = i - 1, height = 0 }
      pages[#pages + 1] = page
    end
    entries[i] = { row = row, index = listIndex[i], label = labelLines, value = valueLines,
      stepper = stepper, y = bodyY + page.height, h = rh, pad = pad, line = rowLine,
      labelX = 24, labelW = labelWidth, valueX = valueX, valueW = valueWidth,
      wide = sameLine }
    page.last, page.height = i, page.height + rh
  end
  -- The page follows the cursor; on BACK it stays where the list was.
  local listPage = self.jpPage or 1
  if selected and not selected.cancel then
    for n, page in ipairs(pages) do
      for i = page.first, page.last do
        if entries[i].index == self.index then listPage = n end
      end
    end
  end
  listPage = math.max(1, math.min(listPage, #pages))
  self.jpPage = listPage
  local current = pages[listPage]
  local used = 0
  for _, page in ipairs(pages) do used = math.max(used, page.height) end
  local height = math.min(m.height, math.max(112, tileCeil(bodyY + used + footerH)))
  local view = GameUILayout.overlay(shim, { anchor = "center", width = width,
    height = height, scale = m.scale, margin = m.margin, rect = m.rect })
  local fy = height - tap - 16
  return {
    view = view, width = width, height = height, tap = tap, title = titleLines,
    entries = entries, first = current.first, last = current.last,
    page = listPage, pages = #pages, help = help,
    helpY = help and (fy - helpHeight + 8) or nil,
    footerY = fy + 8 + math.floor((tap - 8) / 16) * 8,
    navPrevX = width - 16 - tap * 2 - 40, navNextX = width - 16 - tap,
    countX = width - 16 - tap - 40, backSelected = selected and selected.cancel,
  }
end

function OptionsMenu:drawJapanese(winW, winH)
  local Classic = require("src.ui.ClassicUI")
  local Font = require("src.render.Font")
  local G = love.graphics
  Chrome.letterbox(winW, winH, 1, 1, 1)
  local l = self:jpLayout(winW, winH)
  local shim = { data = self.game and self.game.data }
  local width, height = l.width, l.height
  local function cursor(x, y)
    G.setColor(0, 0, 0, 1)
    Font.drawCode(Chrome.CURSOR, x, y)
  end
  local function lines(list, x, y, w, spacing)
    for n, text in ipairs(list or {}) do
      Classic.text(text, x, y + (n - 1) * (spacing or 16), { width = w, clip = true })
    end
  end
  Classic.backdrop(l.view, nil, 0.16)
  Classic.begin(shim, { layout = l.view, paper = { 0, 0, 0, 0 } })
  self.jpBegun = true
  Classic.box(0, 0, width / 8, height / 8)
  lines(l.title, 16, 16, width - 32)
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", 16, 20 + math.min(2, #l.title) * 16 - 8, width - 32, 1)
  for i = l.first, l.last do
    local e = l.entries[i]
    local y = e.y + e.pad
    if e.index == self.index then cursor(12, y) end
    lines(e.label, e.labelX, y, e.labelW, e.line)
    if e.row.group then Classic.text(">", width - 24, y) end
    if e.value then
      local vy = e.wide and y or y + #e.label * e.line
      if e.stepper then
        Classic.text("<", e.valueX + math.floor((l.tap - 8) / 16) * 8, vy)
        Classic.text(">", width - 16 - l.tap + math.floor((l.tap - 8) / 16) * 8, vy)
      end
      local pad = e.stepper and l.tap or 0
      lines(e.value, e.valueX + pad, vy, e.valueW - 2 * pad, e.line)
    end
  end
  if l.help then
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 16, l.helpY - 8, width - 32, 1)
    lines(l.help, 16, l.helpY, width - 32, 16)
  end
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", 16, height - l.tap - 20, width - 32, 1)
  if l.backSelected then cursor(12, l.footerY) end
  -- Same indent as the rows (cursor 12, text 24) so the cursor never sits on
  -- the first kana of もどる.
  Classic.text("もどる", 24, l.footerY, { width = 80, clip = true })
  if l.pages > 1 then
    Classic.text("<", l.navPrevX + math.floor((l.tap - 8) / 16) * 8, l.footerY)
    Classic.text(l.page .. "/" .. l.pages, l.countX, l.footerY,
      { width = 40, align = "center", clip = true })
    Classic.text(">", l.navNextX + math.floor((l.tap - 8) / 16) * 8, l.footerY)
  end
  self.jpBegun = false
  Classic.finish()
end

-- jp.73: on the Japanese carts the settings panel floats over the live map
-- (Game2:drawScene draws the world first when this answers true), the way the
-- Gen 1 settings window sits over its field, instead of a white window.
-- Chrome.letterbox is a no-op while the world is the surround, so the panel's
-- own backdrop dim is all that sits between the map and the box.
function OptionsMenu:worldBehind()
  return isJapanese() and self.game ~= nil and self.game.world ~= nil
    and self.game.world.map ~= nil
end

function OptionsMenu:drawWidescreen(winW, winH)
  if isJapanese() then
    local ok, err = pcall(self.drawJapanese, self, winW, winH)
    if ok then return end
    -- Never leave the player without an OPTION screen: fall back to the
    -- cart layout below if the Japanese panel fails to draw.
    Logger.error("gen2 options (ja) draw failed: %s", tostring(err))
    if self.jpBegun then
      self.jpBegun = false
      pcall(require("src.ui.ClassicUI").finish)
    end
  end
  local G = love.graphics
  Chrome.letterbox(winW, winH, 1, 1, 1)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

OptionsMenu.ROWS = ROWS

return OptionsMenu
