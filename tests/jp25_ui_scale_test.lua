package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Japanese five-step window scale')
local Scale=require('src.ui.JapaneseUIScale')
local Save=require('src.core.SaveData')
local Transfer=require('src.import.SettingsTransfer')
local Json=require('src.link.Json')
local Layout=require('src.ui.GameUILayout')
local Renderer=require('src.render.Renderer')
local Launcher=require('src.import.LauncherSettings')
local Options=require('src.ui.OptionsMenu')
require('src.core.GameVersion').set('red_jp')
local function rows(model)
  local list={}
  for _,section in ipairs(model.sections or {})do for _,row in ipairs(section.rows or {})do list[row.id]=row end end
  return list
end
local function native(game)
  for _,row in ipairs(Options.new(game).rows)do if row.id=='jpDialogScale'then return row end end
end
T.eq(Save.defaultOptions().jpDialogScale,.75,'default coefficient preserved; former Compact is Normal')
T.eq(Scale.label(.75),'ふつう','normal size is labelled unambiguously')
T.eq(Scale.label(.75,true),'Normal','English caption reflects same baseline')
T.eq(Scale.label(.5),'ちいさい','legacy Small shown at its exact relative scale')
T.eq(Scale.label(1),'おおきい','legacy Normal now identified above the new baseline')
for _,value in ipairs({.375,.45,.5,.525,.6,.675,.75,.825,.9,.975,1,1.05,1.125,1.2,1.275,1.35,1.425,1.5,.70123})do
  local opts={jpDialogScale=value,jpLauncherLanguage='ja',colors='redpp_soft',musicVol=4,custom={keep=42}}
  local game={data={constants={language='ja'}},save={options=opts}}
  local model=Launcher.open({options=opts},'red_jp')
  local row=rows(model).jpDialogScale
  local n=native(game)
  T.eq(opts.jpDialogScale,value,'opening settings preserves exact coefficient '..value)
  T.eq(row.value(),n.value(game),'home and native share label '..value)
  local session=rows(require('src.ui.SessionMenu').new(game,'settings'):settings()).jpDialogScale
  T.eq(session.value(),row.value(),'session preferences share label '..value)
  for _,direction in ipairs({-1,1})do
    opts.jpDialogScale=value;row.step(direction);local fromHome=opts.jpDialogScale
    opts.jpDialogScale=value;n.step(game,direction)
    T.eq(opts.jpDialogScale,fromHome,'home/game step agrees '..value..' '..direction)
  end
  opts.jpDialogScale=value
  local text=assert(Transfer.export(opts))
  local restored=assert(Transfer.import(text,{unrelated={kept=true}}))
  T.eq(restored.jpDialogScale,value,'old and custom sizes survive JSON exactly '..value)
  T.eq(restored.colors,'redpp_soft','scale transfer does not reset colour')
  T.eq(restored.unrelated.kept,true,'import retains unspecified local options')
  T.eq(opts.custom.keep,42,'changing size preserves unrelated options')
end
local offered={.375,.5,.75,1,1.5}
local labels={'とてもちいさい','ちいさい','ふつう','おおきい','とてもおおきい'}
local value=.375
for i,expected in ipairs(offered)do
  T.eq(value,expected,'five-step ladder reaches size '..i)
  T.eq(Scale.label(value),labels[i],'five-step label '..i)
  value=Scale.step(value,1)
end
T.eq(value,1.5,'upper endpoint does not wrap to tiny size')
for i=#offered,1,-1 do T.eq(value,offered[i],'reverse ladder reaches size '..i);value=Scale.step(value,-1)end
T.eq(value,.375,'lower endpoint does not wrap to huge size')
T.eq(Scale.step(.6,1),.75,'custom import steps to next larger offered size')
T.eq(Scale.step(.6,-1),.5,'custom import steps to next smaller offered size')
T.eq(Scale.label(.70123),'ふつう','custom import displays nearest simple label without mutation')
for _,bad in ipairs({-.1,.374,1.501,2,'0.75'})do
  local document=Json.encode({format=Transfer.FORMAT,version=1,options={jpDialogScale=bad}})
  T.eq(Transfer.import(document,{}),nil,'invalid or string coefficient rejected: '..tostring(bad))
end
T.eq(Scale.normalize(nil),.75,'unset renderer value defaults to Normal')
T.eq(Scale.normalize(0/0),.75,'NaN never enters geometry')
T.eq(Scale.normalize(math.huge),.75,'infinite value never enters geometry')
T.eq(Scale.normalize(.1),.375,'corrupt local undersize bounded for display')
T.eq(Scale.normalize(10),1.5,'corrupt local oversize bounded for display')
for _,short in ipairs({320,480,800,972,1536,2160})do
  T.eq(Scale.panelPixels(short,.75),math.max(1,math.floor(short/272+.5)),
    'Normal keeps former Compact panel glyph size '..short)
end
for base=1,12 do
  T.eq(Layout.windowScale(base,.75),math.max(1,math.floor(base*.75+.5)),
    'Normal keeps former Compact native glyph size '..base)
  local last=0
  for i,v in ipairs(offered)do
    local p=i;local n=Layout.windowScale(base,v)
    T.eq(n,Renderer.windowScale(base,v),'renderer and window helper agree '..base..' '..p)
    T.check(n>=last and n==math.floor(n),'native size is monotone and whole-pixel '..base..' '..p)
    last=n
  end
end
-- Enlargement is no longer silently capped to the old full-size coefficient.
T.check(Layout.windowScale(8,1.5)>Layout.windowScale(8,1),'larger offered size grows when physical space permits')
local Touch=require('src.core.TouchControls');Touch.visible=function()return false end
local Viewport=require('src.render.GameViewport');Viewport.frameActive=false
love.window=love.window or{}
for _,size in ipairs({{480,800},{972,1536},{1536,972}})do
  local w,h=size[1],size[2]
  love.graphics.getDimensions=function()return w,h end;love.graphics.getPixelDimensions=function()return w,h end
  love.window.getSafeArea=function()return 0,0,w,h end
  for _,factor in ipairs({.375,.75,1.5})do
    local r={vux=0,vuy=0,vuw=w,vuh=h,pw=w,ph=h,dpiX=1,dpiY=1,uiw=160,uih=144}
    Layout.frame(r,factor,true,true)
    T.check(r.uox>=0 and r.uoy>=0 and r.uox+r.uvpw<=w and r.uoy+r.uvph<=h,
      'native page remains inside display '..w..' '..factor)
    require('src.battle.BattlePresentation').frame(r,factor,'wide')
    local b=r.battlePresentation.panels
    T.check(b.x>=0 and b.y>=0 and b.x+b.width*b.sx<=w+.01 and b.y+b.height*b.sy<=h+.01,
      'battle command surface stays inside display '..w..' '..factor)
  end
end
T.finish()
