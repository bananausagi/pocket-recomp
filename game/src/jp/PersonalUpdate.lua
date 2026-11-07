-- Personal-line auto update (PocketRecomp personal build).
--
-- Once per launch, shortly after the launcher opens, this fetches the
-- small latest.json that the public release repo (bananausagi/apps-release)
-- keeps for this app:
--     { packageName, versionCode, versionName, apkUrl, sha256, notes }
-- and compares its versionCode with the build compiled in below.  When a
-- newer build exists it:
--
--   1. downloads the APK in the background (engine async pool, no prompt)
--      to <save>/updates/gen1recomp-0.2.<code>-android.apk -- the name and
--      folder the native installer (love.system.installApk) accepts;
--   2. verifies its SHA-256 against latest.json (mismatch = discard);
--   3. hands it to love.system.installApk, which opens the system install
--      screen (and, the first time, the "install unknown apps" setting).
--
-- A verified APK stays cached, so the same version is not downloaded again
-- on the next launch; cached APKs at or below the running build are removed.
-- Offline / malformed JSON / bad hash / any error = silent no-op.  Only if
-- the native installer is missing or refuses does a banner appear (tap =
-- open the Releases page), as the old notifier did.
--
-- It never blocks or throws into the game loop: every entry point is
-- pcall-guarded.  The upstream self-updater (src/update) stays OFF
-- (Version.upstreamUpdates = false).
--
-- MAINTENANCE: CURRENT_CODE / CURRENT_NAME must match build.py's
-- VERSION_CODE / VERSION_NAME.  build.py asserts this before building.

local PersonalUpdate = {}

PersonalUpdate.CURRENT_CODE = 96
PersonalUpdate.CURRENT_NAME = "0.2.96-personal"
PersonalUpdate.PACKAGE = "org.gen1recomp.japanese.preview"
PersonalUpdate.VERSION_URL =
  "https://raw.githubusercontent.com/bananausagi/apps-release/main/pocket-recomp/latest.json"
PersonalUpdate.RELEASES_URL =
  "https://github.com/bananausagi/apps-release/releases"
PersonalUpdate.UPDATE_DIR = "updates"

local BANNER_SECONDS = 25
local DOWNLOAD_MAX_SECONDS = 900

-- idle | checking | current | downloading | installing | available | error
local phase = "idle"
local job = nil
local target = nil -- { code, name, rel, sha256 }
local latestName = nil
local shownAt = nil
local dismissed = false
local fontCache = nil -- false once a load attempt failed
local drawBroken = false

-- Test seam: tests swap these for stubs.
PersonalUpdate._deps = {
  fetch = function() return require("src.net.Fetch") end,
  json = function() return require("src.link.Json") end,
}

local function fetchMod()
  local ok, F = pcall(PersonalUpdate._deps.fetch)
  if ok and type(F) == "table" then return F end
  return nil
end

function PersonalUpdate.apkName(code)
  return ("gen1recomp-0.2.%d-android.apk"):format(code)
end

-- Validate a decoded latest.json.  Returns { code, name, url, sha256 } when
-- it describes a newer build of this package, otherwise nil.
function PersonalUpdate.evaluate(doc, currentCode)
  if type(doc) ~= "table" then return nil end
  local code = tonumber(doc.versionCode)
  if not code or code ~= math.floor(code) then return nil end
  if code <= (currentCode or PersonalUpdate.CURRENT_CODE) then return nil end
  if doc.packageName ~= nil and doc.packageName ~= PersonalUpdate.PACKAGE then
    return nil
  end
  local url, sha = doc.apkUrl, doc.sha256
  if type(url) ~= "string" or not url:match("^https://") then return nil end
  if type(sha) ~= "string" or #sha ~= 64 or sha:find("[^0-9a-fA-F]") then
    return nil
  end
  return {
    code = code,
    name = type(doc.versionName) == "string" and doc.versionName
      or ("code " .. tostring(code)),
    url = url,
    sha256 = sha:lower(),
  }
end

local function fileSha256(rel)
  local fs = love and love.filesystem
  if not (fs and fs.getInfo and fs.read and love.data) then return nil end
  local info = fs.getInfo(rel)
  if not info or (info.size or 0) == 0 then return nil end
  local data = fs.read(rel)
  if type(data) ~= "string" then return nil end
  local digest = love.data.hash("sha256", data)
  return love.data.encode("string", "hex", digest):lower()
end

-- Remove cached update APKs that are not newer than the running build.
function PersonalUpdate.pruneCache()
  local fs = love and love.filesystem
  if not (fs and fs.getDirectoryItems and fs.remove) then return end
  local items = fs.getDirectoryItems(PersonalUpdate.UPDATE_DIR) or {}
  for _, n in ipairs(items) do
    local c = tonumber(n:match("^gen1recomp%-0%.2%.(%d+)%-android%.apk$"))
    if c and c <= PersonalUpdate.CURRENT_CODE then
      fs.remove(PersonalUpdate.UPDATE_DIR .. "/" .. n)
    end
  end
end

local function showBanner()
  phase = "available"
  shownAt = (love and love.timer and love.timer.getTime
    and love.timer.getTime()) or 0
end

local function install()
  local sys = love and love.system
  local fs = love and love.filesystem
  if not (sys and type(sys.installApk) == "function" and fs
      and fs.getSaveDirectory) then
    showBanner()
    return
  end
  local abs = fs.getSaveDirectory() .. "/" .. target.rel
  local ok, started = pcall(sys.installApk, abs)
  if ok and started == true then
    phase = "installing"
  else
    showBanner()
  end
end

-- A downloaded / cached file: verify, then install.  Bad file = discard.
local function verifyAndInstall()
  if fileSha256(target.rel) == target.sha256 then
    install()
  else
    if love and love.filesystem and love.filesystem.remove then
      pcall(love.filesystem.remove, target.rel)
    end
    phase = "error"
  end
end

local function onLatest(body)
  local okJ, Json = pcall(PersonalUpdate._deps.json)
  if not okJ or type(Json) ~= "table" then phase = "error" return end
  local okDec, doc = pcall(Json.decode, body)
  if not okDec then phase = "error" return end
  local t = PersonalUpdate.evaluate(doc, PersonalUpdate.CURRENT_CODE)
  if not t then phase = "current" return end
  latestName = t.name
  target = { code = t.code, name = t.name, sha256 = t.sha256,
    rel = PersonalUpdate.UPDATE_DIR .. "/" .. PersonalUpdate.apkName(t.code) }
  -- Cache hit: a verified copy from an earlier launch.
  if fileSha256(target.rel) == target.sha256 then
    install()
    return
  end
  local Fetch = fetchMod()
  if not Fetch or type(Fetch.download) ~= "function" then
    phase = "error"
    return
  end
  local okJob, id = pcall(Fetch.download, t.url, target.rel, {
    userAgent = "PocketRecomp-personal",
    maxSeconds = DOWNLOAD_MAX_SECONDS,
  })
  if okJob and id then
    job = id
    phase = "downloading"
  else
    phase = "error"
  end
end

-- Kick the one-shot check.  Called once from love.load after the launcher
-- exists.  Safe to call again: later calls are no-ops.
function PersonalUpdate.start()
  if phase ~= "idle" then return end
  pcall(PersonalUpdate.pruneCache)
  local Fetch = fetchMod()
  if not Fetch or type(Fetch.get) ~= "function" then
    phase = "error"
    return
  end
  phase = "checking"
  local okJob, id = pcall(Fetch.get, PersonalUpdate.VERSION_URL, {
    userAgent = "PocketRecomp-personal",
    accept = "application/json",
    maxSeconds = 15,
  })
  if okJob and id then
    job = id
  else
    phase = "error"
  end
end

-- Per-frame poll, called from love.update.  Never throws.
function PersonalUpdate.tick()
  local ok, err = pcall(function()
    if phase == "available" then
      if shownAt and love.timer and love.timer.getTime
          and love.timer.getTime() - shownAt > BANNER_SECONDS then
        dismissed = true
      end
      return
    end
    if (phase ~= "checking" and phase ~= "downloading") or not job then return end
    local Fetch = fetchMod()
    if not Fetch then phase = "error" return end
    local okPoll, st = pcall(Fetch.poll, job)
    if not okPoll or type(st) ~= "table" then phase = "error" return end
    if st.status == "pending" then return end
    local body = st.body
    pcall(Fetch.release, job)
    job = nil
    if st.status ~= "ok" then phase = "error" return end
    if phase == "checking" then
      if type(body) ~= "string" then phase = "error" return end
      onLatest(body)
    else
      verifyAndInstall()
    end
  end)
  if not ok then phase = "error" end
  return err
end

local function bannerRect()
  local g = love and love.graphics
  local w = (g and g.getWidth and g.getWidth()) or 0
  return 0, 0, w, 46
end

local function bannerFont()
  if fontCache ~= nil then return fontCache or nil end
  local ok, f = pcall(function()
    return love.graphics.newFont("assets/fonts/noto/NotoSansJP-Regular.ttf", 15)
  end)
  fontCache = (ok and f) or false
  return fontCache or nil
end

-- Draw the fallback banner over the launcher.  Never throws; a draw failure
-- disables the banner for the rest of the session.
function PersonalUpdate.draw()
  if phase ~= "available" or dismissed or drawBroken then return end
  local ok = pcall(function()
    local g = love and love.graphics
    if not (g and g.getWidth) then return end
    local x, y, w, h = bannerRect()
    if w <= 0 then return end
    g.push("all")
    g.origin()
    if g.setScissor then g.setScissor() end
    g.setColor(0.10, 0.10, 0.13, 0.93)
    g.rectangle("fill", x, y, w, h)
    g.setColor(1, 1, 1, 1)
    local font = bannerFont()
    if font then g.setFont(font) end
    local msg
    if font then
      msg = "新しいバージョン " .. tostring(latestName)
        .. " があります — タップで Releases を開く"
    else
      msg = "Update available: " .. tostring(latestName)
        .. " - tap to open Releases"
    end
    g.printf(msg, 10, y + 15, w - 20, "center")
    g.pop()
  end)
  if not ok then drawBroken = true end
end

-- Returns true when the press landed on the banner (and was consumed).
function PersonalUpdate.press(x, y)
  if phase ~= "available" or dismissed then return false end
  if type(x) ~= "number" or type(y) ~= "number" then return false end
  local bx, by, bw, bh = bannerRect()
  if bw <= 0 then return false end
  if x < bx or x > bx + bw or y < by or y > by + bh then return false end
  dismissed = true
  if love and love.system and love.system.openURL then
    pcall(love.system.openURL, PersonalUpdate.RELEASES_URL)
  end
  return true
end

-- For tests / debugging.
function PersonalUpdate.phase()
  return phase
end

function PersonalUpdate._reset()
  phase, job, target, latestName, shownAt, dismissed = "idle", nil, nil, nil, nil, false
end

return PersonalUpdate
