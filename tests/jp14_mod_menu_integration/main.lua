local function run()
 local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
 package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
 local g=love.graphics;local checks=0
 local function check(v,s)assert(v,s);checks=checks+1;print('PASS '..s)end
 local function write(n,s)local f=assert(io.open(out..'/'..n,'wb'));f:write(s);f:close()end
 local Data=require('src.core.Data');Data.constants={language='ja'};Data.field={};Data.render_pipelines={}
 require('tests.jp_battle_bitmap_font')(Data)
 require('src.core.Strings').load(Data);require('src.core.GameVersion').set('red_jp')
 local Game=require('src.core.Game');local Renderer=require('src.render.Renderer')
 local Input=require('src.core.Input');local Stack=require('src.core.StateStack');local Viewport=require('src.render.GameViewport')
 local Touch=require('src.core.TouchControls');local Save=require('src.core.SaveData');local Screens=require('src.ui.Screens')
 Input:init();Stack:init();Touch:init();Touch.enabled=false;Renderer:init()
 require('src.render.Pipelines').install(Data);require('src.render.DotMatrix').setLevel(0);require('src.render.PaletteFX').setMode('gbc')
 Game.data=Data;Game.renderer=Renderer;Game.input=Input;Game.stack=Stack
 Game.save={options=Save.defaultOptions(),flags={},player={name='レッド'},party={},playTime=123,pokedex={owned={},seen={}},bag={},modData={}}
 Game.save.options.jpDialogScale=1;Game.save.options.uiLayout='centered';Game.save.options.colors='gbc'
 local writes,restarts,worldTicks,worldDraws=0,0,0,0
 Game.writeOptions=function()writes=writes+1;return true end;Game.restartWithMods=function()restarts=restarts+1 end
 local installed={};for i=1,12 do installed[i]={id='FIX'..i,name=i%3==0 and ('がめんの ひょうじ '..i)or('MOD '..i),version='1.0.0',enabled=i==1,state='disabled',category='GAMEPLAY',description='がめんの せっていを かえます。',permissions={}}end
 Game.mods={generation=1,status=function()return {available=installed,errors={}}end,setEnabled=function(_,id,v)for _,m in ipairs(installed)do if m.id==id then m.enabled=v end end end}
 Game.modStatus=Game.mods:status()
 package.loaded['src.core.Sound']={play=function()end}
 local field={isOpaque=true,isOverworld=true}
 function field:update()worldTicks=worldTicks+1 end
 function field:draw()
  worldDraws=worldDraws+1
  local w,h=g.getDimensions();local old=g.getCanvas()
  if not self.image or self.image:getWidth()~=w or self.image:getHeight()~=h then self.image=g.newCanvas(w,h,{dpiscale=1})end
  g.setCanvas(self.image);g.clear(.22,.48,.30,1)
  for x=0,w,32 do g.setColor(.19,.42,.26,1);g.rectangle('fill',x,0,16,h)end
  g.setColor(.62,.55,.35,1);g.rectangle('fill',w*.15,0,w*.12,h)
  g.setColor(.15,.34,.58,1);g.rectangle('fill',w*.66,h*.12,w*.25,h*.23)
  g.setCanvas(old);Renderer:setWorldOverride(self.image)
 end
 Game.overworld=field;Stack.states={field}
 local tickCalls=0;local Fixed=require('src.core.FixedStep');local oldUpdate=Fixed.update
 Fixed.update=function(...)tickCalls=tickCalls+1;return oldUpdate(...)end
 local ended,overlayCalls=0,0;local oldEnd=Renderer.endFrame
 Renderer.endFrame=function(self,...)local r=oldEnd(self,...);ended=ended+1;return r end
 local function press(k)
  Input:sourcePress(k,'integration');Input:sourceRelease(k,'integration');Game:update(1/60+.000001)
 end
 local function select(id)
  local menu=Stack:top();for i,item in ipairs(menu.items or {})do if item.id==id then menu.index=i;press('a');return end end
  error('missing START action '..id)
 end
 local function render(label)
  local w,h=g.getDimensions();local canvas=g.newCanvas(w,h,{dpiscale=1});Viewport.setOutputTarget(canvas)
  local before=worldDraws;Game:draw();check(worldDraws==before+1,label..' runs actual Game world draw before manager')
  g.setCanvas();Viewport.setOutputTarget(nil);local pixels=canvas:newImageData()
  local r,gg,b=pixels:getPixel(2,2);check(gg>r and gg>b,label..' keeps world outside floating frame')
  write(label..'.png',pixels:encode('png'):getString());canvas:release()
 end
 -- Real navigation method -> real StartMenu -> real Screens Manager factory.
 Game:openSessionMenu();local start=Stack:top()
 check(start.isSystemMenuRoot and start.items~=nil,'host menu opens actual native START')
 select('system-mods');local manager=Stack:top()
 check(manager.screenId=='ManagerState' and manager.floatingPanel and manager.systemMenuPause,'native START action opens actual paused floating Manager')
 check(Stack.states[2]==start and #Stack.states==3,'START stays beneath its MOD child')
 check(manager.restartPending and installed[1].enabled,'pre-existing staged enable flag survives manager enter')
 local oldOverlay=manager.drawWindowOverlay
 manager.drawWindowOverlay=function(self)
  check(ended>overlayCalls,'Manager overlay runs after actual Renderer.endFrame')
  overlayCalls=overlayCalls+1;return oldOverlay(self)
 end
 for _,size in ipairs({{480,800},{800,480}})do love.window.setMode(size[1],size[2],{vsync=0});render('integrated-mods-'..size[1]..'x'..size[2])end
 local before=Game.save.playTime;for _=1,12 do Game:update(1/60)end
 check(worldTicks==0 and tickCalls==0 and Game.save.playTime==before,'Game.update consumes menu input while world/fixedstep/playtime stay paused')
 press('a');check(manager.screen=='detail','A opens actual manager detail')
 press('b');check(manager.screen=='list','B child returns to same manager list')
 press('start');check(manager.screen=='apply','existing staged changes still open Apply')
 press('a');check(manager.overlay~=nil,'Apply uses existing restart confirmation')
 press('b');check(not manager.overlay and restarts==0 and installed[1].enabled,'B confirmation cancel preserves prior staged flags')
 press('b');press('b')
 check(Stack:top()==start and installed[1].enabled,'B manager returns to retained START without discarding staged changes')
 -- Shared renderer integration for the other floating owner, as requested.
 select('system-settings');local options=Stack:top()
 check(options.screenId=='OptionsMenu' and options.floatingPanel,'same START routes through real Options factory')
 render('integrated-options-800x480')
 for _,size in ipairs({{972,1536},{1536,1160}})do love.window.setMode(size[1],size[2],{vsync=0});render('integrated-options-'..size[1]..'x'..size[2])end
 love.window.setMode(800,480,{vsync=0})
 press('a');render('integrated-options-group-800x480')
 press('b');press('b')
 check(Stack:top()==start,'Options back hierarchy returns to the same native START')
 press('b');check(Stack:top()==field and #Stack.states==1,'final START B returns to original game state')
 check(Game.save.playTime==before and worldTicks==0,'menu close does not repay elapsed simulation time')
 write('integration-results.json',require('src.link.Json').encode({checks=checks,romUsed=false,actualGameDraw=true,actualGameUpdate=true,actualRenderer=true,actualScreens=true,worldTicks=worldTicks,playTime=Game.save.playTime,overlayCalls=overlayCalls,writes=writes,restarts=restarts}))
 print('PASS '..checks..' integrated native START / MOD checks')
end
function love.load()local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas();if not ok then print(err);love.event.quit(1)else love.event.quit(0)end end
