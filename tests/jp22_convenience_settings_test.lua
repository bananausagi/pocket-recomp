-- Real home/in-game preference rows and portable+disk persistence. No ROM.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP22 convenience settings integration')
local Json=require('src.link.Json')
local Save=require('src.core.SaveData')
local Home=require('src.import.LauncherSettings')
local Options=require('src.ui.OptionsMenu')
local Transfer=require('src.import.SettingsTransfer')
local Strings=require('src.core.Strings')
local Version=require('src.core.GameVersion')
local Rules=require('src.core.JapaneseRules')
local Catalog=require('src.ui.JapaneseSettingsCatalog')
local ids={'jpRulesPreset','jpPartyExp','jpForgetHM','jpReusableTM','jpFieldActions','jpAnalogWalk','jpBattleIntro'}
local defaults={jpPartyExp=false,jpForgetHM=false,jpReusableTM=false,
  jpFieldActions=true,jpAnalogWalk=false,jpBattleIntro='focus'}
local expected={jpRulesPreset='げんさく',jpPartyExp='げんさくどおり',
  jpForgetHM='オフ',jpReusableTM='オフ',jpFieldActions='オン',jpAnalogWalk='オフ',jpBattleIntro='あいてを アップ'}
local function copy(t)
  if type(t)~='table'then return t end
  local out={};for k,v in pairs(t)do out[k]=copy(v)end;return out
end
local function homeRows(model)
  local rows={}
  local function visit(sections)
    for _,section in ipairs(sections or{})do
      for _,row in ipairs(section.rows or{})do
        T.eq(rows[row.id],nil,'home setting ID is unique: '..row.id)
        rows[row.id]=row
      end
      visit(section.children)
    end
  end
  visit(model.sections);return rows
end
local function gameRows(menu)
  local rows,seen={},{ }
  for _,row in ipairs(menu.rows)do
    T.eq(rows[row.id],nil,'game setting ID is unique: '..row.id)
    rows[row.id]=row
  end
  for _,group in ipairs(menu.view)do
    for _,row in ipairs(group.members or{})do seen[row.id]=(seen[row.id]or 0)+1 end
  end
  for _,id in ipairs(ids)do T.eq(seen[id],1,'new game row belongs to one category: '..id)end
  return rows
end
local function setup(opts)
  Version.set('red_jp')
  local data={constants={language='ja'}};Strings.load(data)
  local model=Home.open({options=opts,save=function(o)return Save.saveOptions(o,love.filesystem)end},'red_jp')
  local game={save={options=opts},data=data,stack={states={}}}
  local menu=Options.new(game)
  return model,game,menu,homeRows(model),gameRows(menu)
end
local opts=Save.defaultOptions()
for k,v in pairs(defaults)do T.eq(opts[k],v,'new installation default '..k)end
for k in pairs(defaults)do opts[k]=nil end
local model,game,menu,home,live=setup(opts)
for _,id in ipairs(ids)do
  T.check(home[id]and live[id],'home and game both expose '..id)
  T.eq(home[id].value(),expected[id],'old options show default in home: '..id)
  T.eq(live[id].value(game),expected[id],'old options show same default in game: '..id)
  T.eq(opts[id],nil,'opening rows never writes absent key '..id)
  T.eq(home[id].label,live[id].label,'matching Japanese captions: '..id)
  T.check(Catalog.entry(id)and Catalog.entry(id)[2],'new row has a help description '..id)
  T.eq(Catalog.group(id),id=='jpAnalogWalk'and'controls'or'game','new row is in expected category: '..id)
end

for _,id in ipairs({'jpPartyExp','jpForgetHM','jpReusableTM','jpFieldActions','jpAnalogWalk','jpBattleIntro'})do
  local initial=defaults[id]
  opts[id]=initial
  T.check(home[id].step(1),'home Right activates '..id)
  T.neq(opts[id],initial,'Right changes value '..id)
  T.eq(live[id].value(game),home[id].value(),'game sees home value immediately '..id)
  T.check(live[id].step(game,-1),'game Left activates '..id)
  T.eq(opts[id],initial,'Left reverses home Right '..id)
  T.check(live[id].step(game,1),'game Right activates '..id)
  T.eq(home[id].value(),live[id].value(game),'home sees game value immediately '..id)
  T.check(home[id].step(-1),'home Left activates '..id)
  T.eq(opts[id],initial,'Left reverses game Right '..id)
end

-- Presets must not overwrite carefully chosen graphics/touch/MOD preferences.
opts.colors='redpp_soft';opts.palette='';opts.jpFieldActions=false;opts.jpAnalogWalk=true;opts.jpBattleIntro='original'
opts.jpDialogScale=.5;opts.jpBattleSpacing='wider';opts.jpBattleBlur='off'
opts.pipelines={voxel=3,tiltshift=5};opts.bindings={a={key='z',pad='a'}}
opts.touchControls={enabled=false,scale=1.2,positions={a={x=.8,y=.7}}}
opts.modOptions={DRAMALESS_SHAPE={daytime='night',renderDistanceSetting=64}}
opts.mods={DRAMALESS_SHAPE=false};opts.futurePreference={retain=31}
local before=copy(opts)
T.eq(home.jpRulesPreset.value(),'げんさく','all three false is original')
home.jpRulesPreset.step(1)
T.eq(Rules.preset(opts),'convenient','home Right enables convenient preset')
T.eq(live.jpRulesPreset.value(game),'べんり','game derives preset from live options')
for _,key in ipairs(Rules.keys)do T.eq(opts[key],true,'convenient enables '..key);before[key]=true end
T.same(opts,before,'preset changes exactly three keys, preserves everything else')
live.jpRulesPreset.step(game,-1)
T.eq(Rules.preset(opts),'classic','game Left restores original preset')
for _,key in ipairs(Rules.keys)do before[key]=false end
T.same(opts,before,'return to original preserves graphics, controls and independent new choices')
for mask=0,7 do
  for i,key in ipairs(Rules.keys)do opts[key]=math.floor(mask/2^(i-1))%2==1 end
  local label=mask==0 and'げんさく'or(mask==7 and'べんり'or'こまかく')
  T.eq(home.jpRulesPreset.value(),label,'home preset derives all boolean combination '..mask)
  T.eq(live.jpRulesPreset.value(game),label,'game preset derives all boolean combination '..mask)
end
opts.jpPartyExp=true;opts.jpForgetHM=false;opts.jpReusableTM=false
home.jpRulesPreset.step(-1);T.eq(Rules.preset(opts),'classic','custom Left selects original')
opts.jpPartyExp=true;opts.jpForgetHM=false;opts.jpReusableTM=false
live.jpRulesPreset.step(game,1);T.eq(Rules.preset(opts),'convenient','custom Right selects convenient')
T.eq(opts.jpRulesPreset,nil,'derived preset is never stored as a stale independent setting')
for _,id in ipairs({'jpFieldActions','jpAnalogWalk','jpBattleIntro'})do
  live[id].step(game,1)
  T.eq(Rules.preset(opts),'convenient',id..' is independent of convenience preset')
end

opts.jpLauncherLanguage='en';model.refreshLabels()
local english={jpRulesPreset='Convenience preset',jpPartyExp='Experience sharing',
  jpForgetHM='Forget HM moves',jpReusableTM='Reusable TMs',jpFieldActions='Inspect to use field moves',
  jpAnalogWalk='Analog walking in 3D',jpBattleIntro='Battle opening'}
for _,id in ipairs(ids)do T.eq(home[id].label,english[id],'home language changes caption '..id)end
T.eq(home.jpRulesPreset.value(),'Convenient','derived preset follows home language')
opts.jpLauncherLanguage='ja';model.refreshLabels()

-- All new persisted choices, including explicit false, roundtrip unchanged.
local variants={
  {jpPartyExp=true,jpForgetHM=false,jpReusableTM=true,jpFieldActions=false,jpAnalogWalk=true,jpBattleIntro='original'},
  {jpPartyExp=false,jpForgetHM=true,jpReusableTM=false,jpFieldActions=true,jpAnalogWalk=false,jpBattleIntro='focus'},
}
for n,values in ipairs(variants)do
  for k,v in pairs(values)do opts[k]=v end
  opts.colors='redpp_soft';opts.palette=''
  T.check(model.save(),'actual model SaveData write '..n)
  local disk=Save.loadOptions(love.filesystem)
  for k,v in pairs(values)do T.eq(disk[k],v,'actual preference disk roundtrip '..k..' '..n)end
  T.eq(disk.colors,'redpp_soft','soft color survives disk write '..n)
  T.eq(disk.jpDialogScale,.5,'explicit small UI preference retained '..n)
  T.same(disk.touchControls,opts.touchControls,'custom touch layout preserved '..n)
  T.same(disk.futurePreference,opts.futurePreference,'future unknown preferences preserved '..n)
  local encoded=assert(Transfer.export(disk))
  local parsed=assert(Json.decode(encoded))
  T.eq(parsed.options.jpRulesPreset,nil,'portable data stores only real rule values '..n)
  local current={colors='gbc',musicVol=1,privateFuture={keep=12}}
  local restored=assert(Transfer.import(encoded,current))
  for k,v in pairs(values)do T.eq(restored[k],v,'portable roundtrip '..k..' '..n)end
  T.eq(restored.colors,'redpp_soft','portable soft palette roundtrip '..n)
  T.eq(current.colors,'gbc','import builds candidate without mutating live options '..n)
  T.eq(restored.privateFuture.keep,12,'import retains local private future preference '..n)
end
local function doc(values)return Json.encode({format=Transfer.FORMAT,version=1,options=values})end
for _,id in ipairs({'jpPartyExp','jpForgetHM','jpReusableTM','jpFieldActions','jpAnalogWalk'})do
  for _,invalid in ipairs({0,1,'true','false','on',{true}})do
    local current=copy(opts);local result,err=Transfer.import(doc({[id]=invalid}),current)
    T.check(result==nil and type(err)=='string','invalid imported boolean rejected: '..id..' '..type(invalid))
    T.same(current,opts,'invalid boolean leaves all current settings unchanged '..id)
  end
end
for _,invalid in ipairs({false,true,1,'zoom','classic'})do
  local current=copy(opts);local result,err=Transfer.import(doc({jpBattleIntro=invalid}),current)
  T.check(result==nil and type(err)=='string','invalid battle intro rejects '..tostring(invalid))
  T.same(current,opts,'invalid intro does not change current settings')
end
local result,err=Transfer.import(doc({colors='redpp_softest'}),opts)
T.check(result==nil and type(err)=='string','unknown soft color spelling rejects')
local old=assert(Transfer.import(doc({musicVol=2}),opts))
for k in pairs(defaults)do T.eq(old[k],opts[k],'older exported document retains explicit new preference '..k)end

for _,version in ipairs({'red','blue','yellow','gold','silver','crystal','firered'})do
  local other=homeRows(Home.open({options=Save.defaultOptions()},version))
  for _,id in ipairs(ids)do T.eq(other[id],nil,'no ineffective home option on '..version..': '..id)end
end
Strings.load({constants={language='en'}});Version.set('red')
local other=Options.new({data={constants={language='en'}},save={options=Save.defaultOptions()}})
local otherIds={};for _,row in ipairs(other.rows)do otherIds[row.id]=true end
for _,id in ipairs(ids)do T.eq(otherIds[id],nil,'non-JP in-game original menu has no new row '..id)end
T.finish()
