-- jp.58: the delivered jp.57 pack -> jp.58 renderer upgrade, real ZIP/file/settings transactions.
function love.load()
 local ok,err=xpcall(function()
  local root=assert(os.getenv('JP_UPGRADE_ROOT'));package.path=root..'/?.lua;'..package.path
  local fs=love.filesystem;local Json=require('src.link.Json');local Save=require('src.core.SaveData')
  local Mods=require('src.mods.LauncherMods');local Pack=require('src.mods.JapaneseStarterPack')
  local NEW='DRAMALESS_SHAPE';local n=0
  -- jp.59: the same transaction from any delivered pack (defaults: jp.57 -> jp.58).
  local label=os.getenv('JP_UPGRADE_LABEL') or 'jp57'
  local fromV,toV=os.getenv('JP_UPGRADE_FROM') or '2.0.22+jp.18',os.getenv('JP_UPGRADE_TO') or '2.0.23+jp.18'
  local function check(v,msg)assert(v,msg);n=n+1;print('PASS '..msg)end
  local function copy(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=copy(x)end;return t end
  local function same(a,b)
   if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
   for k,v in pairs(a)do if not same(v,b[k])then return false end end
   for k in pairs(b)do if a[k]==nil then return false end end;return true
  end
  local function snapshot(path)
   local t={};local function walk(at)
    for _,name in ipairs(fs.getDirectoryItems(at))do local p=at..'/'..name
     if fs.getInfo(p).type=='directory'then walk(p)
     else t[p:sub(#path+2)]=love.data.encode('string','hex',love.data.hash('sha256',assert(fs.read(p))))end
    end
   end
   if fs.getInfo(path)then walk(path)end;return t
  end
  local f=assert(io.open(assert(os.getenv('JP_UPGRADE_BASELINE')),'rb'));local bytes=f:read('*a');f:close()
  assert(fs.mount(fs.newFileData(bytes,'prior.love'),'prior',true));bytes=nil
  local prior=assert(Json.decode(fs.read('prior/assets/jp-mods/catalog.json')))
  local current=assert(Json.decode(fs.read('assets/jp-mods/catalog.json')));local entries,old={},{}
  for _,e in ipairs(current)do entries[e.id]=e end
  for _,e in ipairs(prior)do old[e.id]=e end
  check(#current==7 and entries[NEW].version==toV and old[NEW].version==fromV,'renderer version advances')
  for _,e in ipairs(prior)do if e.id~=NEW then check(fs.read(e.archive)==fs.read('prior/'..e.archive),e.id..' unchanged')end end
  check(fs.read('assets/jp-mods/upgrades-'..label..'.json')==fs.read('prior/assets/jp-mods/managed-renderers.json'),'exact delivered '..label..' fingerprint')
  fs.setIdentity('jp58-expected-'..label);assert(Mods.installZip(entries[NEW].archive,{expectId=NEW}));local expected=snapshot('mods/'..NEW)
  check(expected['lib/VoxelBattleWarmup.lua']~=nil,'packaged renderer carries the battle warm-up')
  local function setup(mode)
   fs.setIdentity('jp58-'..label..'-'..mode);Save.invalidateOptions()
   local o=Save.defaultOptions();o.jpStarterPackV1={};o.jpRendererRollbackV1=true;o.jpDisplayDefaultsV3=true
   o.jpAscendantRetired38=true;o.jpAscendantRemoved39=true
   o.mods={[NEW]=true};o.modsByVersion={red_jp={[NEW]=true}}
   o.modOptions={[NEW]={daytime='night',shadowQuality='off',battleBack=false,voxel_2d_battles=true,sceneryFade=false}}
   o.pipelines={voxel=2,tiltshift=1};o.jpAutoSave=false
   for _,e in ipairs(prior)do assert(Mods.installZip('prior/'..e.archive,{expectId=e.id}));o.jpStarterPackV1[e.id]=e.version end
   if mode=='edited' then assert(fs.write('mods/'..NEW..'/main.lua',fs.read('mods/'..NEW..'/main.lua')..'\n-- owner edit\n'))end
   fs.createDirectory('saves');fs.write('saves/owner-data.txt','untouched fixture')
   assert(Save.saveOptions(o))
   return Save.loadOptions(),snapshot('mods'),snapshot('saves')
  end
  for _,mode in ipairs({'pristine','edited'})do
   local before,files,saves=setup(mode)
   local result,detail=Pack.install()
   local after=Save.loadOptions()
   if mode=='pristine' then
    check(result==true,mode..' upgrade succeeds '..tostring(detail))
    check(same(snapshot('mods/'..NEW),expected),mode..' exact packaged jp.58 renderer installed')
    check(after.jpStarterPackV1[NEW]==toV,mode..' managed version recorded')
   else
    check(result~=nil,mode..' no error '..tostring(detail))
    check(same(snapshot('mods/'..NEW),(function()local t={};for k,v in pairs(files)do if k:sub(1,#NEW+1)==NEW..'/' then t[k:sub(#NEW+2)]=v end end;return t end)()),mode..' owner-edited renderer left as is')
   end
   for id in pairs(old)do if id~=NEW then
    local now,was=snapshot('mods/'..id),{}
    for k,v in pairs(files)do if k:sub(1,#id+1)==id..'/' then was[k:sub(#id+2)]=v end end
    check(same(now,was),mode..' '..id..' untouched')
   end end
   check(same(after.modOptions[NEW],before.modOptions[NEW]),mode..' renderer options kept')
   check(after.mods[NEW]==true and after.modsByVersion.red_jp[NEW]==true,mode..' renderer stays enabled')
   check(after.pipelines.voxel==2 and after.pipelines.tiltshift==1 and after.jpAutoSave==false,mode..' display and save preferences kept')
   check(same(snapshot('saves'),saves),mode..' saves byte-identical')
   check(Pack.install()==false,mode..' repeated launch does no work')
  end
  print('RESULT '..n..' checks passed')
 end,debug.traceback)
 if not ok then print(err)end;love.event.quit(ok and 0 or 1)
end
