-- Real physical framebuffer samples, including high-DPI canvas composition.
-- Layout functions see the corresponding window units; glyph pixels are
-- rendered by LÖVE into a canvas with the actual device-pixel scale.
local function run()
  local root,out=assert(os.getenv("JP_READABLE_ROOT")),assert(os.getenv("JP_READABLE_OUT"))
  package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local before=os.getenv("JP_READABLE_BEFORE")=="1"
  local Importer=require("src.import.RomImporter")
  local View=require("src.import.LauncherView")
  local Session=require("src.ui.SessionMenu")
  local SaveData=require("src.core.SaveData")
  local Json=require("src.link.Json")
  local g=love.graphics
  local checks,report=0,{before=before,samples={}}
  local function check(ok,label)assert(ok,label);checks=checks+1 end
  local function write(name,bytes)local f=assert(io.open(out.."/"..name,"wb"));f:write(bytes);f:close()end
  local imp=Importer.new(function()end,{launcher=true});imp.ready.red_jp=true
  local function hit(id)for _,h in ipairs(imp._ui.hits)do if h.id==id then return h end end end
  local function click(id)local h=assert(hit(id),id);View.clickAt(imp,h.x+h.w/2,h.y+h.h/2)end
  local sizes=before and {{972,1536,1},{2160,3414,1}} or {
    {480,800,1},{972,1536,1},{1080,2400,1},{1536,1160,1},{800,480,1},
    {2160,3414,1},{972,1536,2},{972,1536,3},{1080,2400,3},{1536,1160,2}}
  local function draw(size,factor,page,save)
    local pw,ph,dpi=unpack(size);local w,h=pw/dpi,ph/dpi
    love.window.setMode(pw,ph,{resizable=true})
    g.getDimensions=function()return w,h end
    g.getWidth=function()return w end;g.getHeight=function()return h end
    g.getPixelDimensions=function()return pw,ph end
    love.window.getSafeArea=function()return 0,0,w,h end
    imp._settings=nil;imp._ui.options=SaveData.defaultOptions();imp._ui.options.jpDialogScale=factor
    imp._ui.page=page;imp._ui.sheet=1;imp._ui.focus=1
    if page=="settings-detail" then
      imp:_openSettings();imp._settings.opts.jpDialogScale=factor
      imp._ui.page=page;imp._ui.settingsSection=2
    end
    local c=g.newCanvas(w,h,{dpiscale=dpi});g.setCanvas(c);imp:draw();g.setCanvas()
    local l,p=imp._ui.layout,imp._ui.panel
    local sample={width=pw,height=ph,dpi=dpi,factor=factor,page=page,fontPx=l.scale*8,
      x=l.x*dpi,y=l.y*dpi,panelWidth=l.w*dpi,panelHeight=l.h*dpi,columns=p.columns,
      visibleRows=math.min(#(imp._ui.rows or{}),imp._ui.pageRows),pages=imp._ui.sheets}
    report.samples[#report.samples+1]=sample
    local name=page.."-"..pw.."x"..ph.."-dpi"..dpi.."-size"..factor..(not imp.ready.red_jp and "-empty" or "")
    if save then
      local pixels=c:newImageData()
      check(pixels:getWidth()==pw and pixels:getHeight()==ph,"actual physical framebuffer size "..name)
      write(name..".png",pixels:encode("png"):getString())
    end
    check(imp._ui.options.jpDialogScale==factor,"saved size preference is not rewritten")
    check(table.concat(imp._ui.credit.lines)==View.CREDIT,"complete attribution")
    if not before then
      local short=math.min(pw,ph)
      check(sample.fontPx/short>=0.023 and sample.fontPx/short<=0.041,"readable glyph proportion "..name)
      if factor==1 then check(sample.fontPx/short>=0.026,"standard reading size "..name)end
      check(sample.panelWidth/pw>=.86 and sample.panelWidth/pw<=.97,"panel uses useful window width "..name)
      check(sample.x>=0 and sample.y>=0 and sample.x+sample.panelWidth<=pw+.01
        and sample.y+sample.panelHeight<=ph+.01,"panel remains inside display "..name)
      if page=="games" then
        if ph>pw then
          check(p.columns==1,"portrait has one clear controller column "..name)
          check(sample.panelHeight/ph>=.55,"portrait home avoids excessive blank space "..name)
        end
        check(imp._ui.sheets==1,"all main routes visible "..name)
        local ids={"rom","game-select","home-mods","mod-list","mod-import","home-settings","home-about","home-more"}
        if imp.ready.red_jp then ids[#ids+1]="play";ids[#ids+1]="saves"end
        for _,id in ipairs(ids)do
          check(hit(id)~=nil,"visible main route "..id.." "..name)
        end
      end
    end
    c:release()
    return sample
  end
  for _,size in ipairs(sizes)do
    for _,factor in ipairs({.75,.5,1})do
      draw(size,factor,"games",true)
      draw(size,factor,"settings-detail",factor==.75 or factor==1)
      imp.mods={};for i=1,50 do imp.mods[i]={id="qa"..i,name="TEST MOD "..i,enabled=true,manifest={}}end
      draw(size,factor,"mod-list",factor==.75 or factor==1)
    end
  end
  if not before then
    imp.ready.red_jp=nil
    draw({972,1536,1},1,"games",true)
    draw({2160,3414,1},1,"games",true)
    imp.ready.red_jp=true
    -- Exercise variable-height pages through real input, retaining focus across
    -- DPI changes and never activating a setting while scrolling.
    local function redraw()
      local w,h=g.getDimensions();local pw=g.getPixelDimensions()
      local c=g.newCanvas(w,h,{dpiscale=pw/w});g.setCanvas(c);imp:draw();g.setCanvas();c:release()
    end
    draw({972,1536,3},.75,"mod-list",false)
    local last=imp._ui.pageRanges[1].last
    for _=1,last do imp:keypressed("down")end;redraw()
    check(imp._ui.sheet==2 and hit("mod-qa"..imp._ui.focus),"D-pad reveals selected MOD on the next page")
    imp:keypressed("pageup");redraw()
    check(imp._ui.sheet==1 and imp._ui.focus==1,"page up focuses first visible MOD")
    click("page-next");redraw()
    check(imp._ui.sheet==2 and hit("mod-qa"..imp._ui.focus),"physical page hit preserves visible focus at DPI 3")
    imp:keypressed("acback");redraw();check(imp._ui.page=="mods","MOD list Back keeps hierarchy")
    draw({972,1536,1},.75,"settings-detail",false)
    local calls=0
    local items={}
    for i=1,60 do items[i]={label=i%7==0 and "LONG THIRD PARTY SETTING LABEL THAT WRAPS" or "OPTION "..i,
      value=function()return "ON"end,step=function()calls=calls+1;return true end}end
    imp._settings.sections[2].rows=items;redraw()
    check(imp._ui.pageRows>=15,"one long setting does not inflate every row")
    local total=0
    for _,range in ipairs(imp._ui.pageRanges)do total=total+range.last-range.first+1 end
    check(total==60,"all variable-height settings appear in exactly one page range")
    last=imp._ui.pageRanges[1].last
    for _=1,last do imp:keypressed("down")end;redraw()
    check(imp._ui.sheet==2 and hit("setting-2-"..imp._ui.focus),"setting selection automatically crosses variable-height pages")
    check(calls==0,"paging never changes a setting")
    imp:keypressed("right");check(calls==1,"selected setting changes exactly once")
    local back=assert(hit("page-back"))
    for _,h in ipairs(imp._ui.hits)do if h.row then check(h.y+h.h<=back.y,"last settings hit clears Back")end end
    imp:keypressed("acback");redraw();check(imp._ui.page=="settings","settings detail Back retains categories")
    imp:keypressed("acback");redraw();check(imp._ui.page=="games","outer Back returns home")

    -- Real Font compositing from independently drawn, cartridge-shaped kana.
    -- Test files contain redistributable Misaki glyphs, never extracted ROM art.
    local data={constants={language="ja"}}
    require("tests.jp_battle_bitmap_font")(data)
    local fs=love.filesystem
    fs.createDirectory("red_jp/assets/generated/fonts")
    fs.write("red_jp/assets/generated/fonts/font.png",fs.read("fixture/font.png"))
    fs.write("red_jp/assets/generated/fonts/font_extra.png",fs.read("fixture/extra.png"))
    fs.write("red_jp/rom-cache.complete","readable-ui-independent-kana")
    local native=draw({972,1536,1},.75,"settings-detail",false)
    check(imp._ui.layout.font=="cache","launcher draws through real private cached font")
    local ow={player={}}
    local game={data=data,overworld=ow,stack={top=function()return ow end},save={options=SaveData.defaultOptions()},
      quickSaveAllowed=function()return true end,applyOptions=function()end,writeOptions=function()return true end}
    require("src.core.GameVersion").set("red_jp")
    game.save.options.jpDialogScale=1
    local menu=Session.new(game)
    for _,size in ipairs({{972,1536,1},{1536,1160,1},{972,1536,3}})do
      -- Configure physical units with the same genuine high-DPI canvas path.
      draw(size,1,"settings-detail",false)
      local pw,ph,dpi=unpack(size);local w,h=pw/dpi,ph/dpi
      menu:open("settings-detail",2)
      local c=g.newCanvas(w,h,{dpiscale=dpi});g.setCanvas(c);g.clear(.5,.5,.5,1);menu:draw();g.setCanvas()
      local l,v=menu.geometry,menu.geometry.viewport
      check(v.font=="game","session draws real native Font renderer")
      check(v.scale*8/math.min(pw,ph)>=.026,"session default has readable physical glyphs")
      check(l.last-l.first+1>=9,"native session display settings retain dense visible rows")
      for _,target in ipairs(l.hits)do check(target.y>=0 and target.y+target.h<=v.height,"native session hit fits window")end
      write("session-native-"..pw.."x"..ph.."-dpi"..dpi..".png",c:newImageData():encode("png"):getString());c:release()
      menu:keypressed("escape");check(menu.page=="settings","native session Back reaches categories")
    end
    -- At every native row, independently render the actual glyphs and inspect
    -- their opaque pixel bounds. Voiced marks must stay inside that row's
    -- allocation and neither cross a neighbor nor a frame separator.
    local Classic=require("src.ui.ClassicUI")
    menu:open("settings-detail",2)
    local l=menu:layout()
    local entries={}
    for _,e in ipairs(l.entries)do entries[#entries+1]=e end
    entries[#entries+1]={row={id="footer-back"},label={"もどる"},labelX=16,labelW=l.back.w,
      y=l.back.y,pad=l.footerY-l.back.y,line=16,h=l.back.h}
    for _,e in ipairs(entries)do
      local v=l.viewport;local c=g.newCanvas(v.width,v.height,{dpiscale=1})
      g.setCanvas(c);g.clear(0,0,0,0)
      local layout={x=0,y=0,sx=1,sy=1,scale=1,width=v.width,height=v.height}
      Classic.begin(game,{layout=layout,paper={0,0,0,0}})
      for n,text in ipairs(e.label)do Classic.text(text,e.labelX,e.y+e.pad+(n-1)*e.line,{width=e.labelW})end
      if e.value then
        for n,text in ipairs(e.value)do Classic.text(text,e.valueX+l.tap,e.y+e.pad+(n-1)*e.line,{width=e.valueW-2*l.tap})end
      end
      Classic.finish();g.setCanvas()
      local pixels=c:newImageData();local bounded=true
      for y=0,v.height-1 do if y<e.y or y>=e.y+e.h then
        for x=16,v.width-17 do local _,_,_,a=pixels:getPixel(x,y);if a>0 then bounded=false;break end end
      end end
      check(bounded,"native accent pixels remain within row "..e.row.id);c:release()
    end
    local expanded=false;local custom={}
    for i=1,60 do local index=i
      custom[i]={id="reflow-"..i,label="OPTION "..i,value=function()
        return expanded and index==menu.focus and "A VALUE WHICH NOW WRAPS OVER MANY LINES" or "ON"end,
        step=function()expanded=true;return true end}
    end
    menu.model.sections[2].rows=custom;menu:open("settings-detail",2)
    l=menu:layout();menu.focus=l.pageRanges[1].last
    menu:keypressed("right");l=menu:layout()
    check(menu.focus>=l.first and menu.focus<=l.last,"growing selected value keeps focus visible after reflow")
    imp.mods={};draw({972,1536,1},1,"mod-list",false);redraw();imp:keypressed("pagedown");redraw()
    check(imp._ui.sheet==1 and #imp._ui.rows==0,"empty MOD list redraw and paging stay stable")
  end
  report.checks=checks;report.primaryFactor=1;write("metrics.json",Json.encode(report))
  print("RESULT "..checks.." checks passed")
end
function love.load()
  io.stdout:setvbuf("no")
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
