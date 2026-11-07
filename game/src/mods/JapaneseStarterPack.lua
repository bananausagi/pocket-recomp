-- One-time installation for this Japanese preview's curated mod pack.
-- Uses the normal validated ZIP installer. Only pristine managed copies
-- are upgraded; removed mods and user edits remain the player's choice.
local StarterPack = {}

-- Only upgrade a byte-for-byte copy of the pack we previously shipped.
-- User-edited or separately installed mods are never silently replaced.
local function pristine(id, old, fs, Json, hash)
  if not (old and type(old.files) == "table" and fs.getDirectoryItems) then return false end
  local root, snapshots = "mods/" .. id, {}
  local function scan(path, prefix)
    for _, name in ipairs(fs.getDirectoryItems(path) or {}) do
      local full, rel = path .. "/" .. name, prefix .. name
      local info = fs.getInfo(full)
      if info and info.type == "directory" then
        if not scan(full, rel .. "/") then return false end
      elseif info and info.type == "file" and old.files[rel] then
        local bytes = fs.read(full)
        if not bytes or hash(bytes) ~= old.files[rel] then return false end
        snapshots[rel] = bytes
      else return false end
    end
    return true
  end
  if not scan(root, "") then return false end
  for name in pairs(old.files) do if not snapshots[name] then return false end end
  -- installZip replaces every same-id tree; refuse duplicate copies.
  for _, folder in ipairs(fs.getDirectoryItems("mods") or {}) do
    if folder ~= id then
      local raw = fs.read("mods/" .. folder .. "/manifest.json")
      local m = raw and Json.decode(raw)
      if m and m.id == id then return false end
    end
  end
  return snapshots
end

local function upgrade(entry, old, fs, Json, LauncherMods, hash)
  local snapshots = pristine(entry.id, old, fs, Json, hash)
  if not snapshots then return false end
  local root = "mods/" .. entry.id
  local backup = "jp-mod-backups/" .. (old.backupGroup or "jp2") .. "/" .. entry.id .. "/"
  for name, bytes in pairs(snapshots) do
    local dir = (backup .. name):match("^(.*)/")
    if not fs.createDirectory(dir) or not fs.write(backup .. name, bytes) then
      return nil, "could not save previous mod copy"
    end
  end
  local ok, err = LauncherMods.installZip(entry.archive, { expectId = entry.id, replace = true })
  if not ok then
    -- Retain the backup and restore the shipped files after a partial copy.
    for name, bytes in pairs(snapshots) do
      fs.createDirectory((root .. "/" .. name):match("^(.*)/"))
      fs.write(root .. "/" .. name, bytes)
    end
    return nil, err
  end
  return true, nil, snapshots
end

-- Only roots successfully installed by THIS call are eligible for rollback.
-- Remove new files as well as replacing old ones, so the managed fingerprint
-- is exact again and a later startup can safely retry the upgrade.
local function rollbackMods(undo, fs, errors)
  local function remove(path)
    local info = fs.getInfo(path)
    if not info then return end
    if info.type == "directory" then
      for _, name in ipairs(fs.getDirectoryItems(path) or {}) do remove(path .. "/" .. name) end
    end
    assert(fs.remove(path), "could not remove " .. path)
  end
  for i = #undo, 1, -1 do
    local entry = undo[i]
    local ok, why = pcall(function()
      local root = entry.path or ("mods/" .. entry.id)
      remove(root)
      for name, bytes in pairs(entry.files or {}) do
        local path = root .. "/" .. name
        assert(fs.createDirectory(path:match("^(.*)/")), "could not restore MOD directory")
        assert(fs.write(path, bytes), "could not restore " .. path)
      end
    end)
    if not ok then errors[#errors + 1] = "rollback " .. entry.id .. ": " .. tostring(why) end
  end
end

local OPTION_FILES = { "options.lua", "options.lua.bak", "options.lua.tmp" }
local function optionSnapshot(fs)
  -- Lightweight injected filesystems used by old tests may not expose IO.
  if not (fs.getInfo and fs.read and fs.write and fs.remove) then return nil end
  local files = {}
  for _, name in ipairs(OPTION_FILES) do
    if fs.getInfo(name) then
      files[name] = assert(fs.read(name), "could not snapshot " .. name)
    else files[name] = false end
  end
  return files
end

local function rollbackOptions(files, fs, errors)
  for _, name in ipairs(OPTION_FILES) do
    if files then
      local ok, why = pcall(function()
        local bytes = files[name]
        if bytes == false then
          if fs.getInfo(name) then assert(fs.remove(name), "could not remove " .. name) end
        elseif fs.read(name) ~= bytes then
          assert(fs.write(name, bytes), "could not restore " .. name)
        end
      end)
      if not ok then errors[#errors + 1] = "settings rollback: " .. tostring(why) end
    end
  end
end

function StarterPack.install(deps)
  deps = deps or {}
  local fs = deps.fs or (love and love.filesystem)
  if not fs then return false end
  local raw = fs.read("assets/jp-mods/catalog.json")
  if not raw then return false end
  local Json = deps.Json or require("src.link.Json")
  local catalog, err = Json.decode(raw)
  if type(catalog) ~= "table" then return nil, tostring(err) end
  local SaveData = deps.SaveData or require("src.core.SaveData")
  local LauncherMods = deps.LauncherMods or require("src.mods.LauncherMods")
  local opts = SaveData.loadOptions()
  local Restore = require("src.mods.JapaneseRendererRestore")
  local restoreRenderer = Restore.needed(opts)
  local optionsFs = SaveData.persistenceFs and SaveData.persistenceFs(fs) or fs
  local snapOK, optionsBefore = pcall(optionSnapshot, optionsFs)
  if not snapOK then return nil, "settings: " .. tostring(optionsBefore) end
  opts.jpStarterPackV1 = opts.jpStarterPackV1 or {}
  local installed = LauncherMods.installedVersions()
  local changed, errors, undo = false, {}, {}
  local previous = {}
  for _, group in ipairs({ "jp2", "jp3", "jp8", "jp10", "jp11", "jp12", "jp13", "jp14", "jp15", "jp16", "jp17", "jp18", "jp19", "jp20", "jp21", "jp22", "jp23", "jp24", "jp25", "jp26", "jp27", "jp28", "jp29", "jp30", "jp31", "jp32", "jp33", "jp34", "jp35", "jp36", "jp37", "jp38", "jp39", "jp40", "jp41", "jp42", "jp57", "jp58", "jp59", "jp60", "jp61", "controls20261016", "jp89", "jp90", "jp91", "jp91p1", "jp91p2", "current" }) do
    local previousRaw = fs.read(group == "current" and "assets/jp-mods/managed-renderers.json"
      or "assets/jp-mods/upgrades-" .. group .. ".json")
    local versions = previousRaw and Json.decode(previousRaw) or {}
    for id, old in pairs(type(versions) == "table" and versions or {}) do
      if type(old) == "table" and old.version then
        previous[id] = previous[id] or {}
        old.backupGroup = group
        previous[id][old.version] = old
      end
    end
  end
  local hash = deps.hash or function(bytes)
    return love.data.encode("string", "hex", love.data.hash("sha256", bytes))
  end
  local RendererMigration = require("src.mods.JapaneseRendererMigration")
  local rendererEntry
  for _, entry in ipairs(catalog) do
    if entry.id == RendererMigration.NEW then rendererEntry = entry end
  end
  local migration = rendererEntry and RendererMigration.prepare(opts, installed)
  if not opts.jpDisplayDefaultsV3 then
    if opts.jpDotMatrix == nil then opts.jpDotMatrix = 0 end
    if opts.jpDialogScale == nil then opts.jpDialogScale = 0.75 end
    opts.jpDisplayDefaultsV3, changed = true, true
  end
  for _, entry in ipairs(catalog) do
    -- jp.38 ships only the established renderer and six companion MODs.
    local id = entry.id
    local old = previous[id] and previous[id][installed[id]]
    if old and old.version ~= entry.version and opts.jpStarterPackV1[id] == old.version
        and installed[id] == old.version then
      local ok, detail, snapshots = upgrade(entry, old, fs, Json, LauncherMods, hash)
      if ok then
        undo[#undo + 1] = { id = id, files = snapshots }
        opts.jpStarterPackV1[id], changed = entry.version, true
        installed[id] = entry.version
      elseif ok == nil then errors[#errors + 1] = id .. ": " .. tostring(detail) end
    end
    local repairFallback = migration and migration.needsRestore
      and id == RendererMigration.NEW and not installed[id]
    local repairSwitch = restoreRenderer and id == Restore.NEW and not installed[id]
    if not opts.jpStarterPackV1[id] or repairFallback or repairSwitch then
      if installed[id] then
        -- Existing copies, settings, and enable flags belong to the player.
        opts.jpStarterPackV1[id], changed = "existing", true
      else
        local ok, detail = LauncherMods.installZip(entry.archive, { expectId = id })
        if ok then
          undo[#undo + 1] = { id = id }
          opts.jpStarterPackV1[id], changed = entry.version, true
          installed[id] = entry.version
          opts.modOptions = opts.modOptions or {}
          local settings = opts.modOptions[id] or {}
          opts.modOptions[id] = settings
          if id == "DRAMALESS_SHAPE" then
            -- Orbit camera, half-resolution and cast shadows. The shared
            -- gentle blur default comes from SaveData, not this installer.
            -- Fill only absent keys so prior choices survive an upgrade.
            local defaults = { renderScale = 2, renderDistanceSetting = 64,
              shadowQuality = "high", water = "sky", aa = 0, daytime = "day",
              voxel_2d_battles = true, battleBack = true }
            for key, value in pairs(defaults) do
              if settings[key] == nil then settings[key] = value end
            end
            opts.pipelines = opts.pipelines or {}
            if opts.pipelines.voxel == nil then opts.pipelines.voxel = 3 end
          elseif id == "running_shoes" then
            if settings.fx == nil then settings.fx = "off" end
          elseif id == "SHINY_POKEMON" then
            if settings.shiny_rate == nil then settings.shiny_rate = "gen2" end
            if settings.debug_ow == nil then settings.debug_ow = false end
          elseif id == "ACCESS_PC_ANYWHERE" then
            if settings.overworld_only == nil then settings.overworld_only = false end
          elseif id == "CONTROLLER_RUMBLE" then
            if settings.intensity == nil then settings.intensity = "low" end
            if settings.ambient == nil then settings.ambient = false end
          end
        else
          errors[#errors + 1] = id .. ": " .. tostring(detail)
        end
      end
    end
  end
  if migration and (installed[RendererMigration.NEW] or not migration.needsRestore) then
    if RendererMigration.apply(opts, migration) then changed = true end
  end
  -- Back up and uninstall only the exact managed jp.37 trial. Edited copies
  -- are disabled by Restore but their files remain available to their owner.
  if not opts.jpAscendantRetired38 and installed[Restore.OLD] then
    local old = previous[Restore.OLD] and previous[Restore.OLD][installed[Restore.OLD]]
    local files = old and pristine(Restore.OLD, old, fs, Json, hash)
    if files then
      local backed, why = pcall(function()
        for name, bytes in pairs(files) do
          local path = "jp-mod-backups/jp37/" .. Restore.OLD .. "/" .. name
          assert(fs.createDirectory(path:match("^(.*)/")), "could not create retirement backup")
          assert(fs.write(path, bytes), "could not back up retired renderer")
        end
      end)
      if backed then
        undo[#undo + 1] = { id = Restore.OLD, files = files }
        local removed, detail = LauncherMods.uninstall(Restore.OLD)
        if not removed then errors[#errors + 1] = "retirement: " .. tostring(detail) end
      else errors[#errors + 1] = "retirement: " .. tostring(why) end
    end
  end
  if #errors==0 then
    local ok,result=pcall(require("src.mods.JapaneseTrialCleanup").remove,opts,fs,Json,LauncherMods,undo)
    if not ok then errors[#errors+1]="retirement: "..tostring(result)
    elseif result then changed=true end
  end
  if #errors > 0 then
    rollbackMods(undo, fs, errors)
    rollbackOptions(optionsBefore, optionsFs, errors)
    if SaveData.invalidateOptions then SaveData.invalidateOptions(optionsFs) end
    return nil, table.concat(errors, "; ")
  end
  if Restore.apply(opts, SaveData.defaultOptions and SaveData.defaultOptions()) then changed = true end
  if changed then
    local saveOK, saved, saveErr = pcall(SaveData.saveOptions, opts)
    if not saveOK then saveErr, saved = saved, nil end
    if saved == false or saved == nil then
      errors[#errors + 1] = "settings: " .. tostring(saveErr)
      rollbackMods(undo, fs, errors)
      rollbackOptions(optionsBefore, optionsFs, errors)
      if SaveData.invalidateOptions then SaveData.invalidateOptions(optionsFs) end
    end
  end
  if #errors > 0 then return nil, table.concat(errors, "; ") end
  return changed
end

return StarterPack
