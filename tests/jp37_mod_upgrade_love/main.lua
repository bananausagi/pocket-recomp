-- Exact delivered jp.36 -> jp.37 native ZIP installer and saved selection.
function love.load()
 local ok,err=xpcall(function()
  local root=assert(os.getenv('JP_UPGRADE_ROOT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local fs=love.filesystem
  local Json=require('src.link.Json');local Save=require('src.core.SaveData')
  local Mods=require('src.mods.LauncherMods');local Pack=require('src.mods.JapaneseStarterPack')
  local Switch=require('src.mods.JapaneseAscendantSwitch')
  local OLD,NEW='DRAMALESS_SHAPE','VOXEL_ASCENDANT'
  local n=0
  local function check(v,msg)assert(v,msg);n=n+1;print('PASS '..msg)end
  local function copy(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=copy(x)end;return t end
  local function same(a,b)
   if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
   for k,v in pairs(a)do if not same(v,b[k])then return false end end
   for k in pairs(b)do if a[k]==nil then return false end end;return true
  end
  local function snapshot(path)
   local t={}
   local function walk(at)
    for _,name in ipairs(fs.getDirectoryItems(at))do
     local p=at..'/'..name
     if fs.getInfo(p).type=='directory'then walk(p)
     else t[p:sub(#path+2)]=love.data.encode('string','hex',love.data.hash('sha256',assert(fs.read(p))))end
    end
   end
   if fs.getInfo(path)then walk(path)end;return t
  end
  local f=assert(io.open(assert(os.getenv('JP_UPGRADE_BASELINE')),'rb'))
  local bytes=f:read('*a');f:close()
  assert(fs.mount(fs.newFileData(bytes,'prior.love'),'prior',true))
  local prior=assert(Json.decode(fs.read('prior/assets/jp-mods/catalog.json')))
  local current=assert(Json.decode(fs.read('assets/jp-mods/catalog.json')));local entries={}
  for _,e in ipairs(current)do entries[e.id]=e end
  check(#current==8 and entries[NEW].version=='2.0.2+jp.1','new renderer plus seven retained archives')
  for _,e in ipairs(prior)do check(fs.read(e.archive)==fs.read('prior/'..e.archive),e.id..' unchanged')end
  check(fs.read('assets/jp-mods/upgrades-jp36.json')==fs.read('prior/assets/jp-mods/managed-renderers.json'),'exact prior fingerprint')
  fs.setIdentity('jp37-expected');assert(Mods.installZip(entries[NEW].archive,{expectId=NEW}))
  local expected=snapshot('mods/'..NEW)
  local function setup(mode)
   fs.setIdentity('jp37-switch-'..mode);Save.invalidateOptions()
   local o=Save.defaultOptions()
   o.jpStarterPackV1={};o.jpRendererMigrationV1='managed';o.jpRendererRollbackV1=true;o.jpDisplayDefaultsV3=true
   o.mods={[OLD]=true,[NEW]=false};o.modsByVersion={red_jp={[OLD]=true,[NEW]=false},blue={[OLD]=true,UNKNOWN=false}}
   o.modOptions={[OLD]={daytime='night',shadowQuality='off',water='sky',battleBack=false,voxel_2d_battles=false}}
   o.pipelines={voxel=0,tiltshift=2};o.jpAnalogWalk=true;o.jpFxGrass=false;o.jpFxMoveLight=false;o.jpAtmosphere='off'
   o.modProfilesSeeded=true;o.activeProfile='mine'
   o.modProfiles={{name='mine',enabled=copy(o.mods),enabledByVersion=copy(o.modsByVersion),options=copy(o.modOptions),slots={red_jp='slot1'}}}
   for _,e in ipairs(prior)do assert(Mods.installZip('prior/'..e.archive,{expectId=e.id}));o.jpStarterPackV1[e.id]=e.version end
   o.jpStarterPackV1[NEW]='removed'
   assert(fs.createDirectory('saves'));assert(fs.write('saves/owner-data.txt','untouched fixture'))
   assert(Save.saveOptions(o));return Save.loadOptions(),snapshot('mods')
  end
  for _,mode in ipairs({'pristine','save-failure','install-failure'})do
   local before,files=setup(mode);local witness={}
   for _,name in ipairs({'options.lua','options.lua.bak','options.lua.tmp'})do witness[name]=fs.read(name) or false end
   if mode~='pristine'then
    local deps
    if mode=='save-failure'then deps={SaveData=setmetatable({saveOptions=function(o)
      assert(Save.saveOptions(o));return nil,'fixture failure after persistence'
     end},{__index=Save})}
    else deps={LauncherMods=setmetatable({installZip=function(path,config)
      if config.expectId==NEW then return nil,'fixture install failure' end
      return Mods.installZip(path,config)
     end},{__index=Mods})}end
    local result,detail=Pack.install(deps)
    check(result==nil and detail:find('fixture',1,true),mode..' reported')
    check(same(snapshot('mods'),files),mode..' rolls back all MOD files')
    for name,data in pairs(witness)do check((fs.read(name) or false)==data,mode..' restores '..name)end
    check(same(Save.loadOptions(),before),mode..' restores cached settings')
   end
   check(Pack.install()==true,mode..' switches successfully')
   local after=Save.loadOptions()
   check(after.jpVoxelAscendant37==true,mode..' records one-time switch')
   check(after.modsByVersion.red_jp[NEW] and after.modsByVersion.red_jp[OLD]==false,mode..' selects VASC only for Japanese game')
   check(same(after.modsByVersion.blue,before.modsByVersion.blue),mode..' other game selection unchanged')
   check(same(after.jpRendererBefore37.modOptions,before.modOptions),mode..' saves original renderer preferences')
   check(after.pipelines.voxel==0 and after.pipelines.tiltshift==2,mode..' preserves camera OFF and blur level')
   check(after.jpFxGrass==false and after.jpFxMoveLight==false and after.jpAtmosphere=='off' and after.jpAnalogWalk,mode..' preserves FX OFF and analog choice')
   check(after.modOptions[NEW].battles==false and after.modOptions[NEW].shadows==false,mode..' preserves disabled battles and shadows')
   check(after.modOptions[NEW].daytime=='night',mode..' carries compatible time setting')
   local p=after.modProfiles[1]
   check(p.enabledByVersion.red_jp[NEW] and p.enabledByVersion.red_jp[OLD]==false and p.slots.red_jp=='slot1',mode..' profile switches without changing slots')
   check(p.options[NEW].battles==false and p.options[NEW].battleCameraDistance==1,mode..' profile keeps mapped preferences')
   check(same(snapshot('mods/'..NEW),expected),mode..' installed bytes match candidate archive')
   local installed=snapshot('mods');for path,digest in pairs(files)do check(installed[path]==digest,mode..' retains '..path)end
   check(fs.read('saves/owner-data.txt')=='untouched fixture',mode..' retains saved user data')
   check(Pack.install()==false,mode..' second launch is idempotent')
   after.modsByVersion.red_jp[NEW]=false;after.modsByVersion.red_jp[OLD]=true;assert(Save.saveOptions(after))
   check(Pack.install()==false and Save.loadOptions().modsByVersion.red_jp[NEW]==false,mode..' later manual switch is respected')
  end
  local opts={modsByVersion={red_jp={[OLD]=true}}};local original=copy(opts)
  check(Switch.apply(opts,{[NEW]='user-custom'})==false and same(opts,original),'manual different renderer is not selected or overwritten')
  print('RESULT '..n..' checks passed')
 end,debug.traceback)
 if not ok then print(err)end
 love.event.quit(ok and 0 or 1)
end
