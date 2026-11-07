package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP23 scenery atmosphere settings')
local Save=require('src.core.SaveData')
local Home=require('src.import.LauncherSettings')
local Options=require('src.ui.OptionsMenu')
local Transfer=require('src.import.SettingsTransfer')
local Strings=require('src.core.Strings')
local Version=require('src.core.GameVersion')
local Rules=require('src.core.JapaneseRules')
local Catalog=require('src.ui.JapaneseSettingsCatalog')
local Json=require('src.link.Json')
local function find(rows,id)
  local row,count=nil,0
  for _,candidate in ipairs(rows or{})do
    if candidate.id==id then row=candidate;count=count+1 end
  end
  return row,count
end
local function collect(sections,rows)
  rows=rows or{}
  for _,section in ipairs(sections or{})do
    for _,row in ipairs(section.rows or{})do rows[#rows+1]=row end
    collect(section.children,rows)
  end
  return rows
end
local function copy(v)
  if type(v)~='table'then return v end
  local t={};for k,x in pairs(v)do t[k]=copy(x)end;return t
end
local function document(options)return Json.encode({format=Transfer.FORMAT,version=1,options=options})end
local defaults=Save.defaultOptions()
T.eq(defaults.jpAtmosphere,'soft','new installation defaults to subtle scenery atmosphere')
local opts=Save.defaultOptions();opts.jpAtmosphere=nil
opts.pipelines={voxel=3,tiltshift=0}
opts.colors='redpp_soft';opts.palette='MY_CUSTOM_PALETTE'
opts.modOptions={DRAMALESS_SHAPE={daytime='night',shadowQuality=0,renderScale=2}}
opts.jpBattleBlur='strong';opts.jpPartyExp=true;opts.jpForgetHM=true;opts.jpReusableTM=false
opts.jpFieldActions=false;opts.jpAnalogWalk=true;opts.jpBattleIntro='original'
local unchanged=copy(opts)
Version.set('red_jp');local data={constants={language='ja'}};Strings.load(data)
local home=Home.open({options=opts,save=function(o)return Save.saveOptions(o,love.filesystem)end},'red_jp')
local game={data=data,save={options=opts}}
local menu=Options.new(game)
local homeRow,nhome=find(collect(home.sections),'jpAtmosphere')
local gameRow,ngame=find(menu.rows,'jpAtmosphere')
T.eq(nhome,1,'one home atmosphere choice')
T.eq(ngame,1,'one in-game atmosphere choice')
T.eq(homeRow.label,'けしきの ふんいき','home caption is readable')
T.eq(gameRow.label,homeRow.label,'game uses identical shared descriptor caption')
T.eq(homeRow.value(),'やわらかい','absent old setting displays the new default')
T.eq(gameRow.value(game),homeRow.value(),'game displays same absent-key default')
T.same(opts,unchanged,'viewing old options does not write atmosphere or unrelated settings')
T.eq(Catalog.group('jpAtmosphere'),'world','atmosphere belongs to 3D view')
T.check(Catalog.entry('jpAtmosphere')[2]:find('かすみ',1,true),'help describes distant haze')
local categories=0
for _,group in ipairs(menu.view)do for _,row in ipairs(group.members or{})do
  if row.id=='jpAtmosphere'then categories=categories+1;T.eq(group.id,'group.world','one 3D-view category')end
end end
T.eq(categories,1,'atmosphere does not duplicate another category')
for n,value in ipairs({'off','soft','off','soft'})do
  T.check(n%2==1 and homeRow.step(1)or gameRow.step(game,-1),'home and game can both switch atmosphere')
  local expected=copy(unchanged);expected.jpAtmosphere=value
  T.same(opts,expected,'changing atmosphere only modifies its own preference')
  T.eq(homeRow.value(),gameRow.value(game),'both menus immediately agree')
  T.eq(opts.jpAtmosphere,value,'explicit selected mode persists')
  T.check(home.save(),'actual home model persists atmosphere')
  local loaded=Save.loadOptions(love.filesystem)
  T.eq(loaded.jpAtmosphere,value,'disk roundtrip retains mode')
  for _,key in ipairs({'colors','palette','pipelines','modOptions','jpBattleBlur','jpPartyExp',
      'jpForgetHM','jpReusableTM','jpFieldActions','jpAnalogWalk','jpBattleIntro'})do
    T.same(loaded[key],unchanged[key],'disk save preserves independently selected '..key)
  end
  local exported=assert(Transfer.export(loaded))
  local restored=assert(Transfer.import(exported,{futureLocal={keep=true}}))
  T.eq(restored.jpAtmosphere,value,'portable JSON roundtrip retains atmosphere')
  T.eq(restored.pipelines.tiltshift,0,'explicit blur OFF stays independent in JSON')
  T.eq(restored.colors,'redpp_soft','color mode stays independent in JSON')
  T.eq(restored.modOptions.DRAMALESS_SHAPE.daytime,'night','selected time of day stays independent')
  T.eq(restored.modOptions.DRAMALESS_SHAPE.shadowQuality,0,'shadow OFF stays independent')
  T.eq(restored.futureLocal.keep,true,'local future preference retained')
  local before=copy(opts)
  Rules.applyPreset(opts,'convenient')
  T.eq(opts.jpAtmosphere,value,'gameplay convenience preset never changes scenery')
  for _,key in ipairs(Rules.keys)do opts[key]=before[key]end
end
for _,value in ipairs({false,true,0,1,'strong','SOFT',{}})do
  local before=copy(opts)
  local result,err=Transfer.import(document({jpAtmosphere=value}),opts)
  T.check(result==nil and type(err)=='string','invalid atmosphere JSON choice rejects '..tostring(value))
  T.same(opts,before,'invalid atmosphere input leaves options unchanged')
end
local old=assert(Transfer.import(document({musicVol=2}),{jpAtmosphere='off'}))
T.eq(old.jpAtmosphere,'off','older exported settings retain explicit atmosphere OFF')
opts.jpLauncherLanguage='en';home.refreshLabels()
T.eq(homeRow.label,'Scenery atmosphere','English caption supported')
T.eq(homeRow.value(),'Soft','English value supported')
for _,version in ipairs({'red','blue','yellow','gold','silver','crystal','firered'})do
  T.eq(find(collect(Home.open({options=Save.defaultOptions()},version).sections),'jpAtmosphere'),nil,
    'non-JP home remains unchanged '..version)
end
Strings.load({constants={language='en'}});Version.set('red')
T.eq(find(Options.new({data={constants={language='en'}},save={options=Save.defaultOptions()}}).rows,'jpAtmosphere'),nil,
  'non-JP game remains unchanged')
T.finish()
