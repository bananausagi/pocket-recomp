-- Actual Game.draw + move reminder + Font + touch-safe layout, using
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
  cell(0xed,function(x,y)for row=0,6 do g.rectangle('fill',x+1,y+row,4-math.abs(3-row),1)end end)
  g.setCanvas();fs.write('fixture-font.png',sheet:newImageData():encode('png'));sheet:release()
  local data={constants={language='ja'},font={language='ja',image='fixture-font.png',mainBase=0,
    charmap=manifest.fontCharmap,composites=manifest.fontComposites},pokemon={TEST={name='テスト',level1Moves={},learnset={}}},moves={},field={}}
  local names={'なきごえ','たいあたり','あわ','みずでっぽう','かみつく','しっぽをふる','にらみつける','からにこもる','みずでっぽう','ひっかく'}
  for i,name in ipairs(names)do
    local id='TEST'..i;data.moves[id]={name=name,pp=10+i};data.pokemon.TEST.learnset[i]={level=i,move=id}
  end
  data.moves.CUT={name='いあいぎり',pp=30};data.moves.FLY={name='そらをとぶ',pp=15}
  local Font=require('src.render.Font');Font.load(data)
  require('src.core.Strings').load(data);require('src.core.GameVersion').set('red_jp')
  local Runtime=require('src.mods.Runtime');Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
  local Renderer=require('src.render.Renderer');Renderer:init()
  local Stack=require('src.core.StateStack');Stack:init()
  local Game=require('src.core.Game');Game.data,Game.stack,Game.renderer=data,Stack,Renderer
  local mon={species='TEST',level=15,moves={{id='TEST2',pp=5},{id='CUT',pp=6},{id='FLY',pp=7},{id='TEST8',pp=8}}}
  Game.save={options={jpDialogScale=.75,jpMoveReminder=true},party={mon},player={name='テスト'}}
  Game.input={wasPressed=function()return false end,isDown=function()return false end}
  Game.overworld={isOverworld=true,player={}}
  local Touch=require('src.core.TouchControls');Touch:init();Touch.active=true;Touch.visible=function()return true end
  local Viewport=require('src.render.GameViewport')
  local Menu=require('src.ui.JapaneseMoveReminderMenu')
  require('src.render.PaletteFX').setMode('gbc')
  require('src.render.DotMatrix').setLevel(0)
  local m=Menu.new(Game,mon);Stack:push(Game.overworld);Stack:push(m)
  local function press(key)Game.input.wasPressed=function(_,k)return k==key end;m:update();Game.input.wasPressed=function()return false end end
  local function paint(label,w,h)
    love.window.setMode(w,h,{vsync=0});love.window.getSafeArea=function()return 8,20,w-16,h-28 end
    local canvas=g.newCanvas(w,h,{dpiscale=1});Viewport.setOutputTarget(canvas)
    g.setCanvas(canvas);g.clear(0,0,0,1);g.origin();g.setScissor();g.setColor(1,1,1,1)
    Game:draw();g.setCanvas()
    local r=Renderer:frameRects()
    check(r.uox>=r.body.x and r.uoy>=r.body.y and r.uox+r.uvpw<=r.body.x+r.body.w+.1
      and r.uoy+r.uvph<=r.body.y+r.body.h+.1,label..' page stays inside usable touch-safe playfield')
    check(r.Up==math.floor(r.Up),label..' font uses integer physical pixels')
    local raw=Renderer.canvas:newImageData()
    local darkRows={}
    for y=0,143 do for x=8,151 do local red,green,blue=raw:getPixel(x,y)
      if red<.15 and green<.15 and blue<.15 then darkRows[y]=true;break end
    end end
    check(darkRows[16] or darkRows[17] or darkRows[18],label..' native Japanese title has actual bitmap ink')
    if Stack:top()==m and #m.moves>0 then
      local cursorY=24+(m.index-m.scroll)*16+3
      local red,green,blue=raw:getPixel(10,cursorY)
      check(red<.15 and green<.15 and blue<.15,label..' selected row has actual bitmap cursor')
    end
    write(label..'.png',canvas:newImageData():encode('png'):getString())
    records[#records+1]={label=label,window={w,h},native={160,144},scale=r.Up,phase=m.phase,index=m.index,scroll=m.scroll}
    Viewport.setOutputTarget(nil);canvas:release()
  end
  paint('reminder-list-portrait',480,800)
  for _=1,6 do press('down')end
  check(m.index==7 and m.scroll==2,'long imported learnset scrolls five visible rows')
  paint('reminder-list-scrolled',972,1536)
  press('a');check(m.phase=='replace','full moveset switches to replacement phase')
  paint('reminder-replace-landscape',1536,972)
  press('a');local text=Stack:top()
  check(text.isTextBox and text.defaultNo,'real confirmation uses Japanese dialog and safe No default')
  local page=text.pages[1]
  for _=1,160 do text:update(1/60);if Stack:top()~=text then break end end
  paint('reminder-confirm-portrait',972,1536)
  while Stack:top()~=m do Stack:pop()end
  m.phase='learn';m.index=1;m.scroll=0;m.moves={}
  paint('reminder-empty-landscape',800,480)
  write('results.json',Json.encode({checks=checks,records=records,romUsed=false,
    runtime='actual Game.draw / JapaneseMoveReminderMenu / TextBox / ChoiceBox / Font / GameUILayout',
    font='bundled Misaki8x8 with authored cartridge-layout border/voiced marks'}))
  print('PASS '..checks..' reminder GL checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then love.graphics.setCanvas();print(err);love.event.quit(1)else love.event.quit(0)end
end
