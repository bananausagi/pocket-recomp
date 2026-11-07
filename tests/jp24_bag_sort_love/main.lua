local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local g,checks,records=love.graphics,0,{}
  local function check(ok,why)assert(ok,why);checks=checks+1 end
  local function write(name,bytes)local f=assert(io.open(out..'/'..name,'wb'));f:write(bytes);f:close()end
  local Data=require('src.core.Data')
  for k,v in pairs(require('tests.fixture_data').load())do Data[k]=v end
  Data.constants.language='ja';Data.render_pipelines={}
  require('tests.jp_battle_bitmap_font')(Data)
  require('src.core.Strings').load(Data);require('src.core.GameVersion').set('red_jp')
  package.loaded['src.core.Sound']={play=function()end,playCry=function()end,stop=function()end}
  local Game=require('src.core.Game');local Renderer=require('src.render.Renderer')
  local Input=require('src.core.Input');local Stack=require('src.core.StateStack')
  local Viewport=require('src.render.GameViewport');local Touch=require('src.core.TouchControls')
  Input:init();Stack:init();Touch:init();Touch.active=true;Renderer:init()
  check(Touch:ensureImages(),'touch controls load')
  require('src.render.Pipelines').install(Data)
  require('src.render.DotMatrix').setLevel(0);require('src.render.PaletteFX').setMode('gbc')
  Game.data=Data;Game.renderer=Renderer;Game.input=Input;Game.stack=Stack
  Game.save=require('src.core.SaveData').newGame();Game.save.options.jpDialogScale=.75
  Game.save.options.uiLayout='centered';Game.save.options.colors='gbc'
  Game.save.options.battleLayout='classic';Game.save.options.battleHud='fixed';Game.save.options.battleBg='white'
  Game.save.party={require('src.pokemon.Pokemon').new(Data,'FIXMON_A',10)}
  require('tests.jp24_bag_sort_fixture')(Data,Game.save)
  local field={isOpaque=true,isOverworld=true,update=function()end,draw=function()
    g.setColor(.7,.83,.6,1);g.rectangle('fill',0,0,640,640)
    g.setColor(.8,.87,.67,1)
    for y=0,600,16 do for x=0,600,16 do if (x+y)%32==0 then g.rectangle('fill',x,y,16,16)end end end
    g.setColor(1,1,1,1)
  end}
  Game.overworld=field
  local BagMenu=require('src.ui.BagMenu')
  local native,rects
  local oldEnd=Renderer.endFrame
  Renderer.endFrame=function(self,...)
    rects=self:frameRects()
    local old=g.getCanvas();g.setCanvas();native=self.canvas:newImageData();g.setCanvas(old)
    return oldEnd(self,...)
  end
  local function render(label)
    local w,h=g.getDimensions();local canvas=g.newCanvas(w,h,{dpiscale=1})
    Viewport.setOutputTarget(canvas);Game:draw();g.setCanvas();Viewport.setOutputTarget(nil)
    write(label..'.png',canvas:newImageData():encode('png'):getString());canvas:release()
    write(label..'-native.png',native:encode('png'):getString())
    check(rects.Up>0 and math.abs(rects.Ux*rects.dpiX-rects.Uy*rects.dpiY)<1e-6,
      'menu pixels retain square aspect '..label)
    local Font=require('src.render.Font')
    local list=Stack.states[#Stack.states-1]
    if not(list and list.footer)then list=Stack:top()end
    for line in list.footer:gmatch('[^\n]+')do check(Font.width(line)<=144,'footer fits '..label)end
    local top=Stack:top()
    if top.title=='ならべかえ'then
      check(top.tx>=0 and top.tx+top.tw<=20 and top.ty+top.th<=18,'popup within native canvas')
      for _,item in ipairs(top.items)do check(Font.width(item.label)<=(top.tw-3)*8,'popup choice fits')end
    end
    records[#records+1]={name=label,body=rects.body,layout=Renderer.jpLayout,scale=rects.Up}
  end
  local function press(key)
    Input:sourcePress(key,'sort-qa');Input:step();Stack:update(1/60)
    Input:sourceRelease(key,'sort-qa');Input:step();Stack:update(1/60)
  end
  for _,size in ipairs({{480,800},{800,480}})do
    love.window.setMode(size[1],size[2],{vsync=0});local suffix=size[1]..'x'..size[2]
    for _,inBattle in ipairs({false,true})do
      local battle
      if inBattle then
        battle=require('src.battle.BattleState').newWild(Game,'FIXMON_C',10)
        battle.phase,battle.menuIndex,battle.frame='menu',1,0
        battle.introSlide,battle.introBalls,battle.showPlayerBack=0,false,false
        battle.enemyHudPending,battle.enemySendingOut=false,false;battle.current=nil
      end
      local list=BagMenu.new(Game,{battle=battle})
      Stack.states=inBattle and {field,battle,list}or {field,list}
      local tag=(inBattle and 'battle-'or'field-')..suffix
      render(tag..'-bag');press('start');render(tag..'-sort')
      check(Stack:top().title=='ならべかえ','actual START opens sort popup')
      press('a');check(Stack:top()==list,'actual A applies and returns to bag')
      render(tag..'-sorted')
    end
  end
  write('render-results.json',assert(require('src.link.Json').encode({checks=checks,
    actualGameDraw=true,physicalAndroid=false,assets='authored',records=records})))
  print('PASS '..checks..' item sort render checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas()
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
