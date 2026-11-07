-- Actual Game/Renderer/screens with authored data and licensed font fixtures.
local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local before=os.getenv('JP_QA_BEFORE')=='1'
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
  local field={isOpaque=true,isOverworld=true,draw=function()end,update=function()end}
  Game.overworld=field
  local Party=require('src.ui.PartyMenu');local Pokedex=require('src.ui.PokedexMenu')
  local DexEntry=require('src.ui.DexEntryMenu');local Summary=require('src.ui.SummaryMenu')
  if before then
    -- Reproduce only the old position policy on the same final code/head.
    for _,screen in ipairs({Party,Pokedex,DexEntry,Summary})do screen.centerInPlayfield=false end
  end
  local Pokemon=require('src.pokemon.Pokemon')
  local function setParty(n)
    Game.save.party={}
    for i=1,n do
      local mon=Pokemon.new(Data,'FIXMON_A',5+i,function()return 8 end)
      mon.nickname=i==1 and 'ゼニガメ' or ('サンプル'..i)
      Game.save.party[i]=mon
    end
  end
  local r,source,anchors
  local oldEnd=Renderer.endFrame
  Renderer.endFrame=function(self,...)
    r=self:frameRects();anchors=self.uiAnchors
    local old=g.getCanvas();g.setCanvas();source=self.canvas:newImageData();g.setCanvas(old)
    return oldEnd(self,...)
  end
  local function render(label,centered,party)
    local w,h=g.getDimensions();local canvas=g.newCanvas(w,h,{dpiscale=1})
    Viewport.setOutputTarget(canvas);Game:draw();g.setCanvas();Viewport.setOutputTarget(nil)
    local pixels=canvas:newImageData();write(label..'.png',pixels:encode('png'):getString());canvas:release()
    check(r.Up==math.floor(r.Up) and r.Ux*r.dpiX==r.Uy*r.dpiY,label..' integer square font pixels')
    if centered then
      if before then
        check(math.abs(r.uoy-r.body.y-r.margin/r.dpiY)<1,label..' reproduces old top anchoring')
      else
        check(math.abs(r.uoy+r.uvph/2-r.body.y-r.body.h/2)<1,label..' page centered in usable area')
      end
      check(r.uoy>=r.body.y and r.uoy+r.uvph<=r.body.y+r.body.h,label..' whole page above touch controls')
    end
    if party then
      check(source:getHeight()==152,label..' keeps first-row voicing inset')
      local dark=0
      for y=0,7 do for x=24,63 do if source:getPixel(x,y)<.5 then dark=dark+1 end end end
      check(dark>0,label..' first voiced name remains visible')
    end
    if not centered then
      for _,a in ipairs(anchors or {})do
        local x,y,aw,ah=Layout.place(r,a)
        check(x>=r.body.x and y>=r.body.y and x+aw<=r.body.x+r.body.w+1 and y+ah<=r.body.y+r.body.h+1,label..' overlay remains inside usable area')
      end
    end
    local sourceHash=love.data.encode('string','hex',love.data.hash('sha256',source:getString()))
    records[#records+1]={name=label,x=r.uox,y=r.uoy,w=r.uvpw,h=r.uvph,scale=r.Up,body=r.body,layout=Renderer.jpLayout,sourceHash=sourceHash}
  end
  for _,size in ipairs({{972,1536},{1536,1160},{1536,864}})do
    love.window.setMode(size[1],size[2],{vsync=0});local suffix=size[1]..'x'..size[2]
    for _,n in ipairs({1,6})do
      setParty(n);Stack.states={field,Party.new(Game)}
      render('party-'..n..'-'..suffix,true,true)
    end
    Stack.states={field,Pokedex.new(Game)};render('pokedex-'..suffix,true)
    local dex=DexEntry.new(Game,'FIXMON_A');dex.picDelay=0
    Stack.states={field,dex};render('dex-entry-'..suffix,true)
    local summary=Summary.new(Game,Game.save.party[1]);summary.whiteHold=0
    Stack.states={field,summary};render('summary-'..suffix,true)
  end
  if not before then
    local Battle=require('src.battle.BattleState')
    local battle=Battle.newWild(Game,'FIXMON_C',10)
    battle.phase,battle.menuIndex,battle.frame='menu',1,0
    battle.introSlide,battle.introBalls,battle.showPlayerBack=0,false,false
    battle.enemyHudPending,battle.enemySendingOut=false,false;battle.current=nil
    for _,size in ipairs({{972,1536},{1536,864}})do
      love.window.setMode(size[1],size[2],{vsync=0});local suffix=size[1]..'x'..size[2]
      Stack.states={field,battle,battle:buildScreen('PartyMenu',{battle=battle})}
      render('battle-party-'..suffix,true,true)
      Stack.states={field,battle,battle:buildScreen('BagMenu',{battle=battle})}
      render('battle-bag-'..suffix,false)
      check(Renderer.jpLayout=='battle','bag retains battle composition '..suffix)
    end
    -- Input and callbacks still operate on the exact same party/state/save.
    local function press(key)
      Input:sourcePress(key,'qa');Input:step();Stack:update(1/60)
      Input:sourceRelease(key,'qa');Input:step();Stack:update(1/60)
    end
    local original=Game.save.party;local first=original[1];local chosen,cancelled
    local party=Party.new(Game,{pickOnly=true,onSwitch=function(mon)chosen=mon end,onCancel=function()cancelled=true end})
    Stack.states={field,party};press('down');check(party.index==2,'party native down selects second member')
    press('a');check(chosen==original[2],'party A preserves picker callback and member identity')
    Stack.states={field,Party.new(Game,{onCancel=function()cancelled=true end})};press('b')
    check(Stack:top()==field and cancelled,'party B returns to parent and keeps cancel callback')
    local done=false;local dex=DexEntry.new(Game,'FIXMON_A',function()done=true end);dex.picDelay=0
    Stack.states={field,dex};press('b');check(done and Stack:top()==field,'dex B preserves story completion callback')
    check(Game.save.party==original and Game.save.party[1]==first,'display/navigation never replaces party/save records')
    check(Game.save.options.jpDialogScale==1,'common saved window scale unchanged')
    -- Class attributes have no effect outside the JP layout gate.
    Data.constants.language='en';Stack.states={field,Party.new(Game)}
    render('english-party-unchanged',false);check(Renderer.jpLayout==nil,'overseas layout remains outside JP positioning')
  end
  write('results.json',require('src.link.Json').encode({checks=checks,before=before,romUsed=false,actualGameDraw=true,records=records}))
  print('PASS '..checks..' focused party page position checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas()
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
