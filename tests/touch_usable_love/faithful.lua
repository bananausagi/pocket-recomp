-- Actual Game/Renderer/screens with authored data and licensed font fixtures.
local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local g,fs=love.graphics,love.filesystem
  local checks,records=0,{}
  local function check(ok,why)assert(ok,why);checks=checks+1;print('PASS '..why)end
  local function write(name,bytes)local f=assert(io.open(out..'/'..name,'wb'));f:write(bytes);f:close()end
  local Data=require('src.core.Data')
  for k,v in pairs(require('tests.fixture_data').load())do Data[k]=v end
  Data.constants.language='ja';Data.render_pipelines={}
  require('tests.jp_battle_bitmap_font')(Data)
  require('src.core.Strings').load(Data);require('src.core.GameVersion').set('red_jp')
  local Game=require('src.core.Game');local Renderer=require('src.render.Renderer')
  local Input=require('src.core.Input');local Stack=require('src.core.StateStack')
  local Viewport=require('src.render.GameViewport');local Touch=require('src.core.TouchControls')
  local Save=require('src.core.SaveData');local Layout=require('src.ui.GameUILayout')
  Input:init();Stack:init();Touch:init();Touch.active=true;Renderer:init()
  check(Touch:ensureImages(),'actual touch control images load')
  require('src.render.Pipelines').install(Data)
  require('src.render.DotMatrix').setLevel(0);require('src.render.PaletteFX').setMode('gbc')
  Game.data=Data;Game.renderer=Renderer;Game.input=Input;Game.stack=Stack
  Game.save=Save.newGame();Game.save.options.jpDialogScale=1
  Game.save.options.uiLayout='centered';Game.save.options.colors='gbc'
  Game.save.options.battleLayout='classic';Game.save.options.battleHud='fixed'
  Game.save.options.battleBg='white';Game.save.player.name='テスト'
  package.loaded['src.core.Sound']={play=function()end,playCry=function()end,stop=function()end}
  -- A geometric, independently authored icon and HP strip, never ROM pixels.
  local icon=g.newCanvas(16,16,{dpiscale=1});g.setCanvas(icon);g.clear(0,0,0,0)
  g.setColor(.33,.33,.33,1);g.rectangle('fill',3,4,10,10)
  g.setColor(0,0,0,1);g.rectangle('fill',4,1,3,4);g.rectangle('fill',10,1,3,4)
  g.setCanvas();fs.write('fixture/icon.png',icon:newImageData():encode('png'));icon:release()
  Data.icons={bySpecies={},icons={},byDex={}}
  for id,def in pairs(Data.pokemon)do
    Data.icons.bySpecies[id]={image='fixture/icon.png'}
    def.name='テスト'..def.dex;def.dexEntry.kind='テスト'
    def.dexEntry.heightM=0.5;def.dexEntry.weightKg=10;def.dexEntry.metric=true
    Game.save.pokedex.owned[id]=true;Game.save.pokedex.seen[id]=true
  end
  Data.text['A fixture.']='がめんの いちを\nたしかめる テスト。'
  local hud=g.newCanvas(23*8,8,{dpiscale=1});g.setCanvas(hud);g.clear(0,0,0,0)
  for code=0x62,0x78 do
    local x=(code-0x62)*8
    g.setColor(0,0,0,1);g.rectangle('line',x,2,7,4)
    if code>=0x64 and code<=0x6b then g.setColor(.66,.66,.66,1);g.rectangle('fill',x,3,code-0x63,3)end
  end
  g.setCanvas();fs.write('fixture/hud.png',hud:newImageData():encode('png'));hud:release()
  Data.font.pages={font_battle_extra={image='fixture/hud.png',base=0x62}}
  require('src.render.HudTiles').invalidate()
  local field={isOpaque=true,isOverworld=true,update=function()end}
  function field:draw()
    local w,h=g.getDimensions();local old=g.getCanvas()
    if not self.image or self.image:getWidth()~=w or self.image:getHeight()~=h then
      if self.image then self.image:release()end
      self.image=g.newCanvas(w,h,{dpiscale=1})
    end
    g.setCanvas(self.image);g.clear(.24,.46,.28,1)
    for x=0,w,40 do g.setColor(.20,.40,.25,1);g.rectangle('fill',x,0,20,h)end
    g.setCanvas(old);Renderer:setWorldOverride(self.image)
  end
  Game.overworld=field
  local Party=require('src.ui.PartyMenu')
  local Pokemon=require('src.pokemon.Pokemon')
  local function setParty(n)
    Game.save.party={}
    for i=1,n do
      local mon=Pokemon.new(Data,'FIXMON_A',5+i,function()return 8 end)
      mon.nickname=i==1 and 'ゼニガメ' or ('サンプル'..i)
      Game.save.party[i]=mon
    end
  end
  setParty(6)
  local Faithful=require('src.core.FaithfulRes')
  Faithful.fixedDisplay=function()return true end;Faithful.locked=true
  local oldUsable=Layout.usable
  local function overlap(a,b)return a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y end
  local function draw(label,kind,before)
    if before then Layout.usable=function(...)local r=oldUsable(...);r.touchReserved=false;return r end end
    local screen=kind=='party' and Party.new(Game)
      or require('src.render.TextBox').new(Game,'ボタンに かさならない\nがめんの テストです。',nil,{instant=true})
    Stack.states={field,screen}
    local w,h=g.getDimensions();local canvas=g.newCanvas(w,h,{dpiscale=1})
    Viewport.setOutputTarget(canvas);Game:draw();g.setCanvas(canvas);Touch:draw();g.setCanvas();Viewport.setOutputTarget(nil)
    local r=Renderer:frameRects()
    local rect={x=r.uox,y=r.uoy,w=r.uvpw,h=r.uvph}
    if kind=='dialog' then
      local a=assert(Renderer.uiAnchors and Renderer.uiAnchors[1],'actual textbox registers anchor')
      if r.body then local x,y,w,h=Layout.place(r,a);rect={x=x,y=y,w=w,h=h}
      else rect={x=r.uox+a.x*r.Ux,y=r.vuy+r.vuh-(r.uih-a.y)*r.Uy,w=a.w*r.Ux,h=a.h*r.Uy}end
    end
    local hits=0;for _,c in ipairs(Layout.touchBounds())do if overlap(rect,c)then hits=hits+1 end end
    local native=Renderer.canvas:newImageData():getString()
    write(label..'.png',canvas:newImageData():encode('png'):getString());canvas:release()
    Layout.usable=oldUsable
    records[#records+1]={label=label,kind=kind,before=before,rect=rect,overlaps=hits,uiScale=r.Up,
      world={x=r.ox,y=r.oy,scale=r.Sp},body=r.body}
    return r,native,hits
  end
  local preserved,reduced,reproduced=false,false,false
  for _,size in ipairs({{480,800},{1160,1536},{800,480}})do
    local w,h=size[1],size[2]
    love.window.setMode(w,h,{vsync=0});Viewport.reset();love.window.getSafeArea=function()return 0,0,w,h end
    Touch:applyOptions({hotbar=false});Touch.active=true;Touch.controllerHidden=false
    for _,kind in ipairs({'party','dialog'})do
      local label=kind..'-'..w..'x'..h
      local previous,oldPixels,oldHits=draw(label..'-before',kind,true)
      local current,newPixels,hits=draw(label,kind,false)
      reproduced=reproduced or oldHits>0
      check(hits==0,label..' avoids visible touch buttons under Faithful')
      check(current.body and current.body.touchReserved,label..' uses shared available area')
      check(current.Up<=previous.Up and current.Up==math.floor(current.Up),label..' never enlarges or fractionally rescales UI')
      check(previous.ox==current.ox and previous.oy==current.oy and previous.Sp==current.Sp,label..' keeps Faithful world origin and scale')
      check(oldPixels==newPixels,label..' leaves native page/text pixels unchanged')
      if current.Up==previous.Up then preserved=true else reduced=true end
    end
  end
  check(reproduced,'before path reproduces actual touch overlap')
  check(preserved,'existing UI scale is retained when it fits')
  check(reduced,'UI scale steps down only where the free area requires it')
  Touch:noteGamepad()
  local current=draw('controller-faithful','party',false)
  check(current.body==nil,'controller-only Faithful keeps original fixed placement')
  check(Game.save.options.jpDialogScale==1,'saved common scale is not changed')
  write('results.json',require('src.link.Json').encode({checks=checks,romUsed=false,actualGameDraw=true,records=records}))
  print('PASS '..checks..' Faithful touch UI checks')
end
function love.load()local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas();if not ok then print(err)end;love.event.quit(ok and 0 or 1)end
