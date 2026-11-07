-- Authored synthetic buffers only: never reads or writes a cartridge ROM.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local S = require("tests.harness").suite("Japanese Red revision routing")
local originalRead = love.filesystem.read
love.filesystem.read = function(path)
  local value = originalRead(path)
  if value then return value end
  local f = io.open(path, "rb")
  if f then local out = f:read("*a"); f:close(); return out end
end
local Version = require("src.core.GameVersion")
local Manifest = require("src.import.RomManifest")
local Extractor = require("src.import.RomExtractor")
local Importer = require("src.import.RomImporter")
local Contract = require("src.import.CacheContract")
local CacheFs = require("src.import.CacheFs")
local SaveData = require("src.core.SaveData")
local Json = require("src.link.Json")
local hashes = {"0623ad12f48c259447980d68bd85ddbf8204b2cd", "ef74c79cded14204ac79e77f4964d9cb25003120"}
local patchPath = "tools/rom_manifest_red_jp_v11.json"
local patchRaw = love.filesystem.read(patchPath)
local patch = assert(Json.decode(patchRaw))
local manifests = { Manifest.decode("red_jp", hashes[1]), Manifest.decode("red_jp", hashes[2]) }
local moved = 0
for name, change in pairs(patch.symbolChanges) do
  moved = moved + 1
  S.same(manifests[1].symbols[name], change.from, name .. " v1.0 location")
  S.same(manifests[2].symbols[name], change.to, name .. " v1.1 location")
end
S.eq(moved, 182, "all revision address changes selected")
S.same(Manifest.decode("red_jp").symbols, manifests[1].symbols, "decoding v1.1 never mutates later v1.0 metadata")
S.eq(manifests[2].text.lengths._GettingPumpedText, 102, "tail bound expands only to bank end")
S.eq(manifests[1].text.lengths._GettingPumpedText, 64, "old tail bound retained")
S.same(manifests[1].audio, manifests[2].audio, "inline audio metadata stays unchanged")
S.raises(function() Manifest.decode("red_jp", "unknown") end, "Unsupported", "unknown metadata revision rejected")
S.raises(function() Extractor.new("", manifests[1], nil, hashes[2]) end, "revision metadata", "wrong extractor metadata rejected")
local broken = assert(Json.decode(patchRaw)); broken.baseRomSha1 = "unknown"
love.filesystem.write(patchPath, Json.encode(broken))
S.raises(function() Manifest.decode("red_jp", hashes[2]) end, "metadata mismatch", "wrong delta base rejected")
broken = assert(Json.decode(patchRaw)); broken.symbolChanges._GettingPumpedText.from[2] = broken.symbolChanges._GettingPumpedText.from[2]+1
love.filesystem.write(patchPath, Json.encode(broken))
S.raises(function() Manifest.decode("red_jp", hashes[2]) end, "symbol base mismatch", "stale delta address rejected")
love.filesystem.remove(patchPath)
for _, malformed in ipairs({{-1,0x4000}, {32,0x4000}, {9,0x8000}, {9.5,0x4000}, {9,0x4000.5}, {"9",0x4000}}) do
  broken = assert(Json.decode(patchRaw)); broken.symbolChanges._GettingPumpedText.to = malformed
  love.filesystem.write(patchPath, Json.encode(broken))
  S.raises(function() Manifest.decode("red_jp", hashes[2]) end, "Invalid ROM revision symbol location", "malformed target address rejected")
end
for _, length in ipairs({-1, 0, 1.5, "102", 0x8000}) do
  broken = assert(Json.decode(patchRaw)); broken.textLengthChanges._GettingPumpedText.to = length
  love.filesystem.write(patchPath, Json.encode(broken))
  S.raises(function() Manifest.decode("red_jp", hashes[2]) end, "ROM revision text", "invalid target text length rejected")
end
love.filesystem.remove(patchPath)

local function replace(data, offset, value)
  return data:sub(1, offset) .. value .. data:sub(offset + #value + 1)
end
local function checksum(data)
  local sum = 0
  for offset = 0x134, 0x14c do sum = (sum-data:byte(offset+1)-1)%256 end
  return replace(data, 0x14d, string.char(sum))
end
local function synthetic(revision)
  local data = string.rep("\255", 524288)
  data = replace(data, 0x134, "POKEMON RED")
  data = replace(data, 0x148, string.char(4))
  data = replace(data, 0x14c, string.char(revision))
  return checksum(data)
end
local buffers = {synthetic(0), synthetic(1)}
for i, hash in ipairs(hashes) do
  S.eq(Version.forSha1(hash), "red_jp", "known revision uses existing game identity")
  S.check(Manifest.validateRomData("red_jp", buffers[i], hash), "matching synthetic header accepted")
  S.check(not Manifest.validateRomData("red_jp", buffers[i], hashes[3-i]), "mismatched revision header rejected")
  S.check(not Manifest.validateRomData("red_jp", buffers[i]:sub(2), hash), "wrong exact byte count rejected")
  S.check(not Manifest.validateRomData("red_jp", checksum(replace(buffers[i], 0x134, "X")), hash), "wrong title rejected")
  S.check(not Manifest.validateRomData("red_jp", checksum(replace(buffers[i], 0x148, "\5")), hash), "wrong header ROM size rejected")
  S.check(not Manifest.validateRomData("red_jp", replace(buffers[i], 0x135, "X"), hash), "wrong checksum rejected")
  S.check(Contract.markerMatches("red_jp", Contract.formatFor("red_jp") .. hash), "old and new cache hashes accepted")

  -- Put one authored glyph at each actual relocated text address. A parser
  -- reading padding or the old address encounters an unsupported command.
  local symbol = manifests[i].symbols._GettingPumpedText
  local offset = symbol[1]*0x4000 + symbol[2]%0x4000
  local input = replace(buffers[i], offset, string.char(0, 0x80, 0x57))
  local ex = Extractor.new(input, manifests[i], nil, hash)
  S.eq(ex:decodeTextCommands(ex:symbol("_GettingPumpedText"), {}), ex:textGlyph(0x80).."{DONE}", "terminator prevents reading bank padding")
  S.eq(ex.rom:byte(symbol[1], symbol[2]+3), 255, "padding remains invalid text and unconsumed")
end
S.eq(Version.info("red_jp").cachePrefix, "red_jp/", "cache identity unchanged")
S.eq(Version.info("red_jp").saveSuffix, "_red_jp", "legacy save identity unchanged")
S.eq(SaveData.slotDiskPath("red_jp", "slot1"), love.filesystem.getSaveDirectory().."/saves/red_jp/slot1.lua", "slot save identity unchanged")
S.eq(Version.forSha1("unknown"), nil, "unknown ROM remains rejected")
S.check(not Contract.markerMatches("red_jp", Contract.formatFor("red_jp").."unknown"), "unknown cache hash remains rejected")

local hashCalls = 0
local selectedHash = hashes[1]
love.data = love.data or {}
love.data.hash = function(_, _) hashCalls = hashCalls + 1; return selectedHash end
love.data.encode = function(_, _, value) return value end
local function importer()
  return setmetatable({tab="red_jp", ready={}, returning={}, romName={}, launcher=true}, Importer)
end
local sentinel = "red_jp/data/generated/preserve.txt"
local saves = {"save_red_jp.lua", "saves/red_jp/slot1.lua", "mods/custom/options.lua"}
for _, path in ipairs(saves) do love.filesystem.write(path, "unchanged") end
for _, invalid in ipairs({"unknown", hashes[2]}) do
  selectedHash = invalid
  love.filesystem.write(sentinel, "old cache")
  local imp = importer()
  imp:startData(buffers[1], "authored fixture")
  S.eq(imp.workState, "error", "unknown hash or wrong header rejected at import boundary")
  S.eq(originalRead(sentinel), "old cache", "rejected input cannot clear existing cache")
end
selectedHash = hashes[2]
local readWithDisk = love.filesystem.read
for _, invalid in ipairs({"missing", "malformed", "wrong-base"}) do
  love.filesystem.write(sentinel, "old cache")
  broken = assert(Json.decode(patchRaw)); broken.baseRomSha1 = "unknown"
  love.filesystem.read = function(path)
    if path == patchPath then
      if invalid == "missing" then return nil, "fixture missing" end
      if invalid == "malformed" then return "{" end
      return Json.encode(broken)
    end
    return readWithDisk(path)
  end
  local imp = importer()
  imp:startData(buffers[2], "authored fixture")
  S.eq(imp.workState, "error", invalid.." metadata rejected before cache deletion")
  S.eq(originalRead(sentinel), "old cache", invalid.." metadata keeps old cache")
  S.eq(imp.errorVersion, "red_jp", "metadata error stays on Japanese game")
  for _, path in ipairs(saves) do S.eq(originalRead(path), "unchanged", "failed metadata preserves "..path) end
end
love.filesystem.read = readWithDisk
local basePath = Version.info("red_jp").manifest
local badBase = assert(Json.decode(readWithDisk(basePath))); badBase.romSha1 = hashes[2]
love.filesystem.write(basePath, Json.encode(badBase))
selectedHash = hashes[1]
love.filesystem.write(sentinel, "old cache")
local badBaseImporter = importer()
badBaseImporter:startData(buffers[1], "authored fixture")
S.eq(badBaseImporter.workState, "error", "mislabeled base manifest is rejected")
S.eq(originalRead(sentinel), "old cache", "mislabeled base manifest keeps cache")
love.filesystem.remove(basePath)

-- Run both real importer paths. The expensive ROM extraction body alone is
-- replaced by a spy; constructor, selected symbols, worker script, cache IO,
-- marker publication and completion remain production code.
Contract.VERSION_REQUIRED_FILES_OVERRIDE.red_jp = {"data/generated/revision.txt"}
local realRun = Extractor.run
local ran
Extractor.run = function(self)
  ran = self
  self.progress(1, 1, "fixture", 1, 1)
  assert(CacheFs.write("data/generated/revision.txt", self.manifest.romSha1))
end
local channels = {}
local function channel(name)
  if not channels[name] then
    channels[name] = { clear=function(self) self.values={} end,
      push=function(self,v) self.values[#self.values+1]=v end,
      pop=function(self) return table.remove(self.values,1) end, values={} }
  end
  return channels[name]
end
for _, name in ipairs({"filesystem","image","math","system","timer","data"}) do
  package.preload["love."..name] = function() return love[name] end
end
for _, mode in ipairs({"coroutine", "thread"}) do
  love.thread = mode == "thread" and {getChannel=channel, newThread=function(path)
    return {start=function(_, ...)
      local prefix = CacheFs.prefix
      assert(loadfile(path))(...)
      CacheFs.prefix = prefix -- actual thread has its own module state
    end, getError=function() return nil end}
  end} or nil
  for i, hash in ipairs(hashes) do
    selectedHash = hash
    local beforeHash = hashCalls
    local imp = importer()
    ran = nil
    imp:startData(buffers[i], "authored fixture")
    S.eq(hashCalls-beforeHash, 1, mode.." hashes input once")
    if mode == "coroutine" then
      while coroutine.status(imp.worker) ~= "dead" do
        local ok, err = coroutine.resume(imp.worker); assert(ok, err)
      end
    else
      S.check(imp._extract ~= nil, "real worker path used")
      imp:_pumpExtract()
    end
    S.eq(imp.workState, "complete", mode.." completed")
    S.check(ran ~= nil, mode.." extraction invoked")
    S.eq(ran and ran.manifest.romSha1, hash, mode.." correct metadata revision")
    S.same(ran and ran.symbols._GettingPumpedText, manifests[i].symbols._GettingPumpedText, mode.." correct relocated address")
    S.eq(originalRead("red_jp/data/generated/revision.txt"), hash, mode.." writes same cache subtree")
    S.check(Contract.markerMatches("red_jp", originalRead("red_jp/"..Contract.MARKER_PATH)), mode.." cache can reopen")
    for _, path in ipairs(saves) do S.eq(originalRead(path), "unchanged", mode.." preserves "..path) end
  end
end
Extractor.run = realRun
S.finish()
