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
  local Options=require('src.ui.OptionsMenu')
  local all=Options.new(Game)
  local Catalog=require('src.ui.JapaneseSettingsCatalog')
  for _,size in ipairs({{480,800},{800,480}})do
    local w,h=size[1],size[2];love.window.setMode(w,h,{vsync=0});Viewport.reset()
    for _,group in ipairs({'battleEffects','fieldEffects'})do
      local rows,section,index={},nil,nil
      for _,r in ipairs(all.rows)do if Catalog.group(r.id)==group then rows[#rows+1]=r end end
      for i,s in ipairs(imp._settings.sections)do if s.id==group then section,index=s,i end end
      check(#rows==5 and section and #section.rows==5,group..' contains exactly five independent controls')
      local native=Options.new(Game,{rows=rows,title=section.title})
      for _,mode in ipairs({'home','game'})do
        local canvas=g.newCanvas(w,h,{dpiscale=1});g.setCanvas(canvas);g.clear(.13,.16,.20,1)
        if mode=='home' then
          showTouch=false;imp._ui.page='settings-detail';imp._ui.settingsSection=index;imp._ui.sheet=1;imp._ui.focus=1
          imp:draw()
          check(imp._ui.rows[1].optionId==rows[1].id,group..' launcher opens first effect')
          for i=1,5 do imp._ui.focus=i;imp:draw();check(imp._ui.rows[i].optionId==rows[i].id,group..' launcher exposes '..rows[i].id)end
        else
          showTouch=true;Stack.states={ow};Stack:push(native)
          for i=1,5 do
            native.index=i;g.setCanvas(canvas);Viewport.setOutputTarget(canvas);Game:draw();Viewport.setOutputTarget(nil)
            local l=native.windowPanel.geometry
            check(i>=l.first and i<=l.last,group..' selected effect remains visible '..rows[i].id)
            for n=l.first,l.last do check(l.entries[n].y+l.entries[n].h<=l.back.y+.01,group..' effect row clears footer')end
          end
        end
        g.setCanvas();write(mode..'-'..group..'-'..w..'x'..h..'.png',canvas:newImageData():encode('png'):getString());canvas:release()
      end
    end
  end
  write('results.json',Json.encode({checks=checks,romUsed=false,actualGL=true,groups=2,effects=10}))
  print('PASS '..checks..' effect UI GL checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then love.graphics.setCanvas();print(err);love.event.quit(1)else love.event.quit(0)end
end
