-- Independent review of input wiring and legacy/partial settings semantics.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Battle spacing independent review')
local Save=require('src.core.SaveData')
local Transfer=require('src.import.SettingsTransfer')
local Settings=require('src.import.LauncherSettings')
local View=require('src.import.LauncherView')
local seen={}
local function upvalue(fn,want)
 if seen[fn] then return end;seen[fn]=true
 for i=1,100 do local name,value=debug.getupvalue(fn,i);if not name then break end
  if name==want then return value end
  if type(value)=='function' then local found=upvalue(value,want);if found then return found end end
 end
end
-- Use the view's actual row-builder/closures without substituting actions or
-- requiring graphics. Render/input geometry has its own real-LÖVE suite.
local build=assert(upvalue(View.draw,'model'))
local writes=0
local options={jpDialogScale=.75,customFuture={keep='mine'}}
local model=Settings.open({options=options,save=function(o)writes=writes+1;return Save.saveOptions(o,love.filesystem)end},'red_jp')
local section,index
for s,bucket in ipairs(model.sections)do for i,row in ipairs(bucket.rows)do
 if row.id=='jpBattleSpacing'then section,index=s,i end
end end
assert(section and index)
local imp={tab='red_jp',workState='idle',_settings=model,_ui={page='settings-detail',settingsSection=section,focus=index,sheet=1,options=options,hits={}}}
local function refresh()imp._ui.rows=build(imp).rows end
refresh();T.eq(imp._ui.rows[index].value,'ひろい','actual view resolves missing field to wide')
View.keypressed(imp,'right');T.eq(options.jpBattleSpacing,'wider','actual launcher right key changes spacing')
T.eq(writes,1,'right key persists exactly once');T.eq(Save.loadOptions(love.filesystem).jpBattleSpacing,'wider','view input reaches persisted settings')
refresh();View.keypressed(imp,'left');T.eq(options.jpBattleSpacing,'wide','actual launcher left key reverses selection');T.eq(writes,2,'left key persists exactly once')
refresh();View.keypressed(imp,'return');T.eq(options.jpBattleSpacing,'wider','actual launcher confirm cycles spacing');T.eq(writes,3,'confirm persists exactly once')
T.eq(options.jpDialogScale,.75,'launcher changes do not resize text')
local patch=assert(Transfer.export({musicVol=2}))
local imported=assert(Transfer.import(patch,options))
T.eq(imported.jpBattleSpacing,'wider','partial older JSON retains existing spacing')
T.eq(imported.customFuture.keep,'mine','partial import retains unknown current settings')
T.eq(options.musicVol,nil,'import candidate does not mutate current settings')
local old=assert(Transfer.import(patch,{}));T.eq(old.jpBattleSpacing,nil,'older JSON does not invent missing settings during decode')
T.eq(Save.mergeOptions(old).jpBattleSpacing,'wide','legacy options gain wide default on normal merge')
for _,value in ipairs({'"farther"','0','true','null','[]','{}'})do
 local text='{"format":"kanto-player-jp-settings","version":1,"options":{"jpBattleSpacing":'..value..'}}'
 local candidate=Transfer.import(text,options)
 T.eq(candidate,nil,'invalid spacing JSON is rejected: '..value)
 T.eq(options.jpBattleSpacing,'wider','rejected JSON preserves current spacing')
end
local en=Settings.open({options={jpLauncherLanguage='en'}},'red_jp');local english
for _,s in ipairs(en.sections)do for _,r in ipairs(s.rows)do if r.id=='jpBattleSpacing'then english=r end end end
T.eq(english.label,'Battle spacing','optional English launcher caption is available')
T.eq(english.value(),'Wide','English launcher has matching missing-value default')
for _,version in ipairs({'red','blue','yellow','gold','silver','crystal','firered'})do
 local found=false
 for _,s in ipairs(Settings.open({options={}},version).sections)do for _,r in ipairs(s.rows)do if r.id=='jpBattleSpacing'then found=true end end end
 T.check(not found,'JP spacing hidden in '..version..' launcher')
end
T.finish()
