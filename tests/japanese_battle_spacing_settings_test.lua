package.path = './?.lua;./?/init.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('Japanese battle spacing settings')
local Save = require('src.core.SaveData')
local Settings = require('src.import.LauncherSettings')
local Options = require('src.ui.OptionsMenu')
local Transfer = require('src.import.SettingsTransfer')
local Strings = require('src.core.Strings')
local Version = require('src.core.GameVersion')
Version.set('red_jp')
local data = {constants={language='ja'}}
Strings.load(data)
local function find(rows)
  for _, row in ipairs(rows) do if row.id=='jpBattleSpacing' then return row end end
end
local function launcherRow(model)
  for _, section in ipairs(model.sections) do
    local row=find(section.rows); if row then return row end
  end
end
local opts=Save.defaultOptions()
opts.jpDialogScale=.75
opts.jpBattleSpacing=nil -- an existing pre-jp13 preference file
local model=Settings.open({options=opts,save=function(o)return Save.saveOptions(o,love.filesystem)end},'red_jp')
local row=assert(launcherRow(model))
T.eq(row.label,'せんとうの かんかく','launcher labels the spacing control in Japanese')
T.eq(row.value(),'ひろい','old preferences display the intended wide default')
T.eq(opts.jpBattleSpacing,nil,'viewing the setting does not rewrite old preferences')
T.check(row.step(1),'controller right changes the preset')
T.eq(opts.jpBattleSpacing,'wider','controller chooses wider')
T.check(model.save(),'shared model persists the new setting')
local loaded=Save.loadOptions(love.filesystem)
T.eq(loaded.jpBattleSpacing,'wider','spacing survives preference save and reload')
T.eq(loaded.jpDialogScale,.75,'text scale is independent and survives')
local g={save={options=loaded},data=data}
local inGame=assert(find(Options.new(g).rows))
T.eq(inGame.value(g),'とても ひろい','in-game menu sees the launcher choice')
for _, expected in ipairs({'normal','wide','wider'}) do
  T.check(inGame.step(g,1),'in-game control steps forward')
  T.eq(loaded.jpBattleSpacing,expected,'preset cycles and wraps in order')
  local encoded=assert(Transfer.export(loaded))
  local restored=assert(Transfer.import(encoded,{musicVol=2}))
  T.eq(restored.jpBattleSpacing,expected,'preset survives portable export and import')
end
inGame.step(g,-1)
T.eq(loaded.jpBattleSpacing,'wide','controller left reverses the selection')
T.eq(loaded.jpDialogScale,.75,'cycling presets does not resize text')
T.eq(launcherRow(Settings.open({options={}},'red')),nil,'US launcher has no ineffective JP-only control')
Strings.load({constants={language='en'}})
T.eq(find(Options.new({save={options=Save.defaultOptions()},data={constants={language='en'}}}).rows),nil,
  'US in-game menu retains its own layout controls')
T.finish()
