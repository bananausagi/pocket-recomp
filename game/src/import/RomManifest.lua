-- The per-version import metadata (symbol table + ROM hash) that drives
-- RomExtractor.  Split out of RomImporter so the extraction worker thread can
-- decode it itself: shipping the decoded table across a love.thread channel
-- would deep-copy every symbol for nothing.

local GameVersion = require("src.core.GameVersion")

local RomManifest = {}

local function integer(value)
  return type(value) == "number" and value == math.floor(value)
end

local function validLocation(location, size)
  if type(location) ~= "table" or not integer(location[1])
      or not integer(location[2]) then return false end
  local bank, address = location[1], location[2]
  return bank >= 0 and bank < size / 0x4000
    and address >= (bank == 0 and 0 or 0x4000)
    and address < (bank == 0 and 0x4000 or 0x8000)
end

local function decodeFile(path)
  local raw, readError = love.filesystem.read(path)
  if not raw then
    error("ROM import metadata is missing: " .. tostring(readError))
  end
  local Json = require("src.link.Json")
  local manifest, decodeError = Json.decode(raw)
  if not manifest then
    error("ROM import metadata is invalid: " .. tostring(decodeError))
  end
  return manifest
end

-- Called before clearing an existing cache. Exact hashes remain authoritative;
-- title/revision/size and the small header checksum also guard routing mistakes.
function RomManifest.validateRomData(version, data, sha1)
  if not GameVersion.acceptsSha1(version, sha1) then return false end
  if version ~= "red_jp" then return true end
  if type(data) ~= "string" or #data ~= GameVersion.info(version).romSize then return false end
  local revision
  for _, row in ipairs(GameVersion.revisions(version)) do
    if row.sha1 == sha1 then revision = row; break end
  end
  if not revision or data:sub(0x134+1,0x13e+1) ~= "POKEMON RED"
      or data:byte(0x148+1) ~= 4
      or data:byte(0x14c+1) ~= revision.headerRevision then return false end
  local checksum = 0
  for offset = 0x134, 0x14c do checksum = (checksum-data:byte(offset+1)-1)%256 end
  return checksum == data:byte(0x14d+1)
end

function RomManifest.decode(version, sha1)
  local info = GameVersion.info(version)
  local manifest = decodeFile(info.manifest)
  assert(GameVersion.acceptsSha1(version, manifest.romSha1),
    "ROM import metadata version mismatch")
  if version == "red_jp" then
    assert(manifest.romSha1 == info.sha1, "Japanese base ROM metadata revision mismatch")
  end
  sha1 = sha1 or info.sha1
  assert(GameVersion.acceptsSha1(version, sha1), "Unsupported ROM metadata revision")
  local revision
  for _, row in ipairs(GameVersion.revisions(version)) do
    if row.sha1 == sha1 then revision = row; break end
  end
  if revision and revision.manifest then
    local regional = decodeFile(revision.manifest)
    assert(regional.romSha1 == sha1 and regional.romSize == info.romSize
      and regional.language == info.language and regional.edition == info.edition,
      "ROM revision metadata mismatch")
    manifest = regional
  end
  if revision and revision.manifestPatch then
    local patch = decodeFile(revision.manifestPatch)
    assert(patch.format == "jp-rom-revision-v1" and patch.baseRomSha1 == manifest.romSha1
      and patch.romSha1 == sha1 and patch.romSize == info.romSize,
      "ROM revision metadata mismatch")
    assert(type(patch.symbolChanges) == "table" and type(patch.textLengthChanges) == "table"
      and type(patch.provenance) == "table", "Invalid ROM revision metadata schema")
    for name, change in pairs(patch.symbolChanges) do
      assert(type(name) == "string" and type(change) == "table"
        and validLocation(change.from, info.romSize) and validLocation(change.to, info.romSize),
        "Invalid ROM revision symbol location: " .. tostring(name))
      local old = manifest.symbols[name]
      assert(old and old[1] == change.from[1] and old[2] == change.from[2],
        "ROM revision symbol base mismatch: " .. name)
      manifest.symbols[name] = change.to
    end
    for name, change in pairs(patch.textLengthChanges) do
      assert(type(name) == "string" and type(change) == "table"
        and integer(change.from) and integer(change.to) and change.from > 0 and change.to > 0,
        "Invalid ROM revision text length: " .. tostring(name))
      assert(manifest.text.lengths[name] == change.from,
        "ROM revision text base mismatch: " .. name)
      manifest.text.lengths[name] = change.to
    end
    for name, length in pairs(manifest.text.lengths) do
      if patch.symbolChanges[name] or patch.textLengthChanges[name] then
        local location = manifest.symbols[name]
        assert(validLocation(location, info.romSize) and integer(length) and length > 0
          and location[2] + length <= (location[1] == 0 and 0x4000 or 0x8000),
          "ROM revision text crosses bank boundary: " .. tostring(name))
      end
    end
    manifest.romSha1 = sha1
    manifest.provenance.revision = patch.provenance
  end
  return manifest
end

return RomManifest
