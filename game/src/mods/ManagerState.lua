-- Mod manager v2 (18-mod-manager-ux.md): one stack state routing a fixed
-- set of screens -- list (MODS/PROF/ERRS tabs), detail, options,
-- permissions, errors, apply -- over mapped input, so gamepad and touch
-- drive it like any other menu.  Toggles resolve their dependency closure
-- before they land, edits stage until one apply/restart, and safe mode is
-- read from Runtime.safeMode (19 owns the detection).
local Font = require("src.render.Font")
local GameVersion = require("src.core.GameVersion")
local ModTargets = require("src.mods.ModTargets")
local Runtime = require("src.mods.Runtime")
local SafePath = require("src.mods.SafePath")
local Sandbox = require("src.mods.Sandbox")
local SaveData = require("src.core.SaveData")
local Semver = require("src.mods.Semver")
local Version = require("src.core.Version")
local Theme = require("src.ui.Theme")
local OptionRows = require("src.ui.OptionRows")
local Strings = require("src.core.Strings")
local ModProfile = require("src.mods.ModProfile")
local Classic = require("src.ui.ClassicUI")
local GameUILayout = require("src.ui.GameUILayout")

local ManagerState = {}
ManagerState.__index = ManagerState
ManagerState.isOpaque = true
-- stamped here as well as by Screens.push so the F10 toggle in
-- Game:keypressed recognizes a directly-pushed instance
ManagerState.screenId = "ManagerState"

-- Same as OptionsMenu: without this, title LOGO zones leak through when
-- MODS is opened from the title-screen options path.
function ManagerState:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

-- the charmap has no * ~ + < > glyphs, so the status gutter uses what it
-- does have: staged-awaiting-restart, disabled, errored, dep-unhealthy
-- `skipped` is not a fault: the mod is enabled and intact, this game is just
-- not the generation it declared (Loader:_gateGeneration)
local GLYPH = { staged = ".", disabled = "-", errored = "!", blocked = "?",
                skipped = "-" }

local TABS = { "MODS", "PROFILES", "ERRORS" }
local TAB_LINE = { "[MODS] PROF ERRS", "MODS [PROF] ERRS", "MODS PROF [ERRS]" }

local LIST_ROWS = 4 -- sixteen-pixel rows, including Japanese voiced marks

-- what the mod declared it does, shown before the player enables it
local PERMISSION_ROWS = {
  engine_internals = { glyph = "!", text = "PATCHES ENGINE CODE" },
  network = { glyph = "!", text = "USES THE NETWORK" },
  filesystem = { glyph = "!", text = "READS/WRITES FILES" },
}

local OPTION_TYPES = { toggle = true, choice = true, number = true, text = true }

local function drawText(text, x, y)
  Font.draw(Strings(tostring(text or "")), x, y)
end

local function clipText(text, cols)
  text = Strings(tostring(text or ""))
  local spans = Font.split(text)
  local n = Font.spansFitting(spans, cols * 8)
  return n > 0 and text:sub(1, spans[n].to) or ""
end

local function wrap(text, width)
  local lines = {}
  for paragraph in Strings(tostring(text or "")):gmatch("[^\n]+") do
    local line = ""
    for word in paragraph:gmatch("%S+") do
      while Font.width(word) > width * 8 do
        if line ~= "" then
          lines[#lines + 1] = line
          line = ""
        end
        local part = clipText(word, width)
        if part == "" then part = word:sub(1, Font.split(word)[1].to) end
        lines[#lines + 1] = part
        word = word:sub(#part + 1)
      end
      if word ~= "" then
        local candidate = line == "" and word or line .. " " .. word
        if Font.width(candidate) > width * 8 and line ~= "" then
          lines[#lines + 1] = line
          line = word
        else
          line = candidate
        end
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

local function clampIndex(i, n)
  if i < 1 then return n end
  if i > n then return 1 end
  return i
end

-- enabled at boot is the loader's verdict, not the user's flag: setEnabled
-- flips manifest.enabled but never state, so the difference is exactly the
-- staged-since-boot set and survives closing the manager
local function bootEnabled(m)
  return m.state ~= "disabled"
end

-- ------- pure toggle resolution
-- The closure a requested flip drags along (18 "enable/disable flow").
-- mods is id -> status manifest; enabledSet is the current desired set.
-- Module-level so tests table-drive it without a game.

function ManagerState.resolveToggle(mods, id, want, enabledSet)
  local r = { apply = {}, alsoEnable = {}, alsoDisable = {},
              conflicts = {}, missing = {}, badVersion = {} }
  local function enabledAfter(mid)
    if r.apply[mid] ~= nil then return r.apply[mid] end
    return enabledSet[mid] and true or false
  end
  local function enableWalk(mid, root)
    if r.apply[mid] then return end
    r.apply[mid] = true
    if not root then r.alsoEnable[#r.alsoEnable + 1] = mid end
    local m = mods[mid]
    if not m then return end
    if m.game_version and not Semver.satisfies(Version.engine, m.game_version) then
      r.badVersion[#r.badVersion + 1] =
        { id = mid, need = m.game_version, got = Version.engine, engine = true }
    end
    for _, spec in ipairs(m.dependencySpecs or {}) do
      local dep = mods[spec.id]
      if not dep then
        r.missing[#r.missing + 1] = spec.id
      elseif spec.range and not Semver.satisfies(dep.version, spec.range) then
        r.badVersion[#r.badVersion + 1] =
          { id = spec.id, need = spec.range, got = dep.version }
      elseif not enabledAfter(spec.id) then
        enableWalk(spec.id, false)
      end
    end
  end
  local function disableWalk(mid, root)
    if r.apply[mid] == false then return end
    r.apply[mid] = false
    if not root then r.alsoDisable[#r.alsoDisable + 1] = mid end
    -- reverse hard deps: whoever needs mid has to switch off with it
    for otherId, other in pairs(mods) do
      if enabledAfter(otherId) then
        for _, spec in ipairs(other.dependencySpecs or {}) do
          if spec.id == mid then
            disableWalk(otherId, false)
            break
          end
        end
      end
    end
  end
  if want then enableWalk(id, true) else disableWalk(id, true) end
  if want then
    -- a conflict blocks whichever side declared it
    for mid in pairs(r.apply) do
      local m = mods[mid]
      for _, spec in ipairs((m and m.conflictSpecs) or {}) do
        local other = mods[spec.id]
        if other and spec.id ~= mid and enabledAfter(spec.id)
            and (not spec.range or Semver.satisfies(other.version, spec.range)) then
          r.conflicts[#r.conflicts + 1] = spec.id
        end
      end
      for otherId, other in pairs(mods) do
        if otherId ~= mid and enabledAfter(otherId) then
          for _, spec in ipairs(other.conflictSpecs or {}) do
            if spec.id == mid and (not spec.range
                or not m or Semver.satisfies(m.version, spec.range)) then
              r.conflicts[#r.conflicts + 1] = otherId
            end
          end
        end
      end
    end
  end
  return r
end

-- ------- lifecycle

function ManagerState.new(game)
  return setmetatable({
    game = game,
    floatingPanel = GameUILayout.enabled(game) and true or false,
    systemMenuPause = GameUILayout.enabled(game) and true or false,
    isOpaque = not GameUILayout.enabled(game),
    screen = "list",
    tab = 1,
    cursor = 1,
    scroll = 1,
    backStack = {},
    descScroll = 1,
    restartPending = false,
  }, ManagerState)
end

function ManagerState:enter()
  self:refresh()
  -- #593: the setup that existed before profiles shipped becomes PROFILE 1
  -- the first time the manager opens, so switching away from it is always a
  -- round trip.  Seeded here rather than at boot because profiles are only
  -- ever read on this screen.
  local seeded = ModProfile.ensureFirst(self:optionsTable(),
    self.status.available, self:modOptionsTable())
  if seeded then
    self:persistOptions()
    self:refresh()
  end
  if Runtime.safeMode then
    self.banner = "SAFE MODE - ALL MODS OFF"
  end
  self:snapCursor()
end

function ManagerState:refresh()
  local loader = self.game.mods
  self.status = (loader and loader.status and loader:status())
    or self.game.modStatus or { available = {}, errors = {} }
  self.byId = {}
  for _, m in ipairs(self.status.available or {}) do
    self.byId[m.id] = m
  end
  if self.currentMod then
    self.currentMod = self.byId[self.currentMod.id]
  end
  -- gen2Pending is not in stagedList: the Gen 2 override is not an enable flag
  -- and there is nothing in `available` to diff it against
  self.restartPending = #self:stagedList() > 0 or self.gen2Pending == true
  -- a live set that drifted off the named profile reverts to ad-hoc
  local opts = self:optionsTable()
  if opts.activeProfile then
    local p = self:findProfile(opts.activeProfile)
    if not p or not self:matchesProfile(p) then
      opts.activeProfile = nil
    end
  end
end

function ManagerState:optionsTable()
  local save = self.game.save
  return (save and save.options) or {}
end

-- Per-mod option values as persisted (options.modOptions; setOption below is
-- the only writer).  A profile captures this alongside the enable set.
function ManagerState:modOptionsTable()
  return self:optionsTable().modOptions or {}
end

function ManagerState:manifestMap()
  return self.byId or {}
end

function ManagerState:enabledSet()
  local set = {}
  for _, m in ipairs(self.status.available or {}) do
    if m.enabled then set[m.id] = true end
  end
  return set
end

function ManagerState:isStaged(m)
  return (m.enabled and true or false) ~= bootEnabled(m)
end

function ManagerState:stagedList()
  local out = {}
  for _, m in ipairs(self.status.available or {}) do
    if self:isStaged(m) then out[#out + 1] = m end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- The game this manager judges targets against: the running version, unless a
-- harness injected a loader generation that disagrees with it (Loader.new
-- opts.generation), where only the generation can be trusted.
function ManagerState:targetGame()
  local loader = self.game and self.game.mods
  local gen = loader and loader.generation
  local version = GameVersion.get()
  if gen and GameVersion.generation(version) ~= gen then return nil, gen end
  return version, GameVersion.generation(version)
end

-- will this mod run on this game at all (src/mods/ModTargets.lua, the same
-- derivation the launcher panel shows)
function ManagerState:runsHere(m)
  local version, gen = self:targetGame()
  return ModTargets.runsHere(m, version, gen, m.gen2Forced)
end

function ManagerState:glyphFor(m)
  if self:isStaged(m) then return GLYPH.staged end
  if not m.enabled then return GLYPH.disabled end
  if m.state == "wrong_generation" then return GLYPH.skipped end
  if not self:runsHere(m) then return GLYPH.skipped end
  if m.state == "blocked_dependency" then return GLYPH.blocked end
  if m.error then return GLYPH.errored end
  return " "
end

-- ------- row models
-- Every screen is one flat row list the shared cursor walks; headers are
-- skipped by the cursor and drawn dim.

function ManagerState:modRows()
  local rows = {}
  local byCategory, categories = {}, {}
  for _, m in ipairs(self.status.available or {}) do
    local cat = m.category or "OTHER"
    if not byCategory[cat] then
      byCategory[cat] = {}
      categories[#categories + 1] = cat
    end
    table.insert(byCategory[cat], m)
  end
  table.sort(categories)
  for _, cat in ipairs(categories) do
    rows[#rows + 1] = { header = true, label = cat }
    for _, m in ipairs(byCategory[cat]) do
      rows[#rows + 1] = { mod = m, label = m.name or m.id,
                          glyph = self:glyphFor(m) }
    end
  end
  if #rows == 0 then
    rows[1] = { header = true, label = Strings("NO MODS INSTALLED") }
  end
  return rows
end

function ManagerState:profileRows()
  local rows = {}
  local opts = self:optionsTable()
  for _, p in ipairs(opts.modProfiles or {}) do
    rows[#rows + 1] = { profile = p, label = p.name,
      glyph = opts.activeProfile == p.name and GLYPH.errored or " " }
  end
  rows[#rows + 1] = { saveAs = true, label = Strings("SAVE CURRENT AS..") }
  -- #593 sharing: EXPORT writes the focused profile to profiles/*.g1rmodlist
  -- in the save dir, IMPORT reads back every file dropped in that folder.
  rows[#rows + 1] = { exportProfile = true, label = Strings("EXPORT..") }
  rows[#rows + 1] = { importProfile = true, label = Strings("IMPORT..") }
  rows[#rows + 1] = { adhoc = true,
    label = opts.activeProfile and Strings("[AD-HOC]") or Strings("[AD-HOC] (LIVE)") }
  return rows
end

function ManagerState:errorLines(mod)
  local lines = {}
  if mod and mod.error then
    for _, line in ipairs(wrap(Strings("FAILED: %s", mod.error), 16)) do
      lines[#lines + 1] = line
    end
  end
  for _, err in ipairs(self.status.errors or {}) do
    for _, line in ipairs(wrap(err, 16)) do
      lines[#lines + 1] = line
    end
  end
  if #lines == 0 then lines[1] = Strings("NO ERRORS") end
  return lines
end

function ManagerState:errorRows(mod)
  local rows = {}
  for _, line in ipairs(self:errorLines(mod)) do
    rows[#rows + 1] = { label = line, inert = true }
  end
  return rows
end

function ManagerState:detailRows(m)
  local rows = {}
  if Runtime.safeMode then
    rows[#rows + 1] = { label = "SAFE MODE ACTIVE", inert = true }
  else
    rows[#rows + 1] = { label = m.enabled and "DISABLE" or "ENABLE",
      action = function() self:beginToggle(m) end }
  end
  if not Runtime.safeMode and self:schemaFor(m) then
    rows[#rows + 1] = { label = Strings("OPTIONS.."),
      action = function() self:openOptions(m) end }
  end
  if m.permissions and #m.permissions > 0 then
    rows[#rows + 1] = { label = Strings("PERMISSIONS.."),
      action = function() self:goTo("permissions") end }
  end
  -- The manifest's games list is the AUTHOR's claim, and a mod written before
  -- the field existed can never carry one, so the player gets the override
  -- here rather than being told to edit a manifest they do not own.  Exactly
  -- the answer the loader gates on (Loader:_gateGeneration reads the same
  -- ModTargets.supports), so the row appears only where a restart can change
  -- what this mod does.
  local loader = self.game.mods
  local version, gen = self:targetGame()
  if loader and loader.setGen2Forced and not Runtime.safeMode
      and not ModTargets.supports(m, version, gen) then
    rows[#rows + 1] = {
      label = m.gen2Forced and Strings("DON'T TRY HERE") or Strings("TRY HERE ANYWAY"),
      action = function() self:toggleGen2Force(m) end }
  end
  -- which games the mod says it is for, in the one place the player is
  -- already looking when they wonder why it did not run
  rows[#rows + 1] = { inert = true, label = Strings("FOR %s", ModTargets.chip(m)) }
  if m.github then
    rows[#rows + 1] = { inert = true, label = "GH " .. m.github }
  end
  if m.experimental then
    rows[#rows + 1] = { inert = true, label = "EXPERIMENTAL" }
  end
  if m.error then
    rows[#rows + 1] = { label = Strings("VIEW ERROR.."),
      action = function() self:goTo("errors") end }
  end
  rows[#rows + 1] = { label = Strings("BACK"), action = function() self:goBack() end }
  return rows
end

function ManagerState:applyRows()
  local rows = {}
  rows[#rows + 1] = { label = Strings("APPLY & RESTART"), action = function()
    self:openConfirm({ "RESTART NOW?" }, function() self:restartGame() end)
  end }
  rows[#rows + 1] = { label = Strings("DISCARD CHANGES"), action = function()
    self:discardChanges()
  end }
  rows[#rows + 1] = { label = Strings("BACK"), action = function() self:goBack() end }
  return rows
end

function ManagerState:permissionRows(m)
  local rows = {}
  for _, name in ipairs(m.permissions or {}) do
    local info = PERMISSION_ROWS[name]
    rows[#rows + 1] = { inert = true,
      glyph = info and info.glyph or "?",
      label = info and info.text or name }
  end
  if #rows == 0 then
    rows[1] = { inert = true, label = Strings("DATA & API ONLY") }
  end
  return rows
end

function ManagerState:rowsForScreen()
  if self.screen == "list" then
    if self.tab == 1 then return self:modRows() end
    if self.tab == 2 then return self:profileRows() end
    return self:errorRows(nil)
  elseif self.screen == "detail" then
    return self.currentMod and self:detailRows(self.currentMod) or {}
  elseif self.screen == "errors" then
    return self:errorRows(self.currentMod)
  elseif self.screen == "permissions" then
    return self.currentMod and self:permissionRows(self.currentMod) or {}
  elseif self.screen == "apply" then
    return self:applyRows()
  end
  return {}
end

-- ------- navigation

function ManagerState:goTo(screen)
  self.backStack[#self.backStack + 1] =
    { screen = self.screen, cursor = self.cursor, scroll = self.scroll }
  self.screen = screen
  self.cursor = 1
  self.scroll = screen == "options" and 0 or 1
  self.descScroll = 1
  self:snapCursor()
end

function ManagerState:goBack()
  local prev = table.remove(self.backStack)
  if prev then
    self.screen = prev.screen
    self.cursor = prev.cursor
    self.scroll = prev.scroll
    self:refresh()
  else
    self.game.stack:pop()
  end
end

function ManagerState:snapCursor()
  local rows = self:rowsForScreen()
  local row = rows[self.cursor]
  if row and not row.header then return end
  for i, candidate in ipairs(rows) do
    if not candidate.header then
      self.cursor = i
      return
    end
  end
  self.cursor = 1
end

function ManagerState:moveCursor(dir)
  local rows = self:rowsForScreen()
  local n = #rows
  if n == 0 then return end
  local i = self.cursor
  for _ = 1, n do
    i = clampIndex(i + dir, n)
    if not rows[i].header then
      self.cursor = i
      break
    end
  end
  if self.floatingPanel then self:panelLayout(); return end
  -- keep the cursor inside the scroll window
  if self.cursor < self.scroll then
    self.scroll = self.cursor
  elseif self.cursor > self.scroll + (self.screen == "detail" and 2 or LIST_ROWS) - 1 then
    self.scroll = self.cursor - (self.screen == "detail" and 2 or LIST_ROWS) + 1
  end
end

function ManagerState:adjustOrTab(dir)
  if self.screen == "list" then
    self.tab = clampIndex(self.tab + dir, #TABS)
    self.cursor, self.scroll = 1, 1
    self:snapCursor()
  elseif self.screen == "detail" then
    local m = self.currentMod or {}
    local cols = self.floatingPanel and math.floor((self:panelLayout().width-32)/8) or 16
    local lines = wrap(m.error or m.note or m.description, cols)
    local visible = self.floatingPanel and math.max(1,self:panelLayout().descRows) or 2
    self.descScroll = math.max(1, math.min(math.max(1, #lines - visible + 1), self.descScroll + dir))
  elseif self.screen == "apply" then
    local visible = self.floatingPanel and self:panelLayout().stageRows or 2
    self.descScroll = math.max(1, math.min(math.max(1, #self:stagedList() - visible + 1), self.descScroll + dir))
  else
    local count = self.floatingPanel and self:panelLayout().visible or LIST_ROWS
    for _ = 1, math.max(1,count) do self:moveCursor(dir) end
  end
end

function ManagerState:focusedRow()
  return self:rowsForScreen()[self.cursor]
end

function ManagerState:confirmSound()
  if self.game.data then
    require("src.core.Sound").play(self.game.data, "Press_AB")
  end
end

function ManagerState:notify(text)
  self.notice = text
  self.noticeTimer = 90
end

function ManagerState:activate()
  local row = self:focusedRow()
  if not row or row.header or row.inert then return end
  self:confirmSound()
  if row.action then
    row.action()
  elseif row.mod then
    self.currentMod = row.mod
    self:goTo("detail")
  elseif row.profile then
    self:applyProfile(row.profile)
  elseif row.saveAs then
    self:saveCurrentAs()
  elseif row.exportProfile then
    self:exportActiveProfile()
  elseif row.importProfile then
    self:importProfiles()
  elseif row.adhoc then
    self:optionsTable().activeProfile = nil
    self:notify("AD-HOC SET ACTIVE")
  end
end

function ManagerState:pressStart()
  if self.screen == "list" and self.tab == 2 then
    local row = self:focusedRow()
    if row and row.profile then
      self:openConfirm({ Strings("DELETE %s?", row.profile.name) }, function()
        self:deleteProfile(row.profile)
      end)
      return
    end
  end
  if self.screen == "apply" then return end
  if self.restartPending or Runtime.safeMode then
    self:goTo("apply")
  else
    self:notify("NO CHANGES")
  end
end

function ManagerState:quickToggle()
  if self.screen == "list" and self.tab == 1 then
    local row = self:focusedRow()
    if row and row.mod then self:beginToggle(row.mod) end
  elseif self.screen == "list" and self.tab == 2 then
    local row = self:focusedRow()
    if row and row.profile then self:renameProfile(row.profile) end
  elseif self.screen == "detail" and self.currentMod then
    self:beginToggle(self.currentMod)
  end
end

function ManagerState:update()
  if self.notice then
    self.noticeTimer = (self.noticeTimer or 0) - 1
    if self.noticeTimer <= 0 then self.notice = nil end
  end
  local input = self.game.input
  if self.overlay then return self:updateOverlay(input) end
  if self.screen == "options" then return self:updateOptions(input) end
  if input:wasPressed("up") then self:moveCursor(-1)
  elseif input:wasPressed("down") then self:moveCursor(1)
  elseif input:wasPressed("left") then self:adjustOrTab(-1)
  elseif input:wasPressed("right") then self:adjustOrTab(1)
  elseif input:wasPressed("a") then self:activate()
  elseif input:wasPressed("b") then self:goBack()
  elseif input:wasPressed("start") then self:pressStart()
  elseif input:wasPressed("select") then self:quickToggle()
  end
end

-- ------- overlays

function ManagerState:openBlocked(r)
  local lines = {}
  for _, depId in ipairs(r.missing) do
    lines[#lines + 1] = Strings("NEEDS %s", depId)
    lines[#lines + 1] = "NOT INSTALLED"
  end
  for _, otherId in ipairs(r.conflicts) do
    local other = self.byId[otherId]
    lines[#lines + 1] = "CONFLICTS WITH"
    lines[#lines + 1] = (other and other.name or otherId)
    lines[#lines + 1] = "DISABLE IT FIRST"
  end
  for _, bad in ipairs(r.badVersion) do
    if bad.engine then
      lines[#lines + 1] = Strings("NEEDS ENGINE %s", bad.need)
      lines[#lines + 1] = Strings("HAVE %s", bad.got)
    else
      lines[#lines + 1] = Strings("NEEDS %s", bad.id .. " " .. bad.need)
    end
  end
  self.overlay = { kind = "ok", lines = lines }
end

function ManagerState:openCascade(r, m, want)
  local lines = {}
  if want then
    local names = {}
    for _, depId in ipairs(r.alsoEnable) do
      local dep = self.byId[depId]
      names[#names + 1] = dep and dep.name or depId
    end
    lines[#lines + 1] = "ALSO ENABLE"
    lines[#lines + 1] = table.concat(names, ", ") .. "?"
  else
    local dep = self.byId[r.alsoDisable[1]]
    lines[#lines + 1] = Strings("%s NEEDS THIS.", dep and dep.name or r.alsoDisable[1])
    lines[#lines + 1] = #r.alsoDisable > 1 and "DISABLE ALL?" or Strings("DISABLE BOTH?")
  end
  self.overlay = { kind = "confirm", lines = lines, index = 1,
    onYes = function() self:commitToggle(r.apply) end }
end

function ManagerState:openConfirm(lines, onYes)
  self.overlay = { kind = "confirm", lines = lines, index = 1, onYes = onYes }
end

function ManagerState:updateOverlay(input)
  local overlay = self.overlay
  local total = 0
  for _, raw in ipairs(overlay.lines) do total = total + #wrap(raw, 16) end
  local pages = math.max(1, math.ceil(total / 5))
  if self.floatingPanel then pages=self:panelLayout().pages end
  overlay.page = overlay.page or 1
  if input:wasPressed("left") then
    overlay.page = math.max(1, overlay.page - 1)
    return
  elseif input:wasPressed("right") then
    overlay.page = math.min(pages, overlay.page + 1)
    return
  end
  if overlay.kind == "ok" then
    if input:wasPressed("up") then
      overlay.page = math.max(1, overlay.page - 1)
    elseif input:wasPressed("down") then
      overlay.page = math.min(pages, overlay.page + 1)
    elseif input:wasPressed("a") or input:wasPressed("b") then
      self.overlay = nil
    end
    return
  end
  if input:wasPressed("up") or input:wasPressed("down") then
    overlay.index = overlay.index == 1 and 2 or 1
  elseif input:wasPressed("a") then
    self:confirmSound()
    self.overlay = nil
    if overlay.index == 1 and overlay.onYes then overlay.onYes() end
  elseif input:wasPressed("b") then
    self.overlay = nil
  end
end

-- ------- the enable/disable flow

function ManagerState:beginToggle(m)
  if Runtime.safeMode then
    self:notify("SAFE MODE ACTIVE")
    return
  end
  if not m then return end
  local want = not m.enabled
  local loader = self.game.mods
  local r
  if loader and loader.resolveToggle then
    r = loader:resolveToggle(m.id, want, self:enabledSet())
  else
    r = ManagerState.resolveToggle(self:manifestMap(), m.id, want,
                                   self:enabledSet())
  end
  local function proceed()
    if #r.missing > 0 or #r.conflicts > 0 or #r.badVersion > 0 then
      self:openBlocked(r)
    elseif #r.alsoEnable > 0 or #r.alsoDisable > 0 then
      self:openCascade(r, m, want)
    else
      self:commitToggle(r.apply)
    end
  end
  -- Experimental mods ask once on enable; disable is silent.
  if want and m.experimental then
    self:openConfirm({
      "EXPERIMENTAL MOD",
      "THIS MOD IS MARKED",
      "EXPERIMENTAL.",
      "ENABLE ANYWAY?",
    }, proceed)
    return
  end
  proceed()
end

-- The gate runs once, before any entry chunk, so this can only take effect on
-- the next boot: it stages a restart the way an enable toggle does.  The
-- override is scoped to THIS game, and a boot that cannot name one keeps it in
-- memory only, which the notice says rather than promising a restart.
function ManagerState:toggleGen2Force(m)
  if Runtime.safeMode then
    self:notify("SAFE MODE ACTIVE")
    return
  end
  local loader = self.game.mods
  if not (loader and loader.setGen2Forced) then return end
  local want = not m.gen2Forced
  local function apply()
    local _, persisted = loader:setGen2Forced(m.id, want)
    self.gen2Pending = persisted ~= false
    if loader.status then self.game.modStatus = loader:status() end
    self:refresh()
    if persisted == false then
      -- the gate already ran, so an unsaved override changes no boot at all
      self:notify("COULD NOT SAVE")
    else
      self:notify(want and "WILL TRY ON RESTART" or "WILL BE SKIPPED")
    end
  end
  if not want then
    apply()
    return
  end
  self:openConfirm({
    "NOT MADE FOR",
    "THIS GAME.",
    "TRY IT ANYWAY?",
  }, apply)
end

-- Where the loader persists an enable flag: this running game's slot.
function ManagerState:enableScope()
  return SaveData.modScope((self:targetGame()))
end

function ManagerState:commitToggle(apply)
  if Runtime.safeMode then
    self:notify("SAFE MODE ACTIVE")
    return
  end
  local loader = self.game.mods
  local opts = self:optionsTable()
  local scope = self:enableScope()
  for id, en in pairs(apply) do
    if loader and loader.setEnabled then loader:setEnabled(id, en) end
    -- mirror into the live options so a later writeOptions cannot revert
    -- what setEnabled just persisted
    SaveData.setModEnabled(opts, id, en, scope)
  end
  if loader and loader.status then self.game.modStatus = loader:status() end
  self:refresh()
end

function ManagerState:discardChanges()
  if Runtime.safeMode then
    self:notify("SAFE MODE ACTIVE")
    return
  end
  local loader = self.game.mods
  local opts = self:optionsTable()
  local scope = self:enableScope()
  for _, m in ipairs(self:stagedList()) do
    local en = bootEnabled(m)
    if loader and loader.setEnabled then loader:setEnabled(m.id, en) end
    SaveData.setModEnabled(opts, m.id, en, scope)
  end
  if loader and loader.status then self.game.modStatus = loader:status() end
  self:refresh()
  self:notify("CHANGES DISCARDED")
end

function ManagerState:restartGame()
  if self.game.restartWithMods then
    self.game:restartWithMods()
  elseif love.event and love.event.quit then
    love.event.quit("restart")
  end
end

-- ------- profiles (named enable-sets, not the manifest profile field)

function ManagerState:findProfile(name)
  for _, p in ipairs(self:optionsTable().modProfiles or {}) do
    if p.name == name then return p end
  end
  return nil
end

function ManagerState:matchesProfile(p)
  for _, m in ipairs(self.status.available or {}) do
    local want = p.enabled[m.id] ~= false
    if (m.enabled and true or false) ~= want then return false end
  end
  -- the per-game answers count too, or a profile that only differs on Gold
  -- would read as still active after the player changed it
  return ModProfile.matchesVersions(p, self:optionsTable())
end

function ManagerState:persistOptions()
  if self.game.writeOptions then self.game:writeOptions() end
end

function ManagerState:applyProfile(p)
  if Runtime.safeMode then
    self:notify("SAFE MODE ACTIVE")
    return
  end
  local mods = self:manifestMap()
  local set = self:enabledSet()
  local combined = {}
  for _, m in ipairs(self.status.available or {}) do
    local want = p.enabled[m.id] ~= false
    local cur = set[m.id] and true or false
    if cur ~= want then
      local r = ManagerState.resolveToggle(mods, m.id, want, set)
      if #r.missing > 0 or #r.conflicts > 0 or #r.badVersion > 0 then
        self:openBlocked(r)
        return
      end
      for id, en in pairs(r.apply) do
        combined[id] = en
        set[id] = en or nil
      end
    end
  end
  self:commitToggle(combined)
  -- #593: a profile is the whole setup, not just the enable set.  Options go
  -- through setOption so loader.modOptions and mod.options_changed stay in
  -- step; save slots move only to slots that version already registered
  -- (SaveData.setActiveSlot would otherwise conjure one).
  for modId, bucket in pairs(p.options or {}) do
    if self.byId[modId] then
      for key, value in pairs(bucket) do self:setOption(modId, key, value) end
    end
  end
  for _, move in ipairs(ModProfile.slotMoves(p)) do
    require("src.core.SaveData").setActiveSlot(move[1], move[2])
  end
  -- the per-game half of the setup, restored beside the shared enable set
  ModProfile.restoreVersions(p, self:optionsTable())
  self:optionsTable().activeProfile = p.name
  self:persistOptions()
  local missing = ModProfile.missingIds(p, self.byId)
  if #missing > 0 then
    self:notify(Strings("%d MODS MISSING", #missing))
  else
    self:notify("PROFILE STAGED")
  end
end

function ManagerState:saveCurrentAs()
  local NamingScreen = require("src.ui.NamingScreen")
  self.game.stack:push(NamingScreen.new(self.game, {
    title = Strings("PROFILE NAME?"),
    maxLen = 10,
    onDone = function(name)
      local opts = self:optionsTable()
      opts.modProfiles = opts.modProfiles or {}
      local snap = ModProfile.capture(self.status.available,
        self:modOptionsTable(), opts.modsByVersion)
      local existing = self:findProfile(name)
      if existing then
        existing.enabled, existing.options, existing.slots =
          snap.enabled, snap.options, snap.slots
        existing.enabledByVersion = snap.enabledByVersion
      else
        snap.name = name
        opts.modProfiles[#opts.modProfiles + 1] = snap
      end
      opts.activeProfile = name
      self:persistOptions()
      self:refresh()
    end,
  }))
end

-- #593 sharing.  Export drops the active profile (or the focused one) in the
-- save directory's profiles/ folder as <NAME>.g1rmodlist; import reads every
-- file already there.  Deliberately folder-based rather than a native file
-- picker: the same shape SaveFileIO uses for exports/, and it works on the
-- mobile builds where no picker exists.
function ManagerState:exportActiveProfile()
  local row = self:focusedRow()
  local p = (row and row.profile)
    or self:findProfile(self:optionsTable().activeProfile)
  if not p then return self:notify("NO PROFILE") end
  local ok = ModProfile.export(p)
  self:notify(ok and Strings("SAVED %s", p.name) or "EXPORT FAILED")
end

function ManagerState:importProfiles()
  local opts = self:optionsTable()
  opts.modProfiles = opts.modProfiles or {}
  local n = 0
  for _, path in ipairs(ModProfile.files()) do
    if ModProfile.import(path, opts.modProfiles) then n = n + 1 end
  end
  if n == 0 then return self:notify("NO MODLISTS") end
  self:persistOptions()
  self:snapCursor()
  self:notify(Strings("%d IMPORTED", n))
end

function ManagerState:renameProfile(p)
  local NamingScreen = require("src.ui.NamingScreen")
  self.game.stack:push(NamingScreen.new(self.game, {
    title = Strings("RENAME?"),
    maxLen = 10,
    default = p.name,
    onDone = function(name)
      local opts = self:optionsTable()
      if opts.activeProfile == p.name then opts.activeProfile = name end
      p.name = name
      self:persistOptions()
    end,
  }))
end

function ManagerState:deleteProfile(p)
  local opts = self:optionsTable()
  local profiles = opts.modProfiles or {}
  for i, candidate in ipairs(profiles) do
    if candidate == p then
      table.remove(profiles, i)
      break
    end
  end
  if opts.activeProfile == p.name then opts.activeProfile = nil end
  self:persistOptions()
  self:snapCursor()
end

-- ------- per-mod options (auto-UI from options_schema)

-- the loader captured schemas when mod.options:define ran; a mod that only
-- shipped the manifest options_schema file gets it loaded here on demand
function ManagerState:schemaFor(m)
  local loader = self.game.mods
  if not loader then return nil end
  local schema = loader.optionSchemas and loader.optionSchemas[m.id]
  if schema == nil and m.options_schema and m.path
      and loader.fs and loader.fs.load then
    -- mod-authored code, so it runs in the same sandbox the entry chunk does
    local ok, rows = pcall(function()
      local path = SafePath.join(m.path, m.options_schema, "options_schema")
      local mod = loader.mods and loader.mods[m.id]
      local env = mod and loader._modEnv and loader:_modEnv(mod)
        or Sandbox.envFor()
      local chunk = Sandbox.loadFile(loader.fs, path, env)
      return chunk and chunk()
    end)
    if ok and type(rows) == "table" then
      schema = rows
      if loader.optionSchemas then loader.optionSchemas[m.id] = schema end
    end
  end
  return schema
end

function ManagerState:optionValue(modId, row)
  local loader = self.game.mods
  local stored = loader and loader.modOptions and loader.modOptions[modId]
  local v = stored and stored[row.key]
  if v == nil then v = row.default end
  return v
end

function ManagerState:setOption(modId, key, value)
  if Runtime.safeMode then
    self:notify("SAFE MODE ACTIVE")
    return false
  end
  local save = self.game.save
  if save and save.options then
    save.options.modOptions = save.options.modOptions or {}
    local t = save.options.modOptions
    t[modId] = t[modId] or {}
    t[modId][key] = value
  end
  local loader = self.game.mods
  if loader then
    loader.modOptions = loader.modOptions or {}
    loader.modOptions[modId] = loader.modOptions[modId] or {}
    loader.modOptions[modId][key] = value
  end
  self:persistOptions()
  if loader and loader.events then
    loader.events:emit("mod.options_changed",
      { mod = modId, key = key, value = value })
  end
end

function ManagerState:buildOptionRows(m, schema)
  local rows = {}
  local modId = m.id
  local byKey, visibilityKeys = {}, {}
  for _, row in ipairs(schema) do
    if type(row) == "table" and type(row.key) == "string" then
      byKey[row.key] = row
      local condition = row.visible_if
      if type(condition) == "table" and type(condition.key) == "string" then
        visibilityKeys[condition.key] = true
      end
    end
  end
  local function visible(row)
    local condition = row.visible_if
    if condition == nil then return true end
    if type(condition) ~= "table" or type(condition.key) ~= "string" then
      return false
    end
    local dependency = byKey[condition.key] or { key = condition.key }
    local value = self:optionValue(modId, dependency)
    if condition.equals ~= nil then return value == condition.equals end
    if condition.not_equals ~= nil then return value ~= condition.not_equals end
    return false
  end
  local function refresh(key)
    if not visibilityKeys[key] then return end
    local preferred = rows[self.cursor] and rows[self.cursor].id
    self.optionRows = self:buildOptionRows(m, schema)
    for index, candidate in ipairs(self.optionRows) do
      if candidate.id == preferred then self.cursor = index break end
    end
    self.cursor = clampIndex(self.cursor, #self.optionRows)
  end
  for _, row in ipairs(schema) do
    if type(row) ~= "table" or type(row.key) ~= "string" or row.key == ""
        or not OPTION_TYPES[row.type] then
      -- malformed rows are skipped, reported where the errors screen reads
      Runtime.reportError(modId, "options row skipped: "
        .. tostring(type(row) == "table" and (row.key or row.type) or row))
    elseif not visible(row) then
      -- Keep the row in the schema and stored options, only hide its menu row.
    elseif row.type == "toggle" then
      rows[#rows + 1] = { id = row.key, label = row.label or row.key,
        value = function()
          return self:optionValue(modId, row) and "ON" or "OFF"
        end,
        step = function()
          self:setOption(modId, row.key, not self:optionValue(modId, row))
          refresh(row.key)
          return true
        end }
    elseif row.type == "choice" then
      rows[#rows + 1] = { id = row.key, label = row.label or row.key,
        value = function()
          local cur = self:optionValue(modId, row)
          for _, choice in ipairs(row.choices or {}) do
            if choice[2] == cur then return choice[1] end
          end
          local first = (row.choices or {})[1]
          return first and first[1] or "----"
        end,
        step = function(_, dir)
          local choices = row.choices or {}
          if #choices == 0 then return false end
          local cur = self:optionValue(modId, row)
          local index = 1
          for i, choice in ipairs(choices) do
            if choice[2] == cur then index = i break end
          end
          index = clampIndex(index + dir, #choices)
          self:setOption(modId, row.key, choices[index][2])
          refresh(row.key)
          return true
        end }
    elseif row.type == "number" then
      local function clamp(v)
        if row.min then v = math.max(row.min, v) end
        if row.max then v = math.min(row.max, v) end
        return v
      end
      rows[#rows + 1] = { id = row.key, label = row.label or row.key,
        value = function()
          return tostring(self:optionValue(modId, row) or 0)
        end,
        step = function(_, dir)
          local cur = tonumber(self:optionValue(modId, row)) or 0
          self:setOption(modId, row.key, clamp(cur + dir * (row.step or 1)))
          refresh(row.key)
          return true
        end,
        activate = function()
          local QuantityBox = require("src.ui.QuantityBox")
          self.game.stack:push(QuantityBox.new(self.game, {
            max = row.max or 99,
            start = math.max(1, tonumber(self:optionValue(modId, row)) or 1),
            onDone = function(qty)
              if qty then
                self:setOption(modId, row.key, clamp(qty))
                refresh(row.key)
              end
            end,
          }))
        end }
    elseif row.type == "text" then
      rows[#rows + 1] = { id = row.key, label = row.label or row.key,
        value = function()
          return tostring(self:optionValue(modId, row) or "")
        end,
        activate = function()
          local NamingScreen = require("src.ui.NamingScreen")
          self.game.stack:push(NamingScreen.new(self.game, {
            title = Strings(row.label or row.key) .. "?",
            maxLen = row.maxLen or 7,
            default = self:optionValue(modId, row),
            onDone = function(name)
              self:setOption(modId, row.key, name)
              refresh(row.key)
            end,
          }))
        end }
    end
  end
  rows[#rows + 1] = { id = "__reset", label = Strings("RESET DEFAULTS"),
    value = function() return "" end,
    activate = function()
      for _, row in ipairs(schema) do
        if type(row) == "table" and type(row.key) == "string"
            and OPTION_TYPES[row.type] then
          self:setOption(modId, row.key, row.default)
        end
      end
      self.optionRows = self:buildOptionRows(m, schema)
      self.cursor = clampIndex(self.cursor, #self.optionRows)
      self:notify("DEFAULTS RESTORED")
    end }
  return rows
end

function ManagerState:openOptions(m)
  if Runtime.safeMode then
    self:notify("SAFE MODE ACTIVE")
    return
  end
  local schema = self:schemaFor(m)
  if not schema then
    self:notify("NO OPTIONS")
    return
  end
  self.optionRows = self:buildOptionRows(m, schema)
  self:goTo("options")
end

function ManagerState:updateOptions(input)
  local rows = self.optionRows or {}
  local n = #rows
  if input:wasPressed("b") then
    self:goBack()
    return
  end
  if n == 0 then return end
  if input:wasPressed("up") then
    self.cursor = clampIndex(self.cursor - 1, n)
  elseif input:wasPressed("down") then
    self.cursor = clampIndex(self.cursor + 1, n)
  elseif input:wasPressed("left") or input:wasPressed("right")
      or input:wasPressed("a") then
    local dir = input:wasPressed("left") and -1 or 1
    local row = rows[self.cursor]
    if row.activate and input:wasPressed("a") then
      self:confirmSound()
      row.activate()
    elseif row.step then
      row.step(self.game, dir)
    end
  end
  if self.floatingPanel then self:panelLayout()
  else self.scroll = OptionRows.clampScroll(self.cursor, self.scroll or 0, n, nil) end
end

-- ------- drawing

local function drawTruncated(text, x, y, cols)
  drawText(clipText(text, cols), x, y)
end

function ManagerState:drawRows(rows)
  local last = math.min(#rows, self.scroll + LIST_ROWS - 1)
  local y = 6
  for i = self.scroll, last do
    local row = rows[i]
    if row.header then
      drawTruncated(row.label, 16, y * 8, 17)
    else
      if row.glyph and row.glyph ~= " " then
        drawText(row.glyph, 16, y * 8)
      end
      drawTruncated(row.label, 32, y * 8, 15)
      if i == self.cursor then
        Font.drawCode(Theme.cursor, 8, y * 8)
      end
    end
    y = y + 2
  end
  if #rows > last then
    Font.drawCode(Theme.moreArrow, 18 * 8, 104)
  end
end

function ManagerState:drawFooter(line1, line2)
  if self.notice then
    drawTruncated(self.notice, 8, 128, 18)
    return
  end
  if line1 then drawTruncated(line1, 8, 112, 18) end
  if line2 then drawTruncated(line2, 8, 128, 18) end
end

function ManagerState:drawList()
  drawTruncated(TAB_LINE[self.tab], 8, 32, 18)
  self:drawRows(self:rowsForScreen())
  if self.tab == 1 then
    self:drawFooter("A:OPEN SEL:TOGGLE", "START:APPLY B:EXIT")
  elseif self.tab == 2 then
    self:drawFooter("A:APPLY SEL:RENAME", "START:DELETE")
  else
    self:drawFooter("UP/DOWN:SCROLL")
  end
end

function ManagerState:drawDetail()
  local m = self.currentMod
  if not m then return end
  drawTruncated(m.name or m.id, 16, 16, 17)
  local status = Strings(m.enabled and "ON" or "OFF")
  if m.error then status = "!" end
  if self:isStaged(m) then status = status .. "*" end
  drawTruncated(m.version or "", 16, 32, 11)
  drawTruncated(status, 112, 32, 4)
  local body = m.error or m.note or m.description
  local lines = wrap(body, 16)
  self.descScroll = math.max(1, math.min(self.descScroll, math.max(1, #lines - 1)))
  for i = 1, 2 do
    local line = lines[self.descScroll + i - 1]
    if line then drawText(line, 16, 56 + (i - 1) * 16) end
  end
  if #lines > 2 then Font.drawCode(Theme.moreArrow, 144, 80) end
  local rows = self:rowsForScreen()
  self.scroll = math.max(1, math.min(self.scroll, math.max(1, #rows - 1)))
  for i = self.scroll, math.min(#rows, self.scroll + 1) do
    local y = 96 + (i - self.scroll) * 16
    drawTruncated(rows[i].label, 32, y, 14)
    if i == self.cursor then Font.drawCode(Theme.cursor, 16, y) end
  end
  if self.scroll + 1 < #rows then Font.drawCode(Theme.moreArrow, 144, 120) end
  drawTruncated(self.notice or "A:CHOOSE B:BACK", 8, 128, 18)
end

function ManagerState:drawPermissions()
  drawTruncated("PERMISSIONS", 16, 32, 17)
  self:drawRows(self:rowsForScreen())
  self:drawFooter("DECLARED BY AUTHOR,", "NOT ENFORCED")
end

function ManagerState:drawErrors()
  drawTruncated("ERRORS", 16, 32, 17)
  self:drawRows(self:rowsForScreen())
  self:drawFooter("UP/DOWN:SCROLL B:BACK")
end

function ManagerState:drawApply()
  drawTruncated("PENDING CHANGES", 16, 16, 17)
  local staged = self:stagedList()
  drawTruncated(Strings("%d CHANGES", #staged), 16, 32, 17)
  local first = math.max(1, math.min(self.descScroll or 1, math.max(1, #staged - 1)))
  for i = first, math.min(#staged, first + 1) do
    local m = staged[i]
    local verb = Strings(m.enabled and "ON" or "OFF")
    drawTruncated(verb .. " " .. (m.name or m.id), 16, 48 + (i - first) * 16, 17)
  end
  if #staged == 0 then
    drawText(Runtime.safeMode and "SAFE MODE" or "NO CHANGES", 16, 48)
  end
  if first + 1 < #staged then Font.drawCode(Theme.moreArrow, 144, 72) end
  local rows = self:rowsForScreen()
  for i, row in ipairs(rows) do
    local y = 80 + (i - 1) * 16
    drawTruncated(row.label, 32, y, 15)
    if i == self.cursor then Font.drawCode(Theme.cursor, 24, y) end
  end
  drawTruncated("A:CHOOSE B:BACK", 8, 128, 18)
end

function ManagerState:drawOverlay()
  local overlay = self.overlay
  local lines = {}
  for _, raw in ipairs(overlay.lines) do
    for _, line in ipairs(wrap(raw, 16)) do lines[#lines + 1] = line end
  end
  local pages = math.max(1, math.ceil(#lines / 5))
  overlay.page = math.max(1, math.min(pages, overlay.page or 1))
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  Font.drawBox(0, 0, 20, 18)
  love.graphics.setColor(0, 0, 0, 1)
  for row = 1, 5 do
    local line = lines[(overlay.page - 1) * 5 + row]
    if line then drawTruncated(line, 16, 8 + row * 16, 16) end
  end
  if pages > 1 then drawText("< " .. overlay.page .. "/" .. pages .. " >", 48, 104) end
  if overlay.kind == "confirm" then
    drawText("YES", 32, 128)
    drawText("NO", 96, 128)
    Font.drawCode(Theme.cursor, overlay.index == 1 and 16 or 80, 128)
  else
    drawText("A:OK", 32, 128)
  end
end

function ManagerState:draw()
  if self.floatingPanel then return end
  if self.screen == "options" then
    OptionRows.draw(self.game, self.optionRows or {}, self.cursor,
                    self.scroll or 0)
    love.graphics.setColor(0, 0, 0, 1)
    drawTruncated(self.notice or "B:DONE (NO RESTART)", 8, Font.lineHeight() > 8 and 128 or 136, 18)
    love.graphics.setColor(1, 1, 1, 1)
    if self.overlay then self:drawOverlay() end
    return
  end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 0, 20, 18)
  love.graphics.setColor(0, 0, 0, 1)
  if self.screen ~= "detail" and self.screen ~= "apply" then
    drawTruncated(self.banner or "MOD MANAGER", 16, 16, 17)
  end
  if self.screen == "list" then
    self:drawList()
  elseif self.screen == "detail" then
    self:drawDetail()
  elseif self.screen == "permissions" then
    self:drawPermissions()
  elseif self.screen == "errors" then
    self:drawErrors()
  elseif self.screen == "apply" then
    self:drawApply()
  end
  if self.overlay then self:drawOverlay() end
end

-- Window-sized JP view adapter. The manager's dependency, permission,
-- profile, option callbacks and staged-apply machinery above stay shared.
-- Game composites this after the world has been presented; draw() stays
-- empty only for this explicit floating instance, not for MOD replacements.
local raisedKana={}
for ch in ("がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポヴ"):gmatch("[%z\1-\127\194-\244][\128-\191]*")do raisedKana[ch]=true end
local function raised(text)
  for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*")do
    if raisedKana[ch]then return true end
  end
  return false
end
local function tileCeil(n)return math.ceil(n/8)*8 end
local function translated(text)return Strings(tostring(text or ""))end
local function panelText(text,x,y,width)
  Classic.text(translated(text),x,y,{width=width})
end
function ManagerState:panelLayout()
  local m=GameUILayout.panelMetrics(self.game,{minHeight=112})
  local l={width=m.width,bodyY=48,footerH=24,title=self.banner or "MOD MANAGER",entries={}}
  local options=self.screen=="options"
  local rows=options and (self.optionRows or {}) or self:rowsForScreen()
  if self.overlay then
    l.lines={}
    for _,raw in ipairs(self.overlay.lines or {})do
      for _,line in ipairs(Classic.wrap(translated(raw),l.width-32))do l.lines[#l.lines+1]=line end
    end
    l.bodyY=40;l.footerH=40
    l.perPage=math.max(1,math.floor((m.height-l.bodyY-l.footerH)/16))
    l.pages=math.max(1,math.ceil(#l.lines/l.perPage))
    self.overlay.page=math.max(1,math.min(l.pages,self.overlay.page or 1))
    l.height=math.min(m.height,math.max(112,tileCeil(l.bodyY+math.min(l.perPage,#l.lines)*16+l.footerH)))
  else
    if self.screen=="list" then
      l.subtitle=TAB_LINE[self.tab];l.footerH=40
    elseif self.screen=="detail" then
      local mod=self.currentMod or {}
      l.title=mod.name or mod.id or "MOD MANAGER"
      l.subtitle=(mod.version or "").."  "..translated(mod.enabled and "ON" or "OFF")
      if self:isStaged(mod)then l.subtitle=l.subtitle.." ." end
      l.description=Classic.wrap(translated(mod.error or mod.note or mod.description),l.width-32)
      l.descRows=math.max(0,math.min(2,math.floor((m.height-96)/16)))
      l.bodyY=48+l.descRows*16+8
    elseif self.screen=="apply" then
      l.title="PENDING CHANGES";l.staged=self:stagedList()
      l.subtitle=Strings("%d CHANGES",#l.staged)
      l.stageRows=math.max(1,math.min(3,#l.staged,math.floor((m.height-104)/16)))
      l.bodyY=48+l.stageRows*16+8
    elseif options then
      l.title=self.currentMod and (self.currentMod.name or self.currentMod.id) or "MOD MANAGER"
      l.bodyY=40
    else
      l.subtitle=self.screen=="permissions" and "PERMISSIONS" or "ERRORS"
      if self.screen=="permissions" then l.footerH=40 end
    end
    local native=self.game.data and self.game.data.font
    local wide=options and l.width>=256
    local capacity=math.max(16,m.height-l.bodyY-l.footerH)
    local hideListHeadings=false
    if self.screen=="list"then
      for _,row in ipairs(rows)do if not row.header then hideListHeadings=true;break end end
    end
    for i,row in ipairs(rows)do
      local label=translated(row.label)
      local value=options and translated(row.value and row.value(self.game) or "") or nil
      local pad=native and (raised(label)or raised(value))and 4 or 0
      local line=native and raised(value)and 16 or 12
      local h=(options and not wide and value~="" and 12+line or 12)+pad
      -- Category headings are navigation metadata, not separate actions. The
      -- compact floating list spends its rows on the actual MOD names.
      local hiddenHeader=hideListHeadings and row.header
      l.entries[i]={row=row,label=label,value=value,pad=pad,h=hiddenHeader and 0 or h,
        hiddenHeader=hiddenHeader,wide=wide,line=line}
    end
    local first=math.max(1,math.min(#rows,self.scroll+(options and 1 or 0)))
    first=math.min(first,self.cursor)
    local function occupied(a,b)local h=0;for i=a,b do h=h+(l.entries[i]and l.entries[i].h or 0)end;return h end
    while first<self.cursor and occupied(first,self.cursor)>capacity do first=first+1 end
    local y,last=l.bodyY,first-1
    for i=first,#rows do
      local e=l.entries[i]
      if y+e.h>l.bodyY+capacity then break end
      e.y=y+e.pad;y=y+e.h;last=i
    end
    l.displayIndex,l.displayCount=0,0
    for i,e in ipairs(l.entries)do
      if not e.hiddenHeader then
        l.displayCount=l.displayCount+1
        if i<=self.cursor then l.displayIndex=l.displayCount end
      end
    end
    l.first,l.last,l.visible=first,last,0
    for i=first,last do if not l.entries[i].hiddenHeader then l.visible=l.visible+1 end end
    self.scroll=first-(options and 1 or 0)
    local allHeight=occupied(1,#rows)
    l.height=math.min(m.height,math.max(112,tileCeil(l.bodyY+math.min(capacity,allHeight)+l.footerH)))
    l.rows=rows
  end
  l.viewport=GameUILayout.overlay(self.game,{anchor="center",width=l.width,height=l.height,
    scale=m.scale,margin=m.margin,rect=m.rect})
  self.panelGeometry=l
  return l
end
function ManagerState:drawWindowOverlay()
  if not self.floatingPanel then return end
  local l=self:panelLayout();local width=l.width
  Classic.backdrop(l.viewport,nil,.12)
  Classic.begin(self.game,{layout=l.viewport,paper={0,0,0,0}})
  Classic.box(0,0,width/8,l.height/8)
  love.graphics.setColor(0,0,0,1)
  local pageLabel=not self.overlay and (l.last<#l.rows or l.first>1)
  panelText(l.title,16,16,width-(pageLabel and 88 or 32))
  if self.overlay then
    local o=self.overlay
    for i=1,l.perPage do
      local line=l.lines[(o.page-1)*l.perPage+i]
      if line then Classic.text(line,16,l.bodyY+(i-1)*16,{width=width-32})end
    end
    if l.pages>1 then panelText(o.page.."/"..l.pages,width-56,16,40)end
    if o.kind=="confirm" then
      local yes,no=32,math.floor(width/2)
      panelText("YES",yes,l.height-16,width/2-40);panelText("NO",no,l.height-16,width/2-16)
      Classic.cursor(o.index==1 and yes-12 or no-12,l.height-16)
    else panelText("A:OK",16,l.height-16,width-32)end
  else
    if l.subtitle then panelText(l.subtitle,16,32,width-32)end
    if l.description then
      self.descScroll=math.max(1,math.min(self.descScroll or 1,math.max(1,#l.description-math.max(1,l.descRows)+1)))
      for i=0,l.descRows-1 do local line=l.description[self.descScroll+i]
        if line then Classic.text(line,16,52+i*16,{width=width-32})end
      end
    end
    if l.staged then
      local first=math.max(1,math.min(self.descScroll or 1,math.max(1,#l.staged-l.stageRows+1)))
      for i=first,math.min(#l.staged,first+l.stageRows-1)do
        local mod=l.staged[i]
        panelText(translated(mod.enabled and "ON" or "OFF").." "..(mod.name or mod.id),16,48+(i-first)*16,width-32)
      end
      if #l.staged==0 then panelText(Runtime.safeMode and "SAFE MODE" or "NO CHANGES",16,48,width-32)end
    end
    for i=l.first,l.last do
      local e=l.entries[i];local row=e.row;local x=row.header and 16 or 32
      if not e.hiddenHeader then
      if row.glyph and row.glyph~=" " then panelText(row.glyph,20,e.y,8)end
      if e.value and e.value~="" then
        if e.wide then
          local split=math.floor((width-48)*.58/8)*8
          Classic.text(e.label,x,e.y,{width=split-8});Classic.text(e.value,x+split,e.y,{width=width-x-split-16})
        else
          Classic.text(e.label,x,e.y,{width=width-x-16});Classic.text(e.value,x+8,e.y+e.line,{width=width-x-24})
        end
      else Classic.text(e.label,x,e.y,{width=width-x-16})end
      if i==self.cursor and not row.header then Classic.cursor(8,e.y)end
      end
    end
    local footer=self.notice or (self.screen=="options" and "B:DONE (NO RESTART)" or "A:CHOOSE B:BACK")
    if self.screen=="list" and not self.notice then
      footer=self.tab==1 and "A:OPEN SEL:TOGGLE" or self.tab==2 and "A:APPLY SEL:RENAME" or "UP/DOWN:SCROLL"
    end
    if self.screen=="permissions" and not self.notice then
      panelText("DECLARED BY AUTHOR,",16,l.height-32,width-32)
      footer="NOT ENFORCED"
    elseif self.screen=="errors" and not self.notice then footer="UP/DOWN:SCROLL B:BACK" end
    panelText(footer,16,l.height-16,width-32)
    if self.screen=="list" and not self.notice then
      if self.tab==1 then panelText("START:APPLY B:EXIT",16,l.height-32,width-32)
      elseif self.tab==2 then panelText("START:DELETE",16,l.height-32,width-32)end
    end
    if l.last<#l.rows or l.first>1 then
      panelText(tostring(l.displayIndex).."/"..l.displayCount,width-64,16,48)
    end
  end
  Classic.finish()
end

return ManagerState
