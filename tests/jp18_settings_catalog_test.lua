package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Japanese settings organization')
local Json=require('src.link.Json')
local Save=require('src.core.SaveData')
local Settings=require('src.import.LauncherSettings')
local Mods=require('src.mods.LauncherMods')
Mods.optionSchemas=function()return {
  {id='DRAMALESS_SHAPE',name='Dramaless Shape',schema={
    {key='grid',type='choice',default=0,label='V-GRID',choices={{'OFF',0},{'WHITE',1}}},
    {key='water',type='toggle',default=true,label='WATER',help='Water reflections.'}}},
  {id='QA_EXTRA',name='EXTERNAL TEST',schema={
    {key='enabled',type='toggle',default=true,label='MOD ENABLED'},
    {key='name',type='text',default='kept',label='MOD NAME'}}},
}end
local function collect(model,result)
  result=result or{}
  for _,section in ipairs(model.sections or model.children or{})do
    for _,row in ipairs(section.rows or{})do result[#result+1]=row end
    collect({children=section.children},result)
  end
  return result
end
local function snapshot(rows)
  local result={}
  for _,row in ipairs(rows)do result[#result+1]={id=row.id,step=type(row.step)=='function',action=type(row.action)=='function',text=type(row.setText)=='function'}end
  table.sort(result,function(a,b)return a.id<b.id end)
  return result
end
local function hooks()
  return {options={jpDialogScale=1,jpLauncherLanguage='ja',future={keep='value'}},save=function()return true end,
    editTouchControls=function()end,openSkinStudio=function()end,importSettings=function()end,exportSettings=function()end}
end
local versions={'red_jp','red','blue','yellow','gold','silver','crystal','firered'}
if arg[1]=='--baseline'then
  local Old=assert(loadfile(assert(arg[2])..'/src/import/LauncherSettings.lua'))()
  local result={}
  for _,version in ipairs(versions)do result[version]=snapshot(collect(Old.open(hooks(),version)))end
  local f=assert(io.open('tests/fixtures/jp18_settings_baseline.json','wb'));f:write(Json.encode(result));f:close()
  print('Recorded immutable jp17 row contracts');return
end
local f=assert(io.open('tests/fixtures/jp18_settings_baseline.json','rb'));local baseline=Json.decode(f:read('*a'));f:close()
-- The immutable jp17 contract above remains untouched. Later JP-only
-- additions are accounted for separately instead of re-recording a baseline.
local additions={["pipeline:tiltshift"]=true,jpRulesPreset=true,jpPartyExp=true,
  jpForgetHM=true,jpReusableTM=true,jpFieldActions=true,jpAnalogWalk=true,jpBattleIntro=true,jpAtmosphere=true,
  jpMoveReminder=true,jpFollower=true,jpRepelRepeat=true,jpBattleCameraMotion=true}
for _,version in ipairs(versions)do
  local model=Settings.open(hooks(),version);local rows=collect(model)
  local retained,added={},0
  for _,row in ipairs(rows)do
    if additions[row.id] then
      added=added+1
      T.check(type(row.step)=='function','additive setting keeps controller operation: '..row.id)
    else retained[#retained+1]=row end
  end
  T.eq(added,version=='red_jp' and 13 or 0,'later additions appear only in Japanese settings')
  local actual=snapshot(retained);local old={}
  -- JP25 replaces the old positive intro switch with one explicit skip
  -- switch. Keep the immutable fixture and compare the documented rename.
  for _,row in ipairs(baseline[version])do
    old[#old+1]={id=row.id=='jpOriginalIntro'and'jpSkipIntro'or row.id,
      step=row.step,action=row.action,text=row.text}
  end
  table.sort(old,function(a,b)return a.id<b.id end)
  T.eq(#actual,#old,version..' retains every preexisting leaf setting')
  for i,expected in ipairs(old)do
    for _,key in ipairs({'id','step','action','text'})do T.eq(actual[i][key],expected[key],version..' preserves '..expected.id..' '..key)end
  end
  if version=='red_jp'then
    T.eq(#model.sections,7,'seven discoverable categories')
    local groups={};for _,section in ipairs(model.sections)do groups[section.id]=section;T.check(section.description~=nil,'category has an explanation '..section.id)end
    T.eq(groups.mods.children[1].modId,'QA_EXTRA','external MOD schema remains under its own name')
    local ids={};for _,r in ipairs(groups.world.rows)do ids[r.id]=true end
    T.check(ids['DRAMALESS_SHAPE.grid']and ids['DRAMALESS_SHAPE.water'],'3D MOD features are in 3D display')
    model.opts.jpLauncherLanguage='en';model.refreshLabels()
    T.eq(groups.controls.title,'Controls','language switch updates category captions')
    local english={};for _,row in ipairs(rows)do english[row.id]=row.label end
    T.eq(english.editTouchControls,'Arrange touch buttons','language switch preserves original English action caption')
    T.eq(english.jpDialogScale,'Window size','language switch preserves English window caption')
    T.eq(model.opts.jpDialogScale,1,'organization never changes saved size')
    T.eq(model.opts.future.keep,'value','unknown stored settings remain')
  end
end
local View=require('src.import.LauncherView')
local seen={}
local function upvalue(fn,want)
  if seen[fn]then return end;seen[fn]=true
  for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end
    if n==want then return v end
    if type(v)=='function'then local f=upvalue(v,want);if f then return f end end
  end
end
local build=assert(upvalue(View.draw,'model'))
local model=Settings.open(hooks(),'red_jp')
local imp={tab='red_jp',_settings=model,_ui={page='settings',focus=1,sheet=1,options=model.opts,hits={}}}
local function rebuild()imp._ui.rows=build(imp).rows;return imp._ui.rows end
local controls,mods
for i,section in ipairs(model.sections)do if section.id=='controls'then controls=i elseif section.id=='mods'then mods=i end end
rebuild();imp._ui.focus=controls;View.keypressed(imp,'return');rebuild()
T.eq(imp._ui.page,'settings-detail','home opens selected category')
T.check(imp._ui.rows[1].description~=nil,'home shows per-setting explanation')
View.keypressed(imp,'escape');T.eq(imp._ui.focus,controls,'Back retains selected home category')
rebuild();imp._ui.focus=mods;View.keypressed(imp,'return');rebuild();View.keypressed(imp,'return');rebuild()
T.eq(imp._ui.settingsChild,1,'external MOD schema opens from its category')
T.eq(imp._ui.rows[1].optionId,'QA_EXTRA.enabled','nested MOD row keeps original option ID')
View.keypressed(imp,'escape');T.eq(imp._ui.settingsChild,nil,'Back first returns to MOD list')
T.eq(imp._ui.page,'settings-detail','MOD list remains inside category')
View.keypressed(imp,'escape');T.eq(imp._ui.focus,mods,'second Back retains MOD category focus')

local Runtime=require('src.mods.Runtime');local Options=require('src.ui.OptionsMenu')
local extraCalls=0
local custom={id='qa_external',label='CUSTOM OPTION',activate=function()extraCalls=extraCalls+1 end}
local anonymous={label='WITHOUT ID',step=function()return true end}
Runtime.call=function(event,base,game,rows)
  if event=='ui.options.rows'then rows[#rows+1]=custom;rows[#rows+1]=anonymous end
  return rows
end
local stack={states={}};function stack:top()return self.states[#self.states]end
function stack:push(state)self.states[#self.states+1]=state end
function stack:pop()return table.remove(self.states)end
local game={data={constants={language='ja'}},save={options=Save.defaultOptions()},stack=stack,
  openTouchControlsEditor=function()end,openSkinStudio=function()end}
local root=Options.new(game);stack:push(root)
local leaves={}
for _,group in ipairs(root.view)do
  T.check(group.group and group.description and group.members,'game root contains explained categories')
  for _,row in ipairs(group.members)do leaves[row]=(leaves[row]or 0)+1 end
end
for _,row in ipairs(root.rows)do T.eq(leaves[row],1,'exact original row appears once '..tostring(row.id))end
T.eq(leaves[anonymous],1,'MOD row without ID is retained')
local sub=root:focusRow('qa_external')
T.eq(sub.jpGroup,'mods','unknown external MOD row has a discoverable category')
sub:activateRow(custom);T.eq(extraCalls,1,'original external activate callback called once')
sub:closeWindow();T.eq(stack:top(),root,'category Back returns to same root instance')
T.eq(root.view[root.index].id,'group.mods','category selection survives Back')
local control=root:focusRow('editTouchControls')
T.eq(control.jpGroup,'controls','touch arrangement shares Controls with physical bindings')
control:closeWindow()
local world=root:focusRow('zoom')
T.eq(world.jpGroup,'world','zoom is in 3D display')
local original=world.view[world.index]
local replacement=Options.new(game).rows
replacement[#replacement+1]={id='DRAMALESS_SHAPE:dynamic',label='DYNAMIC',value=function()return 'ON'end}
world.rows=replacement;world:refreshGroups()
T.eq(world.jpGroup,'world','external row rebuild retains current category')
T.eq(world.view[world.index].id,original.id,'external row rebuild retains selected ID')
local found=false;for _,row in ipairs(world.view)do if row.id=='DRAMALESS_SHAPE:dynamic'then found=true end end
T.check(found,'external visibility rebuild is reflected within category')
T.eq(root.rows,replacement,'parent category counts use rebuilt rows')
world:closeWindow();T.eq(stack:top(),root,'rebuild does not duplicate root stack')
T.finish()
