-- Personal-line update notice (PocketRecomp personal build).
--
-- Once per session, shortly after the launcher opens, this asks GitHub
-- Releases for the small version.json that every personal release ships
-- (FoldBoy-style: { versionCode, versionName, apkUrl, note }) and compares
-- its versionCode with the build compiled in below.  When a newer build
-- exists, the launcher shows a banner; tapping the banner opens the
-- Releases page in the browser.  That is all it does:
--
--   * It never downloads, installs or chainloads anything itself.
--   * It never blocks or throws into the game loop: every entry point is
--     pcall-guarded and quietly gives up on any failure (offline, no
--     transport, malformed JSON), which simply means "no banner".
--   * The upstream self-updater (src/update) stays OFF
--     (Version.upstreamUpdates = false): it expects upstream's payload
--     layout and release naming, not this line's full-APK releases.
--
-- The fetch rides the engine's own async pool (src.net.Fetch), the same
-- transport the mod index uses, so the check costs no frame time.
--
-- MAINTENANCE: CURRENT_CODE / CURRENT_NAME must match build.py's
-- VERSION_CODE / VERSION_NAME.  build.py asserts this before building.

local PersonalUpdate = {}

PersonalUpdate.CURRENT_CODE = 95
PersonalUpdate.CURRENT_NAME = "0.2.91-jp.91-personal"
PersonalUpdate.VERSION_URL =
  "https://github.com/bananausagi/pocket-recomp/releases/latest/download/version.json"
PersonalUpdate.RELEASES_URL =
  "https://github.com/bananausagi/pocket-recomp/releases/latest"

local BANNER_SECONDS = 25

local phase = "idle" -- idle | checking | current | available | error
local job = nil
local latestName = nil
local shownAt = nil
local dismissed = false
local fontCache = nil -- false once a load attempt failed
local drawBroken = false

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

-- Kick the one-shot check.  Called once from love.load after the launcher
-- exists.  Safe to call again: later calls are no-ops.
function PersonalUpdate.start()
  if phase ~= "idle" then return end
  local ok, Fetch = pcall(require, "src.net.Fetch")
  if not ok or type(Fetch) ~= "table" or type(Fetch.get) ~= "function" then
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
    if phase ~= "checking" or not job then return end
    local okF, Fetch = pcall(require, "src.net.Fetch")
    if not okF or type(Fetch) ~= "table" then phase = "error" return end
    local okPoll, st = pcall(Fetch.poll, job)
    if not okPoll or type(st) ~= "table" then phase = "error" return end
    if st.status == "pending" then return end
    local body = st.body
    pcall(Fetch.release, job)
    job = nil
    if st.status ~= "ok" or type(body) ~= "string" then
      phase = "error"
      return
    end
    local okJ, Json = pcall(require, "src.link.Json")
    if not okJ or type(Json) ~= "table" then phase = "error" return end
    local okDec, doc = pcall(Json.decode, body)
    if not okDec or type(doc) ~= "table" then phase = "error" return end
    local code = tonumber(doc.versionCode)
    if code and code > PersonalUpdate.CURRENT_CODE then
      latestName = type(doc.versionName) == "string" and doc.versionName
        or ("code " .. tostring(code))
      phase = "available"
      shownAt = (love.timer and love.timer.getTime
        and love.timer.getTime()) or 0
    else
      phase = "current"
    end
  end)
  if not ok then phase = "error" end
  return err
end

-- Draw the banner over the launcher.  Called from love.draw after the
-- launcher has drawn.  Never throws; a draw failure disables the banner
-- for the rest of the session instead of erroring every frame.
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

-- Returns true when the press landed on the banner (and was consumed):
-- opens the Releases page and dismisses the banner.
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

-- idle | checking | current | available | error (for tests / debugging)
function PersonalUpdate.phase()
  return phase
end

return PersonalUpdate
