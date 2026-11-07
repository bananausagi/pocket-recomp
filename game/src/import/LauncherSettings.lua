-- SPDX-License-Identifier: GPL-3.0-only
-- Independent settings model for the gen1recomp-jp launcher.
-- Only engine option keys and the public MOD schema contract are shared.
-- A view renders sections/rows, invokes step/action/setText, then calls save.
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local UIStrings = require("src.ui.JapaneseUIStrings")
local UIScale = require("src.ui.JapaneseUIScale")
local Settings = {}

local function optional(name)
  local ok, result = pcall(require, name)
  if ok then return result end
end

local function finite(value, fallback)
  value = tonumber(value)
  if not value or value ~= value or math.abs(value) == math.huge then return fallback end
  return value
end

local function direction(value)
  return finite(value, 1) < 0 and -1 or 1
end

-- Truncate by UTF-8 characters, never in the middle of a Japanese glyph.
local function shortText(value, limit)
  local result, count = {}, 0
  for character in tostring(value or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if count >= limit then break end
    result[#result + 1], count = character, count + 1
  end
  return table.concat(result)
end

function Settings.open(hooks, version)
  hooks = hooks or {}
  local options = hooks.options or SaveData.loadOptions()
  local model = { opts = options, version = version, sections = {}, warnings = {} }
  local translations = {}
  local function language(ja, en)
    return options.jpLauncherLanguage == "en" and en or ja
  end
  local function translated(text)
    return UIStrings.lookup(text, options.jpLauncherLanguage)
  end
  local function caption(object, key, ja, en)
    translations[#translations + 1] = { object, key, ja, en }
    object[key] = language(ja, en)
  end
  function model.refreshLabels()
    for _, entry in ipairs(translations) do
      entry[1][entry[2]] = language(entry[3], entry[4])
    end
  end
  function model.save()
    local result
    if hooks.save then result = hooks.save(options)
    else result = SaveData.saveOptions(options) end
    if result == nil or result == false then
      return nil, language("せっていを ほぞんできません。", "Settings could not be saved.")
    end
    return result
  end
  function model.close()
    local result, err = model.save()
    if err then return result, err end
    if hooks.onClose then hooks.onClose() end
    return result
  end
  local function section(ja, en)
    local item = { rows = {} }
    caption(item, "title", ja, en)
    model.sections[#model.sections + 1] = item
    return item.rows
  end
  local function insert(rows, key, ja, en)
    local item = { id = key }
    caption(item, "label", ja, en)
    rows[#rows + 1] = item
    return item
  end
  -- A candidate is { persisted value, Japanese caption, English caption }.
  local function choice(rows, target, key, ja, en, default, candidates, changed)
    local item = insert(rows, key, ja, en)
    local function current()
      local value = target[key]
      if value == nil then value = default end
      for index, candidate in ipairs(candidates) do
        if candidate[1] == value then return index end
      end
      return 1
    end
    item.value = function()
      local candidate = candidates[current()]
      return language(candidate[2], candidate[3] or candidate[2])
    end
    item.step = function(delta)
      local index = (current() + direction(delta) - 1) % #candidates + 1
      local previous = target[key]
      target[key] = candidates[index][1]
      if changed then changed(target[key]) end
      return previous ~= target[key]
    end
    return item
  end
  local function toggle(rows, target, key, ja, en, default, changed)
    return choice(rows, target, key, ja, en, default,
      { { false, "オフ", "Off" }, { true, "オン", "On" } }, changed)
  end
  local function numeric(rows, target, key, ja, en, default, minimum, maximum, increment)
    local item = insert(rows, key, ja, en)
    item.value = function() return tostring(finite(target[key], default)) end
    item.step = function(delta)
      local old = finite(target[key], default)
      local value = math.min(maximum, math.max(minimum, old + direction(delta) * increment))
      target[key] = value
      return value ~= old
    end
    return item
  end
  local function moduleCycle(rows, target, key, ja, en, moduleName, fallback, labelName)
    local api = optional(moduleName)
    if not api or type(api.cycle) ~= "function" then return end
    local item = insert(rows, key, ja, en)
    item.value = function()
      local value = target[key]
      if value == nil then value = fallback end
      local formatter = api[labelName or "label"]
      local text = tostring(formatter and formatter(value) or value)
      local hz = text:match("^DISPLAY %((%d+)HZ%)$")
      if hz then return language("がめんに あわせる(" .. hz .. "Hz)", text) end
      local names = {
        AUTO = "じどう", HIGH = "たかい", BALANCED = "ふつう", LOW = "ひくい",
        NORMAL = "ふつう", DISPLAY = "フィット",
      }
      return language(names[text] or translated(text), text)
    end
    item.step = function(delta)
      local value = api.cycle(target[key], direction(delta))
      local changed = target[key] ~= value
      target[key] = value
      return changed
    end
  end

  local generation = (GameVersion.VERSIONS[version] or {}).generation or 1
  local japaneseLayout = generation == 1
    and (GameVersion.VERSIONS[version] or {}).language == "ja"
  local game = options
  if generation == 2 then
    if type(options.gold) ~= "table" then options.gold = {} end
    game = options.gold
  end

  local sound = section("おんりょう", "Audio")
  numeric(sound, game, "musicVol", "おんがく", "Music", 7, 0, 7, 1)
  numeric(sound, game, "sfxVol", "こうかおん", "Sound effects", 7, 0, 7, 1)
  if version == "yellow" then
    numeric(sound, game, "pikaVol", "ピカチュウのこえ", "Pikachu voice", 7, 0, 7, 1)
  end
  choice(sound, game, "musicFilter", "おとの フィルタ", "Audio filter", 0,
    { { 0, "オフ", "Off" }, { 1, "よわい", "Light" }, { 2, "ふつう", "Medium" }, { 3, "つよい", "Strong" } })

  local screen = section("がめん", "Display")
  local zoom = optional("src.render.Zoom")
  if zoom then
    local item = insert(screen, "zoom", "ひょうじ ばいりつ", "Zoom")
    item.value = function()
      local offset = finite(game.zoom, 0)
      if offset == 0 then return language("フィット", "Fit") end
      return language(offset < 0 and "ちいさく " or "おおきく ", offset < 0 and "Out " or "In ") .. math.abs(offset)
    end
    item.step = function(delta)
      local old = game.zoom
      zoom.nudgeOptions(game, direction(delta), zoom.windowFitScale())
      return game.zoom ~= old
    end
  end
  if generation == 1 then
    choice(screen, game, "jpDotMatrix", "ドットマトリクス", "Dot matrix", 0,
      { { 0, "オフ", "Off" }, { 1, "よわい", "Light" }, { 2, "ふつう", "Medium" }, { 3, "つよい", "Strong" } })
    local size=insert(screen,"jpDialogScale","まどと もじの おおきさ","Window size")
    caption(size,"description","まどと もじを まとめて\n5だんかいで ちょうせいします。",
      "Adjust window and text size together in five steps.")
    size.value=function()return UIScale.label(game.jpDialogScale,options.jpLauncherLanguage=="en")end
    size.step=function(delta)
      local old=game.jpDialogScale
      game.jpDialogScale=UIScale.step(old,delta)
      return game.jpDialogScale~=old
    end
    if not japaneseLayout then
      choice(screen, game, "uiLayout", "メニューの ばしょ", "Menu placement", "centered",
        { { "centered", "ちゅうおう", "Centered" }, { "dynamic", "がめんの はし", "Dynamic" } })
    end
  end
  local palette = optional(generation == 2 and "src.render.GbcPalette" or "src.render.PaletteFX")
  if palette and palette.MODES then
    local candidates = {}
    for _, mode in ipairs(palette.MODES) do
      local colors=require("src.ui.JapaneseColorSettings")
      candidates[#candidates + 1] = generation==1
        and {mode,colors.label(mode,false,version),colors.label(mode,true,version)}
        or {mode,palette.modeLabel(mode),palette.modeLabel(mode)}
    end
    if #candidates > 0 then
      local color = choice(screen, game, generation == 2 and "color" or "colors", "いろ", "Color palette", generation == 2 and "gbc" or "redpp", candidates,
        function() game.palette = "" end)
      if generation==1 then
        color.descriptionFor=function()
          local colors=require("src.ui.JapaneseColorSettings")
          local english=options.jpLauncherLanguage=="en"
          if type(game.palette)=="string" and game.palette~="" then return colors.customDescription(english) end
          return colors.description(game.colors or "redpp",english,version)
        end
      end
      local modeValue = color.value
      color.value = function()
        if type(game.palette) == "string" and game.palette ~= "" then
          return language("カスタム", "Custom")
        end
        return modeValue()
      end
    end
  end
  choice(screen, game, "tilt", "がめんの かたむき", "Perspective tilt", 0,
    { { 0, "オフ", "Off" }, { 1, "よわい", "Light" }, { 2, "ふつう", "Medium" }, { 3, "つよい", "Strong" } })
  if japaneseLayout then
    local view = insert(screen, "pipeline:voxel", "3Dの みかた", "3D view")
    local labels={"オフ","ジオラマ","15ど","35ど","50ど","75ど","いちにんしょう","さんにんしょう"}
    local english={"Off","Diorama","15°","35°","50°","75°","First person","Third person"}
    local function viewLevel()
      local bucket=type(options.pipelines)=="table" and options.pipelines or {}
      return math.max(0,math.min(7,math.floor(tonumber(bucket.voxel) or 1)))
    end
    view.value=function()local i=viewLevel()+1;return language(labels[i],english[i])end
    view.step=function(delta)
      options.pipelines=type(options.pipelines)=="table" and options.pipelines or {}
      local value=(viewLevel()+direction(delta))%8;options.pipelines.voxel=value
      local live=optional("src.render.Pipelines")
      if live and live.get("voxel")then live.setLevel("voxel",value)end
      return true
    end
    -- The bundled 3D renderer uses the same pipeline level in the field and
    -- battle. The launcher can edit it before MOD code is loaded; never copy
    -- the obsolete jpBattleBlur value or reset another saved pipeline here.
    local row = insert(screen, "pipeline:tiltshift", "とおくの ぼかし", "Distance blur")
    caption(row, "description", "フィールドと せんとうで つかいます。\nとおくの けしきを ぼかす つよさです。",
      "Blur strength for distant scenery in both the field and battles.")
    local function level()
      local bucket = type(options.pipelines) == "table" and options.pipelines or {}
      return math.max(0, math.min(5, math.floor(finite(bucket.tiltshift, SaveData.DEFAULT_DISTANCE_BLUR))))
    end
    row.value = function() return level() == 0 and language("なし", "Off") or tostring(level()) end
    row.step = function(delta)
      local selected = (level() + direction(delta)) % 6
      if type(options.pipelines) ~= "table" then options.pipelines = {} end
      options.pipelines.tiltshift = selected
      local pipelines = optional("src.render.Pipelines")
      if pipelines and pipelines.get("tiltshift") then pipelines.setLevel("tiltshift", selected) end
      return true
    end
  end
  -- jp.70: the top-screen-only window reaches Gen 2 as well. Its keys are
  -- flat (shared with Gen 1), so the rows edit `options`, not the gold block.
  if generation == 2 and (GameVersion.VERSIONS[version] or {}).language == "ja" then
    local preferences = require("src.ui.JapaneseConvenienceSettings")
    for _, descriptor in ipairs(preferences.rows) do
      if descriptor.id:match("^jpTopScreen") then
        local row = insert(screen, descriptor.id, descriptor.ja, descriptor.en)
        row.value = function() return preferences.value(descriptor, options, options.jpLauncherLanguage == "en") end
        row.step = function(delta) return preferences.step(descriptor, options, delta) end
      end
    end
    -- jp.86: the Gen 2 3D field's とおくの ぼかし (jp3DBlur in the gold block,
    -- read by src/world/gen2/Field3D.lua), the same 0..5 scale as Gen 1's
    -- pipeline:tiltshift row above, so the session menu has the item too.
    local row = insert(screen, "jp3DBlur", "とおくの ぼかし (3D)", "Distance blur (3D)")
    caption(row, "description", "3Dフィールドと せんとうで つかいます。\nとおくの けしきを ぼかす つよさです。",
      "Blur strength for distant scenery in the 3D field and battles.")
    local function level()
      return math.max(0, math.min(5, math.floor(finite(game.jp3DBlur, 1))))
    end
    row.value = function() return level() == 0 and language("なし", "Off") or tostring(level()) end
    row.step = function(delta)
      game.jp3DBlur = (level() + direction(delta)) % 6
      return true
    end
  end
  choice(screen, game, "uiLetterbox", "まわりの いろ", "Border color", "auto",
    { { "auto", "じどう", "Auto" }, { "black", "くろ", "Black" }, { "white", "しろ", "White" }, { "palette", "ゲームの いろ", "Palette" } })
  choice(screen, options, "screenPos", "がめんの いち", "Screen position", "center",
    { { "center", "ちゅうおう", "Center" }, { "upper", "すこし うえ", "Upper" }, { "top", "いちばん うえ", "Top" } })
  choice(screen, options, "videoMode", "ひょうじ モード", "Window mode", "windowed",
    { { "windowed", "ウインドウ", "Window" }, { "borderless", "ぜんがめん", "Fullscreen" } })
  moduleCycle(screen, game, "fpsCap", "フレームレート", "Frame limit", "src.core.FrameCap", 60)
  moduleCycle(screen, game, "performance", "えがく はやさ", "Performance", "src.core.Performance", "auto")

  local battle = section("かいわと バトル", "Dialogue and battle")
  if japaneseLayout then
    local preferences = require("src.ui.JapaneseConvenienceSettings")
    local effectSections={}
    for _, descriptor in ipairs(preferences.rows) do
      local target=battle
      if descriptor.group then
        if not effectSections[descriptor.group] then
          local battleFx=descriptor.group=='battleEffects'
          effectSections[descriptor.group]=section(battleFx and 'バトルの えんしゅつ' or 'フィールドの えんしゅつ',
            battleFx and 'Battle effects' or 'Field effects')
        end
        target=effectSections[descriptor.group]
      end
      local row = insert(target, descriptor.id, descriptor.ja, descriptor.en)
      row.value = function() return preferences.value(descriptor, game, options.jpLauncherLanguage == "en") end
      row.step = function(delta) return preferences.step(descriptor, game, delta) end
    end
    choice(battle, game, "jpBattleSpacing", "せんとうの かんかく", "Battle spacing", "wide",
      { { "normal", "ふつう", "Normal" }, { "wide", "ひろい", "Wide" },
        { "wider", "とても ひろい", "Wider" } })
  end
  if generation == 2 then
    choice(battle, game, "textSpeed", "もじの はやさ", "Text speed", "MID",
      { { "FAST", "はやい", "Fast" }, { "MID", "ふつう", "Normal" }, { "SLOW", "おそい", "Slow" } })
    toggle(battle, game, "battleScene", "バトルの アニメ", "Battle animation", true)
    choice(battle, game, "battleStyle", "バトルの ルール", "Battle style", "SHIFT",
      { { "SHIFT", "いれかえ", "Shift" }, { "SET", "かちぬき", "Set" } })
  else
    choice(battle, game, "textSpeed", "もじの はやさ", "Text speed", 3,
      { { 1, "はやい", "Fast" }, { 3, "ふつう", "Normal" }, { 5, "おそい", "Slow" } })
    toggle(battle, game, "animations", "バトルの アニメ", "Battle animation", true)
    choice(battle, game, "battleStyle", "バトルの ルール", "Battle style", "shift",
      { { "shift", "いれかえ", "Shift" }, { "set", "かちぬき", "Set" } })
  end
  -- JP windows share the Window size control and responsive HUD placement.
  -- Keep legacy values for other engines/import-export without exposing
  -- switches that cannot select the advertised JP scale or HUD position.
  if not japaneseLayout then
    choice(battle, game, "battleLayout", "バトルの がめん", "Battle layout", "og",
      { { "og", "ふつう", "Original" }, { "wide", "よこなが", "Wide" } },
      function(value)
        if value == "og" then game.battleHud = "standard" end
      end)
    choice(battle, game, "battleFit", "バトルの ばいりつ", "Battle scaling", "fixed",
      { { "fixed", "せいすうばい", "Integer" }, { "fill", "フィット", "Fill" } })
    local hud = choice(battle, game, "battleHud", "バトルの じょうほう", "Battle HUD", "standard",
      { { "standard", "ふつう", "Standard" }, { "extended", "ひろい", "Extended" } })
    local hudStep = hud.step
    hud.step = function(delta)
      if game.battleLayout ~= "wide" then return false end
      return hudStep(delta)
    end
  end
  if generation == 1 then
    moduleCycle(battle, game, "speedOverworld", "いどうの はやさ", "Overworld speed", "src.core.GameSpeed", 1, "levelLabel")
    moduleCycle(battle, game, "speedBattle", "バトルの はやさ", "Battle speed", "src.core.GameSpeed", 1, "levelLabel")
    moduleCycle(battle, game, "speedMenu", "メニューの はやさ", "Menu speed", "src.core.GameSpeed", 1, "levelLabel")
  else
    moduleCycle(battle, game, "speed", "ゲームの はやさ", "Game speed", "src.core.GameSpeed", 1, "levelLabel")
  end

  local controls = section("そうさ", "Controls")
  if type(options.touchControls) ~= "table" then options.touchControls = {} end
  toggle(controls, options.touchControls, "enabled", "タッチボタン", "Touch buttons", true)
  if generation ~= 1 then
    toggle(controls, options, "hotbar", "ショートカット", "Shortcut bar", true)
  end
  choice(controls, options, "haptics", "ボタンの しんどう", "Vibration", "light",
    { { "off", "オフ", "Off" }, { "light", "よわい", "Light" }, { "normal", "ふつう", "Medium" }, { "strong", "つよい", "Strong" } })
  local orientation = optional("src.core.Orientation")
  if orientation and (orientation.isAndroid() or orientation.isIOS()) then
    choice(controls, options, "orientation", "がめんの むき", "Orientation", "auto",
      { { "auto", "じどう", "Auto" }, { "portrait", "たて", "Portrait" }, { "landscape", "よこ", "Landscape" }, { "reverseLandscape", "ぎゃくむきの よこ", "Reverse landscape" } },
      function(value) orientation.apply(value) end)
  end
  for _, entry in ipairs({
    { "editTouchAreas", "タッチエリアの はいち", "Arrange touch areas" },
    { "editTouchControls", "ボタンを はいち", "Arrange touch buttons" },
    { "openSkinStudio", "スキンを へんしゅう", "Edit skin" },
  }) do
    local callback = (entry[1] ~= "editTouchAreas" or japaneseLayout) and hooks[entry[1]]
    if callback then
      local item = insert(controls, entry[1], entry[2], entry[3])
      caption(item, "actionLabel", "ひらく", "Open")
      item.action = function()
        local result = model.save()
        if not result then return false end
        callback()
        return false
      end
    end
  end
  local reset = insert(controls, "resetBindings", "はいちを もどす", "Reset button layout")
  caption(reset, "actionLabel", "もとに もどす", "Reset")
  reset.danger = true
  reset.action = function()
    options.bindings = nil
    options.touchControls.layouts = nil
    options.touchControls.positions = nil
    options.jpTouchAreas = nil
    return true
  end

  local app = section("ホーム", "Launcher")
  choice(app, options, "jpLauncherLanguage", "ひょうじの ことば", "Language / 表示言語", "ja",
    { { "ja", "にほんご", "にほんご" }, { "en", "English", "English" } }, model.refreshLabels)
  toggle(app, options, "reduceMotion", "うごきを へらす", "Reduce motion", false,
    function(value)
      local transition = optional("src.ui.kit.Transition")
      if transition then transition.reduceMotion = value end
    end)

  if hooks.importSettings or hooks.exportSettings then
    local files = section("せっていファイル", "Settings files")
    for _, entry in ipairs({
      { "exportSettings", "せっていを かきだす", "Export settings" },
      { "importSettings", "せっていを よみこむ", "Import settings" },
    }) do
      if hooks[entry[1]] then
        local key = entry[1]
        local item = insert(files, key, entry[2], entry[3])
        item.action = function() return hooks[key](options) end
      end
    end
  end

  -- Native MOD schemas are supplied by the independent discovery module.
  -- No MOD code is executed by this settings model.
  local mods = optional("src.mods.LauncherMods")
  local schemas = {}
  if mods and mods.optionSchemas then
    local ok, result = pcall(mods.optionSchemas, version, options)
    if ok and type(result) == "table" then schemas = result
    elseif not ok then model.warnings[#model.warnings + 1] = tostring(result) end
  end
  for _, mod in ipairs(schemas) do
    if type(mod.id) == "string" and type(mod.schema) == "table" then
      local name = tostring(mod.name or mod.id)
      local rows = section(UIStrings.lookup(name), name)
      model.sections[#model.sections].modId=mod.id
      local byKey = {}
      for _, definition in ipairs(mod.schema) do
        if type(definition) == "table" and type(definition.key) == "string" then
          byKey[definition.key] = definition
        end
      end
      local function stored()
        local all = options.modOptions
        return type(all) == "table" and type(all[mod.id]) == "table" and all[mod.id] or {}
      end
      local function get(definition)
        local value = stored()[definition.key]
        if value == nil then return definition.default end
        return value
      end
      local function allowed(definition)
        if SaveData.isSafeMode(options) then return false end
        local condition = definition.visible_if
        if condition == nil then return true end
        if type(condition) ~= "table" or type(condition.key) ~= "string" then return false end
        local value = get(byKey[condition.key] or { key = condition.key })
        if condition.equals ~= nil then return value == condition.equals end
        if condition.not_equals ~= nil then return value ~= condition.not_equals end
        return false
      end
      local function write(definition, value)
        if not allowed(definition) then return false end
        if type(options.modOptions) ~= "table" then options.modOptions = {} end
        if type(options.modOptions[mod.id]) ~= "table" then options.modOptions[mod.id] = {} end
        options.modOptions[mod.id][definition.key] = value
        return true
      end
      for _, definition in ipairs(mod.schema) do
        if type(definition) == "table" and type(definition.key) == "string" and definition.key ~= "" then
          local kind = definition.type
          if kind == "toggle" or kind == "number" or kind == "choice" or kind == "text" then
            local name = tostring(definition.label or definition.key)
            local item = { id = mod.id .. "." .. definition.key, safeModeBlocked = true }
            caption(item, "label", UIStrings.lookup(name), name)
            if definition.description then
              caption(item, "description", UIStrings.lookup(definition.description), definition.description)
            end
            if definition.help then caption(item, "help", UIStrings.lookup(definition.help), definition.help) end
            rows[#rows + 1] = item
            local choices = {}
            if kind == "choice" then
              for _, candidate in ipairs(type(definition.choices) == "table" and definition.choices or {}) do
                if type(candidate) == "table" and candidate[2] ~= nil then choices[#choices + 1] = candidate end
              end
            end
            local function index()
              for i, candidate in ipairs(choices) do if candidate[2] == get(definition) then return i end end
              return 1
            end
            item.value = function()
              if not allowed(definition) then return language("へんこう できません", "Unavailable") end
              if kind == "toggle" then return get(definition) and language("オン", "On") or language("オフ", "Off") end
              if kind == "choice" then
                local label=choices[index()] and choices[index()][1]
                if not label then return "—" end
                -- Resolve setting-specific captions before the general glossary
                -- translates e.g. WIDE into a battle-layout caption.
                if japaneseLayout then
                  label=language(require("src.ui.JapaneseSettingsCatalog").value(item.id,label),label)
                end
                return translated(label)
              end
              return tostring(get(definition) or "")
            end
            if kind == "text" then
              local limit = math.max(1, math.floor(finite(definition.maxLen, 64)))
              item.editText = { maxLen = limit }
              item.setText = function(value) return write(definition, shortText(value, limit)) end
            else
              item.step = function(delta)
                if kind == "toggle" then return write(definition, not get(definition)) end
                if kind == "choice" then
                  if #choices == 0 then return false end
                  return write(definition, choices[(index() + direction(delta) - 1) % #choices + 1][2])
                end
                local value = finite(get(definition), 0) + direction(delta) * math.abs(finite(definition.step, 1))
                value = math.max(finite(definition.min, -math.huge), math.min(finite(definition.max, math.huge), value))
                return write(definition, value)
              end
            end
          end
        end
      end
      if #rows > 0 then
        local defaults = insert(rows, mod.id .. ".reset", "MODを もとに もどす", "Reset this MOD")
        caption(defaults, "actionLabel", "もとに もどす", "Reset")
        defaults.action = function()
          if SaveData.isSafeMode(options) then return false end
          -- SaveData merges MOD keys with disk, so persist each default
          -- explicitly; deleting the bucket would restore the disk values.
          if type(options.modOptions) ~= "table" then options.modOptions = {} end
          if type(options.modOptions[mod.id]) ~= "table" then options.modOptions[mod.id] = {} end
          for key, definition in pairs(byKey) do
            options.modOptions[mod.id][key] = definition.default
          end
          return true
        end
      else
        table.remove(model.sections)
      end
    end
  end
  if japaneseLayout then
    local catalog=require("src.ui.JapaneseSettingsCatalog")
    local buckets,ordered={},{}
    for _,group in ipairs(catalog.groups)do
      local target={id=group.id,rows={},children={}}
      caption(target,"title",group.ja,group.en)
      caption(target,"description",group.description,group.help)
      buckets[group.id]=target;ordered[#ordered+1]=target
    end
    local function english(object,key)
      for _,entry in ipairs(translations)do
        if entry[1]==object and entry[2]==key then return entry[4]end
      end
      return object[key]
    end
    local function route(row)
          if row.value then
            local original=row.value
            row.value=function(...)
              local value=original(...)
              return language(catalog.value(row.id,value),value)
            end
          end
          if not catalog.visible(row.id)then return end
          local entry=catalog.entry(row.id)
          if entry then
            local en=english(row,"label")
            caption(row,"label",entry[1],en)
            caption(row,"description",entry[2],english(row,"description")or("Change "..tostring(en).."."))
          end
          local target=buckets[catalog.group(row.id)]
          target.rows[#target.rows+1]=row
    end
    for _,old in ipairs(model.sections)do
      if old.modId and old.modId~="DRAMALESS_SHAPE" and old.modId~="VOXEL_ASCENDANT"then
        local remaining={}
        for _,row in ipairs(old.rows)do
          if catalog.group(row.id)~='mods' then route(row)
          else remaining[#remaining+1]=row end
        end
        if #remaining>0 then
          old.rows=remaining;old.id="mod."..old.modId
          caption(old,"description","このMODの ついかきのうを かえます。","Change this MOD's features.")
          buckets.mods.children[#buckets.mods.children+1]=old
        end
      else
        for _,row in ipairs(old.rows)do route(row)end
      end
    end
    model.sections={}
    for _,group in ipairs(ordered)do
      catalog.sort(group.rows,group.id)
      if #group.rows>0 or #group.children>0 then model.sections[#model.sections+1]=group end
    end
  end
  return model
end

return Settings
