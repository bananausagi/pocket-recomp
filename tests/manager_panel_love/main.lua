local function run()
 local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
 package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
 local g,fs=love.graphics,love.filesystem
 local Json=require('src.link.Json');local checks=0
 local function check(v,s)assert(v,s);checks=checks+1;print('PASS '..s)end
 local function write(n,s)local fp=assert(io.open(out..'/'..n,'wb'));fp:write(s);fp:close()end
 local manifest=Json.decode(fs.read('tools/rom_manifest_red_jp.json'))
 local glyphs=Json.decode(fs.read('assets/fonts/misaki/glyphs.json'))
 local atlas=g.newImage('assets/fonts/misaki/misaki8x8.png');atlas:setFilter('nearest','nearest')
 local function font(base,count,path)
  local c=g.newCanvas(128,count/16*8,{dpiscale=1});g.setCanvas(c);g.clear(0,0,0,0);g.setColor(0,0,0,1)
  for _,e in ipairs(manifest.fontCharmap)do if e.code>=base and e.code<base+count and glyphs[e.seq]then
   local i,n=glyphs[e.seq],e.code-base
   g.draw(atlas,g.newQuad(i%128*8,math.floor(i/128)*8,8,8,atlas:getDimensions()),n%16*8,math.floor(n/16)*8)
  end end
  if base==0x80 then local n=0xed-base;for y=0,6 do g.rectangle('fill',n%16*8,math.floor(n/16)*8+y,4-math.abs(y-3),1)end end
  g.setCanvas();fs.write(path,c:newImageData():encode('png'))
 end
 font(0x80,128,'fixture-font.png');font(0x60,32,'fixture-extra.png')
 local data={constants={language='ja'},font={language='ja',image='fixture-font.png',imageExtra='fixture-extra.png',mainBase=0x80,extraBase=0x60,charmap=manifest.fontCharmap,composites=manifest.fontComposites}}
 local Font=require('src.render.Font');Font.load(data);require('src.core.Strings').load(data)
 require('src.core.GameVersion').set('red_jp')
 local Touch=require('src.core.TouchControls');Touch.visible=function()return false end
 local Manager=require('src.mods.ManagerState')
 local pressed
 local game={data=data,save={options={jpDialogScale=1,mods={},modOptions={}}},input={wasPressed=function(_,k)return pressed==k end}}
 local StateStack=require('src.core.StateStack');game.stack=setmetatable({states={{isOpaque=true},{screenId='StartMenu'}}},{__index=StateStack})
 local installed={};game.mods={generation=1,status=function()return {available=installed,errors={}}end,setEnabled=function(_,id,value)for _,m in ipairs(installed)do if m.id==id then m.enabled=value end end end}
 local writes,restarts=0,0;game.writeOptions=function()writes=writes+1 end;game.restartWithMods=function()restarts=restarts+1 end
 package.loaded['src.core.Sound']={play=function()end}
 local manager=Manager.new(game);manager:refresh();game.stack.states[3]=manager
 local function mods(n)
  installed={};for i=1,n do installed[i]={id='FIX'..i,name=(i%3==0 and 'がめんと ポケモンの ひょうじ ' or 'MOD ')..i,version='1.0.0',category='GAMEPLAY',description='がめんと せっていを かえます。',state='disabled',enabled=false,permissions={}}end
  manager.screen='list';manager.tab=1;manager.cursor=1;manager.scroll=1;manager.overlay=nil;manager.backStack={};manager.notice=nil;manager:refresh();manager:snapCursor()
 end
 local reports={}
 local function paint(label)
  local w,h=g.getDimensions();local target=g.newCanvas(w,h);g.setCanvas(target);g.clear(.13,.35,.22,1)
  g.setColor(.19,.44,.29,1);for x=0,w,32 do g.rectangle('fill',x,0,16,h)end
  manager:drawWindowOverlay();local l=manager.panelGeometry
  check(g.getCanvas()==target,label..' restores previous canvas')
  check(l.viewport.scale%1==0 and l.viewport.sx==l.viewport.sy,label..' uses integer native pixels')
  check(l.viewport.x>=0 and l.viewport.y>=0 and l.viewport.x+l.viewport.w<=w+1 and l.viewport.y+l.viewport.h<=h+1,label..' remains inside usable view')
  g.setCanvas();local pixels=target:newImageData();local r,gg,b=pixels:getPixel(0,0)
  check(gg>r and gg>b,label..' keeps the game scene visible outside white panel')
  if l.entries[manager.cursor] and l.entries[manager.cursor].y and not l.entries[manager.cursor].row.header then
   local e=l.entries[manager.cursor];local dark=0
   for yy=0,6 do for xx=0,3 do local cr,cg,cb=pixels:getPixel(math.floor(l.viewport.x+(8+xx)*l.viewport.sx),math.floor(l.viewport.y+(e.y+yy)*l.viewport.sy));if cr+cg+cb<.5 then dark=dark+1 end end end
   check(dark>0,label..' paints the selected cursor')
  end
  local bottom=-math.huge
  for i=l.first or 1,l.last or 0 do local e=l.entries[i]
   local top=e.y-(e.pad>0 and 8 or 0)
   check(top>=bottom,label..' preserves row/dakuten separation '..i)
   bottom=e.y+8+(e.value and e.value~=''and not e.wide and e.line or 0)
  end
  g.setCanvas();write(label..'.png',pixels:encode('png'):getString())
  reports[label]={rows=l.visible,width=l.width,height=l.height,scale=l.viewport.scale}
  target:release();return l
 end
 for _,size in ipairs({{360,640},{480,800},{800,480},{972,1536}})do
  love.window.setMode(size[1],size[2],{vsync=0});mods(20)
  local label='long-'..size[1]..'x'..size[2];local l=paint(label)
  check(l.visible>4,label..' shows more rows than the old four-row manager')
  manager.cursor=21;paint(label..'-last');check(manager.panelGeometry.last==21,'selected last item stays visible after scroll')
  mods(1);local sparse=paint('sparse-'..size[1]..'x'..size[2]);check(sparse.height<l.height,'short list fits its content')
 end
 -- Keep native menu lifecycle and existing apply/cancel callbacks.
 love.window.setMode(480,800,{vsync=0});mods(2)
 check(manager.isOpaque==false and manager.floatingPanel,'Japanese manager is a floating state')
 check(game.stack:visibleBase()==1,'state stack still draws the game beneath it')
 local function press(k)pressed=k;manager:update();pressed=nil end
 press('select');check(installed[1].enabled and manager.restartPending,'SELECT stages the existing toggle callback')
 press('start');check(manager.screen=='apply','START opens the existing apply screen')
 press('a');check(manager.overlay~=nil,'apply requires its existing restart confirmation')
 paint('apply-confirm');press('b');check(not manager.overlay and restarts==0 and installed[1].enabled,'B cancels confirmation without applying or discarding')
 manager.cursor=2;press('a');check(not installed[1].enabled and not manager.restartPending,'discard action retains original semantics')
 press('b');check(manager.screen=='list','B returns to previous manager screen')
 installed[1].dependencySpecs={{id='FIX2'}};manager.cursor=2;press('select')
 check(manager.overlay~=nil and not installed[1].enabled,'dependency cascade still asks before staging')
 press('b');check(not installed[1].enabled and not installed[2].enabled,'cascade cancel changes no flags')
 press('select');press('a');check(installed[1].enabled and installed[2].enabled,'cascade confirm stages dependency closure')
 manager.currentMod=installed[1];manager:goTo('detail');paint('detail')
 manager:goTo('permissions');paint('permissions');press('b')
 local changed=0
 manager.optionRows={{label='がめんの せってい',value=function()return 'ゲンガーの ひょうじ'end,step=function()changed=changed+1 end},{label='もどる',value=function()return ''end,activate=function()manager:goBack()end}}
 manager:goTo('options');paint('options');press('right');check(changed==1,'responsive options call the original step callback once');press('b');check(manager.screen=='detail','option cancel preserves back stack')
 manager.backStack={};press('b');check(game.stack:top().screenId=='StartMenu','final B pops manager back to native START menu')
 local english=Manager.new({data={constants={language='en'}}});check(english.isOpaque and not english.floatingPanel,'non-Japanese view retains its existing contract')
 write('results.json',Json.encode({checks=checks,romUsed=false,reports=reports}))
 print('PASS '..checks..' manager floating-panel checks')
end
function love.load()local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas();if not ok then print(err);love.event.quit(1)else love.event.quit(0)end end
