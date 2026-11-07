package.path='./?.lua;./?/init.lua;'..package.path
local kit=require('tests.modkit')
local T=require('tests.harness').suite('jp31 grass hotfix native MOD loader')
local Json=require('src.link.Json')
require('src.core.GameVersion').set('red_jp')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local addon='mods-local/JP_GRASS_PRESERVE/'
local host=Json.decode(read('vendor/jp-mods/DRAMALESS_SHAPE/manifest.json'))
local files={
 ['mods/JP_GRASS_PRESERVE/manifest.json']=read(addon..'manifest.json'),
 ['mods/JP_GRASS_PRESERVE/main.lua']=read(addon..'main.lua'),
 ['mods/DRAMALESS_SHAPE/main.lua']=[[
  local mod=...
  local voxel={}
  function voxel.grassClearance(a,b)voxel.lowered=a~=nil or b~=nil;voxel.decorated=voxel.lowered end
  function voxel.battleDecoration(b)voxel.decorated=b end
  mod.exports.probe=voxel
  mod.exports.lib={require=function(name)assert(name=='Voxel3D');return voxel end}
 ]],
}
for _,version in ipairs({'2.0.11+jp.18','2.0.10+jp.18','2.0.12+jp.18'})do
 host.version=version;files['mods/DRAMALESS_SHAPE/manifest.json']=Json.encode(host)
 local run=kit.sdk.loadMods({'mods/DRAMALESS_SHAPE','mods/JP_GRASS_PRESERVE'},{fs=kit.sdk.memfs(files)})
 local addonExport=run.loader.exports.JP_GRASS_PRESERVE
 local voxel=assert(run.loader.exports.DRAMALESS_SHAPE).probe
 if version=='2.0.11+jp.18' then
  T.eq(#run.errors,0,'real loader and sandbox accept the add-on')
  T.check(addonExport and addonExport.applied,'real mods.loaded event installs the hotfix')
  voxel.grassClearance({1,2,0},{3,4,0},32)
  T.check(not voxel.lowered and voxel.decorated,'public export patch clears flattening and protects foliage')
  run.loader.mods.JP_GRASS_PRESERVE.enabled=false
  voxel.grassClearance({1,2,0})
  T.check(voxel.lowered,'real mod.find observes disabled add-on')
 else
  T.eq(addonExport,nil,'renderer '..version..' is outside the targeted jp.31 range')
  voxel.grassClearance({1,2,0})
  T.check(voxel.lowered,'unsupported renderer is left untouched')
 end
 run.release()
end
local archive=os.getenv('JP_GRASS_ZIP')
if archive then
 local launcher=require('src.mods.LauncherMods')
 local entries=launcher.inspectZip(read(archive))
 local paths={};for _,entry in ipairs(entries)do paths[#paths+1]=entry.name end
 T.eq(launcher.locateRoot(paths),'','actual ZIP import gate accepts one root manifest')
 T.eq(#entries,3,'only manifest, entry point and install instructions are bundled')
end
local out=os.getenv('JP_GRASS_RESULT')
if out then local f=assert(io.open(out,'w'));f:write(Json.encode({checks=T.checks,failures=T.failures,messages=T.messages,actualGL=false}));f:close()end
T.finish()
