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
  local Runtime=require('src.mods.Runtime')
  Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
  local customViewport=false
  Runtime.hooks:wrap('render.viewport',function(next,ctx)
    local r=next(ctx)
    if customViewport then r={x=40,y=32,width=ctx.width-80,height=ctx.height-64}end
    return r
  end,0,'touch-usable-fixture')
  setParty(6)
  local function overlap(a,b)
    return a.x<b.x+b.w-.1 and a.x+a.w>b.x+.1 and a.y<b.y+b.h-.1 and a.y+a.h>b.y+.1
  end
  local function safe(label,rect,controls)
    for _,c in ipairs(controls)do check(not overlap(rect,c),label..' avoids drawn touch button')end
  end
  local function render(label,kind,shot)
    local screen=kind=='options' and require('src.ui.OptionsMenu').new(Game) or Party.new(Game)
    Stack.states={field,screen}
    local w,h=g.getDimensions();local canvas=g.newCanvas(w,h,{dpiscale=1})
    Viewport.setOutputTarget(canvas);Game:draw();g.setCanvas(canvas);Touch:draw();g.setCanvas();Viewport.setOutputTarget(nil)
    local rect
    if kind=='options' then rect=assert(screen.windowPanel.geometry).viewport
    else
      local r=Renderer:frameRects();local ox,oy=0,0
      if Viewport.active() and Viewport.rect then ox,oy=Viewport.rect.x,Viewport.rect.y end
      rect={x=r.uox+ox,y=r.uoy+oy,w=r.uvpw,h=r.uvph}
      check(r.Up==math.floor(r.Up),label..' native font uses integer pixels')
    end
    safe(label,rect,Layout.touchBounds())
    check(rect.x>=0 and rect.y>=0 and rect.x+rect.w<=w+1 and rect.y+rect.h<=h+1,label..' actual window remains on screen')
    if shot then write(label..'.png',canvas:newImageData():encode('png'):getString())end
    records[#records+1]={label=label,window=rect,usable=Layout.usable(false),controls=Layout.touchBounds()}
    canvas:release()
    return rect
  end
  local function prepare(w,h,scale,enabled)
    love.window.setMode(w,h,{vsync=0});Viewport.reset();love.window.getSafeArea=function()return 8,16,w-16,h-24 end
    Touch:applyOptions({hotbar=false,touchControls={enabled=enabled~=false,layouts={
      portrait={scale=scale or 1},landscape={scale=scale or 1}}}})
    Touch.active=true;Touch.controllerHidden=false
  end
  for _,size in ipairs({{480,800},{1160,1536},{800,480},{1536,864}})do
    local w,h=size[1],size[2];prepare(w,h)
    for _,kind in ipairs({'party','options'})do render(kind..'-'..w..'x'..h,kind,true)end
    local b=Layout.usable(false);safe('shared usable',b,Layout.touchBounds())
    local r={vux=0,vuy=0,vuw=w,vuh=h,pw=w,ph=h,dpiX=1,dpiY=1,uiw=160,uih=144}
    require('src.battle.BattlePresentation').frame(r,1)
    safe('battle body',r.body,Layout.touchBounds())
    check(r.body.touchReserved,'battle camera and HUD receive touch-reserved body')
    local p=r.battlePresentation.panels
    safe('battle panel surface',{x=p.x,y=p.y,w=p.width*p.sx,h=p.height*p.sy},Layout.touchBounds())
    if w>h then check(b.h>h*.65,'landscape retains tall central space instead of a short full-width strip')end
    local originalX=b.x;b.x=-999
    check(Layout.usable(false).x==originalX,'cached layout cannot be mutated through returned body')
  end
  prepare(480,800,1.3)
  render('larger-controls','party',true)
  local initial=Layout.usable(false)
  Touch:setControlCenter('a',365,360)
  local moved=Layout.usable(false)
  check(moved.x~=initial.x or moved.y~=initial.y or moved.w~=initial.w or moved.h~=initial.h,'editor move updates usable rectangle without waiting for resize')
  render('custom-raised-a','party',true);render('custom-raised-a-options','options',true)
  local config=require('src.link.Json').encode(Touch:config())
  love.window.setMode(800,480,{vsync=0});love.window.getSafeArea=function()return 8,16,784,456 end
  render('rotated-custom','party',false)
  check(require('src.link.Json').encode(Touch:config())==config,'rotation preserves both saved control layouts')
  prepare(800,480);customViewport=true
  render('custom-viewport','party',true);customViewport=false;Viewport.reset()
  prepare(480,800);Touch.hotbarEnabled=true;Touch.hotbarOpen=true
  render('open-hotbar','party',false);Touch.hotbarOpen=false;Touch.hotbarEnabled=false
  for _,mode in ipairs({'disabled','controller'})do
    prepare(800,480,1,mode~='disabled');if mode=='controller' then Touch:noteGamepad()end
    local b=Layout.usable(false)
    check(not b.touchReserved and b.x==8 and b.y==16 and b.w==784 and b.h==456,mode..' keeps original safe area without upward reservation')
    local r={vux=0,vuy=0,vuw=800,vuh=480,pw=800,ph=480,dpiX=1,dpiY=1,uiw=160,uih=144}
    require('src.battle.BattlePresentation').frame(r,1)
    check(r.body.x==0 and r.body.y==0 and r.body.w==800 and r.body.h==480,mode..' battle keeps original full viewport position')
    render(mode..'-party','party',true)
  end
  check(Game.save.options.jpDialogScale==1,'placement does not rewrite common window scale')
  write('results.json',require('src.link.Json').encode({checks=checks,romUsed=false,actualGameDraw=true,records=records}))
  print('PASS '..checks..' touch-safe layout checks')
end
function love.load()local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas();if not ok then print(err)end;love.event.quit(ok and 0 or 1)end
