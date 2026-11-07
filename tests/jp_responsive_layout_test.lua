package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness")
local Layout=require("src.ui.GameUILayout")
local Viewport=require("src.render.GameViewport")
local Touch=require("src.core.TouchControls")
local ww,wh,pw,ph=800,480,800,480
love.graphics.getDimensions=function()return ww,wh end
love.graphics.getPixelDimensions=function()return pw,ph end
love.window=love.window or {}
love.window.getSafeArea=function()return 0,12,ww,wh-24 end
Touch.visible=function()return true end
Touch.layout=function()return {dpad={cx=80,cy=wh-70,w=120},a={cx=ww-50,cy=wh-110,w=80}} end
local game={data={constants={language="ja"}},save={options={}}}
for _,size in ipairs({{480,800},{800,480},{972,1536},{1536,1160}}) do
  for _,dpi in ipairs({{1,1},{1.25,1.5},{2,2}}) do
    ww,wh=size[1],size[2];pw,ph=ww*dpi[1],wh*dpi[2]
    Viewport.full,Viewport.rect,Viewport.frameActive=nil,nil,false
    for _,factor in ipairs({.5,.75,1}) do
      game.save.options.jpDialogScale=factor
      local r={vux=0,vuy=0,vuw=ww,vuh=wh,pw=pw,ph=ph,dpiX=dpi[1],dpiY=dpi[2],uiw=160,uih=144}
      Layout.frame(r,factor,false)
      local overlay=Layout.overlay(game,{anchor="topright",box={x=48,y=8,w=104,h=80}})
      T.eq(r.Up,overlay.scale,"native and independent menu share physical font size")
      T.eq(r.Up,math.floor(r.Up),"physical glyph size stays integral")
      T.check(math.abs(r.Ux*dpi[1]-r.Uy*dpi[2])<1e-8,"anisotropic DPI keeps square pixels")
      for _,c in pairs(Touch:layout()) do
        local x,y,w,h=c.cx-c.w/2,c.cy-c.w/2,c.w,c.w
        T.check(r.body.x+r.body.w<=x or r.body.x>=x+w
          or r.body.y+r.body.h<=y or r.body.y>=y+h,
          "actual touch bounds are excluded, including landscape side controls")
      end
      for _,a in ipairs({{x=80,y=0,w=80,h=128,anchor="topright"},
          {x=0,y=96,w=160,h=48,anchor="bottom"},
          {x=0,y=0,w=96,h=40,anchor="battleEnemy"},
          {x=64,y=48,w=96,h=48,anchor="battlePlayer"}}) do
        local x,y,w,h=Layout.place(r,a)
        T.check(x>=r.body.x and x+w<=r.body.x+r.body.w+.01
          and y>=r.body.y and y+h<=r.body.y+r.body.h+.01,"anchored element fits safe playfield")
      end
    end
  end
end
local Game=require("src.core.Game")
T.eq(Game.windowScaleInStack({states={{isOpaque=true,isOpeningMovie=true}}},{jpDialogScale=.5}),1,
  "opening art retains its complete picture scale")
local Party=require("src.ui.PartyMenu")
local p=setmetatable({game=game},{__index=Party})
T.eq(p:topInset(),8,"Japanese names reserve an accent row")
T.eq(select(2,p:uiSize()),152,"party source retains all six rows and its footer")
game.data.constants.language="en"
T.eq(p:topInset(),0,"other languages keep original party coordinates")
local Settings=require("src.import.LauncherSettings")
local Options=require("src.ui.OptionsMenu")
local legacy={"uiLayout","battleFit","battleHud","battleLayout","battleBg"}
local function indexed(rows)
  local out={}
  for _,row in ipairs(rows) do out[row.id]=row end
  return out
end
local function settingsRows(model)
  local rows={}
  for _,section in ipairs(model.sections) do
    for _,row in ipairs(section.rows) do rows[#rows+1]=row end
  end
  return indexed(rows)
end
for _,version in ipairs({"red_jp","red","gold"}) do
  local values={uiLayout="dynamic",battleFit="fill",battleHud="extended",battleLayout="wide",battleBg="black"}
  local saved=version=="gold" and {gold=values} or values
  local rows=settingsRows(Settings.open({options=saved},version))
  if version=="red_jp" then
    for _,id in ipairs(legacy) do T.check(not rows[id],"JP launcher hides obsolete "..id) end
    T.check(rows.jpDialogScale~=nil,"JP launcher keeps common window size")
    game.data.constants.language="ja";game.save.options=values
    local native=indexed(Options.new(game).rows)
    for _,id in ipairs(legacy) do T.check(not native[id],"JP game settings hide obsolete "..id) end
    T.eq(values.battleHud,"extended","opening JP settings preserves hidden HUD value")
    T.eq(values.battleLayout,"wide","opening JP settings preserves hidden battle layout")
    T.eq(values.battleBg,"black","opening JP settings preserves hidden battle background")
    T.eq(values.uiLayout,"dynamic","opening JP settings preserves placement preference")
    T.eq(values.battleFit,"fill","opening JP settings preserves battle fit preference")
    local Transfer=require("src.import.SettingsTransfer")
    local restored=assert(Transfer.import(assert(Transfer.export(values)),{}))
    for _,id in ipairs(legacy) do T.eq(restored[id],values[id],"hidden setting survives JSON round trip: "..id) end
  else
    T.check(rows.battleLayout and rows.battleFit and rows.battleHud,"non-JP launcher keeps working battle controls")
    rows.battleLayout.step(1)
    T.eq(values.battleLayout,"og","non-JP launcher still changes battle layout")
    T.eq(values.battleHud,"standard","non-JP original layout keeps its HUD lock")
    if version=="red" then
      T.check(rows.uiLayout~=nil,"non-JP launcher keeps placement control")
      game.data.constants.language="en";game.save.options=values
      local native=indexed(Options.new(game).rows)
      for _,id in ipairs(legacy) do T.check(native[id]~=nil,"non-JP game keeps "..id) end
    end
  end
end
T.finish()
