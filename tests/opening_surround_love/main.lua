-- Actual IntroMovie -> Game.draw -> Renderer.endFrame. Authored geometric
-- assets are created in LOVE's temporary save area, never copied to evidence.
local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('OPENING_QA_OUT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local g,fs=love.graphics,love.filesystem
  g.setDefaultFilter('nearest','nearest')
  local checks,records=0,{}
  local function check(v,s)assert(v,s);checks=checks+1 end
  local function write(name,s)local f=assert(io.open(out..'/'..name,'wb'));f:write(s);f:close()end
  local function asset(name,w,h)
    local d=love.image.newImageData(w,h)
    for y=2,h-3 do for x=2,w-3 do
      if x%8==2 or y==2 or y==h-3 then d:setPixel(x,y,0,0,0,1)end
    end end
    local p='opening-test-'..name..'.png';fs.write(p,d:encode('png'));return {path=p}
  end
  local copy,inc=asset('copy',152,8),asset('inc',72,8)
  local actor=asset('actor',24,24)
  local intro={gamefreakLogo=asset('logo',16,24),gamefreakText=asset('word',80,8),
    gengar={},nidorino={}}
  for i=1,3 do intro.gengar['frame'..i]=actor;intro.nidorino['frame'..i]=actor end
  local palettes={
    GAMEFREAK={{224,240,248},{176,184,208},{88,104,144},{0,0,0}},
    PURPLEMON={{248,224,240},{208,176,216},{120,72,152},{0,0,0}},
    GREENBAR={{248,240,224},{176,208,152},{72,120,64},{0,0,0}},
    BLACK={{248,248,248},{168,168,168},{88,88,88},{0,0,0}}}
  palettes.REDMON=palettes.GAMEFREAK;palettes.VIRIDIAN=palettes.GAMEFREAK;palettes.BLUEMON=palettes.GAMEFREAK
  local data={constants={language='ja'},field={intro=intro,title={copyright=copy,gamefreakInc=inc}},palettes={palettes=palettes}}
  require('src.core.GameVersion').set('red_jp')
  local Runtime=require('src.mods.Runtime');Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
  Runtime.hooks:wrap('render.viewport',function(next,ctx)local r=next(ctx);r.capture=true;return r end,0,'opening-test')
  local P=require('src.render.PaletteFX')
  local forcedShade
  Runtime.hooks:wrap('render.zones',function(next,game,zones) P.setShadeMap(forcedShade);return next(game,zones)end,0,'opening-test-shade')
  local Renderer=require('src.render.Renderer');Renderer:init()
  local Viewport=require('src.render.GameViewport')
  local Stack=require('src.core.StateStack');Stack:init()
  local Game=require('src.core.Game');Game.data,Game.stack,Game.renderer=data,Stack,Renderer
  Game.save={options={jpDialogScale=.75}};Game.input={wasPressed=function()return false end}
  local Touch=require('src.core.TouchControls');Touch:init();Touch.active=false
  require('src.render.DotMatrix').setLevel(0)
  require('src.core.ScreenPosition').setMode('center')
  local Letterbox=require('src.render.Letterbox');Letterbox.setMode('auto')
  local Faithful=require('src.core.FaithfulRes')
  local movie=require('src.ui.IntroMovie').new(Game,function()end);Stack:push(movie)
  movie.nidoX,movie.nidoY=20,72;movie.gengarX,movie.gengarY=104,56
  local custom={{208,232,192},{136,184,120},{72,112,56},{16,32,8}}
  local function rgb(d,x,y)local r,gg,b=d:getPixel(math.floor(x),math.floor(y));return {r,gg,b}end
  local function same(a,b)local e=0;for i=1,3 do e=math.max(e,math.abs(a[i]-b[i]))end;return e<=1.01/255,e end
  local function sample(label,w,h,phase,mode,extra)
    love.window.setMode(w,h,{vsync=0});love.window.getSafeArea=function()return 0,0,w,h end
    movie.phase,movie.timer,movie.fade=phase,80,0
    P.setMode(mode);P.setCustomRamp(extra=='custom' and custom or nil)
    forcedShade=extra=='shade' and {[0]=1,[1]=2,[2]=3,[3]=3}or nil
    Game:draw();g.setCanvas()
    local image=Viewport.target():newImageData();local r=Renderer:frameRects()
    local inner=rgb(image,r.uox+2*r.Ux,r.uoy+64*r.Uy)
    local outside=rgb(image,2,2)
    local okay,err=same(inner,outside)
    if extra=='black' or extra=='faithful' then
      check(same(outside,{0,0,0}),label..' preserves explicitly requested black surround')
    elseif extra=='white' then
      check(same(outside,{1,1,1}),label..' preserves explicitly requested white surround')
    elseif extra=='palette' then
      local a,b,c=P.paperShade(data);check(same(outside,{a,b,c}),label..' preserves explicit palette surround')
    else check(okay,label..' surround matches actual rendered middle paper')end
    check(Renderer.jpLayout==nil and Renderer.dialogScale==1,label..' retains original full opening composition')
    if phase==2 or phase==3 then
      local src=Renderer.canvas:newImageData()
      check(same(rgb(src,2,4),{0,0,0}),label..' retains original native cinematic black bars')
    end
    records[#records+1]={label=label,phase=phase,width=w,height=h,paper=inner,surround=outside,error=err}
    if mode=='gbc' and not extra then write(label..'.png',image:encode('png'):getString())end
  end
  for _,size in ipairs({{480,800},{800,480}})do
    for phase=1,4 do sample('phase'..phase..'-'..size[1]..'x'..size[2],size[1],size[2],phase,'gbc')end
  end
  for _,mode in ipairs({'classic','og_inv','gbc_inv'})do
    for phase=1,4 do sample(mode..'-phase'..phase,480,800,phase,mode)end
  end
  for _,extra in ipairs({'custom','shade'})do
    for phase=1,4 do sample(extra..'-phase'..phase,480,800,phase,'gbc',extra)end
  end
  for _,mode in ipairs({'black','white','palette'})do
    Letterbox.setMode(mode);sample('override-'..mode,480,800,3,'gbc',mode)
  end
  Letterbox.setMode('auto')
  local fixed=Faithful.fixedDisplay;Faithful.fixedDisplay=function()return true end;Faithful.locked=true
  sample('faithful',480,800,3,'gbc','faithful')
  Faithful.fixedDisplay=fixed;Faithful.locked=false
  P.setShadeMap(nil);P.setCustomRamp(nil)
  write('results.json',require('src.link.Json').encode({checks=checks,records=records,romUsed=false}))
  print('PASS '..checks..' actual opening surround checks')
end
function love.load()local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end;love.event.quit(ok and 0 or 1)end
