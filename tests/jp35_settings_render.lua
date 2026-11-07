-- Actual bundled MODs and hooks, real Japanese fonts, launcher and game panels.
-- Imported by the existing isolated display QA boot with JP_QA_SETTINGS35=1.
return function(Game,Renderer,check,write)
  local Catalog=require('src.ui.JapaneseSettingsCatalog')
  local Options=require('src.ui.OptionsMenu')
  local Home=require('src.import.LauncherSettings')
  local Json=require('src.link.Json')
  local Runtime=require('src.mods.Runtime')
  local Append=require('src.ui.JapaneseModSettings')
  local opt=Game.save.options
  opt.jpLauncherLanguage='ja';opt.jpDialogScale=.75
  local saves=0;Game.writeOptions=function()saves=saves+1;return true end
  local model=Home.open({options=opt,save=function()return true end,
    editTouchControls=function()end,openSkinStudio=function()end,
    importSettings=function()end,exportSettings=function()end},'red_jp')
  local all=Options.new(Game)
  local inventory={home={},game={},groups={}}
  local function index(rows,where)
    local result={}
    for _,r in ipairs(rows)do
      local id=Catalog.canonical(r.id)
      check(not result[id],where..' no duplicate '..tostring(id));result[id]=r
    end
    return result
  end
  local hi,gi={},index(all.rows,'game')
  local function collect(sections)
    for _,s in ipairs(sections)do
      for _,r in ipairs(s.rows or {})do
        local id=Catalog.canonical(r.id)
        check(not hi[id],'home no duplicate '..id);hi[id]=r
        inventory.home[#inventory.home+1]={id=id,group=s.id,label=r.label}
      end
      collect(s.children or {})
    end
  end
  collect(model.sections)
  check(not hi.videoMode and not gi.videoMode,'Android hides desktop-only window mode in both menus')
  for _,r in ipairs(all.rows)do local label,help=Catalog.info(r)
    inventory.game[#inventory.game+1]={id=Catalog.canonical(r.id),group=Catalog.group(r.id),label=label,help=help}
  end
  local expected={jpBattleIntro='battleEffects',jpBattleCameraMotion='battleEffects',
    jpBattleSpacing='battleEffects',animations='battleEffects',jpAnalogWalk='controls',
    jpAtmosphere='world',jpFxDensity='world',jpFollower='fieldEffects',jpRulesPreset='game'}
  for _,r in ipairs(require('src.core.JapaneseEffects').rows)do expected[r.id]=r.group end
  for mod,keys in pairs(Catalog.bundled)do for key,group in pairs(keys)do expected[mod..'.'..key]=group end end
  for id,group in pairs(expected)do
    check(hi[id] and gi[id],'both menus expose '..id)
    check(Catalog.group(id)==group,id..' belongs to '..group)
    local label=Catalog.info(gi[id]);check(hi[id].label==label,id..' same caption in both menus')
  end
  for _,id in ipairs({'shiny_pokemon_open','controller_rumble_open','ACCESS_PC_ANYWHERE.open'})do
    check(not gi[id],'duplicate category opener removed '..id)
  end
  -- Each new leaf must still use the installed MOD's own persisted value,
  -- cache-refresh event, and callback. Checking all leaves catches loop capture.
  local events={};Game.mods.events:on('mod.options_changed',function(p)events[#events+1]=p end,0,'jp35-qa')
  for mod,keys in pairs(Catalog.bundled)do for key in pairs(keys)do
    local id=mod..'.'..key;local row=gi[id]
    local before=row.value(Game);local n=#events
    check(row.step(Game,1)==true,'game callback changes '..id)
    check(#events==n+1 and events[#events].mod==mod and events[#events].key==key,id..' emits its own event once')
    check(Game.mods.modOptions[mod][key]==opt.modOptions[mod][key],id..' runtime and saved values agree')
    check(row.step(Game,-1)==true and row.value(Game)==before,id..' reverse restores prior value')
    local gameValue=opt.modOptions[mod][key]
    check(hi[id].step(1)==true and opt.modOptions[mod][key]~=gameValue,id..' home changes same persisted key')
    check(hi[id].step(-1)==true and opt.modOptions[mod][key]==gameValue,id..' home reverse restores value')
  end end
  local before=Json.encode(opt);Runtime.safeMode=true
  check(gi['running_shoes.fx'].step(Game,1)==false,'safe mode blocks schema writes')
  check(Json.encode(opt)==before,'safe mode retains options');Runtime.safeMode=false
  local partial={mods={optionSchemas={SHINY_POKEMON={Game.mods.optionSchemas.SHINY_POKEMON[1]}}}}
  local rows=Append.append(partial,{{id='shiny_pokemon_open'},{id='external.option',label='External'}})
  check(rows[1].id=='shiny_pokemon_open' and rows[2].id=='external.option','partial schema keeps fallback and unknown extension')
  local replacement={};for _,r in ipairs(all.rows)do
    if not Catalog.canonical(r.id):match('^SHINY_POKEMON%.')then replacement[#replacement+1]=r end
  end
  all.rows=replacement;all:refreshGroups()
  check(index(all.rows,'refreshed')['SHINY_POKEMON.sparkles']~=nil,'MOD visibility rebuild restores organized leaves')
  check(#all.view==9 and #model.sections==9,'all nine settings categories remain reachable')
  opt.jpLauncherLanguage='en';model.refreshLabels()
  check(hi['running_shoes.fx'].label=='RUN FX','English launcher retains author captions')
  opt.jpLauncherLanguage='ja';model.refreshLabels()

  local g=love.graphics
  local imp=require('src.import.RomImporter').new(function()end,{launcher=true})
  imp.tab='red_jp';imp.ready.red_jp=true;imp._settings=model;imp._ui.options=opt
  local Touch=require('src.core.TouchControls');Touch:init();Touch.active=true
  local showTouch=false;Touch.visible=function()return showTouch end
  local Viewport=require('src.render.GameViewport')
  local captures={}
  for _,size in ipairs({{480,800},{800,480}})do
    local w,h=size[1],size[2];love.window.setMode(w,h,{vsync=0});Viewport.reset()
    local canvas=g.newCanvas(w,h,{dpiscale=1})
    local function capture(name,draw)
      g.setCanvas(canvas);g.clear(.20,.29,.23,1);draw();g.setCanvas()
      write(name..'.png',canvas:newImageData():encode('png'):getString());captures[#captures+1]=name
    end
    for i,section in ipairs(model.sections)do
      local group
      for _,r in ipairs(all.view)do if r.id=='group.'..section.id then group=r end end
      check(group~=nil,'game has category '..section.id)
      local native=Options.new(Game,{rows=group.members,title=section.title})
      local suffix=section.id..'-'..w..'x'..h
      local localOrder={};for _,r in ipairs(group.members)do localOrder[#localOrder+1]=Catalog.canonical(r.id) end
      local homeOrder,gameOrder={},{}
      for _,r in ipairs(section.rows)do local id=Catalog.canonical(r.id);if gi[id]then homeOrder[#homeOrder+1]=id end end
      for _,r in ipairs(group.members)do local id=Catalog.canonical(r.id);if hi[id]then gameOrder[#gameOrder+1]=id end end
      check(table.concat(homeOrder,'|')==table.concat(gameOrder,'|'),'shared controls have same order in '..section.id)
      if w==480 then inventory.groups[#inventory.groups+1]={id=section.id,game=localOrder,homeCount=#section.rows}end
      showTouch=false;imp._ui.page='settings-detail';imp._ui.settingsSection=i;imp._ui.sheet=1
      for at=1,#section.rows do
        imp._ui.focus=at
        g.setCanvas(canvas);imp:draw();g.setCanvas()
        check(imp._ui.rows[at] and imp._ui.rows[at].optionId==section.rows[at].id,'home reaches '..section.rows[at].id)
      end
      imp._ui.focus=1;capture('home-'..suffix,function()imp:draw()end)
      showTouch=true
      for at=1,#group.members do
        native.index=at;g.setCanvas(canvas);native:drawWindowOverlay();g.setCanvas()
        local l=native.windowPanel.geometry
        check(at>=l.first and at<=l.last,'game scroll keeps selection visible '..group.members[at].id)
        for n=l.first,l.last do check(l.entries[n].y+l.entries[n].h<=l.back.y+.01,'setting clears footer')end
      end
      native.index=1;capture('game-'..suffix,function()native:drawWindowOverlay()end)
      native.index=#group.members
      capture('game-last-'..suffix,function()native:drawWindowOverlay()end)
    end
    canvas:release()
  end
  inventory.captures=captures;inventory.realBundledSchemas=true;inventory.romUsed=false
  write('settings-inventory.json',Json.encode(inventory))
end
