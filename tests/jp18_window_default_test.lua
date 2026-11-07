-- Missing preferences must resolve exactly like explicit COMPACT, while saved
-- choices and full-picture opening/title scaling retain their old behavior.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp18 compact window defaults')
local Layout=require('src.ui.GameUILayout')
local Renderer=require('src.render.Renderer')
local Game=require('src.core.Game')
local Viewport=require('src.render.GameViewport')
local Touch=require('src.core.TouchControls')
local ww,wh,pw,ph=800,480,800,480
love.graphics.getDimensions=function()return ww,wh end
love.graphics.getPixelDimensions=function()return pw,ph end
love.window=love.window or {}
love.window.getSafeArea=function()return 0,0,ww,wh end
Touch.visible=function()return false end
local function game(value)
  return {data={constants={language='ja'}},save={options={jpDialogScale=value}}}
end
for base=1,8 do
  for _,value in ipairs({.5,.75,1}) do
    local expected=math.max(1,math.min(base,math.floor(base*value+.5)))
    T.eq(Layout.windowScale(base,value),expected,'explicit layout scale retained')
    T.eq(Renderer.windowScale(base,value),expected,'explicit renderer scale retained')
  end
  T.eq(Layout.windowScale(base),Layout.windowScale(base,.75),'missing layout scale is compact')
  T.eq(Renderer.windowScale(base),Renderer.windowScale(base,.75),'missing renderer scale is compact')
end
T.eq(Game.windowScaleInStack({states={}},nil),.75,'missing options are compact')
T.eq(Game.windowScaleInStack({states={}},{ }),.75,'missing saved key is compact')
for _,value in ipairs({.5,.75,1}) do
  T.eq(Game.windowScaleInStack({states={}},{jpDialogScale=value}),value,'explicit saved key retained')
end
for _,flag in ipairs({'isOpeningMovie','isTitleScreen'}) do
  local state={isOpaque=true};state[flag]=true
  T.eq(Game.windowScaleInStack({states={state}},{ }),1,'full-picture sequence keeps full size')
end
for _,size in ipairs({{320,568},{800,480},{972,1536},{2560,1440}}) do
  for _,dpi in ipairs({{1,1},{1.25,1.5},{2,2}}) do
    ww,wh=size[1],size[2];pw,ph=ww*dpi[1],wh*dpi[2]
    Viewport.full,Viewport.rect,Viewport.frameActive=nil,nil,false
    local missing=Layout.panelMetrics(game())
    local compact=Layout.panelMetrics(game(.75))
    for _,key in ipairs({'scale','width','height','margin','dpiX','dpiY'}) do
      T.eq(missing[key],compact[key],'missing panel preference matches compact '..key)
    end
    missing=Layout.overlay(game(),{anchor='center'})
    compact=Layout.overlay(game(.75),{anchor='center'})
    for _,key in ipairs({'x','y','w','h','sx','sy','scale'}) do
      T.eq(missing[key],compact[key],'missing overlay preference matches compact '..key)
    end
  end
end
local Settings=require('src.import.LauncherSettings')
local Options=require('src.ui.OptionsMenu')
local Strings=require('src.core.Strings')
local Version=require('src.core.GameVersion')
Version.set('red_jp')
Strings.load({constants={language='ja'}})
local function find(rows)
  for _,row in ipairs(rows) do if row.id=='jpDialogScale' then return row end end
end
local saved={}
local model=Settings.open({options=saved},'red_jp')
local row
for _,section in ipairs(model.sections) do row=row or find(section.rows) end
T.check(row~=nil,'launcher exposes window size')
T.eq(row.value(),'ちいさめ','missing launcher preference displays compact')
T.eq(saved.jpDialogScale,nil,'opening launcher does not rewrite saved preference')
T.check(row.step(1),'launcher compact choice can step forward')
T.eq(saved.jpDialogScale,1,'launcher next value is standard')
local g=game()
row=assert(find(Options.new(g).rows))
T.eq(row.value(g),Strings('COMPACT'),'missing in-game preference displays compact')
T.eq(g.save.options.jpDialogScale,nil,'opening in-game settings does not rewrite preference')
T.check(row.step(g,1),'in-game compact choice can step forward')
T.eq(g.save.options.jpDialogScale,1,'in-game next value is standard')
T.finish()
