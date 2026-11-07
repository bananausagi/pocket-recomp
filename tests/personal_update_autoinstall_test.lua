#!/usr/bin/env luajit
-- PersonalUpdate auto-install flow (stubbed love / Fetch, no network).
-- Run: luajit tests/personal_update_autoinstall_test.lua   (from a tb dir or the repo root)
package.path = "./?.lua;./?/init.lua;./game/?.lua;./game/?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then print("[ok] " .. msg) else failed = failed + 1; print("[FAIL] " .. msg) end
end

-- Minimal sha256 for the stub (pure Lua via bit ops).
local bit = require("bit")
local band, bor, bxor, bnot, rshift, lshift, ror = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift, bit.ror
local K = {
0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local function sha256(msg)
  local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  local ml = #msg * 8
  msg = msg .. "\128" .. string.rep("\0", (55 - #msg) % 64)
  msg = msg .. string.char(0,0,0,0, band(rshift(ml,24),255), band(rshift(ml,16),255), band(rshift(ml,8),255), band(ml,255))
  for c = 1, #msg, 64 do
    local w = {}
    for i = 0, 15 do
      local a,b,cc,d = msg:byte(c+i*4, c+i*4+3)
      w[i] = bor(lshift(a,24), lshift(b,16), lshift(cc,8), d)
    end
    for i = 16, 63 do
      local s0 = bxor(ror(w[i-15],7), ror(w[i-15],18), rshift(w[i-15],3))
      local s1 = bxor(ror(w[i-2],17), ror(w[i-2],19), rshift(w[i-2],10))
      w[i] = bit.tobit(w[i-16] + s0 + w[i-7] + s1)
    end
    local a,b,cc,d,e,f,g,hh = h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
    for i = 0, 63 do
      local S1 = bxor(ror(e,6), ror(e,11), ror(e,25))
      local ch = bxor(band(e,f), band(bnot(e),g))
      local t1 = bit.tobit(hh + S1 + ch + K[i+1] + w[i])
      local S0 = bxor(ror(a,2), ror(a,13), ror(a,22))
      local maj = bxor(band(a,b), band(a,cc), band(b,cc))
      local t2 = bit.tobit(S0 + maj)
      hh,g,f,e,d,cc,b,a = g,f,e,bit.tobit(d+t1),cc,b,a,bit.tobit(t1+t2)
    end
    h[1],h[2],h[3],h[4] = bit.tobit(h[1]+a),bit.tobit(h[2]+b),bit.tobit(h[3]+cc),bit.tobit(h[4]+d)
    h[5],h[6],h[7],h[8] = bit.tobit(h[5]+e),bit.tobit(h[6]+f),bit.tobit(h[7]+g),bit.tobit(h[8]+hh)
  end
  local out = {}
  for i = 1, 8 do out[i] = bit.tohex(h[i]) end
  return table.concat(out)
end
check(sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "stub sha256 sane")

-- Stub love.
local files, removed, installs, opened = {}, {}, {}, {}
local installResult = true
love = {
  filesystem = {
    getSaveDirectory = function() return "/save" end,
    getInfo = function(p) return files[p] and { size = #files[p] } or nil end,
    read = function(p) return files[p] end,
    remove = function(p) removed[#removed+1] = p; files[p] = nil; return true end,
    getDirectoryItems = function(d)
      local t = {}
      for p in pairs(files) do local n = p:match("^" .. d .. "/(.+)$"); if n then t[#t+1] = n end end
      return t
    end,
  },
  data = {
    hash = function(_, s) return { raw = s } end,
    encode = function(_, _, d) return sha256(d.raw) end,
  },
  system = {
    installApk = function(p) installs[#installs+1] = p; return installResult end,
    openURL = function(u) opened[#opened+1] = u end,
  },
  timer = { getTime = function() return 0 end },
}

-- Stub Fetch: jobs resolve on the first poll.
local jobs, nextId, downloads, payload = {}, 0, {}, nil
local latestBody
local Fetch = {
  get = function(url) nextId = nextId + 1; jobs[nextId] = { kind = "get", url = url }; return nextId end,
  download = function(url, rel) nextId = nextId + 1; jobs[nextId] = { kind = "dl", url = url, rel = rel }; downloads[#downloads+1] = rel; return nextId end,
  poll = function(id)
    local j = jobs[id]
    if not j then return { status = "error" } end
    if j.kind == "get" then
      if latestBody == nil then return { status = "error", err = "offline" } end
      return { status = "ok", body = latestBody }
    end
    if payload == nil then return { status = "error", err = "offline" } end
    files[j.rel] = payload
    return { status = "ok", path = j.rel }
  end,
  release = function(id) jobs[id] = nil end,
}

local PU = require("src.jp.PersonalUpdate")
PU._deps.fetch = function() return Fetch end
check(PU.CURRENT_CODE == 96, "CURRENT_CODE 96")
check(PU.VERSION_URL:find("apps-release/main/pocket-recomp/latest.json", 1, true) ~= nil, "VERSION_URL is the public release repo")

local APK = "fake-apk-bytes-0123456789"
local SHA = sha256(APK)
local function latest(code, sha, extra)
  return ('{"packageName":"org.gen1recomp.japanese.preview","versionCode":%d,"versionName":"v%d","apkUrl":"https://github.com/bananausagi/apps-release/releases/download/t/a.apk","sha256":"%s","notes":"n"%s}')
    :format(code, code, sha or SHA, extra or "")
end
local function run()
  PU._reset(); PU.start()
  for _ = 1, 5 do PU.tick() end
  return PU.phase()
end
local REL = "updates/gen1recomp-0.2.97-android.apk"

-- evaluate()
check(PU.evaluate({ versionCode = 97, apkUrl = "https://x/a.apk", sha256 = SHA }, 96) ~= nil, "evaluate: newer")
check(PU.evaluate({ versionCode = 96, apkUrl = "https://x/a.apk", sha256 = SHA }, 96) == nil, "evaluate: same")
check(PU.evaluate({ versionCode = 97, apkUrl = "http://x/a.apk", sha256 = SHA }, 96) == nil, "evaluate: http rejected")
check(PU.evaluate({ versionCode = 97, apkUrl = "https://x/a.apk", sha256 = "zz" }, 96) == nil, "evaluate: bad sha rejected")
check(PU.evaluate({ versionCode = 97, packageName = "other", apkUrl = "https://x/a.apk", sha256 = SHA }, 96) == nil, "evaluate: other package rejected")
check(PU.apkName(97) == "gen1recomp-0.2.97-android.apk", "apk name matches native installer pattern")
check(PU.apkName(97):match("^gen1recomp%-%d+%.%d+%.%d+%-android%.apk$") ~= nil, "name regex")

-- 1. offline: silent
latestBody = nil
check(run() == "error" and #downloads == 0 and #installs == 0 and #opened == 0, "offline: silent no-op")

-- 2. up to date
latestBody = latest(96)
check(run() == "current" and #downloads == 0, "same version: nothing")

-- 3. garbage JSON
latestBody = "<html>rate limited</html>"
local ph = run()
check((ph == "error" or ph == "current") and #downloads == 0, "garbage JSON: silent")

-- 4. newer: download -> verify -> install
latestBody = latest(97); payload = APK
check(run() == "installing", "newer: phase installing")
check(#downloads == 1 and downloads[1] == REL, "downloaded once to updates/")
check(#installs == 1 and installs[1] == "/save/" .. REL, "installApk called with absolute save path")

-- 5. next launch: cached verified file -> no re-download
check(run() == "installing" and #downloads == 1 and #installs == 2, "cache hit: install without re-download")

-- 6. hash mismatch: discard, no install
files = {}; downloads = {}; installs = {}
latestBody = latest(97, string.rep("a", 64)); payload = APK
check(run() == "error" and #installs == 0 and files[REL] == nil, "bad hash: discarded, not installed")

-- 7. download failure: silent
files = {}; downloads = {}; installs = {}; payload = nil; latestBody = latest(97)
check(run() == "error" and #installs == 0 and #opened == 0, "download failure: silent")

-- 8. installer refuses (e.g. unknown-sources setting opened): fallback banner
files = {}; downloads = {}; installs = {}; payload = APK; installResult = false
check(run() == "available" and #installs == 1, "installer refused: fallback banner")
check(PU.press(1, 1) == false or true, "press does not throw")
installResult = true

-- 9. prune: cached APKs at/below current build are removed on start
files = { ["updates/gen1recomp-0.2.95-android.apk"] = "x", ["updates/gen1recomp-0.2.96-android.apk"] = "x",
          ["updates/gen1recomp-0.2.97-android.apk"] = APK, ["updates/other.bin"] = "x" }
latestBody = nil
run()
check(files["updates/gen1recomp-0.2.95-android.apk"] == nil and files["updates/gen1recomp-0.2.96-android.apk"] == nil, "prune: old cached APKs removed")
check(files["updates/gen1recomp-0.2.97-android.apk"] ~= nil and files["updates/other.bin"] ~= nil, "prune: newer APK and unrelated files kept")

-- 10. no love.system.installApk: banner, no throw
files = {}; installs = {}; latestBody = latest(97); payload = APK
local saved = love.system.installApk; love.system.installApk = nil
check(run() == "available", "no native installer: banner fallback")
love.system.installApk = saved

if failed > 0 then print(failed .. " FAILED"); os.exit(1) end
print("ALL PASS")
