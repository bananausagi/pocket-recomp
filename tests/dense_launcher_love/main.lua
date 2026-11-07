-- Real bitmap rendering and controller input; isolated files, no ROM data.
local function run()
  local root,out=assert(os.getenv("KANTO_QA_ROOT")),assert(os.getenv("KANTO_QA_OUT"))
  package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local Importer=require("src.import.RomImporter")
  local View=require("src.import.LauncherView")
  local Session=require("src.ui.SessionMenu")
  local SaveData=require("src.core.SaveData")
  local checks,shots=0,0
  local function check(ok,label)assert(ok,label);checks=checks+1;print("PASS "..label)end
  local imports,modImports,plays=0,0,0
  local imp=Importer.new(function(id)check(id=="red_jp","play keeps regional ROM identity");plays=plays+1 end,{launcher=true})
  imp.choose=function(_,id)check(id=="red_jp","import keeps regional ROM identity");imports=imports+1 end
  imp.chooseMod=function()modImports=modImports+1 end
  local function snapshot(c,name)
    local data=c:newImageData()
    local f=assert(io.open(out.."/"..name..".png","wb"));f:write(data:encode("png"):getString());f:close()
    shots=shots+1
  end
  local function draw(w,h,page,name)
    love.window.setMode(w,h,{resizable=true});imp._ui.page=page
    local c=love.graphics.newCanvas(w,h,{dpiscale=1})
    love.graphics.setCanvas(c);imp:draw();love.graphics.setCanvas()
    local ui,l=imp._ui,imp._ui.layout
    check(table.concat(ui.credit.lines)==View.CREDIT,"full attribution has no omissions")
    check(ui.credit.scale<=2 and ui.credit.y>=l.y+l.h and ui.credit.y+ui.credit.height<=h-8,
      "small credit remains visible below the panel")
    check(l.scale==math.floor(l.scale) and l.scale*8/math.min(w,h)>=.023,"readable integer glyph size "..page)
    check(l.width>160 and l.width%8==0 and l.height%8==0,"variable bitmap canvas "..page)
    check(l.x>=0 and l.y>=0 and l.x+l.w<=w and l.y+l.h<=h,"panel is inside safe window "..page)
    for _,hit in ipairs(ui.hits)do
      check(hit.x>=l.x and hit.y>=l.y and hit.x+hit.w<=l.x+l.w+.01 and hit.y+hit.h<=l.y+l.h+.01,"visible hit "..hit.id)
    end
    if name then
      snapshot(c,name)
      local data=c:newImageData();local pure=true
      for y=math.floor(l.y),math.floor(l.y+l.h)-1 do
        for x=math.floor(l.x),math.floor(l.x+l.w)-1 do
          local r,g,b,a=data:getPixel(x,y)
          if r~=g or g~=b or (r~=0 and r~=1)or a~=1 then pure=false;break end
        end
        if not pure then break end
      end
      check(pure,"only native black/white pixels "..name)
    end
    c:release()
  end
  local function reset(page)imp._ui.page=page;imp._ui.sheet=1;imp._ui.focus=1 end
  local function hit(id)
    for _,v in ipairs(imp._ui.hits)do if v.id==id then return v end end
  end
  local function click(id)
    local h=assert(hit(id),"missing "..id)
    View.clickAt(imp,h.x+h.w/2,h.y+h.h/2)
  end
  local function select(id)
    for _=1,#imp._ui.rows do
      if imp._ui.rows[imp._ui.focus].id==id then imp:keypressed("return");return end
      imp:keypressed("tab")
    end
    error("unreachable keyboard item "..id)
  end
  check(not imp.ready.red_jp,"starts without a ROM")
  for _,size in ipairs({{480,800},{800,480},{1536,1160}})do
    local w,h=size[1],size[2]
    reset("games");draw(w,h,"games","home-empty-"..w.."x"..h)
    check(imp._ui.sheets==1,"all home actions fit "..w.."x"..h)
    for _,id in ipairs({"rom","game-select","home-mods","mod-list","mod-import","mod-discover","home-settings","home-about","home-more"})do
      check(hit(id)~=nil,"home direct route "..id)
    end
    check(imp._ui.panel.rowH>=12,"controller rows preserve a full bitmap cell")
    if imp._ui.panel.columns==2 then
      imp:keypressed("down");check(imp._ui.rows[imp._ui.focus].id=="game-select","down leaves primary action for management")
      imp:keypressed("right");check(imp._ui.focus==3,"right selects adjacent management column")
      imp:keypressed("down");check(imp._ui.focus==5,"down selects next visual management row")
      imp:keypressed("left");check(imp._ui.focus==4,"left selects previous management column")
      imp:keypressed("up");imp:keypressed("up");check(imp._ui.focus==1,"up returns to full-width primary action")
    end
    reset("settings");draw(w,h,"settings","settings-"..w.."x"..h)
    check(imp._ui.sheets==1,"all setting categories fit")
    imp._ui.settingsSection=2;reset("settings-detail")
    draw(w,h,"settings-detail","settings-display-"..w.."x"..h)
    check(imp._ui.panel.wide,"settings prefer same-line labels and values")
    check(imp._ui.pageRows>=7,"at least seven display settings per page")
    imp:keypressed("acback");imp:keypressed("acback")
  end
  reset("games");draw(480,800,"games")
  select("rom");check(imports==1,"controller opens regional ROM picker")
  select("mod-import");check(modImports==1,"controller opens MOD ZIP picker")
  select("game-select");draw(480,800,"library","games-480x800")
  check(imp._ui.sheets==1 and hit("game-red_jp")and hit("game-firered"),"all regional games fit one list")
  click("game-red_jp");check(imp._ui.page=="games"and imp.tab=="red_jp","regional selection returns home")
  imp.ready.red_jp=true
  for _,size in ipairs({{480,800},{800,480},{1536,1160}})do
    reset("games");draw(size[1],size[2],"games","home-ready-"..size[1].."x"..size[2])
    check(imp._ui.sheets==1 and hit("play")and hit("rom")and hit("saves"),"ready home exposes play/import/save in one page")
  end
  click("play");check(plays==1,"play callback fires once")
  imp.workState="working";reset("games");draw(480,800,"games")
  click("play");check(plays==1,"busy import still blocks launching")
  imp.workState=nil
  imp.mods={}
  for i=1,37 do imp.mods[i]={id="qa-"..i,name="QA MOD "..i,enabled=i%2==1,version="1.0",manifest={},description="Test description "..i}end
  for _,size in ipairs({{480,800},{800,480},{1536,1160}})do
    reset("mod-list");draw(size[1],size[2],"mod-list","mods-"..size[1].."x"..size[2])
    check(imp._ui.pageRows>=8,"MOD list shows more than five entries")
    local per=imp._ui.pageRows
    for _=1,math.min(per,#imp.mods-1)do imp:keypressed("down")end
    draw(size[1],size[2],"mod-list")
    check(hit("mod-qa-"..imp._ui.focus)~=nil,"selection follows controller into visible page")
    if per<#imp.mods then check(imp._ui.sheet==2,"controller automatically pages a long MOD list")end
  end
  reset("mod-list");draw(480,800,"mod-list");click("mod-qa-1")
  draw(480,800,"mod-detail","mod-detail-480x800")
  check(hit("toggle-qa-1")and hit("mod-info"),"MOD enable and description actions remain present")
  click("mod-info");draw(480,800,"message","mod-description-480x800")
  imp:keypressed("acback");check(imp._ui.page=="mod-detail","description back preserves MOD context")
  reset("settings");draw(480,800,"settings");click("settings-section-1")
  draw(480,800,"settings-detail")
  local before=imp._settings.opts.musicVol
  imp:keypressed("left");check(imp._settings.opts.musicVol==before-1,"controller edits live audio value")
  imp:keypressed("acback");imp:keypressed("acback")
  check(SaveData.loadOptions().musicVol==before-1,"leaving settings persists the value")
  reset("games");imp._ui.options.jpLauncherLanguage="en"
  draw(480,800,"games","home-english-480x800")
  check(imp._ui.rows[1].label=="PLAY GAME","English language contract remains")
  imp._ui.options.jpLauncherLanguage=nil
  reset("games");draw(240,320,"games","home-small-240x320")
  for _=1,#imp._ui.rows-1 do imp:keypressed("tab")end
  draw(240,320,"games")
  check(hit(imp._ui.rows[imp._ui.focus].id)~=nil,"small window keeps last action reachable")
  local ow={player={}}
  local game={overworld=ow,stack={top=function()return ow end},save={options=SaveData.defaultOptions()},
    quickSaveAllowed=function()return true end,applyOptions=function()end,writeOptions=function()return true end}
  require("src.core.GameVersion").set("red_jp")
  local session=Session.new(game)
  for _,size in ipairs({{480,800},{800,480},{1536,1160}})do
    local w,h=size[1],size[2]
    love.window.setMode(w,h,{resizable=true});session:open("settings-detail",2)
    local c=love.graphics.newCanvas(w,h,{dpiscale=1});love.graphics.setCanvas(c)
    love.graphics.clear(.3,.5,.3,1);session:draw();love.graphics.setCanvas()
    local l,v=session.geometry,session.geometry.viewport
    check(v.scale==math.floor(v.scale) and v.scale*8/math.min(w,h)>=.023,"session keeps readable integer font")
    check(l.wide and l.perPage>=7,"session also uses dense label/value rows")
    check(v.x>=0 and v.y>=0 and v.x+v.w<=w and v.y+v.h<=h,"session panel stays inside available area")
    local range=l.pageRanges[1]
    for _=range.first,range.last do session:keypressed("down")end
    local moved=session:layout()
    check(session.focus>=moved.first and session.focus<=moved.last,"session controller selection remains visible")
    snapshot(c,"session-display-"..w.."x"..h);c:release()
  end
  check(View.CREDIT=="Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC (https://github.com/bryanthaboi/gen1recomp)","exact attribution unchanged")
  print("SCREENSHOTS "..shots)
  print("RESULT "..checks.." checks passed")
end
function love.load()
  io.stdout:setvbuf("no")
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
