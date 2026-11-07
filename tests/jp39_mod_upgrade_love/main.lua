-- Real ZIP/file/settings transactions against both exact delivered APKs.
function love.load()
 local ok,err=xpcall(function()
  local root=assert(os.getenv('JP_UPGRADE_ROOT'));package.path=root..'/?.lua;'..package.path
  local fs=love.filesystem;local Json=require('src.link.Json');local Save=require('src.core.SaveData')
  local Mods=require('src.mods.LauncherMods');local Pack=require('src.mods.JapaneseStarterPack')
  local NEW,OLD='DRAMALESS_SHAPE','VOXEL_ASCENDANT';local label=os.getenv('JP_UPGRADE_LABEL')
  local trial=label=='jp37';local n=0
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
  if label=='jp38' then
   local t=assert(io.open(os.getenv('JP_UPGRADE_TRIAL'),'rb'));local b=t:read('*a');t:close()
   assert(fs.mount(fs.newFileData(b,'trial.love'),'trial',true))
  end
  local prior=assert(Json.decode(fs.read('prior/assets/jp-mods/catalog.json')))
  local current=assert(Json.decode(fs.read('assets/jp-mods/catalog.json')));local entries={}
  for _,e in ipairs(current)do entries[e.id]=e end
  check(#current==7 and not entries[OLD] and not fs.getInfo('assets/jp-mods/VOXEL_ASCENDANT.zip'),'trial absent from delivered pack')
  for _,e in ipairs(prior)do if e.id~=OLD and e.id~=NEW then check(fs.read(e.archive)==fs.read('prior/'..e.archive),e.id..' unchanged')end end
  local fingerprint='assets/jp-mods/upgrades-'..label..'.json'
  check(fs.read(fingerprint)==fs.read('prior/assets/jp-mods/managed-renderers.json'),'exact delivered fingerprint '..label)
  fs.setIdentity('jp39-expected-'..label);assert(Mods.installZip(entries[NEW].archive,{expectId=NEW}));local expected=snapshot('mods/'..NEW)
  local function setup(mode)
   fs.setIdentity('jp39-'..label..'-'..mode);Save.invalidateOptions()
   local o=Save.defaultOptions();o.jpStarterPackV1={};o.jpRendererRollbackV1=true;o.jpDisplayDefaultsV3=true
   o.mods={[NEW]=true,[OLD]=false};o.modsByVersion={red_jp={[NEW]=false,[OLD]=false},blue={[NEW]=true,UNKNOWN=false}}
   o.modOptions={[NEW]={daytime='night',shadowQuality='off',battleBack=false,voxel_2d_battles=false}}
   o.pipelines={voxel=0,tiltshift=2};o.jpAnalogWalk=true;o.jpFxGrass=false;o.jpFxMoveLight=false;o.jpAtmosphere='off'
   o.battleLayout='wide';o.battleBg='world';o.modProfilesSeeded=true;o.activeProfile='mine'
   o.modProfiles={{name='mine',enabled=copy(o.mods),enabledByVersion=copy(o.modsByVersion),options=copy(o.modOptions),slots={red_jp='slot1'}}}
   for _,e in ipairs(prior)do assert(Mods.installZip('prior/'..e.archive,{expectId=e.id}));o.jpStarterPackV1[e.id]=e.version end
   if trial then
    local Switch=assert(loadstring(fs.read('prior/src/mods/JapaneseAscendantSwitch.lua')))()
    assert(Switch.apply(o,{[OLD]='2.0.2+jp.1'},Switch.snapshot(o)))
    o.battleLayout='og';o.battleBg='white';o.modOptions[OLD].weather='clear';o.modOptions[OLD].clouds='off'
    if mode=='manual' then assert(fs.write('mods/'..OLD..'/owner-notes.txt','custom work'))end
    if mode=='missing' then assert(Mods.uninstall(NEW))end
   end
   if mode:find('leftover',1,true) then
    assert(Mods.installZip('trial/assets/jp-mods/VOXEL_ASCENDANT.zip',{expectId=OLD}))
    fs.write('mods/'..OLD..'/owner-notes.txt','archived edited trial')
    o.jpAscendantRetired38=true
    if mode=='renamed-leftover' then
     local function clone(path,to)
      fs.createDirectory(to)
      for _,name in ipairs(fs.getDirectoryItems(path))do
       local a,b=path..'/'..name,to..'/'..name
       if fs.getInfo(a).type=='directory'then clone(a,b)else fs.write(b,fs.read(a))end
      end
     end
     clone('mods/'..OLD,'mods/old-trial-copy')
    end
   end
   fs.createDirectory('saves');fs.write('saves/owner-data.txt','untouched fixture')
   assert(Save.saveOptions(o));return Save.loadOptions(),snapshot('mods')
  end
  local cases=trial and {'pristine','save-failure','install-failure','uninstall-failure','manual','missing'} or (label=='jp38' and {'pristine','save-failure','leftover','renamed-leftover','leftover-save-failure','leftover-uninstall-failure'} or {'pristine','save-failure'})
  for _,mode in ipairs(cases)do
   local before,files=setup(mode);local witness={}
   for _,name in ipairs({'options.lua','options.lua.bak','options.lua.tmp'})do witness[name]=fs.read(name) or false end
   if mode:find('failure',1,true)then
    local deps
    if mode:find('save-failure',1,true) then deps={SaveData=setmetatable({saveOptions=function(o)assert(Save.saveOptions(o));return nil,'fixture save failure'end},{__index=Save})}
    elseif mode=='install-failure' then deps={LauncherMods=setmetatable({installZip=function()return nil,'fixture install failure'end},{__index=Mods})}
    else deps={LauncherMods=setmetatable({uninstall=function(id)
     assert(fs.remove('mods/'..id..'/main.lua'));return nil,'fixture partial uninstall failure'
    end},{__index=Mods})}end
    local result,detail=Pack.install(deps)
    check(result==nil and detail:find('fixture',1,true),mode..' reported')
    check(same(snapshot('mods'),files),mode..' restores all installed files')
    for name,data in pairs(witness)do check((fs.read(name) or false)==data,mode..' restores '..name)end
    check(same(Save.loadOptions(),before),mode..' restores cached preferences')
   end
   local result,detail=Pack.install();check(result==true,mode..' upgrade succeeds '..tostring(detail))
   local after=Save.loadOptions()
   check(after.jpAscendantRetired38 and after.mods[OLD]==false,mode..' one-time retirement')
   check(after.modsByVersion.red_jp[NEW]==trial and after.modsByVersion.red_jp[OLD]==false,mode..' correct renderer; direct upgrade keeps explicit OFF')
   check(same(after.modsByVersion.blue,before.modsByVersion.blue) or after.modsByVersion.blue[OLD]==false,mode..' other game preferences retained')
   check(after.battleLayout=='wide' and after.battleBg=='world',mode..' restores prior battle layout')
   check(after.pipelines.voxel==0 and after.pipelines.tiltshift==2,mode..' retains 3D OFF and blur')
   check(not after.jpFxGrass and not after.jpFxMoveLight and after.jpAtmosphere=='off' and after.jpAnalogWalk,mode..' retains independent FX and controls')
   check(same(after.modOptions[NEW],before.modOptions[NEW]) or trial and after.modOptions[NEW].clouds==false and after.modOptions[NEW].weather=='clear',mode..' preserves Dramaless and field OFF choices')
   check(after.modProfiles[1].enabledByVersion.red_jp[NEW]==trial and after.modProfiles[1].enabledByVersion.red_jp[OLD]==false and after.modProfiles[1].slots.red_jp=='slot1' and after.activeProfile=='mine',mode..' profile migrated without changing slots')
   check(same(snapshot('mods/'..NEW),expected),mode..' exact packaged Dramaless installed')
   if trial then
    if mode=='manual' then check(not fs.getInfo('mods/'..OLD) and fs.read('jp-mod-backups/jp39-retired-1/'..OLD..'/owner-notes.txt')=='custom work',mode..' edited trial archived and removed from menu')
    else
     check(not fs.getInfo('mods/'..OLD),mode..' managed trial removed')
     local saved=snapshot('jp-mod-backups/jp37/'..OLD)
     for path,digest in pairs(files)do if path:sub(1,#OLD+1)==OLD..'/' then check(saved[path:sub(#OLD+2)]==digest,mode..' recoverable '..path)end end
    end
   end
   if mode:find('leftover',1,true) then
    check(not fs.getInfo('mods/old-trial-copy'),'renamed same-ID trial is removed too')
    check(fs.read('jp-mod-backups/jp39-retired-1/'..OLD..'/owner-notes.txt')=='archived edited trial','jp38 edited remainder backed up before removing')
   end
   check(after.jpAscendantRemoved39 and not fs.getInfo('mods/'..OLD),mode..' retired trial has no installed entry')
   check(fs.read('saves/owner-data.txt')=='untouched fixture',mode..' user save untouched')
   check(Pack.install()==false,mode..' repeated launch does no work')
  end
  print('RESULT '..n..' checks passed')
 end,debug.traceback)
 if not ok then print(err)end;love.event.quit(ok and 0 or 1)
end
