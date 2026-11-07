package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require("tests.harness").suite("Japanese starter pack migration")
local Pack = require("src.mods.JapaneseStarterPack")
local Json = require("src.link.Json")
local entries = {
  { id = "DRAMALESS_SHAPE", version = "2.0.4+jp.1", archive = "a.zip" },
  { id = "running_shoes", version = "1.10.0+jp.1", archive = "b.zip" },
  { id = "erilab_bottomless_bag", version = "1.1.0+jp.1", archive = "c.zip" },
}
local function setup(opts, existing, fail)
  local calls, writes = {}, 0
  local deps = {
    Json = Json,
    fs = {
      -- Model a fresh filesystem: historical migration manifests and retired
      -- MOD directories are absent. Returning the catalog for every filename
      -- did not match the production filesystem contract.
      read = function(path) if path == 'assets/jp-mods/catalog.json' then return Json.encode(entries) end end,
      getDirectoryItems = function() return {} end,
      getInfo = function() return nil end,
    },
    SaveData = {
      loadOptions = function() return opts end,
      saveOptions = function(value) opts = value; writes = writes + 1; return value end,
    },
    LauncherMods = {
      installedVersions = function() return existing or {} end,
      installZip = function(path, config)
        calls[#calls + 1] = { path = path, config = config }
        if config.expectId == fail then return nil, "disk full" end
        return true, config.expectId
      end,
    },
  }
  return deps, calls, function() return opts, writes end
end

local deps, calls, state = setup({ musicVol = 3, modOptions = {} })
S.check(Pack.install(deps), "fresh install changes options")
S.eq(#calls, 3, "installs three validated archives")
for _, call in ipairs(calls) do
  S.check(call.config.replace == nil, "never replaces an existing mod")
end
local opts = state()
S.eq(opts.jpDialogScale, 0.75, "fresh unset window size defaults to compact")
S.eq(opts.jpDotMatrix, 0, "fresh unset dot matrix defaults off")
S.eq(opts.musicVol, 3, "keeps unrelated preferences")
S.eq(opts.pipelines.voxel, 3, "starts in the 35 degree camera")
S.eq(opts.modOptions.DRAMALESS_SHAPE.shadowQuality, "high", "fresh mobile shadows on")
S.eq(opts.modOptions.DRAMALESS_SHAPE.renderDistanceSetting, 64, "fresh draw distance defaults to FAR")
S.eq(opts.modOptions.DRAMALESS_SHAPE.aa, 0, "no supersampling")
opts.mods = { DRAMALESS_SHAPE = false }
opts.pipelines.voxel = 0
S.eq(Pack.install(deps), false, "restart does not reinstall even after uninstall")
S.eq(#calls, 3, "no second install calls")
S.eq(opts.mods.DRAMALESS_SHAPE, false, "disabled choice survives")
S.eq(opts.pipelines.voxel, 0, "camera off survives")

deps, calls, state = setup({ pipelines = { voxel = 0 },
  mods = { DRAMALESS_SHAPE = false },
  modOptions = { DRAMALESS_SHAPE = { renderScale = 4 } },
}, { DRAMALESS_SHAPE = "9.0.0" })
S.check(Pack.install(deps), "adds missing companions alongside existing renderer")
S.eq(#calls, 2, "existing renderer untouched")
opts = state()
S.eq(opts.jpStarterPackV1.DRAMALESS_SHAPE, "existing", "records existing copy")
S.eq(opts.modOptions.DRAMALESS_SHAPE.renderScale, 4, "keeps renderer settings")
S.eq(opts.pipelines.voxel, 0, "does not force existing renderer on")

deps, calls, state = setup({}, {}, "running_shoes")
local ok, err = Pack.install(deps)
S.eq(ok, nil, "reports a failed install")
S.check(err:find("disk full", 1, true) ~= nil, "keeps error detail")
opts = state()
S.check(opts.jpStarterPackV1.running_shoes == nil, "failed install remains retryable")
S.check(opts.jpStarterPackV1.erilab_bottomless_bag ~= nil, "successful install recorded")
Pack.install(deps)
S.eq(#calls, 4, "only the failed archive is retried")

for _, value in ipairs({ 0.5, 0.75, 1 }) do
  for _, alreadyInitialized in ipairs({ false, true }) do
    deps, calls, state = setup({ jpDialogScale = value,
      jpDisplayDefaultsV3 = alreadyInitialized })
    S.check(Pack.install(deps), "first pack install succeeds with saved window size")
    opts = state()
    S.eq(opts.jpDialogScale, value, "explicit window size survives display defaults")
    S.eq(Pack.install(deps), false, "window-size initialization is idempotent")
    S.eq(opts.jpDialogScale, value, "restart retains the saved window size")
  end
end

-- Explicit dot-matrix choices must survive both first initialization and upgrades.
for _, value in ipairs({ 0, 1, 2, 3 }) do
  for _, initialized in ipairs({ false, true }) do
    deps, calls, state = setup({ jpDotMatrix=value, jpDisplayDefaultsV3=initialized })
    S.check(Pack.install(deps), "pack initializes with an explicit dot setting")
    opts=state()
    S.eq(opts.jpDotMatrix, value, "saved dot strength is preserved")
    S.eq(Pack.install(deps), false, "saved dot choice is idempotent")
    S.eq(opts.jpDotMatrix, value, "restart preserves dot strength")
  end
end

-- Exercise the real options loader/merger, which fills colors before StarterPack.
local RealSave=require("src.core.SaveData")
local fresh=RealSave.loadOptions({getInfo=function()return nil end})
S.eq(fresh.colors, "redpp", "real fresh options enable additional colors")
S.eq(fresh.jpDialogScale, 0.75, "real fresh options select compact windows")
S.eq(RealSave.mergeOptions({jpDisplayDefaultsV3=true}).jpDialogScale, 0.75, "old options with missing size receive compact")
deps,calls,state=setup(fresh)
S.check(Pack.install(deps), "real defaults initialize the starter pack")
opts=state()
S.eq(opts.jpDotMatrix, 0, "real fresh initialization leaves dot matrix off")
S.eq(opts.colors, "redpp", "starter pack retains additional colors")
for _, value in ipairs({"gbc","redpp","classic","og"}) do
  local encoded=RealSave.encode({colors=value,palette="my-palette",color="original"})
  local loaded=RealSave.loadOptions({
    getInfo=function(path)if path=="options.lua"then return {type="file"}end end,
    read=function()return encoded end})
  deps,calls,state=setup(loaded)
  S.check(Pack.install(deps), "saved palette options initialize")
  opts=state()
  S.eq(opts.colors, value, "saved color mode is preserved")
  S.eq(opts.palette, "my-palette", "saved custom palette is preserved")
  S.eq(opts.color, "original", "Gen2 color preference is preserved")
end

for _, value in ipairs({ "off", "high" }) do
  for _, installed in ipairs({ false, true }) do
    deps,calls,state=setup({modOptions={DRAMALESS_SHAPE={shadowQuality=value}}},
      installed and {DRAMALESS_SHAPE="9.0.0"} or nil)
    S.check(Pack.install(deps), "pack initializes with saved shadow setting")
    opts=state()
    S.eq(opts.modOptions.DRAMALESS_SHAPE.shadowQuality, value, "saved shadow choice is preserved")
    S.eq(Pack.install(deps), false, "saved shadow setting is idempotent")
    S.eq(opts.modOptions.DRAMALESS_SHAPE.shadowQuality, value, "restart preserves shadow choice")
  end
end

-- Stored ladder values are distances, not ordinal selection indices.
for _, value in ipairs({ 16, -1, 32, 64 }) do
  for _, installed in ipairs({ false, true }) do
    deps,calls,state=setup({modOptions={DRAMALESS_SHAPE={renderDistanceSetting=value}}},
      installed and {DRAMALESS_SHAPE="9.0.0"} or nil)
    S.check(Pack.install(deps), "pack initializes with saved draw distance")
    opts=state()
    S.eq(opts.modOptions.DRAMALESS_SHAPE.renderDistanceSetting, value, "saved distance is preserved")
    S.eq(Pack.install(deps), false, "saved distance is idempotent")
    S.eq(opts.modOptions.DRAMALESS_SHAPE.renderDistanceSetting, value, "restart preserves distance")
  end
end

-- Load the actual MOD setting implementation to verify the seeded value maps
-- to FAR rather than FULL or a selection index. No graphics or ROM is involved.
deps,calls,state=setup({})
Pack.install(deps)
opts=state()
local V={mod={id="DRAMALESS_SHAPE",options={get=function(_,key)
  return opts.modOptions.DRAMALESS_SHAPE[key]
end}}}
local ModSetting=assert(loadfile("vendor/jp-mods/DRAMALESS_SHAPE/lib/ModSetting.lua"))(V)
V.require=function(name)assert(name=="ModSetting");return ModSetting end
local Quality=assert(loadfile("vendor/jp-mods/DRAMALESS_SHAPE/lib/Quality.lua"))(V)
S.eq(Quality.renderDistanceSetting:get(), 64, "actual MOD reads the seeded FAR value")
S.eq(Quality.renderDistanceSetting:row().value(), "FAR", "actual MOD labels the default FAR")
S.eq(Quality.renderDistance(), 128, "actual MOD converts FAR to its render distance")

for _, value in ipairs({ 0.5, 0.75, 1 }) do
  S.eq(RealSave.mergeOptions({jpDialogScale=value}).jpDialogScale, value,
    "real option merge preserves every explicit window size")
  local encoded=RealSave.encode({jpDialogScale=value})
  local loaded=RealSave.loadOptions({
    getInfo=function(path)if path=="options.lua"then return {type="file"}end end,
    read=function()return encoded end})
  S.eq(loaded.jpDialogScale, value, "real saved options preserve window size")
end

S.finish()
