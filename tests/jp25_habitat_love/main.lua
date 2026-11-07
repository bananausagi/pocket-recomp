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
  local fixture=require('tests.jp25_habitat_fixture')()
  for _,key in ipairs({'constants','maps','tilesets','encounters','field','pokemon','strings'}) do data[key]=fixture.data[key] end
  Game.save=fixture.save
  Game.save.jpHabitatVisited={ROUTE_1=true,ROUTE_2=true,ROUTE_3=true,MT_MOON_1F=true,MT_MOON_B1F=true}
  ow.map={id='ROUTE_3',def=data.maps.ROUTE_3}
  local Habitat=require('src.ui.JapaneseHabitatList')
  local Input=require('src.core.Input');Input:init();Game.input=Input
  local menu=Habitat.new(Game);Stack:push(menu)

  require('src.render.PaletteFX').setMode('classic')
  require('src.render.DotMatrix').setLevel(0)
  local Touch=require('src.core.TouchControls');Touch:init();Touch.active=true;Touch.visible=function()return true end
  local Layout=require('src.ui.GameUILayout');local Viewport=require('src.render.GameViewport')
  local Banner=require('src.ui.JapaneseAreaBanner')
  local function overlap(a,b)return a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y end
  local function activate(name)
    Game._jpAreaBanner={data=data,save=Game.save,mapId=ow.map.id,eligible=true,name=name,
      active={name=name,time=.3,presented=true}}
  end

  local records={}
  local function press(key)
    Input:sourcePress(key,'habitat-qa');Input:step();menu:update()
    Input:sourceRelease(key,'habitat-qa');Input:step();menu:update()
  end
  local function sample(label,w,h)
    love.window.setMode(w,h,{vsync=0});love.window.getSafeArea=function()return 2,2,w-4,h-4 end
    local canvas=g.newCanvas(w,h,{dpiscale=1});Viewport.setOutputTarget(canvas)
    g.setCanvas(canvas);g.clear(.13,.16,.20,1);Game:draw();g.setCanvas()
    local l=menu:layout();local m=l.view
    check(m.x>=m.rect.x and m.y>=m.rect.y and m.x+m.w<=m.rect.x+m.rect.w+.001
      and m.y+m.h<=m.rect.y+m.rect.h+.001,label..' contained by touch-safe viewport')
    for i,b in ipairs(Layout.touchBounds())do check(not overlap(m,b),label..' avoids touch artwork '..i)end
    check(l.last-l.first+1<=l.rows and l.body+l.rows*l.rowHeight<=l.footer,label..' row capacity avoids footer')
    if w>h then check(l.rows>=7,label..' landscape provides at least seven rows')end
    check(m.scale>=1 and m.scale==math.floor(m.scale),label..' whole physical pixels')
    local pixels=canvas:newImageData()
    write(label..'.png',pixels:encode('png'):getString())
    local rr,gg,bb=pixels:getPixel(math.floor(m.x+m.w*.5),math.floor(m.y+7*m.sy))
    check(rr>.98 and gg>.98 and bb>.98,label..' native white paper')
    local edge={pixels:getPixel(math.floor(m.rect.x+1),math.floor(m.rect.y+1))}
    check(edge[2]>edge[1],label..' field remains behind floating panel')
    records[#records+1]={label=label,window={w,h},panel={x=m.x,y=m.y,w=m.w,h=m.h},native={l.width,l.height},rows=l.rows}
    Viewport.setOutputTarget(nil);canvas:release()
  end
  sample('portrait-480x800',480,800)
  sample('portrait-972x1536',972,1536)
  sample('landscape-1536x972',1536,972)
  check(menu.areas[menu.areaIndex].name=='3ばんどうろ','actual menu opens current region')
  for i=1,16 do press('down')end
  check(menu.index==17,'controller advances beyond first page')
  sample('scrolled-landscape',1536,972)
  check(menu.scroll>0 and menu.geometry.last>=17,'controller scroll keeps selected species visible')
  local at=menu.areaIndex;press('left');check(menu.areaIndex~=at,'left cycles regions')
  local method=menu.method;press('a');check(menu.method~=method,'A cycles encounter-method filter')
  press('select');check(menu.areaMode,'SELECT opens visited-area chooser')
  sample('area-picker-972x1536',972,1536)
  press('down');local chosen=menu.areaIndex;press('a')
  check(not menu.areaMode and menu.areaIndex==chosen,'A opens chosen visited region')
  press('select');press('b');check(not menu.areaMode and Stack:top()==menu,'B from chooser returns to habitat list')
  press('b');check(Stack:top()==ow,'B returns to parent without closing game')
  write('results.json',Json.encode({checks=checks,records=records,romUsed=false,
    runtime='actual Game.draw / JapaneseHabitatList / ClassicUI / Font / GameUILayout / TouchControls',
    font='bundled Misaki8x8 at cartridge mapping, authored border tiles',terrain='authored geometric fixture'}))
  print('PASS '..checks..' habitat GL checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then love.graphics.setCanvas();print(err);love.event.quit(1)else love.event.quit(0)end
end
