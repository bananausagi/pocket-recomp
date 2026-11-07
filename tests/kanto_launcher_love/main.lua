-- Real LÖVE launcher input/render checks; handwritten state, never a game ROM.
local function run()
  local root=assert(os.getenv("KANTO_QA_ROOT"));local out=assert(os.getenv("KANTO_QA_OUT"))
  package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local Importer=require("src.import.RomImporter")
  local View=require("src.import.LauncherView")
  local Classic=require("src.ui.ClassicUI")
  local checks=0
  local function check(ok,msg)assert(ok,msg);checks=checks+1;print("PASS "..msg)end
  local imported,launched=0,0
  local imp=Importer.new(function(id)check(id=="red_jp","launch preserves regional identity");launched=launched+1 end,{launcher=true})
  imp.choose=function()imported=imported+1 end
  local function render(w,h,page,filename)
    love.window.setMode(w,h,{resizable=true});imp._ui.page=page
    local c=love.graphics.newCanvas(w,h,{dpiscale=1});love.graphics.setCanvas(c);imp:draw();love.graphics.setCanvas()
    local l=imp._ui.layout
    check(l.width%8==0 and l.height%8==0,"canvas uses whole bitmap cells "..page)
    if imp._ui.panel then check(l.width>160,"launcher lists use a wider window")
    else check(l.width==160 and l.height==144,"ordinary launcher retains 160x144 grid") end
    check(l.scale==math.floor(l.scale)and l.x>=0 and l.y>=0 and l.x+l.w<=w and l.y+l.h<=h,"integer canvas fits "..w.."x"..h)
    if filename then
      local data=c:newImageData();local f=assert(io.open(out.."/"..filename,"wb"));f:write(data:encode("png"):getString());f:close()
      local pure=true
      for yy=math.floor(l.y),math.floor(l.y+l.h)-1 do
        for xx=math.floor(l.x),math.floor(l.x+l.w)-1 do
          local r,g,b,a=data:getPixel(xx,yy)
          if r~=g or g~=b or (r~=0 and r~=1)or a~=1 then pure=false;break end
        end
        if not pure then break end
      end
      check(pure,"only black and white pixels, no antialiasing "..filename)
    end
    return c
  end
  local function hit(id)
    for _,h in ipairs(imp._ui.hits)do if h.id==id then return h end end
    error("missing hit "..id.." on "..imp._ui.page)
  end
  local function click(id)
    local h=hit(id);View.clickAt(imp,h.x+h.w/2,h.y+h.h/2)
  end
  local function page(name)imp._ui.sheet=1;imp._ui.focus=1;render(480,800,name)end
  check(not imp.ready.red_jp,"ROM-free first launch")
  check(View.CREDIT=="Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)","exact attribution retained")
  check(Classic.width("あAいう") == 32,"kana and Latin occupy the same 8px cells")
  render(320,480,"games","home-empty-320x480.png")
  local r=hit("rom");local x,y=r.x+r.w/2,r.y+r.h/2
  imp:touchpressed(1,x,y);imp:touchreleased(1,x,y);imp:mousepressed(x,y,1)
  check(imported==1,"touch and synthesized mouse activate import only once")
  imp:touchpressed(2,x,y);imp:touchmoved(2,x,y-65);imp:touchreleased(2,x,y-65)
  check(imported==1,"swipe never activates a menu row")
  imp._ui.sheet=1;render(480,800,"games","home-empty-480x800.png")
  click("home-settings");render(480,800,"settings","settings-480x800.png")
  check(imp._ui.page=="settings","home opens settings directly")
  click("settings-section-2");render(480,800,"settings-detail","settings-display-480x800.png")
  check(imp._ui.panel.wide and imp._ui.pageRows>=7,"portrait prefers dense label and value columns")
  local oldZoom=imp._settings.opts.zoom or 0
  click("setting-2-1-next")
  check((imp._settings.opts.zoom or 0)~=oldZoom,"touch updates the real setting")
  click("setting-2-1-prev")
  local footer=hit("page-back");local overlaps=false
  for _,h in ipairs(imp._ui.hits)do if h.row and h.y+h.h>footer.y then overlaps=true end end
  check(not overlaps,"last setting touch target never overlaps back")
  local steps=math.min(imp._ui.pageRows,#imp._ui.rows-1)
  for _=1,steps do imp:keypressed("down") end
  local range=imp._ui.pageRanges[imp._ui.sheet]
  check(imp._ui.focus>=range.first and imp._ui.focus<=range.last,"keyboard follows selection across settings pages")
  render(480,800,"settings-detail","settings-display-page2-480x800.png")
  imp:keypressed("acback");check(imp._ui.page=="settings"and imp._settings,"category back returns to settings list")
  imp:keypressed("acback");check(imp._ui.page=="games"and not imp._settings,"outer back saves and closes settings")
  for _,size in ipairs({{800,480},{960,640},{1536,1160}})do
    imp._ui.sheet=1;imp._ui.focus=1
    render(size[1],size[2],"settings","settings-"..size[1].."x"..size[2]..".png")
    imp._ui.settingsSection=2
    render(size[1],size[2],"settings-detail","settings-display-"..size[1].."x"..size[2]..".png")
    check(imp._ui.panel.wide,"wide launcher pairs the label with its value")
  end
  imp:keypressed("acback");imp:keypressed("acback")
  imp.mods={{id="qa-fixture",name="QA EXAMPLE MOD",version="1.0.0",description="テストの MODです。",enabled=true,manifest={}}}
  page("mods");click("mod-list");render(480,800,"mod-list","mods-480x800.png")
  click("mod-qa-fixture");render(480,800,"mod-detail","mod-details-480x800.png")
  check(hit("toggle-qa-fixture")~=nil,"installed mod details offer the toggle")
  imp:keypressed("escape");check(imp._ui.page=="mod-list","mod detail back preserves hierarchy")
  page("discover")
  local oldOpenURL,opened=love.system.openURL
  love.system.openURL=function(url)opened=url;return true end
  click("qol-release");love.system.openURL=oldOpenURL
  check(opened=="https://github.com/unxpected-uxp/pokemon-gen1-recomp-mod-qol/releases/tag/v1.3.0","QoL release link preserved")
  page("library");render(480,800,"library","games-page1-480x800.png")
  check(imp._ui.sheets==1 and hit("game-firered"),"dense game list retains all supported games in one page")
  click("game-red_jp");check(imp._ui.page=="games"and imp.tab=="red_jp","game selection returns to home")
  imp.workState=nil;imp.ready.red_jp=true
  for _,size in ipairs({{320,480},{480,800},{800,480},{1080,1920}})do
    imp._ui.sheet=1;render(size[1],size[2],"games","home-ready-"..size[1].."x"..size[2]..".png")
    local play=hit("play");local l=imp._ui.layout
    check(play.y>=l.y and play.y+play.h<=l.y+l.h,"play remains on-screen "..size[1].."x"..size[2])
    check(play.h>=12*l.sy,"whole logical row is tappable "..size[1].."x"..size[2])
  end
  page("games");click("saves");render(480,800,"saves","saves-jp-480x800.png")
  local raw=false;for _,row in ipairs(imp._ui.rows)do if row.id=="import-save"or row.id=="export-save"then raw=true end end
  check(raw,"Japanese native backup import and export are available")
  click("save-help");render(480,800,"message","save-help-480x800.png")
  check(#imp._ui.panel.lines>=5,"complete save help remains readable")
  if imp._ui.sheets>1 then
    click("page-next");render(480,800,"message","save-help-page2-480x800.png")
    check(imp._ui.sheet==2,"long help page advances")
  end
  imp:keypressed("escape");check(imp._ui.page=="saves","help returns to its originating menu")
  imp._modConfirm={title="CONFIRM",lines={"This confirmation deliberately contains enough text to exceed one page. Every line must stay accessible before choosing either action. End of confirmation."}}
  imp._ui.sheet=1;render(480,800,"mods","confirmation-480x800.png")
  check(imp._ui.sheets>1 and hit("confirm-cancel")and hit("confirm-yes"),"confirmation has paging and both actions")
  click("confirm-cancel");check(not imp._modConfirm,"cancel closes confirmation")
  page("about");click("license");render(480,800,"license","license-480x800.png")
  check(imp._ui.sheets>1,"complete license is readable in pages")
  imp:_openSettings()
  local filesSection
  for n,section in ipairs(imp._settings.sections)do
    for _,row in ipairs(section.rows)do if row.id=="importSettings"then filesSection=n end end
  end
  check(filesSection~=nil,"settings file import/export category is discoverable")
  imp._ui.settingsSection=filesSection;imp._ui.sheet=1
  render(480,800,"settings-detail","settings-files-480x800.png")
  check(#imp._ui.rows==2,"settings file actions remain directly tappable")
  local oldSaves,newSaves=0,0
  local oldModel={opts={},sections={{title="IMPORT",rows={{id="replace-model",label="IMPORT",action=function()
    imp._settings={opts={qaReplacement=true},sections={},save=function()newSaves=newSaves+1 end}
    View.showMessage(imp,"IMPORTED","OK")
  end}}}},save=function()oldSaves=oldSaves+1 end}
  imp._settings=oldModel;imp._ui.settingsSection=1;imp._ui.sheet=1
  render(480,800,"settings-detail")
  click("setting-1-1")
  check(oldSaves==0 and newSaves==1 and imp._ui.options.qaReplacement,"replacement settings are not overwritten by the old action model")
  check(imp._ui.page=="message","settings transfer opens its result message")
  imp._settings=nil;imp._ui.options=require("src.core.SaveData").loadOptions()
  imp._ui.options.jpLauncherLanguage="en";page("games");render(480,800,"games","home-english-480x800.png")
  check(imp._ui.rows[1].label=="PLAY GAME","English preference keeps the same menu contract")
  imp._ui.options.jpLauncherLanguage=nil
  imp:play("red_jp");check(launched==1,"play callback contract preserved")
  print("RESULT "..checks.." checks passed")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
