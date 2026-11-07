-- Exact delivered jp.22 archives: upgrade only pristine managed Dramaless.
function love.load()
  local ok, err = xpcall(function()
    local root = assert(os.getenv("JP_UPGRADE_ROOT"))
    package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
    local fs = love.filesystem
    local Json = require("src.link.Json")
    local Save = require("src.core.SaveData")
    local Mods = require("src.mods.LauncherMods")
    local Pack = require("src.mods.JapaneseStarterPack")
    local NEW, OLD = "DRAMALESS_SHAPE", "VOXEL_ASCENDANT"
    local f = assert(io.open(assert(os.getenv("JP_UPGRADE_JP22")), "rb"))
    local bytes = f:read("*a"); f:close()
    assert(fs.mount(fs.newFileData(bytes, "jp22.love"), "jp22", true))
    local prior = assert(Json.decode(fs.read("jp22/assets/jp-mods/catalog.json")))
    local current = assert(Json.decode(fs.read("assets/jp-mods/catalog.json")))
    local before, after = {}, {}
    for _, e in ipairs(prior) do before[e.id] = e end
    for _, e in ipairs(current) do after[e.id] = e end
    local n = 0
    local function check(value, message)
      assert(value, message); n = n + 1; print("PASS " .. message)
    end
    local function copy(value)
      if type(value) ~= "table" then return value end
      local out = {}; for k, v in pairs(value) do out[k] = copy(v) end
      return out
    end
    local function same(a, b)
      if type(a) ~= type(b) then return false end
      if type(a) ~= "table" then return a == b end
      for k, v in pairs(a) do if not same(v, b[k]) then return false end end
      for k in pairs(b) do if a[k] == nil then return false end end
      return true
    end
    local function snapshot(path)
      local out = {}
      local function walk(at, prefix)
        for _, name in ipairs(fs.getDirectoryItems(at) or {}) do
          local full = at .. "/" .. name
          if fs.getInfo(full).type == "directory" then walk(full, prefix .. name .. "/")
          else out[prefix .. name] = assert(fs.read(full)) end
        end
      end
      walk(path, ""); return out
    end
    local function remove(path)
      for _, name in ipairs(fs.getDirectoryItems(path) or {}) do
        local full = path .. "/" .. name
        if fs.getInfo(full).type == "directory" then remove(full)
        else assert(fs.remove(full)) end
      end
      assert(fs.remove(path))
    end
    check(before[NEW].version == "2.0.4+jp.16", "baseline is delivered jp22 Dramaless .16")
    check(after[NEW].version == "2.0.4+jp.17", "candidate is jp23 Dramaless .17")
    check(not after[OLD], "candidate never bundles Ascendant")
    check(fs.read("assets/jp-mods/upgrades-jp22.json") ==
      fs.read("jp22/assets/jp-mods/managed-renderers.json"), "jp22 fingerprint is exact delivered snapshot")
    for id, e in pairs(before) do
      if id ~= NEW then
        check(after[id] and after[id].version == e.version, id .. " retains delivered companion version")
        check(fs.read(after[id].archive) == fs.read("jp22/" .. e.archive),
          id .. " archive remains byte-identical")
      end
    end
    -- Independent expected tree comes from the validated candidate ZIP installer.
    fs.setIdentity("jp23-upgrade-expected")
    assert(Mods.installZip(after[NEW].archive, {expectId=NEW}))
    local expected = snapshot("mods/" .. NEW)
    local function setup(mode, blurLevel, legacyBattleBlur)
      fs.setIdentity("jp23-upgrade-" .. mode)
      Save.invalidateOptions()
      local options = {
        jpStarterPackV1={}, jpRendererMigrationV1="managed", jpRendererRollbackV1=true,
        jpDisplayDefaultsV3=true, jpDialogScale=0.5, jpDotMatrix=1,
        jpPartyExp=true, jpForgetHM=true, jpReusableTM=true, jpFieldActions=false,
        jpAnalogWalk=true, jpBattleIntro="original", colors="redpp_soft",
        jpBattleBlur=legacyBattleBlur or "strong",
        jpAtmosphere=(blurLevel or 3) % 2 == 0 and "off" or "soft",
        mods={[NEW]=true, [OLD]=false, SHINY_POKEMON=false},
        modsByVersion={red_jp={[NEW]=true,[OLD]=false,OTHER=false},
          future_cart={[NEW]=false,[OLD]=false,UNKNOWN=true}},
        modOptions={[NEW]={daytime="dusk",renderDistanceSetting=32,shadowQuality="off",
          renderScale=1,voxel_2d_battles=false,battleBack=false},
          [OLD]={daytime="night",terrainHeights="world"},running_shoes={bike=false}},
        modProfiles={{name="mine",enabled={[NEW]=true,[OLD]=false},
          enabledByVersion={red_jp={[NEW]=true,[OLD]=false,OTHER=false}},
          slots={red_jp="slot1"},options={[NEW]={daytime="night"}}},
          {name="off",enabled={[NEW]=false,[OLD]=false},slots={},options={},
            enabledByVersion={red_jp={[NEW]=false,[OLD]=false}}}},
        activeProfile="mine", customFuture={keep="mine"}, pipelines={voxel=2,tiltshift=blurLevel or 3},
      }
      for _, e in ipairs(prior) do
        assert(Mods.installZip("jp22/" .. e.archive, {expectId=e.id}))
        options.jpStarterPackV1[e.id] = e.version
      end
      if mode == "disabled" then
        options.mods[NEW] = false; options.modsByVersion.red_jp[NEW] = false
      elseif mode == "modified" then
        assert(fs.write("mods/" .. NEW .. "/main.lua", "-- user's modified renderer\nreturn {}\n"))
      elseif mode == "added-file" then
        assert(fs.write("mods/" .. NEW .. "/user-custom.txt", "user data"))
      elseif mode == "manual" then
        options.jpStarterPackV1[NEW] = "existing"
      elseif mode == "removed" then
        remove("mods/" .. NEW)
      elseif mode == "removed-file" then
        assert(fs.remove("mods/" .. NEW .. "/main.lua"))
      elseif mode == "duplicate" then
        local original = snapshot("mods/" .. NEW)
        for path, data in pairs(original) do
          local full = "mods/manual-dramaless/" .. path
          assert(fs.createDirectory(full:match("^(.*)/")))
          assert(fs.write(full, data))
        end
      end
      assert(Save.saveOptions(options))
      -- Compare the persisted state, including SaveData's ordinary normalization.
      return Save.loadOptions(), snapshot("mods")
    end
    for _, mode in ipairs({"pristine","disabled","modified","added-file","manual",
      "removed","removed-file","duplicate"}) do
      local options, allBefore = setup(mode)
      local original = snapshot("mods/" .. NEW)
      local changes = mode == "pristine" or mode == "disabled"
      local result, detail = Pack.install()
      check(result == changes, mode .. " upgrade result: " .. tostring(detail))
      local saved = Save.loadOptions()
      local wanted = copy(options)
      if changes then wanted.jpStarterPackV1[NEW] = after[NEW].version end
      check(same(saved, wanted), mode .. " changes only managed version marker")
      check(saved.jpRendererRollbackV1 == true, mode .. " retains completed retirement marker")
      check(not Mods.installedVersions()[OLD], mode .. " does not reinstall Ascendant")
      if changes then
        check(same(snapshot("mods/" .. NEW), expected), mode .. " installed tree equals candidate ZIP")
        check(same(snapshot("jp-mod-backups/jp22/" .. NEW), original),
          mode .. " backup equals all exact jp22 bytes")
        local allAfter = snapshot("mods")
        for path, data in pairs(allBefore) do
          if path:sub(1, #NEW + 1) ~= NEW .. "/" then
            check(allAfter[path] == data, mode .. " companion byte retained " .. path)
          end
        end
      else
        check(same(snapshot("mods"), allBefore), mode .. " all user files remain unchanged")
        check(not fs.getInfo("jp-mod-backups/jp22/" .. NEW), mode .. " creates no misleading backup")
      end
      check(Pack.install() == false, mode .. " second launch does not repeat upgrade")
    end
    -- Retired battle-only values are retained as user data, while every shared
    -- field blur level survives exactly. No migration silently chooses a level.
    for level = 0, 5 do
      for _, legacy in ipairs({"off", "normal", "strong"}) do
        local mode = "blur-" .. level .. "-" .. legacy
        local options = setup(mode, level, legacy)
        check(Pack.install() == true, mode .. " updates managed renderer")
        local saved = Save.loadOptions()
        local wanted = copy(options); wanted.jpStarterPackV1[NEW] = after[NEW].version
        check(same(saved, wanted), mode .. " preserves all options including jp22 conveniences")
        check(saved.pipelines.tiltshift == level, mode .. " retains shared field blur level")
        check(saved.jpBattleBlur == legacy, mode .. " retains unused legacy battle preference")
        check(Pack.install() == false, mode .. " second launch is idempotent")
      end
    end
    -- A settings writer can fail after installing the replacement and after it
    -- has persisted the new marker. Roll back every MOD byte and all witnesses.
    for _, mode in ipairs({"save-failure", "install-failure"}) do
      local options, allBefore = setup(mode)
      local names = {"options.lua", "options.lua.bak", "options.lua.tmp"}
      local witnesses = {}; for _, name in ipairs(names) do witnesses[name] = fs.read(name) or false end
      local deps
      if mode == "save-failure" then
        deps = {SaveData=setmetatable({saveOptions=function(value)
          assert(Save.saveOptions(value))
          check(Save.loadOptions().jpStarterPackV1[NEW] == after[NEW].version,
            "save failure occurs after candidate marker reaches cache and disk")
          return nil, "fixture partial settings failure"
        end}, {__index=Save})}
      else
        deps = {LauncherMods=setmetatable({installZip=function(path, config)
          if config.expectId == NEW then return nil, "fixture install failure" end
          return Mods.installZip(path, config)
        end}, {__index=Mods})}
      end
      local result, detail = Pack.install(deps)
      check(result == nil and detail:find("fixture",1,true), mode .. " is reported")
      check(same(snapshot("mods"), allBefore), mode .. " restores exact installed bytes")
      for _, name in ipairs(names) do
        check((fs.read(name) or false) == witnesses[name], mode .. " restores " .. name)
      end
      check(same(Save.loadOptions(), options), mode .. " restores cached preferences and marker")
      check(Pack.install() == true, mode .. " retry upgrades successfully")
      check(same(snapshot("mods/" .. NEW), expected), mode .. " retry installs exact candidate")
      local wanted = copy(options); wanted.jpStarterPackV1[NEW] = after[NEW].version
      check(same(Save.loadOptions(), wanted), mode .. " retry preserves every saved choice")
      check(Pack.install() == false, mode .. " successful retry is not repeated")
    end
    print("RESULT " .. n .. " checks passed")
  end, debug.traceback)
  if not ok then print(err) end
  love.event.quit(ok and 0 or 1)
end
