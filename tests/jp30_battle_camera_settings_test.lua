-- Exercise the shared live UI models, persistence and portable JSON codec.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp30 battle camera settings')
local Save=require('src.core.SaveData')
local Transfer=require('src.import.SettingsTransfer')
local Json=require('src.link.Json')
local Home=require('src.import.LauncherSettings')
local Options=require('src.ui.OptionsMenu')
local Catalog=require('src.ui.JapaneseSettingsCatalog')
local Rules=require('src.core.JapaneseRules')
local Version=require('src.core.GameVersion')
local Strings=require('src.core.Strings')
local id='jpBattleCameraMotion'
local function document(options)return Json.encode({format=Transfer.FORMAT,version=1,options=options})end
local function flatten(sections,out)
  out=out or{}
  for _,s in ipairs(sections or{})do
    for _,r in ipairs(s.rows or{})do out[#out+1]=r end
    flatten(s.children,out)
  end
  return out
end
local function find(rows,key)
  local found,n=nil,0
  for _,r in ipairs(rows)do if r.id==key then found=r;n=n+1 end end
  return found,n
end
T.eq(Save.defaultOptions()[id],true,'new installation enables battle camera motion')
T.eq(Save.mergeOptions({})[id],true,'old save with absent key defaults ON')
for _,invalid in ipairs({'false',0,1,{}})do
  T.eq(Save.mergeOptions({[id]=invalid})[id],true,'malformed saved value safely uses boolean default')
end
for _,value in ipairs({false,true})do
  local original={[id]=value,jpBattleIntro='focus',futureOption='kept'}
  local merged=Save.mergeOptions(original)
  T.eq(merged[id],value,'explicit boolean retained on save merge '..tostring(value))
  T.eq(merged.jpBattleIntro,'focus','save merge keeps independent opening')
  T.eq(original.futureOption,'kept','save merge preserves original source')
  T.check(Save.saveOptions(merged)~=nil,'real options file persists camera choice')
  T.eq(Save.loadOptions()[id],value,'real options reload preserves camera choice')
  local encoded=assert(Transfer.export(merged))
  T.eq(Json.decode(encoded).options[id],value,'JSON explicitly exports boolean '..tostring(value))
  local restored=assert(Transfer.import(encoded,{futureOption='kept'}))
  T.eq(restored[id],value,'JSON camera setting roundtrip')
  T.eq(restored.jpBattleIntro,'focus','JSON preserves independent opening choice')
  T.eq(restored.futureOption,'kept','JSON import retains unrelated local future key')
  local old=assert(Transfer.import(document({musicVol=2}),merged))
  T.eq(old[id],value,'legacy JSON without new key preserves explicit current choice')
end
for _,value in ipairs({'false','true',0,1,{},'off'})do
  local current={[id]=false,jpBattleIntro='focus'}
  local result,err=Transfer.import(document({[id]=value}),current)
  T.check(result==nil and type(err)=='string','non-boolean JSON is rejected')
  T.eq(current[id],false,'rejected JSON leaves current explicit OFF unchanged')
  T.eq(current.jpBattleIntro,'focus','rejected JSON leaves opening unchanged')
end
Version.set('red_jp')
local data={constants={language='ja'}};Strings.load(data)
local options=Save.defaultOptions();options[id]=nil
local before=Json.encode(options)
local game={data=data,save={options=options}}
local home=Home.open({options=options,save=function()return true end},'red_jp')
local menu=Options.new(game)
local hr,hn=find(flatten(home.sections),id)
local gr,gn=find(menu.rows,id)
T.eq(hn,1,'home settings exposes camera toggle once')
T.eq(gn,1,'in-game settings exposes camera toggle once')
T.eq(hr.label,'せんとうカメラの うごき','home uses clear camera label')
T.eq(gr.label,hr.label,'both settings use the shared camera descriptor')
T.eq(hr.value(),'オン','home renders missing old key as ON')
T.eq(gr.value(game),'オン','game renders missing old key as ON')
T.eq(Json.encode(options),before,'viewing missing old key never writes settings')
T.eq(Catalog.group(id),'game','camera belongs to Game category')
T.check(Catalog.entry(id)[2]:find('ゆっくり',1,true),'description explains gentle movement')
local foundGroup,adjacent
for _,section in ipairs(home.sections)do
  for i,row in ipairs(section.rows or{})do
    if row.id==id then foundGroup=section.id;adjacent=section.rows[i-1]and section.rows[i-1].id end
  end
end
T.eq(foundGroup,'game','home displays toggle in Game')
T.eq(adjacent,'jpBattleIntro','home places toggle beside opening setting')
for _,group in ipairs(menu.view)do
  for i,row in ipairs(group.members or{})do
    if row.id==id then
      T.eq(group.id,'group.game','game displays toggle in Game category')
      T.eq(group.members[i-1].id,'jpBattleIntro','game places toggle beside opening setting')
    end
  end
end
hr.step(1)
T.eq(options[id],false,'home controller toggle disables camera')
T.eq(gr.value(game),'オフ','in-game UI immediately reflects home change')
T.eq(options.jpBattleIntro,'focus','camera OFF does not disable opening sequence')
gr.step(game,-1)
T.eq(options[id],true,'in-game controller toggle enables camera')
T.eq(hr.value(),'オン','home immediately reflects in-game change')
options.reduceMotion=true;options[id]=false
hr.step(1)
T.eq(options[id],true,'camera choice may be saved independently of accessibility override')
T.eq(options.reduceMotion,true,'camera toggle never disables reduce-motion preference')
for _,preset in ipairs({'classic','convenient'})do
  options[id]=false;Rules.applyPreset(options,preset)
  T.eq(options[id],false,'battle convenience preset leaves camera OFF unchanged')
  T.eq(options.jpBattleIntro,'focus','battle convenience preset leaves opening unchanged')
end
options.jpLauncherLanguage='en';home.refreshLabels()
T.eq(hr.label,'Battle camera motion','English home caption supported')
T.eq(hr.value(),'Off','English home OFF supported')
for _,version in ipairs({'red','blue','yellow','gold','silver','crystal','firered'})do
  T.eq(find(flatten(Home.open({options=Save.defaultOptions()},version).sections),id),nil,
    'non-JP launcher has no unavailable camera option '..version)
end
Version.set('red');Strings.load({constants={language='en'}})
T.eq(find(Options.new({data={constants={language='en'}},save={options=Save.defaultOptions()}}).rows,id),nil,
  'non-JP in-game menu remains unchanged')
T.finish()
