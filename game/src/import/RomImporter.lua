-- Kanto Player JP: independent launcher integration, 2026-09-20.
-- ROM verification/extraction and file-import backend below retain their
-- upstream copyright and GPLv3 + additional-terms license (see LICENSE.MD).
-- Proprietary launcher presentation and navigation have been removed.
local GameVersion = require("src.core.GameVersion")
local GamepadMap = require("src.core.GamepadMap")
local Logger = require("src.core.Logger")
local UIStrings = require("src.ui.JapaneseUIStrings")
-- File operations may finish before a game/catalog is loaded. Honor the
-- launcher's explicit language rather than the previously running game.
local function Strings(source, ...)
  local opts = require("src.core.SaveData").loadOptions()
  return UIStrings.format(source, opts.jpLauncherLanguage, ...)
end
local function pickerTitle(name)
  local language = require("src.core.SaveData").loadOptions().jpLauncherLanguage or "ja"
  local source = "Select %s"
  if language == "ja" then
    local key = "UI kit: " .. source
    local translated = UIStrings.lookup(key, language)
    if translated ~= key then source = translated end
  end
  return string.format(source, name)
end
local HostShell = require("src.core.HostShell")
local Platform = require("src.core.Platform")
local RomImporter = {}
RomImporter.__index = RomImporter
local PICK_COMPLETE_FILENAME = "pick_complete.flag"
local finishDirectRequiredImport
local function pickFile(...)
  local fn = love.system.pickFile
  return type(fn) == "function" and fn(...) and true or false
end
local CART_SCOPE = "cart_"
local function cartOfScope(scope)
  return type(scope) == "string" and scope:match("^cart_(.+)$") or nil
end
local CacheContract = require("src.import.CacheContract")

-- ------- ROM cache location
--
-- The extracted cache (data/generated, assets/generated) plus the
-- rom-cache.complete marker normally live in LÖVE's per-user OS save
-- directory.  A portable install instead keeps them in the game folder next
-- to the executable (the folder holding portable.txt), so nothing is left on
-- the host machine.  Every cache write/read/remove goes through CacheFs,
-- which writes that folder with io.* and makes it readable (mounting it via
-- PhysFS for a fused build) -- there is no mirror step and no per-file
-- os.execute (issue #74: that flashed a console window per file on Windows
-- and froze the app).

-- Remove a cache subtree from the OS save directory.  The realDirectory
-- guard keeps this from ever deleting the game folder (portable installs
-- read the cache from there) or a developer's checked-out source tree.
local function removeTree(path)
  local info = love.filesystem.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, child in ipairs(love.filesystem.getDirectoryItems(path)) do
      removeTree(path .. "/" .. child)
    end
  end
  if love.filesystem.getRealDirectory
      and love.filesystem.getRealDirectory(path)
        ~= love.filesystem.getSaveDirectory() then
    return
  end
  local ok, err = love.filesystem.remove(path)
  if ok == false then
    error("could not remove stale cache: " .. tostring(err))
  end
end

-- Portable installs read the cache from the game folder.  Any copy an
-- earlier non-portable run -- or the pre-#74 build, which always wrote the
-- cache to the save directory and only mirrored it out -- left behind would
-- shadow it, because physfs searches the save directory before the source.
-- Clear it out once, and only when a remnant is actually present so a clean
-- install pays nothing.
local saveDirPurged = false
local function purgeSaveDirCache()
  if saveDirPurged then return end
  saveDirPurged = true
  local saveDir = love.filesystem.getSaveDirectory()
  local function saveDirHas(rel)
    local f = io.open(saveDir .. "/" .. rel, "rb")
    if not f then return false end
    f:close()
    return true
  end
  -- Purge each version's stale save-directory copy (under its red/ / blue/
  -- / yellow/ / gold/ prefix) so it cannot shadow the portable game-folder cache.
  for _, version in ipairs(GameVersion.ORDER) do
    local prefix = GameVersion.cachePrefix(version)
    local required = CacheContract.requiredFilesFor(version)
    local hasRequired = false
    for _, path in ipairs(required) do
      if saveDirHas(prefix .. path) then hasRequired = true; break end
    end
    if saveDirHas(prefix .. CacheContract.MARKER_PATH) or hasRequired then
      removeTree(prefix .. "data/generated")
      removeTree(prefix .. "assets/generated")
      love.filesystem.remove(prefix .. CacheContract.MARKER_PATH)
    end
  end
end

-- Whether a given game version's ROM has already been imported and cached.
function RomImporter.isReady(version)
  version = version or "red"
  local CacheFs = require("src.import.CacheFs")
  if CacheFs.root() then
    -- Portable: the cache lives in the game folder next to the executable
    -- (mounted onto the read path for a fused build).  Drop any stale
    -- save-directory copy that would otherwise shadow it at runtime.
    purgeSaveDirCache()
  end
  return CacheContract.isReady(version, CacheFs)
end

function RomImporter.syncAndroidShortcuts(activeVersion)
  if not (love.system and love.system.getOS and love.system.getOS() == "Android"
      and love.system.updateShortcuts) then
    return false
  end

  local allVersions = GameVersion.ORDER
  local ready = {}
  local seen = {}

  if activeVersion and RomImporter.isReady(activeVersion) then
    table.insert(ready, activeVersion)
    seen[activeVersion] = true
  end

  for _, v in ipairs(allVersions) do
    if not seen[v] and RomImporter.isReady(v) then
      table.insert(ready, v)
      seen[v] = true
      if #ready >= 4 then break end
    end
  end

  return love.system.updateShortcuts(ready)
end

-- Load the import manifest for a version and confirm it matches that ROM.
local function sha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

local function readExternalPath(path)
  local file, openError = io.open(path, "rb")
  if not file then return nil, openError end
  local data = file:read("*a")
  file:close()
  return data
end

local function externalFileSize(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local size = file:seek("end")
  file:close()
  return size
end

local function openImportSource(path)
  -- Desktop picker paths live outside LÖVE's virtual filesystem. Prefer the
  -- native file handle so a 1.46 GiB disc is never copied to a temp file or
  -- read into one Lua string before validation.
  local native = io.open(path, "rb")
  if native then
    local size, sizeErr = native:seek("end")
    if size == nil or size == false then
      native:close()
      return nil, sizeErr or "could not determine source file size"
    end
    local reset, resetErr = native:seek("set", 0)
    if reset == nil or reset == false then
      native:close()
      return nil, resetErr or "could not rewind source file"
    end
    return {
      size = size,
      read = function(_, n) return native:read(n) end,
      close = function() native:close() end,
    }
  end
  if love and love.filesystem and love.filesystem.newFile then
    local file, makeErr = love.filesystem.newFile(path)
    if not file then return nil, makeErr or "could not open source file" end
    local ok, openErr = file:open("r")
    if not ok then return nil, openErr or "could not open source file" end
    local size = file.getSize and file:getSize() or nil
    return {
      size = size,
      read = function(_, n) return file:read(n) end,
      close = function() file:close() end,
    }
  end
  return nil, "streaming source access is unavailable"
end
local function streamRequiredImport(manifest, importId, source)
  local RequiredImports = require("src.mods.RequiredImports")
  local spec = RequiredImports.spec(manifest, importId)
  if not spec then return nil, "Import declaration was not found." end
  if spec.format == "n64" then
    return nil, "streaming canonicalization is unavailable for N64 imports"
  end
  local input, openErr = openImportSource(source)
  if not input then return nil, openErr end
  local sizeErr = RequiredImports.sizeError(spec, input.size, false)
  if sizeErr then input:close(); return nil, sizeErr end

  local CacheFs = require("src.import.CacheFs")
  local destination = RequiredImports.path(manifest, spec)
  local savedPrefix = CacheFs.prefix
  local output
  local inputClosed, outputClosed = false, false

  local function closeInput()
    if inputClosed then return end
    inputClosed = true
    pcall(function() input:close() end)
  end

  local function closeOutput()
    if outputClosed or not output then return end
    outputClosed = true
    pcall(function() output:close() end)
  end

  local resultOk, resultDetail
  CacheFs.prefix = ""
  local ran, thrown = xpcall(function()
    CacheFs.remove(RequiredImports.receiptPath(manifest, spec))
    CacheFs.remove(destination)
    local makeErr
    output, makeErr = CacheFs.openWrite(destination)
    if not output then
      resultDetail = makeErr or "could not create imported file"
      return
    end

    local MD5 = require("src.mods.StreamMD5")
    local md5 = MD5.new()
    local total, chunkBytes = 0, 4 * 1024 * 1024
    while true do
      local chunk = input:read(chunkBytes)
      if not chunk or #chunk == 0 then break end
      md5:update(chunk)
      local wrote, writeErr = output:write(chunk)
      if wrote == false or wrote == nil then
        resultDetail = "could not copy import: "
.. tostring(writeErr or "write failed")
        return
      end
      total = total + #chunk
      if #chunk < chunkBytes then break end
    end

    closeInput()
    closeOutput()
    if input.size and total ~= input.size then
      resultDetail = ("source read ended early (expected %d bytes, copied %d)")
        :format(input.size, total)
      return
    end
    local storedSizeErr = RequiredImports.sizeError(spec, total, true)
    if storedSizeErr then resultDetail = storedSizeErr; return end
    local digest = md5:final()

    -- acceptStoredDigest uses the normal engine path/receipt rules, so
    -- restore the caller's prefix before handing control to it.
    CacheFs.prefix = savedPrefix
    local accepted, detail = RequiredImports.acceptStoredDigest(
      manifest, importId, digest, love.filesystem)
    if not accepted then resultDetail = detail; return end
    resultOk, resultDetail = true, detail
  end, function(err)
    if debug and debug.traceback then
      return debug.traceback(tostring(err), 2)
    end
    return tostring(err)
  end)

  -- finally: resource handles and the process-global CacheFs prefix must
  -- be restored even when a read/hash/write helper raises a Lua error.
  closeInput()
  closeOutput()
  CacheFs.prefix = ""
  if not ran or not resultOk then
    pcall(function() CacheFs.remove(destination) end)
  end
  CacheFs.prefix = savedPrefix

  if not ran then
    return nil, "could not copy import: " .. tostring(thrown)
  end
  if not resultOk then return nil, resultDetail end
  return true, resultDetail
end
local function readDroppedFile(file)
  local ok, openError = file:open("r")
  if not ok then return nil, openError end
  local data, readError = file:read(file:getSize())
  file:close()
  return data, readError
end

local function trim(value)
  return value and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

-- Turn a filesystem path into a well-formed file:// URI for love.system.openURL.
-- openURL feeds SDL_OpenURL, whose macOS backend ([NSURL URLWithString:]) returns
-- nil for any unencoded space -- and the default save dir lives under
-- "Application Support" -- so the click silently no-ops on real macOS installs.
-- Windows needs forward slashes and a leading slash on the drive path so the
-- authority is empty (file:///C:/...), not a hostname.  Percent-encode the rest
-- (spaces -> %20) but keep the unreserved set plus "/" and ":" (drive letter and
-- path separators stay literal so the shell resolves the folder).
local function fileUrl(path)
  path = tostring(path):gsub("\\", "/")
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  local encoded = path:gsub("[^%w%-%._~/:]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return "file://" .. encoded
end

-- The native pickers below block the whole loop inside io.popen, and they are
-- opened straight out of mousepressed -- with the button still physically
-- down.  SDL auto-captures the pointer for the length of a press (on X11 an
-- XGrabPointer with owner_events) and only drops that capture when it
-- processes the matching button-up, which it cannot do while we sit in popen
-- and never pump.  The grab then outlives the click and every pointer event
-- over the file chooser is still routed to our window: the dialog draws and
-- keyboard-navigates (keyboard focus is a separate grab) but ignores the
-- mouse entirely -- issue #254 on Linux.  Whether it bites is a race with how
-- long the click was held, which is why the same build picks one ROM fine and
-- then hangs the mouse on the next.
--
-- The release itself now lives in HostShell.releasePointerGrab, called from
-- HostShell.popen, so every host spawn inherits it and not just the three
-- pickers here.  It stays a single release point on purpose: this file used
-- to run its own copy first, and each copy carries its own one-second bound,
-- so keeping both made a stuck button cost two seconds instead of one.

local function commandOutput(command)
  if not Platform.canSpawnProcess() then return nil end
  local pipe = HostShell.popen(command)
  if not pipe then return nil end
  local result = pipe:read("*a")
  -- HostShell.pclose, never pipe:close(): closing a pipe outside the spawn
  -- lock can free a FILE while a worker thread's popen is walking the stream
  -- list, which deadlocks that thread for good (see HostShell).
  HostShell.pclose(pipe)
  HostShell.pumpHostEvents()
  result = trim(result)
  return result ~= "" and result or nil
end

local IMPORTS_DIR = "imports"
local BASE_ROMS_DIR = "baseroms"
local MODS_INBOX_DIR = "imports/mods"
local SAVES_INBOX_DIR = "imports/saves"
local ROM_BYTES_GEN1 = 1024 * 1024
local ROM_BYTES_GEN2 = 2 * 1024 * 1024
local ROM_BYTES_GEN3 = 16 * 1024 * 1024
-- Historical alias: Gen 1 helpers and tests still refer to ROM_BYTES.
local ROM_BYTES = ROM_BYTES_GEN1

local function isAcceptedRomSize(n)
  return n == 512 * 1024 or n == ROM_BYTES_GEN1 or n == ROM_BYTES_GEN2 or n == ROM_BYTES_GEN3
end

-- .gb / .gbc / .gba (case-insensitive after lowercasing the name).
local function isRomFilename(name)
  return type(name) == "string" and name:lower():match("%.gb[ac]?$") ~= nil
end

local function cartLabels(generation)
  local out = {}
  for _, id in ipairs(GameVersion.ORDER) do
    if generation == nil or GameVersion.generation(id) == generation then
      out[#out + 1] = GameVersion.info(id).label
    end
  end
  return out
end

local function cartsSlashed(generation)
  return table.concat(cartLabels(generation), "/")
end

local function cartsProse()
  local names = cartLabels(nil)
  local last = table.remove(names)
  if #names == 0 then return last end
  return table.concat(names, ", ") .. ", or " .. last
end

local function savesInboxDir(version)
  return SAVES_INBOX_DIR .. "/" .. tostring(version)
end

local function savesImportedHashesPath(version)
  return savesInboxDir(version) .. "/.imported-sha1"
end

local function exportsDir(version)
  return "exports/" .. tostring(version)
end

-- Strip only a validated sdmc:/ prefix for OpenMTP/DBI relative paths.
function RomImporter.mtpHintPath(saveDir)
  if type(saveDir) ~= "string" then return "" end
  if saveDir:sub(1, 6) == "sdmc:/" then return saveDir:sub(7) end
  return saveDir
end

function RomImporter:ensureImportsDir()
  local info = love.filesystem.getInfo(IMPORTS_DIR)
  if info and info.type == "directory" then return true end
  if info then return false end
  if love.filesystem.createDirectory then
    return love.filesystem.createDirectory(IMPORTS_DIR)
  end
  return false
end

-- NX mod zip inbox (separate from ROM imports/). Parent imports/ first --
-- love.filesystem.createDirectory does not create nested parents.
function RomImporter:ensureModsInboxDir()
  self:ensureImportsDir()
  local info = love.filesystem.getInfo(MODS_INBOX_DIR)
  if info and info.type == "directory" then return true end
  if info then return false end
  if love.filesystem.createDirectory then
    return love.filesystem.createDirectory(MODS_INBOX_DIR)
  end
  return false
end

-- NX raw .sav inbox per game: imports/saves/{red,blue,yellow}/.
-- Parent imports/ then imports/saves/ first -- createDirectory is not nested.
-- Creates all three version folders so MTP browsing shows where each game goes.
function RomImporter:ensureSavesInboxDir(version)
  self:ensureImportsDir()
  local info = love.filesystem.getInfo(SAVES_INBOX_DIR)
  if info and info.type ~= "directory" then return false end
  if not info then
    if not (love.filesystem.createDirectory
        and love.filesystem.createDirectory(SAVES_INBOX_DIR)) then
      return false
    end
  end
  for v in pairs(GameVersion.VERSIONS) do
    local dir = savesInboxDir(v)
    local vInfo = love.filesystem.getInfo(dir)
    if vInfo and vInfo.type ~= "directory" then return false end
    if not vInfo then
      if not (love.filesystem.createDirectory
          and love.filesystem.createDirectory(dir)) then
        return false
      end
    end
  end
  return true
end

function RomImporter:_setNxInboxNotice(version)
  version = version or self.tab or "red"
  local saveDir = love.filesystem.getSaveDirectory()
  local rel = RomImporter.mtpHintPath(saveDir)
  if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
  self.notice = {
    version = version,
    status = Strings("Copy your .gb/.gbc/.gba into:"),
    detail = Strings("%s/imports/\nDBI MTP → 1: SD Card/%simports/", saveDir, rel),
  }
end

function RomImporter:_setNxModsInboxNotice()
  local saveDir = love.filesystem.getSaveDirectory()
  local rel = RomImporter.mtpHintPath(saveDir)
  if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
  self.modNotice = {
    ok = true,
    text = Strings("Copy your .zip into:\n%s/imports/mods/\nDBI MTP → 1: SD Card/%simports/mods/",
      saveDir, rel),
  }
end

function RomImporter:_resolveSaveVersion(version)
  version = version or self.panelVersion or self.tab
  if GameVersion.VERSIONS[version] then return version end
  return self:_savedropTarget()
end

function RomImporter:_setNxSavesInboxNotice(version)
  version = self:_resolveSaveVersion(version)
  local inbox = savesInboxDir(version)
  local saveDir = love.filesystem.getSaveDirectory()
  local rel = RomImporter.mtpHintPath(saveDir)
  if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
  local game = GameVersion.info(version).displayName
  self.saveNotice = self.saveNotice or {}
  self.saveNotice[version] = {
    ok = true,
    text = Strings("Copy your %s .sav into:\n%s/%s/\nDBI MTP → 1: SD Card/%s%s/",
      game, saveDir, inbox, rel, inbox),
  }
end

local function listRomPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    -- Skip AppleDouble / hidden junk from Mac MTP (._cart.gb ends in .gb
    -- but is not a ROM -- rescan would try it first and block the real dump).
    if name:sub(1, 1) ~= "." then
      local path = (dir == "" or dir == "/") and name or (dir .. "/" .. name)
      if isRomFilename(name)
          and love.filesystem.getInfo(path, "file") then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

local function baseRomScanSatisfied(self)
  for _, version in ipairs(GameVersion.ORDER) do
    if not self.ready[version] and not self.baseRoms[version] then
      return false
    end
  end
  return true
end

function RomImporter:_queueBaseRomScan()
  if not self.baseRomDiscovery then return end
  if baseRomScanSatisfied(self) then
    self.baseRomScan = { state = "done" }
    return
  end
  self.baseRomScan = { state = "queued", index = 1 }
end

function RomImporter:_stepBaseRomScan()
  local scan = self.baseRomScan
  if not scan or scan.state == "done" or self.workState == "working" then
    return
  end
  if scan.state == "queued" then
    local info = love.filesystem.getInfo(BASE_ROMS_DIR)
    if not info and love.filesystem.createDirectory then
      love.filesystem.createDirectory(BASE_ROMS_DIR)
    end
    scan.paths = listRomPaths(BASE_ROMS_DIR)
    table.sort(scan.paths)
    scan.state = "running"
  end

  local path = scan.paths[scan.index]
  if not path then
    scan.state = "done"
    return
  end
  scan.index = scan.index + 1

  local info = love.filesystem.getInfo(path, "file")
  if info and isAcceptedRomSize(info.size) then
    local data = love.filesystem.read(path)
    if type(data) == "string" and isAcceptedRomSize(#data) then
      local version = GameVersion.forSha1(sha1(data))
      if version and not self.ready[version] and not self.baseRoms[version] then
        self.baseRoms[version] = {
          path = path,
          name = path:match("[^/\\]+$") or path,
        }
      end
    end
  end

  if baseRomScanSatisfied(self) or not scan.paths[scan.index] then
    scan.state = "done"
  end
end

local function listZipPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    -- Skip AppleDouble / hidden junk from Mac MTP (._foo.zip ends in .zip
    -- but is not a PhysFS archive -- mount fails with "could not be opened").
    if name:sub(1, 1) ~= "." then
      local path = (dir == "" or dir == "/") and name or (dir .. "/" .. name)
      if name:lower():match("%.zip$")
          and love.filesystem.getInfo(path, "file") then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

local function listSavPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    -- Skip AppleDouble / hidden junk from Mac MTP (._foo.sav ends in .sav
    -- but is not a real battery save -- import would fail and invent noise).
    if name:sub(1, 1) ~= "." then
      local path = (dir == "" or dir == "/") and name or (dir .. "/" .. name)
      if name:lower():match("%.sav$")
          and love.filesystem.getInfo(path, "file") then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

function RomImporter:scanInbox()
  local paths = {}
  for _, path in ipairs(listRomPaths(IMPORTS_DIR)) do
    paths[#paths + 1] = path
  end
  for _, path in ipairs(listRomPaths("")) do
  -- Root scan is second; imports/ entries were already collected above.
    paths[#paths + 1] = path
  end
  return paths
end

-- NX mods inbox: only *.zip under imports/mods/ (never ROM extensions).
function RomImporter:scanModsInbox()
  self:ensureModsInboxDir()
  return listZipPaths(MODS_INBOX_DIR)
end

-- NX saves inbox: only non-hidden *.sav under imports/saves/<version>/.
function RomImporter:scanSavesInbox(version)
  version = self:_resolveSaveVersion(version)
  self:ensureSavesInboxDir(version)
  return listSavPaths(savesInboxDir(version))
end

local function loadImportedSavHashes(version)
  local set = {}
  local raw = love.filesystem.read(savesImportedHashesPath(version))
  if type(raw) ~= "string" then return set end
  for line in raw:gmatch("[^\r\n]+") do
    local h = line:match("^(%x+)$")
    if h then set[h] = true end
  end
  return set
end

local function appendImportedSavHash(version, hash)
  if type(hash) ~= "string" or hash == "" then return end
  local path = savesImportedHashesPath(version)
  local prev = love.filesystem.read(path) or ""
  if prev:find(hash, 1, true) then return end
  love.filesystem.write(path, prev .. hash .. string.char(10))
end

-- Keep bytes for the player (MTP recovery) but stop matching %.sav$ on rescan.
local function retireImportedSav(path)
  if type(path) ~= "string" or path == "" then return false end
  local data = love.filesystem.read(path)
  if type(data) ~= "string" then return false end
  local dest = path .. ".imported"
  if love.filesystem.getInfo(dest) then
    dest = path .. ".imported." .. tostring(os.time())
  end
  if not love.filesystem.write(dest, data) then return false end
  love.filesystem.remove(path)
  return true
end

-- Rescan imports/mods/: install each .zip via _installMod / installZip.
-- Never deletes inbox zips (success or failure). Empty inbox → MTP notice.
function RomImporter:rescanModsAction()
  if self.workState == "working" then return end
  self:_switchTab("mods")
  self:ensureModsInboxDir()
  local candidates = self:scanModsInbox()
  if #candidates == 0 then
    self:_setNxModsInboxNotice()
    return
  end
  local anyOk = false
  local lastOk = nil
  local lastFail = nil
  local failCount = 0
  for _, path in ipairs(candidates) do
    -- Reuse _installMod carefully: it must not remove the inbox source.
    self:_installMod(path)
    if self.modNotice and self.modNotice.ok then
      anyOk = true
      lastOk = self.modNotice
    else
      failCount = failCount + 1
      lastFail = self.modNotice
    end
  end
  -- Success wins overall ok=true so a leftover MTP junk sibling cannot hide
  -- a good install; still append the last failure so a real broken zip is
  -- visible beside the success line.
  if anyOk and lastFail then
    local okText = (lastOk and lastOk.text) or "Installed"
    local failText = (lastFail and lastFail.text) or "unknown error"
    self.modNotice = {
      ok = true,
      text = Strings("%s\n(%d failed: %s)", okText, failCount, failText),
    }
  elseif anyOk then
    self.modNotice = lastOk
  elseif lastFail then
    self.modNotice = lastFail
  end
end

-- Rescan imports/saves/<version>/: import each new .sav via _importSave.
-- Failure retains the original .sav. Success records a per-game content hash
-- and retires the file to `*.sav.imported` so a second Import save cannot clone
-- slots (bytes stay in the inbox for MTP recovery). Already-hashed content
-- is skipped even under a new filename. Empty / AppleDouble-only → MTP notice.
function RomImporter:rescanSavesAction(version)
  if self.workState == "working" then return end
  version = self:_resolveSaveVersion(version)
  self:ensureSavesInboxDir(version)
  local candidates = self:scanSavesInbox(version)
  if #candidates == 0 then
    self:_setNxSavesInboxNotice(version)
    return
  end
  local seenHashes = loadImportedSavHashes(version)
  local okCount, failCount, skipCount = 0, 0, 0
  local lastOk, lastFail = nil, nil
  local gameLabel = GameVersion.info(version).displayName
  for _, path in ipairs(candidates) do
    local data = love.filesystem.read(path)
    local hash = (type(data) == "string" and data ~= "") and sha1(data) or nil
    if hash and seenHashes[hash] then
      skipCount = skipCount + 1
      -- Leftover live .sav after a prior success: retire without re-importing.
      retireImportedSav(path)
    else
      self:_importSave(version, path)
      local notice = self.saveNotice and self.saveNotice[version]
      if notice and notice.ok then
        okCount = okCount + 1
        lastOk = notice
        if hash then
          seenHashes[hash] = true
          appendImportedSavHash(version, hash)
        end
        retireImportedSav(path)
      else
        failCount = failCount + 1
        lastFail = notice
      end
    end
  end
  if okCount > 0 then
    local okText
    if okCount == 1 and lastOk then
      okText = Strings("%s (%s tab)", lastOk.text, gameLabel)
    else
      okText = Strings("Imported %d saves into %s. Active: %s.",
        okCount, gameLabel, tostring(self.activeSlot[version]))
    end
    if failCount > 0 then
      local failText = (lastFail and lastFail.text) or "unknown error"
      okText = Strings("%s\n(%d failed: %s)", okText, failCount, failText)
    end
    if skipCount > 0 then
      okText = Strings("%s\n(%d already imported, skipped)", okText, skipCount)
    end
    self.saveNotice[version] = { ok = true, text = okText }
  elseif failCount > 0 then
    self.saveNotice[version] = lastFail
  elseif skipCount > 0 then
    self.saveNotice[version] = {
      ok = true,
      text = Strings("Already imported: %d file(s) skipped. Check SAVE SLOT.",
        skipCount),
    }
  end
end

-- NX "Scan again" on a game tab: import only the dump whose SHA-1 matches
-- that tab. A shared imports/ inbox often holds Red+Blue+Yellow at once;
-- picking the first pending file would jump Yellow → Red (and switch the
-- launcher tab via startData). Other known dumps stay for their own tabs.
-- Junk (wrong size / unknown hash) still surfaces when nothing matches the
-- tab and no other known dump is present -- same feedback as before for a
-- lone bad file.
function RomImporter:rescanAction(version)
  if self.workState == "working" then return end
  version = version or self.tab or "red"
  self.chooseVersion = version
  self:ensureImportsDir()
  local ready = self.ready
  local candidates = self:scanInbox()
  local targetReady = false
  local sawOtherVersion = false
  local junkData, junkName = nil, nil
  for _, path in ipairs(candidates) do
    local data = love.filesystem.read(path)
    local displayName = path:match("[^/\\]+$") or path
    if type(data) ~= "string" then
      self:setError(Strings("The file could not be read: %s", displayName), version)
      return
    end
    if not isAcceptedRomSize(#data) then
      if not junkData then junkData, junkName = data, displayName end
    else
      local romVersion = GameVersion.forSha1(sha1(data))
      if not romVersion then
        if not junkData then junkData, junkName = data, displayName end
      elseif romVersion ~= version then
        sawOtherVersion = true
      elseif ready[romVersion] then
        targetReady = true
      else
        self:startData(data, displayName)
        return
      end
    end
  end
  if targetReady then
    self.notice = {
      version = version,
      status = Strings("No new ROM found."),
      detail = Strings("Already-imported dumps are ignored. Add another version or "
        .. "delete the copy when finished."),
    }
    return
  end
  if junkData and not sawOtherVersion then
    self:startData(junkData, junkName)
    return
  end
  if #candidates > 0 then
    local label = GameVersion.info(version).displayName
    self.notice = {
      version = version,
      status = Strings("No matching ROM found."),
      detail = Strings(
        "%s is matched by SHA-1 on this tab. Other dumps in imports/ stay "
          .. "for their own tabs; open that game and Scan again.", label),
    }
    return
  end
  self:_setNxInboxNotice(version)
end

function RomImporter:_romAction(version)
  if self.isNX then
    if self.ready[version] then self:reimport(version)
    else self:rescanAction(version) end
  elseif self.ready[version] then self:reimport(version)
  else self:choose(version) end
end

-- Sanitize a string before it is interpolated into a picker shell command:
--   * "%" would be eaten as a string.format directive (#665);
--   * '"' would break the AppleScript / zenity double-quoted argument and
--     "'" the surrounding single-quoted shell string.
local function shellSafe(s)
  s = tostring(s):gsub("%%", "%%%%")
  return s:gsub('"', '\\"'):gsub("'", "''")
end

-- LOVE 11.5 on Android has no native file picker (love.window.showFileDialog
-- is a LOVE 12 nightly-only addition) and never fires love.filedropped, so
-- neither desktop path below works there. conf.lua points the Android save
-- directory at the app's external-files folder instead (readable/writable
-- via USB or a file manager, no runtime permission needed), and this scans
-- it directly through love.filesystem -- already mounted at the physfs
-- root, so no io.* absolute-path handling is needed.
--
-- Only a .gb/.gbc/.gba whose SHA maps to a version that is not yet ready
-- counts as pending.  GameActivity always writes the SAF pick to
-- picked_rom.gb, so a naive "first ROM wins" scan would re-import Red when
-- the player tries to add Blue (issue #167).  Yellow and Gold carts are
-- typically .gbc (Gold is 2 MiB); FireRed is a 16 MiB .gba.
-- `wanted` narrows the scan to one version.  A Choose names the cart it is
-- for, so without it several dumps sitting in the save directory answered in
-- listing order and the selection was dropped: picking Red imported Blue
-- (#1274).  The callers that are not a Choose, the Android USB-drop scans,
-- pass nothing and still take the first pending cart of any version.
local function findPendingRom(ready, wanted)
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if isRomFilename(name) and love.filesystem.getInfo(name, "file") then
      local data = love.filesystem.read(name)
      if type(data) == "string" and isAcceptedRomSize(#data) then
        local version = GameVersion.forSha1(sha1(data))
        if version and not ready[version]
            and (wanted == nil or version == wanted) then
          return name, data
        end
      end
    end
  end
  return nil
end

local function importPendingRom(self)
  local name, data = findPendingRom(self.ready, self.chooseVersion)
  if not name then return false end
  self:startData(data, name)
  return true
end

-- GameActivity always writes the SAF pick to picked_rom.gb, so a leftover
-- under that exact basename is the file the player just chose and
-- findPendingRom silently refused: wrong size, or a hacked/overdumped cart
-- whose SHA-1 matches no known version ([b]/[BF] dumps never will).  Route it
-- through startData so the launcher says which of the two it was instead of
-- staying on "No ROM imported" with no message at all (issue #442), and drop
-- the file so the next tap starts from a clean slate.  A cart that is simply
-- already imported is not an error -- #167 skips it on purpose -- so leave
-- that one alone.
local function consumePickedRomError(self)
  local preferred = "picked_rom.gb"
  if not love.filesystem.getInfo(preferred, "file") then return false end
  local data = love.filesystem.read(preferred)
  if type(data) == "string" and isAcceptedRomSize(#data) then
    local version = GameVersion.forSha1(sha1(data))
    if version and self.ready[version] then return false end
  end
  love.filesystem.remove(preferred)
  if type(data) ~= "string" then
    self:setError("The picked file could not be read. Reopen the picker and "
      .. "choose the ROM with the Files (Documents) app.")
    return true
  end
  self:startData(data, preferred)
  return true
end

-- Android SAF writes mod picks to picked_mod.zip; USB copies may use any
-- .zip basename at the save-dir root.  preferAny=true also accepts those USB
-- copies (Choose / Import); focus only consumes the SAF basename so a random
-- leftover archive is never auto-installed on every refocus.
local function findPendingMod(preferAny, skip)
  local preferred = "picked_mod.zip"
  if love.filesystem.getInfo(preferred, "file") then
    return preferred
  end
  if not preferAny then return nil end
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:lower():match("%.zip$") and not (skip and skip[name])
        and love.filesystem.getInfo(name, "file") then
      return name
    end
  end
  return nil
end

-- Same pattern as findPendingMod for battery saves (picked_save.sav / *.sav).
local function findPendingSav(preferAny, skip)
  local preferred = "picked_save.sav"
  if love.filesystem.getInfo(preferred, "file") then
    return preferred
  end
  if not preferAny then return nil end
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:lower():match("%.sav$") and not (skip and skip[name])
        and love.filesystem.getInfo(name, "file") then
      return name
    end
  end
  return nil
end

local function pickerHasKind(kind)
  local fn = love.system.pickFileKinds
  if type(fn) ~= "function" then return false end
  local ok, kinds = pcall(fn)
  if not ok or type(kinds) ~= "string" then return false end
  for token in kinds:gmatch("[^,%s]+") do
    if token == kind then return true end
  end
  return false
end

local function findPendingRequiredImport(self)
  local names = { "picked_required_import.bin", "picked_stadium.z64" }
  -- Builds released before required_import was added to the Android JNI bridge
  -- only understand the long-standing "rom" picker kind.  While a required
  -- import request is in flight, it is safe to treat its staging name as a
  -- dependency file: the pending IDs below select the same validation/copy
  -- path as a current bridge.  Never scan picked_rom.gb otherwise, since that
  -- remains reserved for an ordinary game-ROM import.
  if self and self.requiredImportLegacyRomPick
      and self.pickerPendingKind == "required_import" then
    names[#names + 1] = "picked_rom.gb"
  end
  for _, name in ipairs(names) do
    if love.filesystem.getInfo(name, "file") then return name end
  end
  return nil
end

local function importerPickName(importerId)
  return "picked_importer_" .. tostring(importerId) .. ".bin"
end

local function findPendingImporter(self)
  if self and self.pickerPendingImporterId then
    local name = importerPickName(self.pickerPendingImporterId)
    if love.filesystem.getInfo(name, "file") then
      return name, self.pickerPendingImporterId
    end
  end

  local Importers = require("src.import.Importers")
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    local importerId = name:lower():match(
      "^picked_importer_([%l%d_%-]+)%.bin$")
    if importerId and Importers.get(importerId)
        and love.filesystem.getInfo(name, "file") then
      return name, importerId
    end
  end
  return nil
end

-- Retire an Android pick once it has been through the installer / importer,
-- whether or not it worked: a pick left on disk wins the scans above forever,
-- so the next tap re-runs the same failing file and the picker never reopens
-- (#420).  The SAF basename is GameActivity's own copy of the pick and is
-- always deleted; a USB copy is the player's file, so a failed one is only
-- skipped for the rest of the session.
local function consumePick(self, name, safName, ok)
  if ok or name == safName then
    love.filesystem.remove(name)
    return
  end
  self.pickSkip = self.pickSkip or {}
  self.pickSkip[name] = true
end

local function chooseRom(promptName)
  promptName = promptName or "Pokemon"
  local prompt = shellSafe("Choose your " .. promptName .. " ROM")
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"gb", "gbc", "gba"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Game Boy / GBA ROM (*.gb;*.gbc;*.gba)|*.gb;*.gbc;*.gba|All files (*.*)|*.*';",
      -- copy the pick to a plain-ASCII temp name and answer with that:
      -- the console's OEM codepage would mangle a non-ASCII path
      -- (Pokémon -> Pok\x82mon) and io.open on Windows needs ANSI bytes,
      -- so returning the original name both crashed the notice draw and
      -- could never have opened the file (#325, #665)
      "if($d.ShowDialog() -eq 'OK'){",
      "$t=Join-Path $env:TEMP 'pokeport_rom_pick.gb';",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Game Boy / GBA ROM | *.gb *.gbc *.gba" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.gb *.gbc *.gba|Game Boy / GBA ROM" 2>/dev/null]])
  end
  return nil
end

-- chooseRom for an importer's own dump: same per-OS dialogs, but the file
-- types come from the importer descriptor rather than being Game Boy ROMs.
local function chooseImporterFile(promptName, exts)
  local prompt = shellSafe("Choose your " .. (promptName or "game") .. " dump")
  local platform = love.system.getOS()
  local quoted, globs, semis = {}, {}, {}
  for _, ext in ipairs(exts) do
    quoted[#quoted + 1] = ('"%s"'):format(ext)
    globs[#globs + 1] = "*." .. ext
    semis[#semis + 1] = "*." .. ext
  end
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {%s})' 2>/dev/null]])
        :format(prompt, table.concat(quoted, ", ")))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Cartridge dump (" .. table.concat(semis, ";") .. ")|"
        .. table.concat(semis, ";") .. "|All files (*.*)|*.*';",
      "if($d.ShowDialog() -eq 'OK'){",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($d.FileName)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Cartridge dump | %s" 2>/dev/null]])
        :format(prompt, table.concat(globs, " ")))
    if path then return path end
    return commandOutput(
      ([[kdialog --getopenfilename "$HOME" "%s|Cartridge dump" 2>/dev/null]])
        :format(table.concat(globs, " ")))
  end
  return nil
end

-- Open a native picker for a mod .zip (mirrors chooseRom's per-OS dialogs).
-- Returns the chosen absolute path or nil.  Android uses love.system.pickFile
-- ("mod") instead -- see RomImporter:chooseMod.
local function chooseZip()
  local prompt = shellSafe(Strings("Choose a mod .zip"))
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"zip"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Mod archive (*.zip)|*.zip|All files (*.*)|*.*';",
      -- copy the pick to a plain-ASCII temp name and answer with that:
      -- the console's OEM codepage would mangle a non-ASCII path
      -- (Pokémon -> Pok\x82mon) and io.open on Windows needs ANSI bytes,
      -- so returning the original name both crashed the notice draw and
      -- could never have opened the file (#325)
      "if($d.ShowDialog() -eq 'OK'){",
      "$t=Join-Path $env:TEMP 'pokeport_mod_pick.zip';",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Mod archive | *.zip" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.zip|Mod archive" 2>/dev/null]])
  end
  return nil
end

-- Open a native picker for a raw .sav battery save (mirrors chooseZip's per-OS
-- dialogs).  Returns the chosen absolute path or nil.  Android uses
-- love.system.pickFile("sav") instead -- see RomImporter:chooseSaveImport.
local function chooseSav()
  local prompt = shellSafe(Strings("Choose a .sav save file"))
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"sav"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Game Boy save (*.sav)|*.sav|All files (*.*)|*.*';",
      -- copy the pick to a plain-ASCII temp name: io.open on Windows
      -- needs ANSI bytes, so a non-ASCII path (Pokémon -> Pok\x82mon)
      -- could never have been opened (#325, #665)
      "if($d.ShowDialog() -eq 'OK'){",
      "$t=Join-Path $env:TEMP 'pokeport_sav_pick.sav';",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Game Boy save | *.sav" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.sav|Game Boy save" 2>/dev/null]])
  end
  return nil
end

-- Generic user-supplied dependency picker. Keep the native prompt entirely
-- engine-owned: manifest labels are untrusted and must never enter shell
-- command templates. The LÖVE modal already shows the specific import name.
local function chooseRequiredFile()
  local prompt = shellSafe(Strings("Choose required mod file"))
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s")' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='All files (*.*)|*.*';",
      -- Required imports can be multi-gigabyte optical-disc images. Do NOT
      -- stage them through %TEMP%: that doubles free-space requirements and a
      -- failed Copy-Item can leave a plausible-looking truncated temp file.
      -- Stream the selected source directly into the mod-owned destination.
      "if($d.ShowDialog() -eq 'OK'){",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($d.FileName)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" 2>/dev/null]]):format(prompt))
    if path then return path end
    return commandOutput([[kdialog --getopenfilename "$HOME" 2>/dev/null]])
  end
  return nil
end

function RomImporter:focus(f)
  if not f then
    self._activeTouch = nil
    self._pagePress = nil
    self._slotPress = nil
    self._modPress = nil
    return
  end
  if type(self._sync) == "table" then
    pcall(self._sync.noteResumed, self._sync)
  end
  if not (f and self.android and self.workState ~= "working") then return end
  -- SAF create-document finished: GameActivity wrote export_done.flag.
  if love.filesystem.getInfo("export_done.flag", "file") then
    love.filesystem.remove("export_done.flag")
    love.filesystem.remove("pending_export.sav")
    if self.androidPendingCartExport then
      self.androidPendingCartExport = nil
      self._cartNotice = Strings("Cart exported.")
      return
    end
    local version = self.androidPendingExportVersion or self:_savedropTarget()
    self.androidPendingExportVersion = nil
    self.saveNotice[version] = { ok = true, text = Strings("Save exported.") }
    if self.tab == "mods" then self.tab = version end
    return
  end
  -- The SAF pick failed inside GameActivity, which wrote pick_error.flag with
  -- the destination basename in it: some OEM shells (ColorOS) let a third-party
  -- archive manager win the ACTION_OPEN_DOCUMENT chooser and hand back a URI
  -- this app has no permission to read, and until #442 that returned to a
  -- launcher that said nothing at all.
  local pickError = love.filesystem.getInfo("pick_error.flag", "file")
    and love.filesystem.read("pick_error.flag")
  if pickError then
    love.filesystem.remove("pick_error.flag")
    local text
    if pickError:find("cancelled:", 1, true) == 1 then
      text = Strings("The file manager did not return a file. Try a different file manager, or copy it into: %s",
        love.filesystem.getSaveDirectory())
    else
      text = Strings("Could not read the picked file. Reopen the picker and choose it with the Files (Documents) app, or copy it into: %s",
        love.filesystem.getSaveDirectory())
    end
    local legacyRequiredPick = self.requiredImportLegacyRomPick
      and self.pickerPendingKind == "required_import"
    if self.pickerPendingKind == "importer"
        or pickError:find("picked_importer_", 1, true) then
      self._importerNotice = { ok = false, text = text }
      self.pickPending = nil
      self.pickerPendingKind = nil
      self.pickerPendingImporterId = nil
    elseif self.pickerPendingKind == "required_import"
        or pickError:find("picked_required_import", 1, true)
        or pickError:find("picked_stadium", 1, true)
        or pickError:find("/baseroms/", 1, true)
        or pickError:find("\\baseroms\\", 1, true)
        or (legacyRequiredPick and pickError:find("picked_rom", 1, true)) then
      self.modNotice = { ok = false, text = text }
      self.pickerPendingKind = nil
      self.pickerPendingModId = nil
      self.pickerPendingImportId = nil
      self.requiredImportLegacyRomPick = nil
    elseif pickError:find("picked_mod", 1, true) then
      if self.pickerPendingKind == "skin" then
        self.pickerPendingKind = nil
        self._skinNotice = { ok = false, text = text }
      else
        self.modNotice = { ok = false, text = text }
      end
    elseif pickError:find("picked_save", 1, true) then
      local version = self.androidPendingVersion or self:_savedropTarget()
      self.androidPendingVersion = nil
      self.saveNotice[version] = { ok = false, text = text }
    else
      self:setError(text)
    end
    return
  end

  -- Current mobile bridge: the native picker has already streamed a raw
  -- dependency into mods/<id>/baseroms and published its digest/size marker.
  local completedRequired = love.filesystem.getInfo(PICK_COMPLETE_FILENAME, "file")
    and love.filesystem.read(PICK_COMPLETE_FILENAME)
  if completedRequired then
    love.filesystem.remove(PICK_COMPLETE_FILENAME)
    self.pickPending = nil
    finishDirectRequiredImport(self, completedRequired)
    self.pickerPendingKind = nil
    self.pickerPendingModId = nil
    self.pickerPendingImportId = nil
    self.requiredImportLegacyRomPick = nil
    return
  end

  local importerName, importerId = findPendingImporter(self)
  if importerName then
    local data = love.filesystem.read(importerName)
    love.filesystem.remove(importerName)
    self.pickPending = nil
    self.pickerPendingKind = nil
    self.pickerPendingImporterId = nil
    if type(data) ~= "string" then
      self._importerNotice = {
        ok = false,
        text = Strings("Could not read the picked importer file."),
      }
    else
      self:_runImporterData(importerId, data)
    end
    return
  end

  local requiredName = findPendingRequiredImport(self)
  if requiredName then
    local modId, importId = self.pickerPendingModId, self.pickerPendingImportId
    self.pickerPendingKind = nil
    self.pickerPendingModId, self.pickerPendingImportId = nil, nil
    self.requiredImportLegacyRomPick = nil
    local imported = modId and importId
      and self:_importRequiredSource(modId, importId, requiredName)
    consumePick(self, requiredName, requiredName, imported)
    if not modId or not importId then
      self.modNotice = { ok = false,
        text = Strings("A picked dependency file had no pending mod request and was discarded.") }
    end
    return
  end
  local modName = findPendingMod(false, self.pickSkip)
  if modName then
    if self.pickerPendingKind == "skin" then
      self.pickerPendingKind = nil
      self:_installSkinZip(modName)
      consumePick(self, modName, "picked_mod.zip",
        self._skinNotice and self._skinNotice.ok)
      return
    end
    self:_installMod(modName)
    consumePick(self, modName, "picked_mod.zip",
      self.modNotice and self.modNotice.ok)
    return
  end
  local savName = findPendingSav(false, self.pickSkip)
  if savName then
    local version = self.androidPendingVersion or self:_savedropTarget()
    self.androidPendingVersion = nil
    self:_importSave(version, savName)
    consumePick(self, savName, "picked_save.sav",
      self.saveNotice[version] and self.saveNotice[version].ok)
    return
  end
  for _, v in ipairs(GameVersion.ORDER) do
    if not self.ready[v] then
      local name, data = findPendingRom(self.ready)
      if name then
        self:startData(data, name)
      else
        consumePickedRomError(self)
      end
      return
    end
  end
end

function RomImporter:setError(message, version)
  require("src.import.CacheFs").prefix = ""
  self.workState = "error"
  self.errorVersion = version or self.importing or self.chooseVersion or "red"
  self.importing = nil
  self.notice = nil
  self.status = Strings("That ROM could not be imported")
  self.detail = Strings(tostring(message))
  self.progress = 0
  self.worker = nil
  -- Dropping the job stops collection; the next import clears the channels.
  self._extract = nil
  self.romData = nil
  -- A headless import has no launcher to read this off: POKEPORT_IMPORT_ONLY
  -- only ever quits from onComplete, so an import that fails here would sit in
  -- the error state forever and look to a build script (or a person) exactly
  -- like a hang.  Log what broke and exit non-zero instead.  Logger, not a
  -- literal write: this is a diagnostic for whoever ran the import, never text
  -- a player sees, so it is deliberately not a translated string.
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
    Logger.error("import failed: %s", tostring(message))
    love.event.quit(1)
  end
end

-- draw() may leave the system hand cursor set while hovering a Play /
-- Choose control.  Once the importer is torn down that draw path stops
-- running, so restore the arrow before handing off to boot (issue #114).
local function resetPointerCursor(self)
  if self.android then return end
  if not (love.mouse.isCursorSupported and love.mouse.isCursorSupported()) then
    return
  end
  if not self.arrowCursor then
    local ok, cursor = pcall(love.mouse.getSystemCursor, "arrow")
    if not ok then return end
    self.arrowCursor = cursor
  end
  love.mouse.setCursor(self.arrowCursor)
end

-- Verify + extract a ROM.  The version is decided by the ROM's own SHA-1, so
-- dropping a Red, Blue, or Yellow cart into any column always lands in the
-- right one.
function RomImporter:startData(data, displayName)
  if self.workState == "working" then return end
  if type(data) ~= "string" then
    self:setError(Strings("The selected file could not be read."))
    return
  end
  if not isAcceptedRomSize(#data) then
    self:setError(Strings("Expected a 512 KiB Japanese Red ROM, a 1 MiB Game Boy ROM (%s), a "
      .. "2 MiB Game Boy Color ROM (%s), or a 16 MiB Game Boy Advance ROM (%s); "
      .. "this file is %.2f MiB.",
        cartsSlashed(1), cartsSlashed(2), cartsSlashed(3),
        #data / 1024 / 1024))
    return
  end
  local actualHash = sha1(data)
  local version = GameVersion.forSha1(actualHash)
  if not version then
    self:setError(Strings("Unsupported ROM (SHA-1 %s). This needs Japanese Red v1.0/v1.1 or a clean US Pokemon "
      .. "%s dump; patched, trimmed or "
      .. "\"fixed\" dumps "
      .. "(tagged [b] or [BF]) never verify.", actualHash, cartsProse()))
    return
  end
  self.romSha1 = actualHash
  local info = GameVersion.info(version)
  if not require("src.import.RomManifest").validateRomData(version, data, actualHash) then
    self:setError(Strings("The Japanese Red ROM header does not match v%s.",
      GameVersion.revisionLabel(version, actualHash) or "?"), version)
    return
  end
  -- A missing/broken packaged revision overlay must not discard a playable
  -- existing cache. The worker decodes its own table again after this gate.
  if info.language == "ja" then
    local valid, metadataError = pcall(require("src.import.RomManifest").decode, version, actualHash)
    if not valid then
      Logger.error("Japanese ROM metadata preflight failed: %s", tostring(metadataError))
      self:setError(version == "red_jp" and Strings("Japanese Red import metadata is missing or invalid. Please reinstall the app.")
        or "にほんご ROMの よみこみデータに\nもんだいが あります。\nアプリを いれなおしてください。", version)
      return
    end
  end

  -- Bring the launcher to this version's tab so its progress bar is on screen
  -- (a dropped cart is routed by SHA-1 regardless of which tab was showing).
  if GameVersion.VERSIONS[self.tab] then
    self.tab = version
  end
  self.importing = version
  self.workState = "working"
  self.notice = nil
  self.status = Strings("Verifying %s", info.displayName)
  self.detail = displayName or info.displayName
  self.progress = 0
  self.romData = data
  self.status = Strings("Preparing private game data")

  -- Clear this version's previous cache from both homes before anything
  -- writes.  Stays on the main thread so delete-then-fill-then-mark keeps one
  -- owner; the prefix is restored at once because the worker sets its own.
  local CacheFs = require("src.import.CacheFs")
  local prefix = info.cachePrefix
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = prefix
  local cleared, clearError = pcall(function()
    removeTree(prefix .. "data/generated")
    removeTree(prefix .. "assets/generated")
    love.filesystem.remove(prefix .. CacheContract.MARKER_PATH)
    CacheFs.removeTree("data/generated")
    CacheFs.removeTree("assets/generated")
    CacheFs.remove(CacheContract.MARKER_PATH)
  end)
  CacheFs.prefix = savedPrefix
  if not cleared then
    self:setError(tostring(clearError), version)
    return
  end

  if self:_startExtractThread(version, prefix, data, displayName) then return end
  self:_startExtractCoroutine(version, info, prefix, displayName)
end

-- False when threads are unavailable, so the coroutine path still covers
-- that host.  POKEPORT_NO_THREAD=1 forces it, which is the only way to
-- exercise the fallback on a desktop.
function RomImporter:_startExtractThread(version, prefix, data, displayName)
  if os.getenv("POKEPORT_NO_THREAD") == "1" then return false end
  if not (love.thread and love.thread.newThread) then return false end
  local ok, thread = pcall(love.thread.newThread, "src/import/ExtractThread.lua")
  if not ok or not thread then return false end
  local progressName = "rom_import_progress"
  local resultName = "rom_import_result"
  love.thread.getChannel(progressName):clear()
  love.thread.getChannel(resultName):clear()
  local started = pcall(thread.start, thread, version, prefix, data,
    progressName, resultName, self.romSha1)
  if not started then return false end
  self._extract = {
    thread = thread, version = version, prefix = prefix,
    displayName = displayName,
    progress = love.thread.getChannel(progressName),
    result = love.thread.getChannel(resultName),
  }
  -- The worker owns the bytes now; drop ours so the 1-16 MiB string can go.
  self.romData = nil
  return true
end

function RomImporter:_startExtractCoroutine(version, info, prefix, displayName)
  self.worker = coroutine.create(function()
    coroutine.yield()
    local CacheFs = require("src.import.CacheFs")
    CacheFs.prefix = prefix
    local manifest = require("src.import.RomManifest").decode(version, self.romSha1)
    local gen = GameVersion.generation(version)
    local RomExtractor = gen == 3
      and require("src.import.RomExtractorGen3")
      or gen == 2
      and require("src.import.RomExtractorGen2")
      or require("src.import.RomExtractor")
    local extractor = RomExtractor.new(self.romData, manifest,
      function(progress, total, stage, current, stageTotal)
        self.status = stage -- launcher shows a translated progress percentage
        self.progress = progress / total
        self.stageCurrent = current
        self.stageTotal = stageTotal
        coroutine.yield()
      end, self.romSha1)
    extractor:run()
    CacheFs.prefix = ""   -- restore the default so later writes stay at the root
    self.romData = nil
    collectgarbage("collect")
    self:_completeImport(version, prefix, displayName)
  end)
end

-- Everything after the tree is filled, shared by both worker paths.  Raises
-- on a failed marker write; the thread path calls it inside a pcall.
function RomImporter:_completeImport(version, prefix, displayName)
  local info = GameVersion.info(version)
  local CacheFs = require("src.import.CacheFs")
  -- Written last: the marker is what isReady() checks, so it must only
  -- appear once every required file is in place.
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = prefix
  local ok, writeError = CacheContract.publish(version, CacheFs, self.romSha1)
  CacheFs.prefix = savedPrefix
  if not ok then
    error("could not finish the private cache: " .. tostring(writeError))
  end
  self.ready[version] = true
  self.returning[version] = false
  self.romName[version] = (displayName
    and (displayName:match("[^/\\]+$") or displayName)) or self.romName[version]
  -- Android: drop the consumed save-dir .gb/.gbc/.gba (picked_rom.gb or a USB copy)
  -- so the next Choose / focus cannot treat it as a fresh pending ROM.
  if self.mobileFileBridge and type(displayName) == "string"
      and not displayName:find("[/\\]") then
    love.filesystem.remove(displayName)
  end
  self.importing = nil
  self.workState = "complete"
  self.completeVersion = version
  self.status = Strings("Ready")
  RomImporter.syncAndroidShortcuts(version)
  -- NX launcher stays put: keep the imports/ cleanup hint instead of
  -- overwriting it with a "Starting…" line that never boots from here.
  if self.launcher and self.isNX and type(displayName) == "string" then
    self.detail = Strings("%s imported. You may delete the copy from "
      .. "imports/ when finished.", displayName)
  else
    self.detail = Strings("Starting %s...", info.displayName)
  end
  self.progress = 1
  if self.launcher then
    -- Stay on the launcher; the player presses Play to boot the new game.
    return
  end
  self._handedOff = true
  resetPointerCursor(self)
  if self._flex then require("src.import.LauncherView").detach(self) end
  if self.onComplete then self.onComplete(version) end
end

-- Drain the worker's progress and finish when it reports done.  One
-- non-blocking poll per frame, like the other _pump* collectors above.
function RomImporter:_pumpExtract()
  local job = self._extract
  if not job then return end
  local msg = job.progress:pop()
  while msg do
    self.status = msg.stage
    self.progress = msg.progress / msg.total
    self.stageCurrent = msg.current
    self.stageTotal = msg.stageTotal
    msg = job.progress:pop()
  end
  local res = job.result:pop()
  if not res then
    -- A thread that died before pushing a result would strand the loader.
    local threadError = job.thread.getError and job.thread:getError()
    if threadError then
      self._extract = nil
      self:setError(tostring(threadError), job.version)
    end
    return
  end
  self._extract = nil
  if not res.ok then
    self:setError(tostring(res.error), job.version)
    return
  end
  local ok, err = pcall(self._completeImport, self, job.version, job.prefix,
    job.displayName)
  if not ok then self:setError(tostring(err), job.version) end
end

function RomImporter:startPath(path)
  if not path then return end
  local data, readError = readExternalPath(path)
  if not data then
    self:setError(Strings("Could not read the selected file: %s", tostring(readError)))
    return
  end
  self:startData(data, path:match("[^/\\]+$") or path)
end

function RomImporter:filedropped(file)
  if self.workState == "working" then return end
  -- A dropped .zip is a mod archive: hand it straight to the mods installer
  -- (which mounts + validates it).  A .deltaskin is only ever a skin, and
  -- everything else is treated as a ROM.  The dropped file itself is passed
  -- through -- installZip opens it the same way readDroppedFile does here.
  local name = file:getFilename() or ""
  if name:lower():match("%.deltaskin$") then
    self:_installSkinZip(file)
    return
  end
  if name:lower():match("%.zip$") then
    -- On the SKINS tab a zip is a skin; everywhere else it is a mod archive.
    if self.tab == "skins" then
      self:_installSkinZip(file)
    else
      self:_installMod(file)
    end
    return
  end
  -- A dropped .sav is a battery save: import it to a new slot for the active
  -- game tab (see _savedropTarget for the tab-selection rule).  It never steals
  -- .gb/.zip routing above.
  if name:lower():match("%.sav$") then
    self:_importSave(self:_savedropTarget(), file)
    return
  end
  local data, readError = readDroppedFile(file)
  if not data then
    self:setError(Strings("Could not read the dropped file: %s", tostring(readError)))
    return
  end
  if self._importerDropFor then
    local importerId = self._importerDropFor
    self._importerDropFor = nil
    self:_runImporterData(importerId, data)
    return
  end
  self:startData(data, file:getFilename())
end

-- Install a mod .zip from a picker path or a dropped file, then surface the
-- result on the mods panel (switching to it so the notice is visible).  The
-- source is whatever LauncherMods.installZip accepts: an absolute path string
-- or a love DroppedFile.
function RomImporter:_installMod(source)
  if self.workState == "working" then return end
  self:_switchTab("mods")
  local ok, installed, res, manifest = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    return LauncherMods.installZip(source)
  end)
  if not ok then
    self.modNotice = { ok = false,
      text = Strings("Import failed: %s", tostring(installed)) }
    return
  end
  if installed then
    pcall(self._refreshMods, self)
    self.modNotice = { ok = true, text = Strings("Installed %s", tostring(res)) }
    local LauncherMods = require("src.mods.LauncherMods")
    local checkTarget = manifest
    if not checkTarget and type(res) == "string" then
      checkTarget = { id = res }
    end
    if checkTarget and LauncherMods.checkDependencies then
      local depCheck = LauncherMods.checkDependencies(checkTarget)
      if depCheck and depCheck.hasIssues then
        self._modDepResolver = depCheck
      end
    end
  else
    self.modNotice = { ok = false, text = tostring(res) }
  end
end

-- Remove an installed mod from the save-dir mods/ tree and refresh the panel.
function RomImporter:_deleteMod(id)
  if self.workState == "working" then return end
  local ok, deleted, res = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    return LauncherMods.uninstall(id)
  end)
  if not ok then
    self.modNotice = { ok = false,
      text = Strings("Delete failed: %s", tostring(deleted)) }
    return
  end
  if deleted then
    pcall(self._refreshMods, self)
    self.modNotice = { ok = true, text = Strings("Deleted %s", tostring(id)) }
  else
    self.modNotice = { ok = false, text = tostring(res) }
  end
end

-- "Import mod .zip" button: open a native picker and install the pick.
-- Android mirrors ROM import: scan for a pending .zip in the save dir (USB
-- or a fresh SAF drop), else love.system.pickFile("mod") -> picked_mod.zip
-- which focus/Choose consumes on return.
-- NX: no HostShell/desktop picker -- rescan imports/mods/ inbox instead.
function RomImporter:chooseMod()
  if self.workState == "working" then return end
  if self.isNX then
    self:ensureModsInboxDir()
    self:rescanModsAction()
    return
  end
  if self.nativePicker and love.system.getPickedFile then
    self.pickerPendingKind = "mod"
    if not pickFile("mod") then
      self.pickerPendingKind = nil
      self.modNotice = { ok = false, text = Strings("Could not open the file picker.") }
    end
    return
  end
  if self.android then
    local name = findPendingMod(true, self.pickSkip)
    if name then
      self:_installMod(name)
      consumePick(self, name, "picked_mod.zip",
        self.modNotice and self.modNotice.ok)
      return
    end
    if not pickFile("mod") then
      self.modNotice = { ok = false,
        text = Strings("Could not open the file picker. Copy a mod .zip via USB.") }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local isHandheld = os.getenv("HANDHELD") == "1" or os.getenv("PORTMASTER") == "1"
    or os.getenv("POKEPORT_HANDHELD") == "1" or os.getenv("TRIMUI") == "1"
    or os.getenv("MUOS") == "1" or os.getenv("KNULLI") == "1"

  if isHandheld then
    local okKit, Kit = pcall(require, "src.ui.kit.Kit")
    if okKit and Kit.FileBrowser then
      self._padCursorActive = false
      Kit.FileBrowser.open({
        language = require("src.core.SaveData").loadOptions().jpLauncherLanguage or "ja",
        title = Strings("Select Mod (.zip)"),
        mode = "mod",
        onSelect = function(pickedPath)
          self:_installMod(pickedPath)
        end,
      })
      return
    end
  end

  local path = chooseZip()
  if path then
    self:_installMod(path)
    return
  end
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit and Kit.FileBrowser then
    self._padCursorActive = false
    Kit.FileBrowser.open({
      language = require("src.core.SaveData").loadOptions().jpLauncherLanguage or "ja",
      title = Strings("Select Mod (.zip)"),
      mode = "mod",
      onSelect = function(pickedPath)
        self:_installMod(pickedPath)
      end,
    })
    return
  end
end

local function requiredManifest(self, modId)
  for _, row in ipairs(self.mods or {}) do
    if row.id == modId then return row.manifest, row end
  end
  return nil
end

local function requiredSpec(manifest, importId)
  for _, candidate in ipairs(require("src.mods.RequiredImports").specs(manifest)) do
    if candidate.id == importId then return candidate end
  end
  return nil
end

local function requiredImportNotice(self, modId, importId, text)
  self.requiredImportNotice = {
    modId = modId,
    importId = importId,
    text = Strings(tostring(text)),
  }
end

-- Current Android/iOS bridges can stream a raw required import directly from
-- the system document provider into its engine-owned baseroms destination.
-- The bridge hashes/counts the same bytes and then publishes this tiny marker:
--   v1\n<relative destination>\n<md5>\n<byte count>\n
-- Older mobile builds still stage picked_required_import.bin, so this is an
-- additive completion path rather than a replacement for the legacy one.
local function directRequiredImportTarget(self, marker)
  local fields = {}
  for line in tostring(marker or ""):gmatch("[^\r\n]+") do
    fields[#fields + 1] = line
    if #fields > 4 then break end
  end
  local version, path, digest, count = fields[1], fields[2], fields[3], fields[4]
  if version ~= "v1" or not path or not digest or not count or #digest ~= 32
      or not digest:match("^%x+$") or not count:match("^%d+$") then
    return nil, "The completed dependency marker was malformed."
  end
  digest = digest:lower()
  count = tonumber(count)
  if not count then return nil, "The completed dependency size was invalid." end

  if not self.mods and self._refreshMods then pcall(self._refreshMods, self) end
  local RequiredImports = require("src.mods.RequiredImports")

  local function matchRow(row, wantedImportId)
    local manifest = row and row.manifest
    if not manifest then return nil end
    for _, spec in ipairs(RequiredImports.specs(manifest)) do
      if (not wantedImportId or spec.id == wantedImportId)
          and RequiredImports.path(manifest, spec) == path then
        return manifest, spec, row.id or manifest.id
      end
    end
    return nil
  end

  -- Normal resume: bind the marker to exactly the request that opened picker.
  if self.pickerPendingModId and self.pickerPendingImportId then
    for _, row in ipairs(self.mods or {}) do
      if row.id == self.pickerPendingModId then
        local manifest, spec, modId = matchRow(row, self.pickerPendingImportId)
        if manifest then return path, digest, count, manifest, spec, modId end
      end
    end
    return nil, "The completed dependency did not match the pending import request."
  end

  -- Android may recreate GameActivity while DocumentsUI is open. If Lua was
  -- restarted too, recover by the exact engine-owned destination. The path
  -- includes the mod id and only a manifest-declared import can match it.
  for _, row in ipairs(self.mods or {}) do
    local manifest, spec, modId = matchRow(row)
    if manifest then return path, digest, count, manifest, spec, modId end
  end
  return nil, "The completed dependency did not match an installed mod request."
end

finishDirectRequiredImport = function(self, marker)
  local path, digestOrErr, nativeSize, manifest, spec, modId =
    directRequiredImportTarget(self, marker)
  if not path then
    self.modNotice = { ok = false, text = Strings(tostring(digestOrErr)) }
    return nil
  end
  local digest = digestOrErr
  local RequiredImports = require("src.mods.RequiredImports")
  local info = love.filesystem.getInfo(path, "file")
  if not info or type(info.size) ~= "number" then
    requiredImportNotice(self, modId, spec.id,
      "The completed dependency file was not found.")
    self.modNotice = nil
    return nil
  end
  if info.size ~= nativeSize then
    love.filesystem.remove(path)
    if RequiredImports.receiptPath then
      love.filesystem.remove(RequiredImports.receiptPath(manifest, spec))
    end
    requiredImportNotice(self, modId, spec.id,
      Strings("Dependency copy size changed after completion (expected %d bytes, found %d).", nativeSize, info.size))
    self.modNotice = nil
    return nil
  end
  local sizeErr = RequiredImports.sizeError(spec, info.size, true)
  if sizeErr then
    love.filesystem.remove(path)
    if RequiredImports.receiptPath then
      love.filesystem.remove(RequiredImports.receiptPath(manifest, spec))
    end
    requiredImportNotice(self, modId, spec.id, sizeErr)
    self.modNotice = nil
    return nil
  end

  -- No second 665 MiB / 1.46 GiB read: native calculated this digest while
  -- streaming the selected document into the one final copy.
  local ok, detail = RequiredImports.acceptStoredDigest(
    manifest, spec.id, digest, love.filesystem)
  if not ok then
    love.filesystem.remove(path)
    if RequiredImports.receiptPath then
      love.filesystem.remove(RequiredImports.receiptPath(manifest, spec))
    end
    requiredImportNotice(self, modId, spec.id, detail)
    self.modNotice = nil
    return nil
  end

  self.requiredImportNotice = nil
  self.modNotice = { ok = true, text = Strings("Imported %s for %s.", tostring(spec.id), tostring(manifest.name or manifest.id)) }
  self:_refreshMods()
  return true
end

function RomImporter:_importRequiredData(modId, importId, data)
  local manifest = requiredManifest(self, modId)
  if not manifest then
    self.modNotice = { ok = false, text = Strings("Required import failed: mod not found.") }
    return nil
  end
  local ok, result = require("src.mods.RequiredImports")
    .importData(manifest, importId, data)
  if ok then
    self.requiredImportNotice = nil
    self.modNotice = { ok = true, text = Strings("Imported %s for %s.", tostring(importId), tostring(manifest.name or manifest.id)) }
    self:_refreshMods()
    return true
  end
  -- Keep validation feedback on the imported-files page.  A general Mods-page
  -- notice is hidden by this modal and made MD5 failures especially easy to miss.
  requiredImportNotice(self, modId, importId, result)
  self.modNotice = nil
  return nil
end

function RomImporter:_importRequiredSource(modId, importId, source, confirmed)
  local manifest = requiredManifest(self, modId)
  local spec = manifest and requiredSpec(manifest, importId)
  if not spec then
    requiredImportNotice(self, modId, importId, "Import declaration was not found.")
    self.modNotice = nil
    return nil
  end
  local RequiredImports = require("src.mods.RequiredImports")
  -- A desktop picker returns a host path. Ask the host file handle first;
  -- love.filesystem.getInfo is only authoritative for virtual/save paths.
  local size = externalFileSize(source)
  if not size then
    local info = love.filesystem.getInfo(source, "file")
    size = info and info.size or nil
  end
  local sizeErr = RequiredImports.sizeError(spec, size, false)
  if sizeErr then
    requiredImportNotice(self, modId, importId, sizeErr)
    self.modNotice = nil
    return nil
  end
  if not confirmed and type(size) == "number"
      and size > RequiredImports.LARGE_WARN_BYTES then
    self._modConfirm = {
      kind = "largeImport",
      modId = modId, importId = importId, source = source,
      title = Strings("Large import"),
      lines = {
        Strings("This is a large import (%s).",
          RequiredImports.sizeLabel(size)),
        Strings("Please ensure you have enough space on your"),
        Strings("device before doing this."),
      },
      yesLabel = Strings("I understand"),
    }
    return nil
  end
  if spec.format ~= "n64" and (size == nil
      or size > RequiredImports.LARGE_WARN_BYTES) then
    local ok, result = streamRequiredImport(manifest, importId, source)
    if ok then
      self.requiredImportNotice = nil
      self.modNotice = { ok = true, text = Strings("Imported %s for %s.", tostring(importId), tostring(manifest.name or manifest.id)) }
      self:_refreshMods()
      return true
    end
    requiredImportNotice(self, modId, importId, result)
    self.modNotice = nil
    return nil
  end
  local data = love.filesystem.read(source)
  if not data then data = readExternalPath(source) end
  if not data then
    requiredImportNotice(self, modId, importId, "Could not read the selected file.")
    self.modNotice = nil
    return nil
  end
  return self:_importRequiredData(modId, importId, data)
end

function RomImporter:_removeRequiredImport(modId, importId)
  local manifest = requiredManifest(self, modId)
  if not manifest then return end
  local ok, err = require("src.mods.RequiredImports").remove(manifest, importId)
  if ok then
    self.requiredImportNotice = nil
    self.modNotice = { ok = true, text = Strings("Deleted %s", tostring(importId)) }
    self:_refreshMods()
  else
    requiredImportNotice(self, modId, importId, err)
    self.modNotice = nil
  end
end

-- Select and validate one manifest-declared file.  NX has no host picker, so
-- its equivalent is an engine-owned imports/baseroms inbox that can be filled
-- over MTP; every other native/mobile picker lands on the same validation path.
function RomImporter:chooseRequiredImport(modId, importId)
  if self.workState == "working" then return end
  local manifest = requiredManifest(self, modId)
  if not manifest then return end
  local spec = requiredSpec(manifest, importId)
  if not spec then return end

  if self.isNX then
    local inbox = "imports/baseroms"
    love.filesystem.createDirectory(inbox)
    local lastError
    for _, name in ipairs(love.filesystem.getDirectoryItems(inbox) or {}) do
      if name:sub(1, 1) ~= "." then
        local path = inbox .. "/" .. name
        local info = love.filesystem.getInfo(path, "file")
        local RequiredImports = require("src.mods.RequiredImports")
        local sizeErr = info
          and RequiredImports.sizeError(spec, info.size, false)
        if info and not sizeErr
            and info.size > RequiredImports.LARGE_WARN_BYTES then
          return self:_importRequiredSource(modId, importId, path)
        end
        local data = not sizeErr and love.filesystem.read(path) or nil
        if data and self:_importRequiredData(modId, importId, data) then return end
        if sizeErr then lastError = sizeErr
        elseif self.requiredImportNotice
            and self.requiredImportNotice.modId == modId
            and self.requiredImportNotice.importId == importId then
          lastError = self.requiredImportNotice.text
        end
      end
    end
    requiredImportNotice(self, modId, importId, lastError
      or "No matching file in imports/baseroms/. Copy it there over MTP, then try again.")
    self.modNotice = nil
    return
  end
  if self.nativePicker then
    -- Android 13+ uses the Storage Access Framework for both paths.  Some
    -- Android 15 installs carry the newer Lua launcher with an older native
    -- bridge, however, so they do not advertise required_import yet.  Fall
    -- back to that bridge's known "rom" picker and quarantine its result by
    -- the pending required-import IDs. iOS has a different asynchronous
    -- bridge and deliberately keeps the explicit capability requirement.
    local legacyAndroidPicker = self.mobileFileBridge
      and love.system.getOS() == "Android"
      and not pickerHasKind("required_import")
    if self.mobileFileBridge and not pickerHasKind("required_import")
        and not legacyAndroidPicker then
      requiredImportNotice(self, modId, importId,
        "This app build cannot pick required mod files yet. Update the app and try again.")
      self.modNotice = nil
      return
    end
    self.pickerPendingKind = "required_import"
    self.pickerPendingModId = modId
    self.pickerPendingImportId = importId
    self.requiredImportLegacyRomPick = legacyAndroidPicker or nil
    -- Raw imports can go straight to their final private destination on current
    -- Android/iOS bridges. N64 stays on staging because the launcher still has
    -- to canonicalize byte order/copier headers before storing it.
    local directDestination = (self.mobileFileBridge and not legacyAndroidPicker
        and spec.format ~= "n64"
        and type(manifest.path) == "string" and manifest.path ~= "")
      and require("src.mods.RequiredImports").path(manifest, spec) or nil
    if not pickFile(legacyAndroidPicker and "rom" or "required_import",
        directDestination) then
      self.pickerPendingKind = nil
      self.pickerPendingModId = nil
      self.pickerPendingImportId = nil
      self.requiredImportLegacyRomPick = nil
      requiredImportNotice(self, modId, importId, "Could not open the file picker.")
      self.modNotice = nil
    elseif self.android then
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end

  local path = chooseRequiredFile()
  if path then self:_importRequiredSource(modId, importId, path) end
end

-- Which game a dropped .sav imports into: a .sav has no version signature of
-- its own, so it lands on the active game tab.  When a non-game tab (mods) is
-- showing, default to red -- the always-present first game -- rather than
-- guess.
function RomImporter:_savedropTarget()
  local v = self.tab
  if GameVersion.VERSIONS[v] then return v end
  return "red"
end

-- Import a raw .sav into a fresh slot for a version, from a picker path or a
-- dropped file, and surface the outcome on that game's SAVE FILES card.  Brings
-- the target tab forward so the notice (and, on success, the new active slot)
-- is visible.  Requires the ROM to be imported first, since a save is only
-- playable with its game's data present.
function RomImporter:_importSave(version, source, force)
  if self.workState == "working" then return end
  if GameVersion.VERSIONS[self.tab] or self.tab == "mods" then
    self.tab = version
  end
  if not self.ready[version] then
    self.saveNotice[version] = { ok = false, text = Strings("Import the %s ROM before importing a save.",
      GameVersion.info(version).displayName) }
    return
  end
  local ok, res, info = require("src.import.SaveFileIO").importToSlot(source, version, force)
  if ok then
    self:_refreshSlots(version)
    self.activeSlot[version] = res
    self.slotScroll[version] = math.huge   -- pin the new row on screen (clamped in draw)
    self.saveNotice[version] = { ok = true, text = Strings("Imported save into %s.", tostring(res)) }
    return
  end
  if res == nil and info and info.needsConfirm then
    -- A .sav larger than 32 KB whose first 32768 bytes checksum: the surplus
    -- is almost certainly an emulator RTC footer, so ask before truncating.
    -- The yes arm re-enters with force=true; cancel leaves the file untouched.
    self._modConfirm = {
      kind = "importOversize",
      version = version,
      source = source,
      title = Strings("Oversized save file"),
      lines = {
        Strings("This save is %d bytes; a cartridge save is exactly %d bytes (32 KB).", info.size, 32768),
        Strings("It may come from a ROM that saved the battery image with an emulator."),
        Strings("The extra bytes would be discarded."),
        Strings("Import it anyway?"),
      },
      yesLabel = Strings("Import anyway"),
    }
    return
  end
  self.saveNotice[version] = { ok = false, text = tostring(res) }
end

-- "Import save" button: open a native .sav picker and import the pick.
-- Android mirrors ROM / mod import via love.system.pickFile("sav").
-- NX: no HostShell/desktop picker -- rescan imports/saves/ inbox instead.
function RomImporter:chooseSaveImport(version)
  if self.workState == "working" then return end
  version = self:_resolveSaveVersion(version)
  if self.isNX then
    self:ensureSavesInboxDir(version)
    self:rescanSavesAction(version)
    return
  end
  if self.nativePicker and love.system.getPickedFile then
    self.pickerPendingKind = "sav"
    self.pickerPendingVersion = version
    if not pickFile("sav") then
      self.pickerPendingKind = nil
      self.pickerPendingVersion = nil
      self.saveNotice[version] = { ok = false, text = Strings("Could not open the file picker.") }
    end
    return
  end
  if self.android then
    local name = findPendingSav(true, self.pickSkip)
    if name then
      self.androidPendingVersion = version
      self:_importSave(version, name)
      consumePick(self, name, "picked_save.sav",
        self.saveNotice[version] and self.saveNotice[version].ok)
      return
    end
    self.androidPendingVersion = version
    if not pickFile("sav") then
      self.androidPendingVersion = nil
      self.saveNotice[version] = { ok = false,
        text = Strings("Could not open the file picker. Copy a .sav via USB.") }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local isHandheld = os.getenv("HANDHELD") == "1" or os.getenv("PORTMASTER") == "1"
    or os.getenv("POKEPORT_HANDHELD") == "1" or os.getenv("TRIMUI") == "1"
    or os.getenv("MUOS") == "1" or os.getenv("KNULLI") == "1"

  if isHandheld then
    local okKit, Kit = pcall(require, "src.ui.kit.Kit")
    if okKit and Kit.FileBrowser then
      self._padCursorActive = false
      Kit.FileBrowser.open({
        language = require("src.core.SaveData").loadOptions().jpLauncherLanguage or "ja",
        title = Strings("Select Save (.sav)"),
        mode = "save",
        onSelect = function(pickedPath)
          self:_importSave(version, pickedPath)
        end,
      })
      return
    end
  end

  local path = chooseSav()
  if path then
    self:_importSave(version, path)
    return
  end
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit and Kit.FileBrowser then
    self._padCursorActive = false
    Kit.FileBrowser.open({
      language = require("src.core.SaveData").loadOptions().jpLauncherLanguage or "ja",
      title = Strings("Select Save (.sav)"),
      mode = "save",
      onSelect = function(pickedPath)
        self:_importSave(version, pickedPath)
      end,
    })
    return
  end
end

-- "Export save" button: write the active slot back out to a raw .sav in the save
-- directory's exports/ folder.  On desktop, show the path with an open-folder
-- affordance.  On Android, stage pending_export.sav and open the system
-- create-document picker (love.system.createFile) so the player can save to
-- Downloads / Drive / etc. -- the app-private exports/ path is not useful there.
-- NX: surface exports path + MTP hint; do not rely on openURL / open-folder.
function RomImporter:exportSave(version, options)
  if self.workState == "working" then return end
  version = self:_resolveSaveVersion(version)
  local ok, res = require("src.import.SaveFileIO").exportActiveSlot(version, options)
  if not ok then
    self.saveNotice[version] = { ok = false, text = tostring(res) }
    return
  end
  if self.isNX then
    local saveDir = love.filesystem.getSaveDirectory()
    local rel = RomImporter.mtpHintPath(saveDir)
    if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
    local outDir = exportsDir(version)
    self.saveNotice[version] = {
      ok = true,
      text = Strings("Exported to %s\nDBI MTP → 1: SD Card/%s%s/", res, rel, outDir),
    }
    return
  end
  if self.android then
    local rel = res:match("(exports[/\\].+%.[Ss][Aa][Vv])$")
      or res:match("(exports[/\\].+)$")
    local data = rel and love.filesystem.read(rel)
    if not data then
      self.saveNotice[version] = { ok = false,
        text = Strings("Exported, but could not stage the file for the picker.") }
      return
    end
    local suggested = rel:match("[^/\\]+$") or "export.sav"
    local wrote, writeErr = love.filesystem.write("pending_export.sav", data)
    if not wrote then
      self.saveNotice[version] = { ok = false,
        text = Strings("Could not stage the export: %s", tostring(writeErr)) }
      return
    end
    self.androidPendingExportVersion = version
    if love.system.createFile and love.system.createFile(suggested, love.filesystem.getSaveDirectory()) then
      self.pickPending = true
      self.pickTimer = 0
      self.saveNotice[version] = { ok = true,
        text = Strings("Pick where to save %s...", suggested) }
    else
      self.androidPendingExportVersion = nil
      self.saveNotice[version] = { ok = true,
        text = Strings("Exported inside the app folder (picker unavailable).") }
    end
    return
  end
  local dir = res:match("^(.*)[/\\][^/\\]+$")
  self.saveNotice[version] = { ok = true, text = Strings("Exported to %s", res), dir = dir }
end

-- Open a picker (or, on Android, scan the external folder) for a column.  The
-- version argument only titles the dialog and steers error/notice text; the
-- picked ROM is still routed by its SHA-1, so choosing a Blue cart in the Red
-- column imports Blue.
function RomImporter:choose(version)
  if self.workState == "working" then return end
  self.chooseVersion = version or "red"
  if self.isNX then
    -- Same path as the Scan again button: rescan imports/ (or show MTP hint).
    self:rescanAction(self.chooseVersion)
    return
  end
  local baseRom = self.baseRomDiscovery and self.baseRoms[self.chooseVersion]
  if baseRom then
    self.baseRoms[self.chooseVersion] = nil
    local data = love.filesystem.read(baseRom.path)
    if not data then
      self.notice = {
        version = self.chooseVersion,
        status = Strings("The detected ROM is no longer available."),
        detail = Strings("Choose Import ROM to select it another way."),
      }
      return
    end
    self:startData(data, baseRom.name)
    return
  end
  if self.nativePicker and love.system.getPickedFile then
    self.pickerPendingKind = "rom"
    if not pickFile("rom") then
      self.pickerPendingKind = nil
      self:setError("Could not open the file picker.")
    end
    return
  end
  if self.android then
    -- Prefer a not-yet-imported .gb/.gbc/.gba already in the save dir (USB copy, or
    -- a fresh SAF pick).  Never reuse an already-imported cart's file -- that
    -- was the #167 failure mode (second Choose just re-extracted Red).  This
    -- is a Choose, so it takes the cart that was asked for and nothing else.
    local name, data = findPendingRom(self.ready, self.chooseVersion)
    if name then
      self:startData(data, name)
    elseif consumePickedRomError(self) then
      return   -- a rejected pick explains itself instead of silently reopening
    elseif not pickFile() then
      -- Picker unavailable (API < 19, or no document-picker app installed):
      -- fall back to the USB folder-drop path as a friendly notice, not an
      -- error (which would read as a rejected file).
      self.notice = {
        version = self.chooseVersion,
        status = Strings("No picker available, copy your ROM into:"),
        detail = love.filesystem.getSaveDirectory(),
      }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local isHandheld = os.getenv("HANDHELD") == "1" or os.getenv("PORTMASTER") == "1"
    or os.getenv("POKEPORT_HANDHELD") == "1" or os.getenv("TRIMUI") == "1"
    or os.getenv("MUOS") == "1" or os.getenv("KNULLI") == "1"

  if isHandheld then
    if importPendingRom(self) then return end
    local okKit, Kit = pcall(require, "src.ui.kit.Kit")
    if okKit and Kit.FileBrowser then
      self._padCursorActive = false
      Kit.FileBrowser.open({
        language = require("src.core.SaveData").loadOptions().jpLauncherLanguage or "ja",
        title = pickerTitle(GameVersion.info(self.chooseVersion).displayName or "ROM"),
        mode = "rom",
        onSelect = function(pickedPath)
          self:startPath(pickedPath)
        end,
      })
      return
    end
  end

  local path = chooseRom(GameVersion.info(self.chooseVersion).displayName)
  if path then
    self:startPath(path)
    return
  end
  if importPendingRom(self) then return end
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit and Kit.FileBrowser then
    self._padCursorActive = false
    Kit.FileBrowser.open({
      language = require("src.core.SaveData").loadOptions().jpLauncherLanguage or "ja",
      title = pickerTitle(GameVersion.info(self.chooseVersion).displayName or "ROM"),
      mode = "rom",
      onSelect = function(pickedPath)
        self:startPath(pickedPath)
      end,
    })
    return
  end
  if love.system.getOS() == "Linux" then
    local where = love.filesystem.getSourceBaseDirectory
      and love.filesystem.getSourceBaseDirectory()
      or love.filesystem.getSource and love.filesystem.getSource()
      or "the game folder"
    self.notice = {
      version = self.chooseVersion,
      status = Strings("No file picker. Copy your .gb/.gbc/.gba into:"),
      detail = where,
    }
    return
  end
  if love.system.getOS() ~= "OS X" and love.system.getOS() ~= "Windows" then
    self:setError("File selection is unavailable here. Drop the .gb/.gbc/.gba file onto the window.")
  end
end

-- Poll the save dir for a delivered pick (picked_rom.gb / picked_mod.zip /
-- picked_save.sav / export_done.flag) and run the same import path a refocus
-- runs.  Both mobiles need this, for different reasons:
--
--   iOS     the document picker is an in-process modal sheet, so there is no
--           love.focus(true) when it dismisses -- nothing else would consume it.
--   Android the SAF picker IS a separate activity and normally does refocus,
--           but Android may destroy GameActivity while it is up, in which case
--           the app restarts and that focus event never comes.  Polling makes
--           the outcome the same either way instead of leaving the pick on disk
--           for the next tap to find, which is what made users import twice and
--           what made it look random: it depends on memory pressure (#553).
--
-- Deliberately NO timeout.  A version of this disarmed the poll after 120s so a
-- cancelled picker would stop scanning, which was wrong on iOS: the picker there
-- is an in-process modal sheet, so update() keeps running while it is open and
-- the window burned down while the player was still browsing Files.  The pick
-- then landed with nothing armed to consume it, and because every path here is
-- silent on success the import just did not happen, with no error shown.  A
-- half-second directory listing on a menu screen is far cheaper than an import
-- that vanishes, so the poll stays armed until something is actually consumed.

function RomImporter:_pollPickedFiles(dt)
  if not self.pickPending then return end
  if self.workState == "working" then return end
  self.pickTimer = (self.pickTimer or 0) + dt
  if self.pickTimer < 0.5 then return end
  self.pickTimer = 0
  -- The Swift bridge reports a failed pick copy through pick_error.txt;
  -- surface it on whichever tab the player is looking at rather than
  -- letting the pick silently do nothing.
  local pickError = love.filesystem.read("pick_error.txt")
  if pickError then
    love.filesystem.remove("pick_error.txt")
    self.pickPending = nil
    self.modNotice = { ok = false, text = pickError }
    self.notice = { version = self.chooseVersion or "red",
                    status = Strings("File import failed:"), detail = pickError }
    return
  end
  local found = love.filesystem.getInfo("export_done.flag", "file") ~= nil
    or love.filesystem.getInfo("pick_error.flag", "file") ~= nil
    or love.filesystem.getInfo(PICK_COMPLETE_FILENAME, "file") ~= nil
  if not found then
    for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
      local n = name:lower()
      if isRomFilename(n) or n == "picked_mod.zip" or n == "picked_save.sav"
          or n == "picked_required_import.bin" or n == "picked_stadium.z64"
          or n:match("^picked_importer_[%l%d_%-]+%.bin$") then
        found = true
        break
      end
    end
  end
  if found then
    self.pickPending = nil
    self:focus(true)
  end
end

function RomImporter:_beginImporterImport(importerId)
  local Importers = require("src.import.Importers")
  local desc = Importers.get(importerId)
  if not desc or desc.status == "planned" then return end
  if self._importerJob then return end
  self._importerNotice = nil
  if self.nativePicker and love.system.getPickedFile then
    self.pickerPendingKind = "importer"
    self.pickerPendingImporterId = importerId
    if not pickFile("rom") then
      self.pickerPendingKind, self.pickerPendingImporterId = nil, nil
      self._importerNotice = { text = Strings("Could not open the file picker.") }
    end
    return
  end
  if self.android then
    self.pickerPendingKind = "importer"
    self.pickerPendingImporterId = importerId
    if pickFile("required_import", importerPickName(importerId)) then
      self.pickPending = true
      self.pickTimer = 0
      return
    end
    self.pickerPendingKind = nil
    self.pickerPendingImporterId = nil
  end
  local path = chooseImporterFile(desc.name, desc.source.formats or { "sfc" })
  if path then
    self:_runImporter(importerId, path)
    return
  end
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit and Kit.FileBrowser then
    self._padCursorActive = false
    Kit.FileBrowser.open({
      language = require("src.core.SaveData").loadOptions().jpLauncherLanguage or "ja",
      title = pickerTitle(desc.name),
      mode = "rom",
      onSelect = function(pickedPath)
        self:_runImporter(importerId, pickedPath)
      end,
    })
    return
  end
  self._importerNotice = {
    text = "Drop your " .. desc.name .. " dump onto this window.",
  }
  self._importerDropFor = importerId
end

function RomImporter:_runImporter(importerId, path)
  local data, readErr = readExternalPath(path)
  if not data then
    self._importerNotice = { text = Strings("Could not read that file: %s", tostring(readErr)) }
    return
  end
  return self:_runImporterData(importerId, data)
end

function RomImporter:_runImporterData(importerId, data)
  local LttpImport = require("src.import.lttp.LttpImport")
  if importerId ~= LttpImport.IMPORTER then return end
  local source, err = LttpImport.identify(data)
  if not source then
    self._importerNotice = { text = tostring(err) }
    return
  end
  self._importerJob = {
    id = importerId,
    co = LttpImport.job(data),
    progress = 0,
    status = "Reading " .. source.name,
  }
  self._importerNotice = nil
end

function RomImporter:_stepImporter()
  local job = self._importerJob
  if not job then return end
  local budget = 24
  while budget > 0 do
    budget = budget - 1
    if coroutine.status(job.co) == "dead" then break end
    local ok, value = coroutine.resume(job.co)
    if not ok then
      self._importerJob = nil
      self._importerNotice = { text = "Import failed: " .. tostring(value) }
      self._importerRows = nil
      return
    end
    if coroutine.status(job.co) == "dead" then
      self._importerJob = nil
      self._importerRows = nil
      local packs = {}
      for id, count in pairs(type(value) == "table" and value.packs or {}) do
        packs[#packs + 1] = id .. " (" .. count .. ")"
      end
      table.sort(packs)
      self._importerNotice = { ok = true,
        text = "Imported " .. table.concat(packs, ", ") }
      return
    end
    if type(value) == "table" and value.total and value.total > 0 then
      job.progress = value.done / value.total
      job.status = value.status or job.status
    end
  end
end


-- Independent launcher/controller implementation follows.
local function view() return require("src.import.LauncherView") end
local function options() return require("src.core.SaveData").loadOptions() end

function RomImporter.new(onComplete, opts)
  opts = opts or {}
  local osName = love.system.getOS()
  local mobile = osName == "Android" or osName == "iOS"
  local saved = options()
  local initial = opts.initialTab or os.getenv("POKEPORT_LAUNCHER_TAB")
  local okLO, launch = pcall(require, "src.core.LaunchOptions")
  initial = initial or (okLO and launch.pendingTab) or saved.lastVersion or "red_jp"
  local self = setmetatable({
    onComplete = onComplete, launcher = opts.launcher == true,
    forceImport = opts.forceImport == true, onEditSave = opts.onEditSave,
    onEditTouchControls = opts.onEditTouchControls,
    onEditTouchAreas = opts.onEditTouchAreas,
    onOpenSkinStudio = opts.onOpenSkinStudio,
    isNX = Platform.isNX(), romImportMode = Platform.romImportMode(),
    mobileFileBridge = mobile, android = mobile, ios = osName == "iOS",
    pickPending = mobile, baseRoms = {}, baseRomDiscovery = false,
    ready = {}, returning = {}, romName = {}, slots = {}, activeSlot = {},
    slotScroll = {}, saveNotice = {}, activeCart = {}, carts = {},
    status = "", detail = "", progress = 0, pulse = 0,
    stageCurrent = 0, stageTotal = 1, tab = "red_jp", modScope = "red_jp",
    _ui = { page = "games", scroll = 0, focus = 1, hits = {} },
  }, RomImporter)
  self.nativePicker = self.romImportMode == "native-picker"
  local CacheFs = require("src.import.CacheFs")
  CacheFs.migrateLegacyRedCache()
  for _, id in ipairs(GameVersion.ORDER) do
    self.ready[id] = not self.forceImport and RomImporter.isReady(id)
    local marker = CacheContract.readMarker(id, CacheFs)
    self.returning[id] = not self.ready[id] and marker ~= nil
    self.romName[id] = GameVersion.info(id).displayName
  end
  self:_switchTab(initial)
  RomImporter.syncAndroidShortcuts()
  if mobile then self:focus(true) end
  -- main.lua consumes wheel events while an importer is active. Retain one
  -- dispatcher and replace its owner on re-entry, instead of stacking hooks.
  if self.launcher then
    RomImporter._wheelOwner = self
    if not RomImporter._wheelHook then
      RomImporter._wheelHook = true
      local hostWheel = love.wheelmoved
      love.wheelmoved = function(dx, dy)
        local owner = RomImporter._wheelOwner
        if owner and not owner._handedOff then owner:wheelmoved(dx, dy)
        elseif hostWheel then hostWheel(dx, dy) end
      end
    end
  end
  return self
end

function RomImporter:_switchTab(id)
  self._settings = nil
  self._ui.scroll, self._ui.focus = 0, 1
  if GameVersion.VERSIONS[id] then
    self.tab, self.modScope, self._ui.page = id, id, "games"
  else
    self._ui.page = ({mods="mods",find="discover",settings="settings",about="about"})[id] or "about"
    if id == "settings" then self:_openSettings() end
  end
end

function RomImporter:update(dt)
  self.pulse = self.pulse + dt
  self:_pollPickedFiles(dt)
  self:_stepBaseRomScan()
  self:_pumpExtract()
  if self._importerJob then self:_stepImporter() end
  if self.nativePicker and love.system.getPickedFile then
    local path = love.system.getPickedFile()
    if path then
      local kind, version = self.pickerPendingKind, self.pickerPendingVersion or self.tab
      self.pickerPendingKind, self.pickerPendingVersion = nil, nil
      if kind == "mod" then self:_installMod(path)
      elseif kind == "sav" then self:_importSave(version, path)
      elseif kind == "required_import" then
        self:_importRequiredSource(self.pickerPendingModId, self.pickerPendingImportId, path)
        self.pickerPendingModId, self.pickerPendingImportId = nil, nil
      elseif kind == "importer" then self:_runImporter(self.pickerPendingImporterId, path)
      else self:startPath(path) end
    elseif love.system.getPickError then
      local err = love.system.getPickError()
      if err then self.modNotice = {ok=false,text=tostring(err)} end
    end
  end
  if self.worker and self.workState == "working" then
    local deadline = love.timer.getTime() + 0.008
    repeat
      local ok, err = coroutine.resume(self.worker)
      if not ok then self:setError(err); break end
      if coroutine.status(self.worker) == "dead" then self.worker = nil; break end
    until love.timer.getTime() >= deadline
  end
  view().update(self, dt)
  -- Deterministic desktop capture; no ROM, network request or game data needed.
  local shot = os.getenv("POKEPORT_LAUNCHER_SHOT")
  if shot and not self._shotDone then
    if not self._shotSized then
      self._shotSized = true
      local w,h = (os.getenv("POKEPORT_WIN") or ""):match("^(%d+)x(%d+)$")
      if w then love.window.setMode(tonumber(w),tonumber(h),{resizable=true}) end
      if os.getenv("POKEPORT_LAUNCHER_SETTINGS") == "1" then self:_openSettings() end
    end
    if self.pulse > 0.5 then
      self._shotDone = true
      love.graphics.captureScreenshot(function(data)
        local f=assert(io.open(shot,"wb")); f:write(data:encode("png"):getString()); f:close()
        love.event.quit()
      end)
    end
  end
end
function RomImporter:draw() return view().draw(self) end
function RomImporter:mousepressed(x,y,button,istouch)
  if button == 1 and not istouch then return view().mousepressed(self,x,y) end
end
function RomImporter:touchpressed(id,x,y) return view().touchpressed(self,id,x,y) end
function RomImporter:touchmoved(id,x,y) return view().touchmoved(self,id,x,y) end
function RomImporter:touchreleased(id,x,y) return view().touchreleased(self,id,x,y) end
function RomImporter:touchcancelled(id) return view().touchcancelled(self,id) end
function RomImporter:wheelmoved(dx,dy) return view().wheelmoved(self,dx,dy) end
function RomImporter:keypressed(key) return view().keypressed(self,key) end
function RomImporter:textinput(text) return view().textinput(self,text) end
function RomImporter:gamepadpressed(_,button)
  local mapped=GamepadMap.mapLauncherButton(button)
  local keys={a="return",b="escape",dpup="up",dpdown="down",dpleft="left",dpright="right",start="return",back="escape"}
  if keys[mapped] then self:keypressed(keys[mapped]) end
end
function RomImporter:gamepadreleased() end
function RomImporter:gamepadaxis(_,axis,value)
  self._axisLatch=self._axisLatch or {}
  local sign=value > 0.55 and 1 or value < -0.55 and -1 or 0
  if sign ~= 0 and self._axisLatch[axis] ~= sign then
    if axis == "lefty" then self:keypressed(sign > 0 and "down" or "up")
    elseif axis == "leftx" then self:keypressed(sign > 0 and "right" or "left") end
  end
  self._axisLatch[axis]=sign
end
function RomImporter:joystickpressed(joystick,button)
  if joystick and joystick.isGamepad and joystick:isGamepad() then return end
  local map=self.isNX and GamepadMap.NX_RAW_TO_GAMEPAD_BUTTON or GamepadMap.RAW_TO_GAMEPAD_BUTTON
  if map[button] then self:gamepadpressed(joystick,map[button]) end
end
function RomImporter:joystickreleased() end
function RomImporter:joystickaxis(joystick,axis,value)
  if joystick and joystick.isGamepad and joystick:isGamepad() then return end
  if axis == 1 or axis == 2 then self:gamepadaxis(joystick,axis == 1 and "leftx" or "lefty",value) end
end
function RomImporter:joystickhat(_,_,direction)
  local names={u="up",d="down",l="left",r="right"}
  if names[direction] then self:keypressed(names[direction]) end
end
function RomImporter:prepareOverlayHandoff() view().detach(self) end
function RomImporter:resumeAfterOverlay() self._ui.hits={}; self._ui.scroll=0 end
function RomImporter:ignoreReturningPointer() self._ui.ignoreMouseUntil=self.pulse+0.3 end
function RomImporter:parkNxPointerForHost() end

function RomImporter:play(version,launchOpts)
  if self._handedOff or self.workState == "working" or not self.ready[version] then return end
  local SaveData=require("src.core.SaveData")
  local opts=SaveData.loadOptions(); opts.lastVersion=version; SaveData.saveOptions(opts)
  self._handedOff=true
  view().detach(self)
  if self.onComplete then self.onComplete(version,nil,launchOpts) end
end
function RomImporter:reimport(version)
  if self.workState ~= "working" then self:choose(version) end
end
function RomImporter:_refreshMods()
  self.mods=require("src.mods.LauncherMods").list(self.modScope) or {}
end
function RomImporter:_ensureMods() if not self.mods then self:_refreshMods() end end
function RomImporter:_toggleMod(id)
  self:_ensureMods()
  for _, row in ipairs(self.mods) do
    if row.id==id then
      require("src.mods.LauncherMods").setEnabled(id,not row.enabled,self.modScope)
      self:_refreshMods(); return
    end
  end
end
function RomImporter:_refreshSlots(version)
  self._ui.homeSummaryKey=nil
  self._ui.options=require('src.core.SaveData').loadOptions()
  local SaveData=require("src.core.SaveData")
  self.slots[version]=SaveData.listSlots(version) or {}
  local reg=(SaveData.loadOptions().saveSlots or {})[version]
  self.activeSlot[version]=reg and (reg.active or (reg.list or {})[1])
end
function RomImporter:_ensureSlots(version) if not self.slots[version] then self:_refreshSlots(version) end end
function RomImporter:_selectSlot(version,id)
  require("src.core.SaveData").setActiveSlot(version,id); self.activeSlot[version]=id
  self._ui.homeSummaryKey=nil
end
function RomImporter:_newSlot(version)
  local SaveData=require("src.core.SaveData")
  local id=SaveData.createSlot(version)
  if id then SaveData.setActiveSlot(version,id); self:_refreshSlots(version) end
end
function RomImporter:savesChanged(version) self:_refreshSlots(version) end
function RomImporter:_openSettings()
  self._ui.page,self._ui.scroll,self._ui.focus="settings",0,1
  self._settings=require("src.import.LauncherSettings").open({
    importSettings=function(options)
      local files=require("src.import.SettingsFiles")
      files.import(options,{
        apply=function(candidate)
          local ok=require("src.core.SaveData").saveOptions(candidate)
          if not ok then return false end
          self._settings=nil
          self._ui.options=candidate
          self:_refreshMods()
          self:_openSettings()
          return true
        end,
        notify=function(text)
          require("src.import.LauncherView").showMessage(self,"せっていファイル",text)
        end,
      })
    end,
    exportSettings=function(options)
      require("src.import.SettingsFiles").export(options,{
        notify=function(text)
          require("src.import.LauncherView").showMessage(self,"せっていファイル",text)
        end,
      })
    end,
    editTouchControls=self.onEditTouchControls and function()
      self:_closeSettings(); self.onEditTouchControls(self.tab)
    end,
    editTouchAreas=self.onEditTouchAreas and function()
      self:_closeSettings(); self.onEditTouchAreas(self.tab)
    end,
    openSkinStudio=self.onOpenSkinStudio and function(id)
      self:_closeSettings(); self.onOpenSkinStudio(self.tab,id)
    end,
  },self.tab)
end
function RomImporter:_closeSettings()
  if self._settings then self._settings.save(); self._ui.options=self._settings.opts end
  self._settings=nil; self._ui.page="games"; self._ui.scroll=0
end
function RomImporter:_quitApp() love.event.quit() end
function RomImporter:_setBusy(title,detail,cancel) self._busy={title=title,detail=detail,cancel=cancel} end
function RomImporter:_clearBusy() self._busy=nil end
function RomImporter:_resyncPointerAfterDialog() self:ignoreReturningPointer() end
function RomImporter:_installSkinZip()
  self.modNotice={ok=false,text="スキンのインポートは新しい起動画面へ移植準備中です。"}
end
function RomImporter:_syncEngine() return nil end
function RomImporter:_safeModeEnabled() return false end
function RomImporter.pageScrollFor(content,viewport,offset)
  local limit=math.max(0,content-viewport)
  return limit>0,math.max(0,math.min(limit,offset or 0)),limit
end
return RomImporter
