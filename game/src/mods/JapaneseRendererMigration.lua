-- jp.20 retires the bundled Voxel Ascendant adapter and restores Dramaless.
-- Only enable-state changes: preserve both renderers' settings, manual files,
-- unrelated MOD choices and save slots, including those in named profiles.
local M = { OLD = "VOXEL_ASCENDANT", NEW = "DRAMALESS_SHAPE" }
local versions = require("src.core.GameVersion").ORDER
local conflicts = { "DRAMATIC_SHAPE", "TERRARIUM", "BATTLE_ART_VOXEL_FORK",
  "potato_voxel", "STADIUM_BATTLE_FX" }

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

local function flag(shared, bucket, id)
  if type(bucket[id]) == "boolean" then return bucket[id] end
  if type(shared[id]) == "boolean" then return shared[id] end
  return nil
end

local function restore(shared, bucket, installed)
  local retired = flag(shared, bucket, M.OLD)
  if retired == nil then retired = installed[M.OLD] ~= nil end
  local wanted = flag(shared, bucket, M.NEW)
  local other = false
  for _, id in ipairs(conflicts) do
    if installed[id] and flag(shared, bucket, id) ~= false then other = true end
  end
  -- A disabled fallback next to active Ascendant is jp.19's automatic choice;
  -- transfer that choice back. Keep an independently selected renderer or an
  -- explicit "both off" setup. Missing flags retain the usual enabled default.
  if retired then wanted = not other
  elseif wanted == nil then wanted = not other end
  return wanted, retired and wanted
end

local function versionKeys(byVersion, inherited)
  local keys = {}
  for _, version in ipairs(versions) do keys[version] = true end
  for version in pairs(byVersion) do keys[version] = true end
  for version in pairs(inherited) do keys[version] = true end
  return keys
end

local function originalBucket(byVersion, inherited, version)
  local bucket = byVersion[version]
  -- Applying a profile with a missing/empty bucket retains the live overlay.
  -- Materialize it before modifying renderer flags so its unrelated choices
  -- survive profile switching and its old Ascendant flag cannot reappear.
  if type(bucket) ~= "table" or next(bucket) == nil then
    return copy(type(inherited[version]) == "table" and inherited[version] or {})
  end
  return copy(bucket)
end

local function needsRestore(shared, byVersion, inherited, installed)
  local _, required = restore(shared, {}, installed)
  if required then return true end
  for version in pairs(versionKeys(byVersion, inherited)) do
    local _, requiredHere = restore(shared, originalBucket(byVersion, inherited, version), installed)
    if requiredHere then return true end
  end
  return false
end

function M.prepare(opts, installed)
  if opts.jpRendererRollbackV1 then return nil end
  local shared, byVersion = opts.mods or {}, opts.modsByVersion or {}
  local context = { installed = copy(installed or {}), byVersion = copy(byVersion) }
  context.needsRestore = needsRestore(shared, byVersion, {}, context.installed)
  for _, profile in ipairs(opts.modProfiles or {}) do
    if needsRestore(profile.enabled or {}, profile.enabledByVersion or {}, byVersion, context.installed) then
      context.needsRestore = true
    end
  end
  return context
end

local function migrateFlags(shared, byVersion, inherited, installed)
  local before = copy(shared)
  for version in pairs(versionKeys(byVersion, inherited)) do
    local bucket = originalBucket(byVersion, inherited, version)
    bucket[M.NEW] = restore(before, bucket, installed)
    bucket[M.OLD] = false
    byVersion[version] = bucket
  end
  shared[M.NEW] = restore(before, {}, installed)
  shared[M.OLD] = false
end

function M.apply(opts, context)
  if not context or opts.jpRendererRollbackV1 then return false end
  opts.mods, opts.modsByVersion = opts.mods or {}, opts.modsByVersion or {}
  migrateFlags(opts.mods, opts.modsByVersion, {}, context.installed)
  for _, profile in ipairs(opts.modProfiles or {}) do
    profile.enabled, profile.enabledByVersion = profile.enabled or {}, profile.enabledByVersion or {}
    migrateFlags(profile.enabled, profile.enabledByVersion, context.byVersion, context.installed)
  end
  opts.jpRendererRollbackV1 = true
  return true
end

return M
