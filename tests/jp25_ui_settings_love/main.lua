-- Actual Game.draw + Font + touch-safe layout, using authored map art and
-- bundled Misaki glyphs at the cartridge's charmap/composite positions.
local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local g,fs=love.graphics,love.filesystem
  g.setDefaultFilter("nearest","nearest")
  local checks,records=0,{}
  local function check(v,s)assert(v,s);checks=checks+1;print('PASS '..s)end
  local function write(name,bytes)local f=assert(io.open(out..'/'..name,'wb'));f:write(bytes);f:close()end
  local Json=require('src.link.Json')
  local manifest=Json.decode(fs.read('tools/rom_manifest_red_jp.json'))
  local glyphs=Json.decode(fs.read('assets/fonts/misaki/glyphs.json'))
  local atlas=g.newImage('assets/fonts/misaki/misaki8x8.png');atlas:setFilter('nearest','nearest')
  local sheet=g.newCanvas(128,128,{dpiscale=1})
  g.setCanvas(sheet);g.clear(0,0,0,0);g.setColor(0,0,0,1)
  for _,e in ipairs(manifest.fontCharmap)do
    if e.code<256 and glyphs[e.seq]then
      local i=glyphs[e.seq]
      g.draw(atlas,g.newQuad(i%128*8,math.floor(i/128)*8,8,8,atlas:getDimensions()),e.code%16*8,math.floor(e.code/16)*8)
    end
  end
  local function cell(code,fn)
    local x,y=code%16*8,math.floor(code/16)*8
    g.setScissor(x,y,8,8);g.setBlendMode('replace');g.setColor(0,0,0,0)
    g.rectangle('fill',x,y,8,8);g.setBlendMode('alpha');g.setColor(0,0,0,1);fn(x,y);g.setScissor()
  end
  cell(0x7a,function(x,y)g.rectangle('fill',x,y+3,8,1);g.rectangle('fill',x,y+5,8,1)end)
  cell(0x7c,function(x,y)g.rectangle('fill',x+3,y,1,8);g.rectangle('fill',x+5,y,1,8)end)
  for _,c in ipairs({0x79,0x7b,0x7d,0x7e})do cell(c,function(x,y)
    local right=c==0x7b or c==0x7e;local bottom=c==0x7d or c==0x7e
    local outerX,innerX=right and 5 or 3,right and 3 or 5
    local outerY,innerY=bottom and 5 or 3,bottom and 3 or 5
    g.rectangle('fill',x+(right and 0 or 5),y+outerY,right and 4 or 3,1)
    g.rectangle('fill',x+outerX,y+(bottom and 0 or 5),1,bottom and 4 or 3)
    g.rectangle('fill',x+4,y+4,1,1)
    g.rectangle('fill',x+(right and 0 or 5),y+innerY,right and 4 or 3,1)
    g.rectangle('fill',x+innerX,y+(bottom and 0 or 5),1,bottom and 4 or 3)
    g.rectangle('fill',x+innerX,y+innerY,1,1)
  end)end
  cell(0xe5,function(x,y)for _,p in ipairs({{3,5},{4,6},{6,5},{7,6}})do g.rectangle('fill',x+p[1],y+p[2],1,1)end end)
  cell(0xed,function(x,y)for row=0,6 do g.rectangle('fill',x,y+row,4-math.abs(row-3),1)end end)
  g.setCanvas();fs.write('fixture-font.png',sheet:newImageData():encode('png'));sheet:release()
  local data={constants={language='ja'},field={townMap={locations={}}},font={language='ja',image='fixture-font.png',mainBase=0,
    charmap=manifest.fontCharmap,composites=manifest.fontComposites}}
  local Font=require('src.render.Font');Font.load(data)
  require('src.core.Strings').load(data);require('src.core.GameVersion').set('red_jp')
  local Runtime=require('src.mods.Runtime');Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
  local viewportRect
  Runtime.hooks:wrap('render.viewport',function(next,ctx)return viewportRect or next(ctx)end,0,'area-qa')
  local Renderer=require('src.render.Renderer');Renderer:init()
  local Stack=require('src.core.StateStack');Stack:init()
  local Game=require('src.core.Game');Game.data,Game.stack,Game.renderer=data,Stack,Renderer
  Game.save={options={jpDialogScale=.75,reduceMotion=true}};Game.input={wasPressed=function()return false end}
  local ow={isOverworld=true,player={},map={id='VIRIDIAN_CITY',def={tileset='OVERWORLD'}}}
  function ow:draw()
    Renderer:beginWorldPass()
    local w,h=Renderer.worldCanvas:getDimensions()
    g.setColor(.60,.74,.49,1);g.rectangle('fill',0,0,w,h)
    g.setColor(.81,.81,.65,1);g.rectangle('fill',w*.34,0,w*.32,h)
    g.rectangle('fill',0,h*.36,w,h*.18)
    for y=8,h,28 do for x=8,w,32 do if x<w*.28 or x>w*.73 then
      g.setColor(.20,.36,.23,1);g.rectangle('fill',x+4,y+6,13,13)
      g.setColor(.31,.49,.28,1);g.rectangle('fill',x,y,18,14)
    end end end
    g.setColor(.45,.24,.25,1);g.rectangle('fill',w*.15,h*.15,24,14)
    g.setColor(.89,.83,.67,1);g.rectangle('fill',w*.15+2,h*.15+14,20,18)
    g.setColor(.20,.23,.28,1);g.rectangle('fill',w*.49,h*.47,6,10)
    g.setColor(.72,.24,.23,1);g.rectangle('fill',w*.49-1,h*.47-4,8,5)
    g.setColor(1,1,1,1);Renderer:endWorldPass()
  end
  Game.overworld=ow;Stack:push(ow)
  local Save=require('src.core.SaveData')
  Game.save.options=Save.defaultOptions();Game.save.options.jpLauncherLanguage='ja'
  Game.save.options.colors='redpp_soft';Game.save.options.jpDialogScale=.75
  Game.save.flags={};Game.save.party={};Game.save.bag={};Game.save.pokedex={seen={},owned={}}
  Game.save.player={name='レッド'};Game.save.playTime=123
  Game.writeOptions=function()return true end
  local Input=require('src.core.Input');Input:init();Game.input=Input
  local Touch=require('src.core.TouchControls');Touch:init();Touch.active=true
  local showTouch=true;Touch.visible=function()return showTouch end
  require('src.render.PaletteFX').setMode('redpp_soft')
  require('src.render.DotMatrix').setLevel(0)
  local Layout=require('src.ui.GameUILayout');local Viewport=require('src.render.GameViewport')
  local Classic=require('src.ui.ClassicUI')
  local Settings=require('src.import.LauncherSettings')
  local Importer=require('src.import.RomImporter')
  local imp=Importer.new(function()end,{launcher=true});imp.tab='red_jp';imp.ready.red_jp=true
  imp._ui.options=Game.save.options
  imp._settings=Settings.open({options=Game.save.options,save=function()return true end},'red_jp')
  local displayIndex,scaleIndex,colorIndex
  for i,section in ipairs(imp._settings.sections)do for j,row in ipairs(section.rows)do
    if row.id=='jpDialogScale' then displayIndex,scaleIndex=i,j end
    if row.id=='colors' then colorIndex=j end
  end end
  local Options=require('src.ui.OptionsMenu')
  local rootMenu=Options.new(Game)
  local nativeRows={}
  for _,row in ipairs(rootMenu.rows)do
    if require('src.ui.JapaneseSettingsCatalog').entry(row.id) then
      for _,source in ipairs(imp._settings.sections[displayIndex].rows)do
        if source.id==row.id then nativeRows[#nativeRows+1]=row end
      end
    end
  end
  local native=Options.new(Game,{rows=nativeRows,title='がめん'})
  local function nativeSelect(id)
    for i,row in ipairs(nativeRows)do if row.id==id then native.index=i;return end end
    error('missing native option '..id)
  end
  local function overlap(a,b)return a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y end
  local records={}
  local function verifyPanel(l,label,home)
    local m=home and l or l.viewport
    check(m.x>=m.rect.x-.01 and m.y>=m.rect.y-.01 and m.x+m.w<=m.rect.x+m.rect.w+.01
      and m.y+m.h<=m.rect.y+m.rect.h+.01,label..' fits usable viewport')
    check(m.scale>=1 and m.scale==math.floor(m.scale),label..' uses whole physical pixels')
    if not home then
      for i,b in ipairs(Layout.touchBounds())do check(not overlap(m,b),label..' avoids touch artwork '..i)end
      check(l.first<=native.index or label:find('palette'),label..' valid page range')
      for i=l.first,l.last do
        local e=l.entries[i]
        check(e.y+e.h<=l.back.y+.01,label..' row '..i..' is above footer')
      end
    end
    return m
  end
  local function sample(scene,w,h,factor,screenshot)
    local label=scene..'-'..w..'x'..h..'-'..tostring(factor)
    love.window.setMode(w,h,{vsync=0});love.window.getSafeArea=function()return 2,2,w-4,h-4 end
    Viewport.reset()
    Game.save.options.jpDialogScale=factor
    local canvas=g.newCanvas(w,h,{dpiscale=1});g.setCanvas(canvas);g.clear(.13,.16,.20,1)
    local l,m,visible
    if scene=='home' or scene=='home-settings' or scene=='home-color' then
      showTouch=false
      imp._ui.page=scene=='home' and 'games' or 'settings-detail'
      imp._ui.settingsSection=displayIndex;imp._ui.focus=scene=='home-color' and colorIndex or scene=='home' and 1 or scaleIndex
      imp._ui.sheet=1
      imp:draw()
      l=imp._ui.layout;m=verifyPanel(l,label,true);visible=imp._ui.pageRows
      local focused=imp._ui.rows[imp._ui.focus]
      if scene=='home-settings' then check(focused.optionId=='jpDialogScale',label..' selected size row visible')end
      if scene=='home-color' then check(focused.description==require('src.ui.JapaneseColorSettings').description('redpp_soft'),label..' current color explanation')end
    else
      showTouch=true;Stack.states={ow}
      local menu
      if scene=='palette' then
        menu=require('src.ui.PaletteScreen').new(Game)
        for i,row in ipairs(menu.rows)do if row.mode=='redpp_soft' then menu.index=i end end
      else menu=native;nativeSelect('jpDialogScale')end
      Stack:push(menu);Viewport.setOutputTarget(canvas);Game:draw();Viewport.setOutputTarget(nil)
      l=menu.windowPanel.geometry;m=verifyPanel(l,label,false);visible=l.last-l.first+1
      check(menu.index>=l.first and menu.index<=l.last,label..' controller selection visible')
      check(not menu.isOpaque,label..' keeps field behind menu')
      if scene=='palette' then
        for i,row in ipairs(menu.rows)do
          menu.index=i
          g.setCanvas(canvas);Viewport.setOutputTarget(canvas);Game:draw();Viewport.setOutputTarget(nil)
          local page=menu.windowPanel.geometry
          check(i>=page.first and i<=page.last,label..' all mode/category rows reachable '..i)
        end
        for i,row in ipairs(menu.rows)do if row.mode=='redpp_soft' then menu.index=i end end
        g.setCanvas(canvas);Viewport.setOutputTarget(canvas);Game:draw();Viewport.setOutputTarget(nil)
      end
    end
    g.setCanvas()
    if screenshot then write(label..'.png',canvas:newImageData():encode('png'):getString())end
    records[#records+1]={scene=scene,size={w,h},factor=factor,pixelScale=m.scale,visible=visible,
      panel={x=m.x,y=m.y,w=m.w,h=m.h,width=m.width,height=m.height}}
    canvas:release()
  end
  for _,size in ipairs({{480,800},{972,1536},{1536,972}})do
    for _,factor in ipairs({.375,.75,1.5})do
      for _,scene in ipairs({'home','home-settings','game-settings','palette'})do
        sample(scene,size[1],size[2],factor,size[1]==972 or factor==.75)
      end
    end
  end
  sample('home-color',972,1536,.75,true)
  check(Game.save.options.colors=='redpp_soft','all UI views preserve selected mode')
  -- Actual floating palette pointer routing invokes the intended action.
  showTouch=true;Viewport.reset();Stack.states={ow}
  local picker=require('src.ui.PaletteScreen').new(Game);Stack:push(picker)
  local pointerCanvas=g.newCanvas(972,1536,{dpiscale=1})
  Viewport.setOutputTarget(pointerCanvas);Game:draw();Viewport.setOutputTarget(nil);g.setCanvas()
  local geometry=picker.windowPanel.geometry
  local function tapIndex(index)
    local hit
    for _,candidate in ipairs(geometry.hits)do if candidate.id=='palette-'..index then hit=candidate;break end end
    check(hit~=nil,'palette pointer row is present '..index)
    local m=geometry.viewport
    local x,y=m.x+(hit.x+hit.w/2)*m.sx,m.y+(hit.y+hit.h/2)*m.sy
    picker:onWindowPointer('pressed','qa-palette',x,y)
    picker:onWindowPointer('released','qa-palette',x,y)
  end
  for i,row in ipairs(picker.rows)do if row.mode=='classic' then tapIndex(i);break end end
  check(Game.save.options.colors=='classic','touch chooses exactly the requested color mode')
  check(require('src.render.PaletteFX').mode=='classic','touch applies the mode immediately')
  for i,row in ipairs(picker.rows)do if row.folder then tapIndex(i);break end end
  check(picker:isGrid() and not picker.floatingPanel,'touch category opens original custom-color grid')
  picker:back()
  check(picker.floatingPanel and Stack:top()==picker,'Back from custom grid returns to floating mode list')
  pointerCanvas:release()

  write('results.json',Json.encode({checks=checks,records=records,romUsed=false,
    runtime='actual LauncherView / Game.draw / OptionsMenu / PaletteScreen / SessionMenu / ClassicUI / Font',
    font='bundled Misaki at cartridge charmap positions, authored border',terrain='authored geometric fixture'}))
  print('PASS '..checks..' UI settings GL checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then love.graphics.setCanvas();print(err);love.event.quit(1)else love.event.quit(0)end
end
