-- No ROM: readiness is a fixture flag; completion uses the real launch callback.
local function run()
  local root,out=assert(os.getenv('JP_HOME_ROOT')),assert(os.getenv('JP_HOME_OUT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local before=os.getenv('JP_HOME_BEFORE')=='1'
  local Importer=require('src.import.RomImporter')
  local View=require('src.import.LauncherView')
  local SaveData=require('src.core.SaveData')
  local Json=require('src.link.Json')
  local g=love.graphics
  local checks,plays,imports=0,{},{}
  local report={romFree=true,before=before,samples={}}
  local function check(ok,label)assert(ok,label);checks=checks+1 end
  local function write(name,bytes)local f=assert(io.open(out..'/'..name,'wb'));f:write(bytes);f:close()end
  local imp=Importer.new(function(id)plays[#plays+1]=id end,{launcher=true})
  imp.choose=function(_,id)imports[#imports+1]=id end
  local function hit(id)for _,h in ipairs(imp._ui.hits)do if h.id==id then return h end end end
  local function click(id)
    local h=assert(hit(id),'missing hit '..id)
    View.clickAt(imp,h.x+h.w/2,h.y+h.h/2)
  end
  local function reset(ready,language)
    imp.ready={};if ready then imp.ready.red_jp=true end
    imp.tab='red_jp';imp.workState=nil;imp._settings=nil
    imp._ui.page='games';imp._ui.focus=1;imp._ui.sheet=1
    imp._ui.options=SaveData.defaultOptions();imp._ui.options.jpLauncherLanguage=language
  end
  local function draw(size,name)
    local pw,ph,dpi=size[1],size[2],size[3]or 1;local w,h=pw/dpi,ph/dpi
    love.window.setMode(pw,ph,{resizable=true})
    g.getDimensions=function()return w,h end
    g.getWidth=function()return w end;g.getHeight=function()return h end
    g.getPixelDimensions=function()return pw,ph end
    love.window.getSafeArea=function()return 0,0,w,h end
    local c=g.newCanvas(w,h,{dpiscale=dpi});g.setCanvas(c);imp:draw();g.setCanvas()
    local ui,p,l=imp._ui,imp._ui.panel,imp._ui.layout
    check(table.concat(ui.credit.lines)==View.CREDIT,'full attribution remains visible')
    check(l.x>=0 and l.y>=0 and l.x+l.w<=w+.01 and l.y+l.h<=h+.01,'panel inside physical window')
    check(l.scale*8/math.min(pw,ph)>=.026,'standard glyphs remain readable')
    if ui.page=='games'and not before then
      check(ui.sheets==1,'home actions visible together '..tostring(name))
      local main=assert(hit(imp.ready[imp.tab]and 'play'or 'rom'))
      local secondary=assert(hit('game-select'))
      check(main.y+main.h<secondary.y,'primary action has its own separated row')
      check(main.w>=l.w*.70,'primary hit uses most of panel width')
      check(ui.rows[1].id==main.id,'initial controller action is primary')
      for _,id in ipairs({'rom','game-select','home-mods','mod-list','mod-import','mod-discover','home-settings','home-about','home-more'})do
        check(hit(id)~=nil,'existing management route visible '..id)
      end
      for _,target in ipairs(ui.hits)do
        check(target.x>=l.x and target.y>=l.y and target.x+target.w<=l.x+l.w+.01
          and target.y+target.h<=l.y+l.h+.01,'hit stays inside panel '..target.id)
      end
    end
    if name then
      local pixels=c:newImageData();write(name..'.png',pixels:encode('png'):getString())
      report.samples[#report.samples+1]={name=name,width=pw,height=ph,dpi=dpi,
        fontPx=l.scale*8,panelWidth=l.w*dpi,panelHeight=l.h*dpi,columns=p.columns,
        rows=#ui.rows,pages=ui.sheets,primaryId=ui.rows[1]and ui.rows[1].id,primaryLabel=ui.rows[1]and ui.rows[1].label}
    end
    c:release()
  end
  local portrait,landscape={972,1536,1},{800,480,1}
  for _,size in ipairs({portrait,landscape,{480,800,1},{1536,1160,1},{2160,3414,3}})do
    for _,ready in ipairs({false,true})do
      reset(ready);draw(size,(ready and 'ready-'or 'empty-')..size[1]..'x'..size[2]..'-dpi'..size[3])
      if not before then
        local primary=imp._ui.rows[1]
        if ready then
          imp:gamepadpressed(nil,'a');check(plays[#plays]=='red_jp','controller A keeps normal selected-version launch callback')
        else
          check(primary.label:find('ROM',1,true)~=nil,'missing ROM primary explains required import')
          imp:keypressed('return');check(imports[#imports]=='red_jp','Enter opens import for selected version')
          check(not hit('play'),'missing ROM never exposes launch action')
        end
      end
    end
  end
  if not before then
    reset(true);draw(landscape)
    imp:gamepadpressed(nil,'dpdown');check(imp._ui.rows[imp._ui.focus].id=='game-select','down reaches first management action')
    imp:gamepadpressed(nil,'dpright');check(imp._ui.rows[imp._ui.focus].id=='rom','right reaches adjacent management action')
    imp:gamepadpressed(nil,'dpup');check(imp._ui.focus==1,'up returns to featured launch')
    for _,direction in ipairs({'dpleft','dpright','dpdown','dpup'})do
      imp._ui.focus=1;imp:gamepadpressed(nil,direction)
      check(imp._ui.focus>1 and imp._ui.focus<=#imp._ui.rows,'every D-pad direction can leave primary '..direction)
    end
    imp._ui.focus=1
    local reached={};for _=1,#imp._ui.rows do reached[imp._ui.rows[imp._ui.focus].id]=true;imp:keypressed('tab')end
    for _,row in ipairs(imp._ui.rows)do check(reached[row.id],'keyboard traversal retains '..row.id)end
    click('game-select');draw(portrait)
    click('game-blue');draw(portrait,'selected-missing-blue')
    check(imp.tab=='blue'and imp._ui.focus==1 and imp._ui.rows[1].id=='rom','selection resets focus and detects missing selected ROM')
    local count=#plays;imp:keypressed('return')
    check(imports[#imports]=='blue'and #plays==count,'missing selected game imports instead of launching previously ready game')
    imp.ready.blue=true;draw(portrait,'selected-ready-blue')
    imp:keypressed('return');check(plays[#plays]=='blue','ready selection launches its own version')
    check(SaveData.loadOptions().lastVersion=='blue','real launch saves selected ROM identity')
    reset(true);imp.workState='working';imp.progress=.42;draw(portrait,'import-busy')
    count=#plays;local n=#imports
    imp:keypressed('return');click('play')
    check(#plays==count and #imports==n,'busy import blocks keyboard and pointer launch')
    check(imp._ui.rows[1].label=='よみこみを まってね','busy primary communicates unavailable action')
    reset(false);imp.workState='error';imp.detail='Fixture import error';draw(portrait,'import-error')
    check(hit('import-error')and hit('rom')and not hit('play'),'failed import retains retry and error routes')
    reset(true,'en');draw(landscape,'english-ready')
    check(imp._ui.rows[1].label=='PLAY GAME','English label retained')
    reset(false,'en');draw(portrait,'english-empty')
    check(imp._ui.rows[1].label=='IMPORT ROM TO PLAY','English first-import guidance')
    local arranged,edited=0,0
    imp.onEditTouchControls=function()arranged=arranged+1 end
    imp.onOpenSkinStudio=function()edited=edited+1 end
    reset(true);draw(portrait);click('home-settings');draw(portrait)
    local section,arrangeRow,skinRow
    for index,group in ipairs(imp._settings.sections)do
      for n,row in ipairs(group.rows)do
        if row.id=='editTouchControls'then section=index;arrangeRow=n end
        if row.id=='openSkinStudio'then skinRow=n end
      end
    end
    check(section and arrangeRow and skinRow,'home settings retains touch arrangement and skin editor hooks')
    click('settings-section-'..section);draw(portrait)
    click('setting-'..section..'-'..arrangeRow)
    check(arranged==1,'home > settings > controls opens touch layout exactly once')
    draw(portrait);click('home-settings');draw(portrait)
    click('settings-section-'..section);draw(portrait);click('setting-'..section..'-'..skinRow)
    check(edited==1,'home > settings > controls opens skin editor exactly once')
    reset(true);draw(portrait)
    local primary=assert(hit('play'));count=#plays
    View.touchpressed(imp,'tap',primary.x+primary.w-4,primary.y+primary.h/2)
    View.touchreleased(imp,'tap',primary.x+primary.w-4,primary.y+primary.h/2)
    check(#plays==count+1,'far right of full-width primary is actionable')
    -- Exercise actual cached kana composition using an independently drawn
    -- Misaki fixture. No cartridge font or image is distributed with the test.
    require('tests.jp_battle_bitmap_font')({constants={language='ja'}})
    love.filesystem.createDirectory('red_jp/assets/generated/fonts')
    love.filesystem.write('red_jp/assets/generated/fonts/font.png',love.filesystem.read('fixture/font.png'))
    love.filesystem.write('red_jp/assets/generated/fonts/font_extra.png',love.filesystem.read('fixture/extra.png'))
    love.filesystem.write('red_jp/rom-cache.complete','independent-home-font')
    reset(true);draw(portrait,'native-kana-ready')
    check(imp._ui.layout.font=='cache','real cached font renderer used for kana')
  end
  report.checks=checks;write('results.json',Json.encode(report));print('RESULT '..checks..' checks passed')
end
function love.load()
  io.stdout:setvbuf('no')
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
