-- The field's existing blur pipeline is also the battle's only setting.
-- Exercise real home/game rows and disk/portable persistence without ROM data.
package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('JP23 shared field and battle blur settings')
local Save = require('src.core.SaveData')
local Settings = require('src.import.LauncherSettings')
local Options = require('src.ui.OptionsMenu')
local Transfer = require('src.import.SettingsTransfer')
local Strings = require('src.core.Strings')
local Version = require('src.core.GameVersion')
local Json = require('src.link.Json')
local Catalog = require('src.ui.JapaneseSettingsCatalog')
local Pipelines = require('src.render.Pipelines')
local TiltShift = assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/TiltShift.lua'))({})
Version.set('red_jp')
local data = {constants={language='ja'},render_pipelines={
  tiltshift={label='T-SHIFT',levels=TiltShift.LABELS,update=TiltShift.update,
    worldPresent=TiltShift.apply},
}}
Pipelines.install(data)
Strings.load(data)
local function collect(sections,rows)
  rows=rows or {}
  for _,section in ipairs(sections or {}) do
    for _,row in ipairs(section.rows or {}) do rows[#rows+1]=row end
    collect(section.children,rows)
  end
  return rows
end
local function find(rows,id)
  local found,count=nil,0
  for _,row in ipairs(rows) do
    if row.id==id then found=row;count=count+1 end
  end
  return found,count
end
local function copy(value)
  if type(value)~='table' then return value end
  local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out
end
local function doc(options)
  return Json.encode({format=Transfer.FORMAT,version=1,options=options})
end
local opts=Save.defaultOptions()
T.eq(opts.jpBattleBlur,nil,'new installations no longer create a battle-only blur default')
Pipelines.applyOptions(opts)
T.eq(Pipelines.level('tiltshift'),2,'fresh installation enables gentle shared field and battle blur')
local fresh=Settings.open({options=opts},'red_jp')
T.eq(find(collect(fresh.sections),'pipeline:tiltshift').value(),'2','home shows the same default as the renderer')
local oldBucket={voxel=3,anotherRenderer=4}
local old=Save.mergeOptions({pipelines=oldBucket})
Pipelines.applyOptions(old)
T.eq(Pipelines.level('tiltshift'),2,'an absent legacy blur choice receives the new default')
T.eq(old.pipelines.voxel,3,'default fill keeps the selected 3D view')
T.eq(old.pipelines.anotherRenderer,4,'default fill keeps an unknown renderer')
T.eq(oldBucket.tiltshift,nil,'default fill does not mutate the decoded source bucket')
for level=0,5 do
  local chosen=Save.mergeOptions({pipelines={tiltshift=level}})
  Pipelines.applyOptions(chosen)
  T.eq(Pipelines.level('tiltshift'),level,'existing explicit blur level survives the default update')
end
opts.jpDialogScale=.75
opts.jpPartyExp=true;opts.jpForgetHM=true;opts.jpReusableTM=false
opts.jpFieldActions=false;opts.jpAnalogWalk=true;opts.jpBattleIntro='original'
opts.colors='redpp_soft'
opts.pipelines={tiltshift=0,voxel=3,unknownRenderer=2}
opts.jpBattleBlur='strong' -- a real old preference that must stay inert
local before=copy(opts)
Pipelines.applyOptions(opts)
local model=Settings.open({options=opts,save=function(o)return Save.saveOptions(o,love.filesystem)end},'red_jp')
local rows=collect(model.sections)
local row,count=find(rows,'pipeline:tiltshift')
T.eq(count,1,'one common blur row is discoverable from home')
T.check(row~=nil,'home can configure blur before starting a game')
T.eq(row.label,'とおくの ぼかし','home uses the existing field caption')
T.check(row.description:find('フィールド',1,true) and row.description:find('せんとう',1,true),
  'help explicitly says field and battle share the choice')
T.eq(Catalog.group(row.id),'world','common blur is grouped with the 3D view')
T.eq(find(rows,'jpBattleBlur'),nil,'no duplicate battle-only home row remains')
T.eq(Catalog.entry('jpBattleBlur'),nil,'no obsolete battle-only help remains')
T.same(opts,before,'opening home settings neither rewrites nor migrates any saved choice')
T.eq(row.value(),'なし','explicit field OFF wins over old battle STRONG')
local game={save={options=opts},data=data}
local menu=Options.new(game)
local inGame,nGame=find(menu.rows,'pipeline:tiltshift')
T.eq(nGame,1,'game uses the original pipeline control exactly once')
T.eq(find(menu.rows,'jpBattleBlur'),nil,'game has no second battle-only control')
local present=0
for _,group in ipairs(menu.view)do for _,member in ipairs(group.members or {})do
  if member.id=='pipeline:tiltshift'then
    present=present+1;T.eq(group.id,'group.world','game exposes it in 3D view')
  end
end end
T.eq(present,1,'common in-game blur appears in one category')
for step=1,12 do
  local selected=step%6
  if step%2==0 then
    T.check(inGame.step(game,1),'controller Right changes common blur in game')
  else
    T.check(row.step(1),'controller Right changes common blur from home')
  end
  T.eq(opts.pipelines.tiltshift,selected,'single saved canonical level tracks both routes')
  T.eq(Pipelines.level('tiltshift'),selected,'live renderer level changes without reopening game')
  T.eq(Strings(inGame.value(game)),row.value(),'both visible rows show the same live selection')
  local expected=copy(before);expected.pipelines.tiltshift=selected
  T.same(opts,expected,'changing blur preserves all unrelated settings and legacy data')
  T.check(model.save(),'common level saves through actual home model')
  local disk=Save.loadOptions(love.filesystem)
  T.eq(disk.pipelines.tiltshift,selected,'every 0..5 level survives disk save/load')
  T.eq(disk.jpBattleBlur,'strong','legacy choice remains stored without controlling blur')
  for _,id in ipairs({'jpPartyExp','jpForgetHM','jpReusableTM','jpFieldActions','jpAnalogWalk','jpBattleIntro','colors','jpDialogScale'})do
    T.eq(disk[id],before[id],'existing jp22 preference survives saving blur: '..id)
  end
  local exported=assert(Transfer.export(disk))
  local restored=assert(Transfer.import(exported,{musicVol=2}))
  T.eq(restored.pipelines.tiltshift,selected,'every 0..5 level roundtrips portable JSON')
  T.eq(restored.jpBattleBlur,'strong','older JSON key remains codec compatible')
end
T.check(row.step(-1),'home controller Left wraps')
T.eq(Pipelines.level('tiltshift'),5,'Left from OFF selects level 5')
T.check(inGame.step(game,1),'game controller Right wraps')
T.eq(opts.pipelines.tiltshift,0,'Right from 5 returns to explicit OFF')
for _,legacy in ipairs({'off','normal','strong'})do
  for level=0,5 do
    local restored=assert(Transfer.import(doc({jpBattleBlur=legacy}),{pipelines={tiltshift=level}}))
    T.eq(restored.jpBattleBlur,legacy,'older battle-only JSON is still accepted')
    T.eq(restored.pipelines.tiltshift,level,'older battle-only JSON never overwrites field level')
    Pipelines.applyOptions(restored)
    T.eq(Pipelines.level('tiltshift'),level,'loaded field value controls live pipeline regardless of legacy choice')
  end
end
local missing={jpBattleBlur='strong'}
local missingHome=Settings.open({options=missing},'red_jp')
local missingRow=assert(find(collect(missingHome.sections),'pipeline:tiltshift'))
T.eq(missingRow.value(),'2','absent field setting shows the shared gentle default')
T.eq(missing.pipelines,nil,'viewing missing field setting does not materialize a new bucket')
local restored=assert(Transfer.import(doc({jpBattleBlur='strong'}),{}))
T.eq(restored.pipelines,nil,'legacy-only import does not invent a stronger field default')
Pipelines.install({constants={language='ja'}})
local inactiveOpts={jpBattleBlur='strong',pipelines={voxel=3,otherPipeline=2}}
local inactive=assert(find(collect(Settings.open({options=inactiveOpts},'red_jp').sections),'pipeline:tiltshift'))
inactive.step(1)
T.eq(inactiveOpts.pipelines.tiltshift,3,'home advances the default even before MOD pipeline registration')
T.eq(inactiveOpts.pipelines.voxel,3,'inactive home does not zero stored camera mode')
T.eq(inactiveOpts.pipelines.otherPipeline,2,'inactive home preserves unregistered pipeline preferences')
model.opts.jpLauncherLanguage='en';model.refreshLabels()
T.eq(row.label,'Distance blur','English launcher caption describes the common effect')
T.check(row.description:find('field and battles',1,true),'English help also explains the shared effect')
for _,version in ipairs({'red','blue','yellow','gold','silver','crystal','firered'})do
  local others=collect(Settings.open({options={}},version).sections)
  T.eq(find(others,'pipeline:tiltshift'),nil,'non-JP home does not acquire a bundled-renderer setting '..version)
  T.eq(find(others,'jpBattleBlur'),nil,'non-JP home remains without removed JP setting '..version)
end
Strings.load({constants={language='en'}});Version.set('red')
local nonJP=Options.new({save={options=Save.defaultOptions()},data={constants={language='en'}}})
T.eq(find(nonJP.rows,'jpBattleBlur'),nil,'non-JP in-game menu keeps original layout controls')
T.finish()
