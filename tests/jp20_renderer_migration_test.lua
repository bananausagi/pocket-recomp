package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness").suite("jp20 renderer rollback")
local M = require("src.mods.JapaneseRendererMigration")
local Save = require("src.core.SaveData")
local Profiles = require("src.mods.ModProfile")
local versions = require("src.core.GameVersion").ORDER
local Json = require("src.link.Json")
local function clone(x)
  if type(x) ~= "table" then return x end
  local out = {}; for k,v in pairs(x) do out[k]=clone(v) end; return out
end
local function apply(opts, installed)
  local c = M.prepare(opts, installed or {})
  T.check(M.apply(opts,c), "first migration applies")
  return c
end
for _, mode in ipairs({"fresh", "jp18", "jp19", "manual", "missing-fallback", "both-off", "other-renderer"}) do
  local opts = {jpStarterPackV1={},mods={},modsByVersion={red_jp={OTHER=false}},
    modOptions={[M.OLD]={daytime="dusk",terrainHeights="world"},[M.NEW]={daytime="day",renderScale=4}},
    modProfiles={{name="inherit",enabled={},slots={red_jp="mine"},enabledByVersion={red_jp={}}},
      {name="off",enabled={[M.OLD]=false,[M.NEW]=false},options={retained={nested={keep=true}}},
       enabledByVersion={red_jp={[M.OLD]=false,[M.NEW]=false,UNRELATED=true}}}},activeProfile="inherit"}
  local installed = {}
  if mode ~= "fresh" then installed[M.NEW]="fallback" end
  local revert = mode=="jp19" or mode=="manual" or mode=="missing-fallback"
  if revert then
    installed[M.OLD]="ascendant"
    opts.mods[M.OLD],opts.mods[M.NEW]=false,true
    opts.modsByVersion.red_jp[M.OLD],opts.modsByVersion.red_jp[M.NEW]=true,false
    opts.jpRendererMigrationV1="managed"
  end
  if mode=="missing-fallback" then installed[M.NEW]=nil end
  if mode=="both-off" then opts.mods[M.OLD],opts.mods[M.NEW]=false,false end
  if mode=="other-renderer" then installed.TERRARIUM="manual";opts.mods.TERRARIUM=true end
  local oldOptions = Json.encode(opts.modOptions)
  local profileOptions = Json.encode(opts.modProfiles[2].options)
  local c=apply(opts,installed)
  T.eq(c.needsRestore,revert,mode.." repair eligibility")
  T.eq(Save.modEnabled(opts,M.OLD,"red_jp"),false,mode.." retired renderer disabled")
  T.eq(Save.modEnabled(opts,M.NEW,"red_jp"),mode~="both-off" and mode~="other-renderer",mode.." fallback selection")
  T.eq(opts.modsByVersion.red_jp.OTHER,false,mode.." unrelated overlay retained")
  T.eq(Json.encode(opts.modOptions),oldOptions,mode.." both renderer options unchanged")
  T.eq(Json.encode(opts.modProfiles[2].options),profileOptions,mode.." profile options untouched")
  T.eq(opts.modProfiles[1].slots.red_jp,"mine",mode.." save slot untouched")
  T.eq(opts.activeProfile,"inherit",mode.." active profile untouched")
  for _,p in ipairs(opts.modProfiles)do
    local live={mods=clone(p.enabled),modsByVersion=clone(opts.modsByVersion)}
    Profiles.restoreVersions(p,live)
    for _,version in ipairs(versions)do
      T.eq(Save.modEnabled(live,M.OLD,version),false,mode.." "..p.name.." no Ascendant "..version)
    end
    if p.name=="off"then
      T.eq(Save.modEnabled(live,M.NEW,"red_jp"),false,mode.." profile both-off choice preserved")
      T.eq(live.modsByVersion.red_jp.UNRELATED,true,mode.." profile custom overlay retained")
    else
      T.eq(live.modsByVersion.red_jp.OTHER,false,mode.." empty profile overlay inherits unrelated flag")
      T.eq(Save.modEnabled(live,M.NEW,"red_jp"),mode~="other-renderer",mode.." inherited fallback choice")
    end
  end
  opts.mods[M.NEW]=false
  T.eq(M.prepare(opts,installed),nil,mode.." marker prevents repeat migration")
  T.eq(M.apply(opts,c),false,mode.." old context cannot repeat migration")
  T.eq(opts.mods[M.NEW],false,mode.." later fallback disable remains deliberate")
end
-- Installed manual Ascendant with no explicit flags is enabled by the loader.
local opts={mods={[M.NEW]=false},modsByVersion={future_cart={[M.OLD]=true,OTHER=false}},
  modProfiles={{name="future",enabled={[M.OLD]=true},enabledByVersion={future_cart={}}}}}
local c=apply(opts,{[M.OLD]="manual"})
T.eq(c.needsRestore,true,"implicit active manual renderer requires missing fallback")
T.eq(opts.mods[M.NEW],true,"implicit active manual renderer restored")
T.eq(opts.modsByVersion.future_cart[M.OLD],false,"unknown game overlay also retires renderer")
T.eq(opts.modsByVersion.future_cart.OTHER,false,"unknown game unrelated choice retained")
T.eq(opts.modProfiles[1].enabledByVersion.future_cart[M.OLD],false,"unknown profile overlay retires renderer")
T.eq(opts.modProfiles[1].enabledByVersion.future_cart.OTHER,false,"unknown profile inherits unrelated choice")
-- An empty profile game bucket must inherit an explicit live per-game disable.
opts={mods={[M.NEW]=true},modsByVersion={red_jp={[M.NEW]=false,[M.OLD]=false,OTHER=false}},
  modProfiles={{name="empty",enabled={[M.NEW]=true},enabledByVersion={red_jp={}}}}}
apply(opts,{[M.OLD]="installed",[M.NEW]="installed"})
T.eq(opts.modProfiles[1].enabledByVersion.red_jp[M.NEW],false,"empty profile retains live per-game fallback disable")
T.eq(opts.modProfiles[1].enabledByVersion.red_jp.OTHER,false,"empty profile retains live unrelated disable")
T.finish()
