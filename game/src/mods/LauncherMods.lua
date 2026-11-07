-- Independent Japanese launcher MOD service, written 2026-09-20.
-- SPDX-License-Identifier: GPL-3.0-or-later
-- This replaces the excluded upstream launcher module; no upstream launcher
-- implementation is included. Compatibility uses the public GPL MOD APIs.
local Manifest = require("src.mods.Manifest")
local Targets = require("src.mods.ModTargets")
local Semver = require("src.mods.Semver")
local SaveData = require("src.core.SaveData")
local Profiles = require("src.mods.ModProfile")
local GameVersion = require("src.core.GameVersion")
local Version = require("src.core.Version")
local Json = require("src.link.Json")
local Serializer = require("src.core.SaveSerializer")
local SafePath = require("src.mods.SafePath")
local M = {}

local function filesystem() return love and love.filesystem end
local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end
local function validId(id)
  return type(id) == "string" and id:match("^[%w_%-]+$") ~= nil
end
local function decode(bytes, path)
  if type(bytes) ~= "string" then return nil, "manifest.json cannot be read" end
  local ok, value, reason = pcall(Json.decode, bytes)
  if not ok or type(value) ~= "table" then return nil, tostring(reason or value) end
  local accepted, manifest = pcall(Manifest.validate, value, path)
  if not accepted then return nil, tostring(manifest) end
  return manifest
end
local function discover()
  local fs, rows = filesystem(), {}
  if not (fs and fs.getDirectoryItems and fs.getInfo and fs.read) then return rows end
  if not fs.getInfo("mods") then return rows end
  local names = fs.getDirectoryItems("mods") or {}
  table.sort(names)
  for _, name in ipairs(names) do
    if SafePath.safe(name) == name and not name:find("/", 1, true) then
      local path = "mods/" .. name
      local info = fs.getInfo(path)
      if info and info.type == "directory" then
        local m = decode(fs.read(path .. "/manifest.json"), path)
        if m then rows[#rows + 1] = m end
      end
    end
  end
  return rows
end
local function index(rows)
  local out = {}
  for _, m in ipairs(rows or {}) do if m.id and not out[m.id] then out[m.id] = m end end
  return out
end
local function selected(options, manifest, scope)
  if SaveData.isSafeMode(options) then return false end
  local value = SaveData.modEnabled(options, manifest.id, scope)
  if value ~= nil then return value end
  return manifest.experimental ~= true
end
local function targetsHere(m, options, scope)
  if not scope then return true end
  return Targets.runsHere(m, scope, nil, SaveData.modForced(options, m.id, scope))
end
local function matches(m, spec)
  return m and (not spec.range or Semver.satisfies(m.version, spec.range))
end

function M.resolveDependencyRepo(id, manifest, installed)
  local candidates = {}
  for _, spec in ipairs((manifest and manifest.dependencySpecs) or {}) do
    if spec.id == id and spec.github then candidates[#candidates + 1] = spec.github end
  end
  local raw = manifest and (manifest.raw or manifest)
  if raw and type(raw.dependency_sources) == "table" and raw.dependency_sources[id] then
    candidates[#candidates + 1] = raw.dependency_sources[id]
  end
  if installed and installed.github then candidates[#candidates + 1] = installed.github end
  for _, candidate in ipairs(candidates) do
    local ok, clean = pcall(Manifest.parseGithub, candidate)
    if ok and clean then return clean end
  end
end

function M.checkDependencies(manifest, options, version, installedManifests)
  options = options or SaveData.loadOptions()
  local installed = index(installedManifests or discover())
  manifest = type(manifest) == "table" and manifest or { name = "Unknown" }
  if manifest.id and not manifest.dependencySpecs and installed[manifest.id] then
    manifest = installed[manifest.id]
  end
  local result = { targetMod = manifest, deps = {}, hasIssues = false }
  local function append(spec, other, status, conflict)
    local repo = M.resolveDependencyRepo(spec.id, manifest, other)
    result.deps[#result.deps + 1] = {
      id = spec.id, name = other and other.name or spec.id,
      range = spec.range, requiredVersion = spec.range,
      installedVersion = other and other.version, installed = other ~= nil,
      enabled = other and selected(options, other, version) or false,
      status = status, conflict = conflict or false, github = repo,
      safeUrl = repo and ("https://github.com/" .. repo) or nil,
    }
    if status ~= "ok" then result.hasIssues = true end
  end
  for _, spec in ipairs(manifest.dependencySpecs or {}) do
    if Targets.specApplies(spec, version) then
      local other, status = installed[spec.id], "ok"
      if not other then status = "missing"
      elseif not selected(options, other, version) then status = "disabled"
      elseif not targetsHere(other, options, version) then status = "other_game"
      elseif not matches(other, spec) then status = "version" end
      append(spec, other, status)
    end
  end
  local conflicts = {}
  local function conflict(spec, other)
    if other and not conflicts[other.id] and selected(options, other, version)
        and targetsHere(other, options, version) and Targets.specApplies(spec, version) then
      conflicts[other.id] = true
      append({ id = other.id, range = spec.range }, other, "conflict", true)
    end
  end
  for _, spec in ipairs(manifest.conflictSpecs or {}) do
    local other = installed[spec.id]
    if matches(other, spec) then conflict(spec, other) end
  end
  for id, other in pairs(installed) do
    if id ~= manifest.id then
      for _, spec in ipairs(other.conflictSpecs or {}) do
        if spec.id == manifest.id and matches(manifest, spec) then conflict(spec, other) end
      end
    end
  end
  return result
end

function M.deriveList(manifests, options, version)
  options = options or {}
  local rows = {}
  local installed = index(manifests)
  for id, manifest in pairs(installed) do
    local row = copy(manifest)
    row.manifest = manifest
    row.enabled = selected(options, manifest, version)
    row.enabledByVersion = {}
    for _, scope in ipairs(GameVersion.ORDER) do
      row.enabledByVersion[scope] = selected(options, manifest, scope)
    end
    row.safeMode = SaveData.isSafeMode(options)
    row.badge = manifest.experimental and "EXPERIMENTAL" or tostring((manifest.raw and manifest.raw.category) or manifest.profile or "MOD"):upper()
    row.targetLabel = Targets.label(manifest)
    row.targetChip = Targets.chip(manifest)
    row.targets = row.targetChip
    if version then row.targetsHere = targetsHere(manifest, options, version) else row.targetsHere = nil end
    row.gen2Forced = version and SaveData.modForced(options, id, version) or false
    row.status, row.statusDetail = "ok", "Ready"
    if row.safeMode then
      row.status, row.statusDetail = "safe_mode", "Safe mode: mods are disabled"
    elseif version and not row.targetsHere then
      row.status, row.statusDetail = "other_game", Targets.detail(manifest, version)
    elseif row.enabled then
      local report = M.checkDependencies(manifest, options, version, manifests)
      for _, dep in ipairs(report.deps) do
        if dep.status == "conflict" then
          row.status, row.statusDetail = "conflict", "Conflicts with " .. dep.name
          break
        elseif dep.status ~= "ok" and row.status == "ok" then
          local why = dep.status == "missing" and "not installed" or dep.status
          if dep.status == "other_game" then why = "not for " .. Targets.gameLabel(version) end
          row.status = "warn"
          row.statusDetail = "Needs " .. dep.id .. " " .. (dep.range or "") .. " (" .. why .. ")"
        end
      end
      if row.status == "ok" and manifest.game_version and not Version.isDev()
          and not Semver.satisfies(Version.engine, manifest.game_version) then
        row.status, row.statusDetail = "warn", "Needs engine " .. manifest.game_version .. " (current " .. Version.engine .. ")"
      end
      if row.status == "ok" and row.gen2Forced and not Targets.supports(manifest, version) then
        row.status, row.statusDetail = "warn", "Forced onto " .. Targets.gameLabel(version)
      end
    end
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b) return a.id < b.id end)
  return rows
end

function M.installedVersions()
  local versions = {}
  for _, m in ipairs(discover()) do if not versions[m.id] then versions[m.id] = m.version end end
  return versions
end
function M.list(version)
  local manifests, options = discover(), SaveData.loadOptions()
  if SaveData.migrateModEnablement(options, manifests) then SaveData.saveOptions(options) end
  local rows = M.deriveList(manifests, options, version)
  local Imports = require("src.mods.RequiredImports")
  for _, row in ipairs(rows) do
    row.imports, row.missingImports, row.missingOptionalImports = Imports.inspect(row.manifest, filesystem())
    row.requiredImports = row.imports
    if row.enabled and row.missingImports > 0 and row.status == "ok" then
      row.status, row.statusDetail = "warn", "Required file import missing"
    end
  end
  return rows
end

-- Catalogs and schema files are parsed as data. No MOD script runs in the UI.
local function dataTable(path)
  local fs = filesystem()
  local bytes = fs and fs.read(path)
  if type(bytes) ~= "string" or #bytes > 4 * 1024 * 1024 then return nil end
  return Serializer.decode(bytes, { allowArray = true, allowComments = true, maxDepth = 30, maxNodes = 100000, maxTableEntries = 20000 })
end
function M.deriveStrings(rows, byId, read)
  local result = {}
  for _, row in ipairs(rows or {}) do
    local manifest = byId and byId[row.id]
    if row.enabled and manifest and manifest.path then
      local catalog = read(manifest.path)
      for key, value in pairs(type(catalog) == "table" and catalog or {}) do
        if type(key) == "string" and type(value) == "string" and value ~= "" then result[key] = value end
      end
    end
  end
  return next(result) and result or nil
end
function M.translationStrings()
  local manifests = discover()
  return M.deriveStrings(M.deriveList(manifests, SaveData.loadOptions()), index(manifests),
    function(path) return dataTable(path .. "/strings.lua") end)
end
function M.optionSchemas(version, options)
  local fs, out = filesystem(), {}
  local bytes = fs and fs.read("mod_option_schemas.json")
  local snapshot = bytes and Json.decode(bytes)
  snapshot = type(snapshot) == "table" and snapshot.mods or {}
  for _, row in ipairs(M.deriveList(discover(), options or SaveData.loadOptions(), version)) do
    if row.enabled then
      local schema = row.options_schema and dataTable(row.path .. "/" .. row.options_schema)
      schema = schema or (type(snapshot) == "table" and snapshot[row.id])
      if type(schema) == "table" then out[#out + 1] = { id = row.id, name = row.name, schema = schema } end
    end
  end
  return out
end
function M.modOptions()
  return copy(SaveData.loadOptions().modOptions or {})
end
function M.setModOptions(id, values)
  if not validId(id) or type(values) ~= "table" then return false end
  local options = SaveData.loadOptions()
  if SaveData.isSafeMode(options) then return false end
  options.modOptions = options.modOptions or {}
  local bucket = options.modOptions[id] or {}
  for key, value in pairs(values) do
    local t = type(value)
    if type(key) == "string" and (t == "string" or t == "boolean" or
        (t == "number" and value == value and math.abs(value) < math.huge)) then bucket[key] = value end
  end
  options.modOptions[id] = bucket
  M.syncActiveProfile(options)
  return not not SaveData.saveOptions(options)
end
function M.setAllEnabled(ids, enabled, version)
  local options = SaveData.loadOptions()
  if SaveData.isSafeMode(options) then return false end
  local manifests = discover()
  SaveData.migrateModEnablement(options, manifests)
  for _, id in ipairs(ids or {}) do
    if validId(id) then SaveData.setModEnabled(options, id, enabled, version) end
  end
  M.syncActiveProfile(options)
  return not not SaveData.saveOptions(options)
end
function M.setEnabled(id, enabled, version)
  if not validId(id) then return false end
  return M.setAllEnabled({ id }, enabled, version)
end

-- ZIP metadata is checked before PhysFS mounts or any destination is touched.
local MAX_BYTES, MAX_FILES = 512 * 1024 * 1024, 20000
local function u16(s, p) local a, b = s:byte(p, p + 1); if not b then error("Truncated ZIP", 0) end; return a + b * 256 end
local function u32(s, p) return u16(s, p) + u16(s, p + 2) * 65536 end
local function archivePath(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("\\", "/")
  if name:find("[%z\1-\31\127:]") or name:sub(1, 1) == "/" then return nil end
  local parts = {}
  for part in name:gmatch("[^/]+") do
    if part == ".." then return nil end
    if part ~= "." then
      if part:match("[ .]$") then return nil end
      local device = (part:match("^([^%.]+)") or part):upper()
      if device == "CON" or device == "NUL" or device == "AUX" or device == "PRN"
          or device:match("^COM%d$") or device:match("^LPT%d$") then return nil end
      parts[#parts + 1] = part
    end
  end
  return table.concat(parts, "/")
end
local function le16(value) return string.char(value % 256, math.floor(value / 256) % 256) end
local function le32(value) return le16(value % 65536) .. le16(math.floor(value / 65536)) end
local function inspectZip(bytes)
  assert(type(bytes) == "string" and #bytes <= MAX_BYTES, "ZIP exceeds 512 MiB limit")
  local eocd
  for p = #bytes - 21, math.max(1, #bytes - 65557), -1 do
    if bytes:sub(p, p + 3) == "PK\5\6" and p + 21 + u16(bytes, p + 20) == #bytes then eocd = p; break end
  end
  assert(eocd, "ZIP directory missing")
  assert(u16(bytes, eocd + 4) == 0 and u16(bytes, eocd + 6) == 0, "Split ZIP is unsupported")
  local count, size, start = u16(bytes, eocd + 10), u32(bytes, eocd + 12), u32(bytes, eocd + 16) + 1
  assert(count == u16(bytes, eocd + 8) and count > 0 and count <= MAX_FILES, "ZIP file count is invalid")
  assert(start + size == eocd and count ~= 65535, "ZIP64 or malformed directory is unsupported")
  local files, seen, fileNames, p, total = {}, {}, {}, start, 0
  local localRecords, directoryRecords, nextOffset, recordCount = {}, {}, 0, 0
  for _ = 1, count do
    assert(bytes:sub(p, p + 3) == "PK\1\2", "Invalid ZIP directory record")
    local nameLen, extraLen, commentLen = u16(bytes, p + 28), u16(bytes, p + 30), u16(bytes, p + 32)
    local name = bytes:sub(p + 46, p + 45 + nameLen)
    local clean, length, offset = archivePath(name), u32(bytes, p + 24), u32(bytes, p + 42) + 1
    assert(clean and #name == nameLen, "Unsafe ZIP path")
    local flags, method = u16(bytes, p + 8), u16(bytes, p + 10)
    assert(flags % 2 == 0 and (method == 0 or method == 8), "Encrypted or unsupported ZIP entry")
    local mode = math.floor(u32(bytes, p + 38) / 65536) % 65536
    local kind = math.floor(mode / 4096) % 16
    assert(kind == 0 or kind == 4 or kind == 8, "ZIP links and special files are forbidden")
    assert(u16(bytes, p + 34) == 0 and length ~= 4294967295, "ZIP64 is unsupported")
    assert(bytes:sub(offset, offset + 3) == "PK\3\4" and offset < start, "ZIP local header missing")
    local localNameLen, localExtraLen = u16(bytes, offset + 26), u16(bytes, offset + 28)
    assert(bytes:sub(offset + 30, offset + 29 + localNameLen) == name, "ZIP filenames disagree")
    assert(u16(bytes, offset + 6) == flags and u16(bytes, offset + 8) == method, "ZIP headers disagree")
    assert(offset + 30 + localNameLen + localExtraLen + u32(bytes, p + 20) <= start, "ZIP entry exceeds payload")
    total = total + length
    assert(total <= MAX_BYTES, "Expanded MOD exceeds 512 MiB limit")
    local directory = name:gsub("\\", "/"):sub(-1) == "/" or kind == 4
    assert(clean ~= "" or directory, "ZIP file has an empty name")
    if clean ~= "" then
      assert(not seen[clean:lower()], "ZIP has duplicate or case-colliding paths")
      seen[clean:lower()] = true
      if not directory then
        files[#files + 1] = { name = clean, size = length }
        fileNames[clean:lower()] = true
      else assert(length == 0, "ZIP directory contains data") end
      -- Authors sometimes publish Windows separators or ./ path prefixes.
      -- Rebuild both headers around the original compressed payload so
      -- PhysFS reads exactly the same canonical paths that were validated.
      local canonical = clean .. (directory and "/" or "")
      local payloadStart = offset + 30 + localNameLen + localExtraLen
      local payload = bytes:sub(payloadStart, payloadStart + u32(bytes, p + 20) - 1)
      local cleanFlags = flags - (math.floor(flags / 8) % 2) * 8
      local localRecord = "PK\3\4" .. bytes:sub(p + 6, p + 7) .. le16(cleanFlags)
        .. bytes:sub(p + 10, p + 27) .. le16(#canonical) .. le16(0) .. canonical .. payload
      local directoryRecord = "PK\1\2" .. bytes:sub(p + 4, p + 7) .. le16(cleanFlags)
        .. bytes:sub(p + 10, p + 27) .. le16(#canonical) .. le16(0) .. le16(0) .. le16(0)
        .. bytes:sub(p + 36, p + 41) .. le32(nextOffset) .. canonical
      localRecords[#localRecords + 1], directoryRecords[#directoryRecords + 1] = localRecord, directoryRecord
      nextOffset, recordCount = nextOffset + #localRecord, recordCount + 1
    end
    p = p + 46 + nameLen + extraLen + commentLen
    assert(p <= eocd, "ZIP record extends past directory")
  end
  assert(p == eocd, "ZIP directory length mismatch")
  for _, file in ipairs(files) do
    local parent = file.name:match("^(.*)/")
    while parent do
      assert(not fileNames[parent:lower()], "ZIP file/directory collision")
      parent = parent:match("^(.*)/")
    end
  end
  local central = table.concat(directoryRecords)
  local ending = "PK\5\6" .. le16(0) .. le16(0) .. le16(recordCount) .. le16(recordCount)
    .. le32(#central) .. le32(nextOffset) .. le16(0)
  return files, table.concat(localRecords) .. central .. ending
end
M.inspectZip = inspectZip
function M.locateRoot(paths)
  local roots = {}
  for _, path in ipairs(paths or {}) do
    if path == "manifest.json" then roots[""] = true
    else
      local root = path:match("^([^/]+)/manifest%.json$")
      if root and root ~= "__MACOSX" then roots[root] = true end
    end
  end
  local selectedRoot, count = nil, 0
  for root in pairs(roots) do selectedRoot, count = root, count + 1 end
  if count == 0 then return nil, "no manifest.json found in the .zip" end
  if count > 1 then return nil, "the .zip must contain a single mod folder" end
  return selectedRoot
end
local function readArchive(source)
  if type(source) == "string" then
    local fs = filesystem()
    local path = SafePath.safe(source)
    if path and fs then
      local info = fs.getInfo(path)
      if info and info.type == "file" then
        assert((info.size or 0) <= MAX_BYTES, "ZIP exceeds 512 MiB limit")
        return assert(fs.read(path))
      end
    end
    local handle = assert(io.open(source, "rb"), "Could not open ZIP")
    local bytes = handle:read(MAX_BYTES + 1)
    handle:close()
    return bytes
  end
  assert(source and source.open and source.read, "Unsupported ZIP source")
  assert(source:open("r"), "Could not open dropped ZIP")
  local ok, bytes = pcall(source.read, source, MAX_BYTES + 1)
  source:close()
  assert(ok, tostring(bytes))
  return bytes
end
local function erase(fs, path)
  local info = fs.getInfo(path)
  if not info then return true end
  if info.type == "directory" then
    for _, name in ipairs(fs.getDirectoryItems(path)) do
      assert(archivePath(name) == name and not name:find("/", 1, true), "Unsafe installed path")
      erase(fs, path .. "/" .. name)
    end
  end
  assert(fs.remove(path), "Could not remove " .. path)
  return true
end
local function writeFile(fs, path, bytes)
  local parent = path:match("^(.*)/")
  assert(not parent or fs.createDirectory(parent), "Could not create MOD directory")
  assert(fs.write(path, bytes), "Could not write MOD file: " .. path)
end
local serial = 0
local function writable(fs, path)
  if not fs.getRealDirectory then return true end
  return fs.getRealDirectory(path) == fs.getSaveDirectory()
end
local function install(bytes, opts)
  local fs = assert(filesystem(), "MOD installation needs LOVE")
  local entries, normalized = inspectZip(bytes)
  local paths = {}
  for _, entry in ipairs(entries) do paths[#paths + 1] = entry.name end
  local prefix, rootError = M.locateRoot(paths)
  assert(prefix, rootError)
  local root = prefix == "" and "" or prefix .. "/"
  serial = serial + 1
  local token = tostring(os.time()) .. "-" .. tostring(serial)
  local temp = "jp-mod-transactions/" .. token
  assert(not fs.getInfo(temp), "Transaction path already exists; retry installation")
  assert(fs.createDirectory(temp), "Could not prepare MOD transaction")
  local archive, mountpoint = temp .. "/source.zip", "jp-mod-mount-" .. token
  local mounted, backups, committed, result = false, {}, false, nil
  local abs = fs.getSaveDirectory() .. "/"
  local ok, failure = pcall(function()
    writeFile(fs, archive, normalized)
    assert(fs.mount(archive, mountpoint, false), "Could not mount ZIP")
    mounted = true
    local manifest, why = decode(fs.read(mountpoint .. "/" .. root .. "manifest.json"))
    assert(manifest, "Invalid MOD manifest: " .. tostring(why))
    assert(not opts.expectId or manifest.id == opts.expectId, "ZIP mod id does not match expected id")
    local destination, previous = "mods/" .. manifest.id, {}
    for _, m in ipairs(discover()) do if m.id == manifest.id then previous[#previous + 1] = m.path end end
    assert(opts.replace or #previous == 0, "A MOD with this id is already installed")
    local known = false
    for _, path in ipairs(previous) do
      assert(writable(fs, path), "Cannot replace a read-only MOD")
      if path == destination then known = true end
    end
    assert(not fs.getInfo(destination) or known, "Destination belongs to another or invalid MOD")
    local files = {}
    for _, entry in ipairs(entries) do
      if entry.name:sub(1, #root) == root then
        local relative = entry.name:sub(#root + 1)
        if relative:sub(1, 9):lower() == "baseroms/" or relative:lower() == "baseroms" then
          error("MOD archives must not contain user-supplied baseroms files", 0)
        end
        if relative ~= "" and not relative:match("^__MACOSX/") then
          local contents = assert(fs.read(mountpoint .. "/" .. entry.name), "ZIP entry cannot be read")
          assert(#contents == entry.size, "ZIP entry has incorrect expanded size")
          writeFile(fs, temp .. "/new/" .. relative, contents)
          files[relative] = true
        end
      end
    end
    assert(files[manifest.entry], "MOD entry script is missing")
    for _, key in ipairs({ "options_schema", "assets_transforms" }) do
      assert(not manifest[key] or files[manifest[key]], "MOD declared file is missing: " .. key)
    end
    -- Preserve local required imports across updates, never archive content.
    local function preserve(path, relative)
      if not fs.getInfo(path) then return end
      for _, name in ipairs(fs.getDirectoryItems(path)) do
        assert(archivePath(name) == name and not name:find("/", 1, true), "Unsafe local import filename")
        local source, rel = path .. "/" .. name, relative .. "/" .. name
        local info = fs.getInfo(source)
        assert(info and info.type ~= "symlink", "Local import links are not supported")
        if info.type == "directory" then preserve(source, rel)
        elseif info.type == "file" then
          local target = temp .. "/new/" .. rel
          local contents = assert(fs.read(source))
          if fs.getInfo(target) then assert(fs.read(target) == contents, "Conflicting local imports in duplicate MOD folders")
          else writeFile(fs, target, contents) end
        end
      end
    end
    for _, path in ipairs(previous) do preserve(path .. "/baseroms", "baseroms") end
    assert(fs.createDirectory("mods"), "Could not create MOD directory")
    for n, path in ipairs(previous) do
      local backup = temp .. "/old-" .. n
      assert(os.rename(abs .. path, abs .. backup), "Could not back up previous MOD")
      backups[#backups + 1] = { path = path, backup = backup }
    end
    assert(os.rename(abs .. temp .. "/new", abs .. destination), "Could not activate MOD")
    committed = true
    manifest.path = destination
    result = manifest
  end)
  if mounted then pcall(fs.unmount, archive) end
  local rollbackError
  if not ok and not committed then
    for n = #backups, 1, -1 do
      local b = backups[n]
      if not os.rename(abs .. b.backup, abs .. b.path) then rollbackError = "Previous MOD backup retained at " .. abs .. temp end
    end
  end
  if not rollbackError then pcall(erase, fs, temp) end
  if not ok then return nil, tostring(failure) .. (rollbackError and ("; " .. rollbackError) or "") end
  return true, result.id, result
end
function M.installZip(source, opts)
  local ok, accepted, id, manifest = pcall(function() return install(readArchive(source), opts or {}) end)
  if not ok then return nil, tostring(accepted) end
  return accepted, id, manifest
end
function M.installDownloadedZip(id, path, version)
  if not validId(id) then return nil, "invalid mod id" end
  local ok, result = M.installZip(path, { expectId = id, replace = true })
  if not ok then return nil, result end
  return true, version or result
end
function M.installFromRelease(id, release)
  if not validId(id) then return nil, "invalid mod id" end
  if not (type(release) == "table" and type(release.zip) == "table" and release.zip.url) then return nil, "release has no ZIP" end
  local path, why = require("src.mods.ModUpdate").downloadZip(release.zip.url, "jp-download-" .. id .. ".zip")
  if not path then return nil, why end
  local ok, result = M.installDownloadedZip(id, path, release.version)
  if filesystem() then pcall(filesystem().remove, path) end
  return ok, result
end
function M.installFromIndex(entry)
  if not (type(entry) == "table" and validId(entry.id)) then return nil, "invalid MOD index entry" end
  local release, why = require("src.mods.ModIndex").releaseFor(entry)
  if not release then return nil, why end
  return M.installFromRelease(entry.id, release)
end
function M.uninstall(id)
  if id == nil or id == "" then return nil, "missing mod id" end
  if not validId(id) then return nil, "invalid mod id" end
  local fs = filesystem()
  if not fs then return nil, "MOD uninstall needs LOVE" end
  local roots = {}
  for _, m in ipairs(discover()) do
    if m.id == id then
      if not writable(fs, m.path) then return nil, "Cannot remove read-only MOD" end
      roots[#roots + 1] = m.path
    end
  end
  if #roots == 0 then return nil, "MOD is not installed" end
  local ok, why = pcall(function() for _, path in ipairs(roots) do erase(fs, path) end end)
  if not ok then return nil, tostring(why) end
  return true
end
function M.pickStrays(found, installed)
  local rows, seen = {}, copy(installed or {})
  for _, row in ipairs(found or {}) do
    if validId(row.id) and not seen[row.id] then
      local item = copy(row); item.name = item.name or item.id
      rows[#rows + 1], seen[row.id] = item, true
    end
  end
  table.sort(rows, function(a, b) return a.id < b.id end)
  return rows
end
function M.isReadableRoot(folder, source, cacheRoot)
  return type(folder) == "string" and folder ~= "" and (folder == source or folder == cacheRoot)
end
-- Explicit ZIP import is the supported cross-platform discovery path.
function M.strays() return {} end
function M.adoptStrays() return {} end

local function optionsOr(options) return options or SaveData.loadOptions() end
local function profileNamed(options, name)
  for i, profile in ipairs(options.modProfiles or {}) do if profile.name == name then return profile, i end end
end
local function snapshot(options, name)
  local value = Profiles.capture(M.deriveList(discover(), options), options.modOptions, options.modsByVersion)
  -- Retain flags for temporarily missing mods, too.
  for id, enabled in pairs(options.mods or {}) do if value.enabled[id] == nil then value.enabled[id] = enabled end end
  value.options, value.name = copy(options.modOptions or {}), name
  return value
end
function M.getProfiles(options)
  options = optionsOr(options)
  if not options.modProfilesSeeded then
    Profiles.ensureFirst(options, M.deriveList(discover(), options), options.modOptions)
    SaveData.saveOptions(options)
  end
  return options.modProfiles or {}, options.activeProfile or "PROFILE 1"
end
function M.applyProfile(name, options)
  options = optionsOr(options)
  if SaveData.isSafeMode(options) then return false end
  local profile = profileNamed(options, name)
  if not profile then return false end
  options.mods, options.modOptions = copy(profile.enabled or {}), copy(profile.options or {})
  Profiles.restoreVersions(profile, options)
  local moves = Profiles.slotMoves(profile)
  options.activeProfile = name
  if not SaveData.saveOptions(options) then return false end
  for _, move in ipairs(moves) do SaveData.setActiveSlot(move[1], move[2]) end
  return true
end
function M.saveProfile(name, options)
  if type(name) ~= "string" or not name:find("%S") then return nil end
  options = optionsOr(options)
  if SaveData.isSafeMode(options) then return nil end
  options.modProfiles = options.modProfiles or {}
  local _, position = profileNamed(options, name)
  local profile = snapshot(options, name)
  options.modProfiles[position or (#options.modProfiles + 1)] = profile
  options.activeProfile, options.modProfilesSeeded = name, true
  SaveData.saveOptions(options)
  return profile
end
function M.syncActiveProfile(options)
  options = optionsOr(options)
  local _, position = profileNamed(options, options.activeProfile)
  if not position then return nil end
  local profile = snapshot(options, options.activeProfile)
  options.modProfiles[position] = profile
  return profile
end
function M.duplicateProfile(name, options)
  options = optionsOr(options)
  local profile = profileNamed(options, name)
  if not profile then return nil end
  local n, newName = 2, name .. " 2"
  while profileNamed(options, newName) do n = n + 1; newName = name .. " " .. n end
  local duplicate = copy(profile); duplicate.name = newName
  options.modProfiles[#options.modProfiles + 1] = duplicate
  SaveData.saveOptions(options)
  return duplicate
end
function M.renameProfile(oldName, newName, options)
  options = optionsOr(options)
  if type(newName) ~= "string" or not newName:find("%S") or profileNamed(options, newName) then return false end
  local profile = profileNamed(options, oldName)
  if not profile then return false end
  profile.name = newName
  if options.activeProfile == oldName then options.activeProfile = newName end
  return not not SaveData.saveOptions(options)
end
function M.deleteProfile(name, options)
  options = optionsOr(options)
  if SaveData.isSafeMode(options) then return false end
  local _, position = profileNamed(options, name)
  if not position then return false end
  table.remove(options.modProfiles, position)
  if options.activeProfile == name then
    options.activeProfile = nil
    if options.modProfiles[1] then return M.applyProfile(options.modProfiles[1].name, options) end
  end
  return not not SaveData.saveOptions(options)
end
return M
