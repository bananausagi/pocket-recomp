-- Actual TitleState -> Game.draw -> Renderer, using original geometric art.
local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('TITLE_QA_OUT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local g,fs=love.graphics,love.filesystem
  g.setDefaultFilter('nearest','nearest')
  local checks,records=0,{}
  local function check(v,s)assert(v,s);checks=checks+1;print('PASS '..s)end
  local function write(n,s)local f=assert(io.open(out..'/'..n,'wb'));f:write(s);f:close()end
  local function asset(name,w,h)
    local d=love.image.newImageData(w,h)
    for y=2,h-3 do for x=2,w-3 do
      if x%8==2 or y==2 or y==h-3 then d:setPixel(x,y,0,0,0,1)end
    end end
    local p='title-test-'..name..'.png';fs.write(p,d:encode('png'));return {path=p}
  end
  local paper={255,255,255}
  local palettes={LOGO2={paper,{180,190,200},{60,90,150},{30,70,150}},
    LOGO1={paper,{200,160,180},{140,40,60},{90,0,20}},
    MEWMON={paper,{210,150,100},{130,50,160},{0,0,0}},
    GREENBAR={{200,240,200},{140,190,130},{70,100,50},{0,0,0}}}
  local data={constants={language='ja'},field={title={
    logo=asset('logo',128,48),versionRibbon=asset('ribbon',80,8),
    player=asset('player',40,56),copyright=asset('copy',152,8),gamefreakInc=asset('inc',72,8),
    cycleSpecies={'TEST'}}},pokemon={},palettes={palettes=palettes}}
  local Version=require('src.core.GameVersion');Version.set('red_jp')
  local Runtime=require('src.mods.Runtime');Runtime.install(require('src.mods.Events').new(),require('src.mods.Hooks').new())
  Runtime.hooks:wrap('render.viewport',function(next,ctx)local r=next(ctx);r.capture=true;return r end,0,'title-test')
  local P=require('src.render.PaletteFX');local forcedShade,customZone
  Runtime.hooks:wrap('render.zones',function(next,game,zones)
    P.setShadeMap(forcedShade)
    if customZone then zones[#zones+1]=customZone end
    return next(game,zones)
  end,0,'title-test-zones')
  local Renderer=require('src.render.Renderer');Renderer:init()
  local Viewport=require('src.render.GameViewport')
  local Stack=require('src.core.StateStack');Stack:init()
  local Game=require('src.core.Game');Game.data,Game.stack,Game.renderer=data,Stack,Renderer
  Game.save={options={jpDialogScale=.5}};Game.input={wasPressed=function()return false end}
  local Touch=require('src.core.TouchControls');Touch:init();Touch.active=false
  require('src.render.DotMatrix').setLevel(0);require('src.core.ScreenPosition').setMode('center')
  local Letterbox=require('src.render.Letterbox');Letterbox.setMode('auto')
  local Faithful=require('src.core.FaithfulRes')
  local Title=require('src.ui.TitleState');local title=Title.new(Game)
  check(type(title.surroundColor)=='function' and title.preferTitleSurround,'supported native JP title opts into preferred paper surround')
  Stack:push(title)
  local originalPhase=title.phase
  for _=1,300 do if title.phase=='loop' then break end;title:update(1/60)end
  check(originalPhase=='drop' and title.phase=='loop' and title.scy==0,'original bounce and ribbon sequence reaches settled loop')
  local hook=title.surroundColor
  local function rgb(d,x,y)local r,gg,b=d:getPixel(math.floor(x),math.floor(y));return {r,gg,b}end
  local function same(a,b)for i=1,3 do if math.abs(a[i]-b[i])>1.01/255 then return false end end;return true end
  local function render()
    Game:draw();g.setCanvas()
    return Viewport.target():newImageData(),Renderer.canvas:newImageData():getString(),Renderer:frameRects()
  end
  local function sample(label,w,h,mode,extra,shot)
    love.window.setMode(w,h,{vsync=0});love.window.getSafeArea=function()return 0,0,w,h end
    P.setMode(mode);P.setCustomRamp(extra=='custom' and {{208,232,192},{136,184,120},{72,112,56},{16,32,8}} or nil)
    forcedShade=extra=='shade' and {[0]=1,[1]=2,[2]=3,[3]=3}or nil
    customZone=extra=='zone' and P.zone({{244,214,184},{160,100,60},{80,40,20},{0,0,0}},0,0,19,17)
      or extra=='truecolor' and P.trueColorZone(0,0,19,17) or nil
    title.surroundColor=nil
    local before,nativeBefore,rectBefore=render()
    title.surroundColor=hook
    local image,nativeAfter,r=render()
    local inner=rgb(image,r.uox+2*r.Ux,r.uoy+2*r.Uy)
    local outside=rgb(image,2,2)
    check(same(inner,outside),label..' actual paper and surround match, including generic overrides')
    check(nativeBefore==nativeAfter,label..' native title pixels unchanged')
    check(r.uox==rectBefore.uox and r.uoy==rectBefore.uoy and r.Up==rectBefore.Up,label..' composition scale and position unchanged')
    check(Renderer.jpLayout==nil and Renderer.dialogScale==1,label..' title stays outside menu layout')
    if extra=='black' or extra=='faithful' then
      check(same(rgb(before,2,2),{0,0,0}),label..' previously produced black bars')
    end
    if shot then
      write(label..'.png',image:encode('png'):getString())
      write(label..'-before.png',before:encode('png'):getString())
    end
    records[#records+1]={label=label,width=w,height=h,mode=mode,extra=extra,paper=inner,surround=outside}
  end
  for _,size in ipairs({{480,800},{1160,1536},{800,480}})do
    sample('default-'..size[1]..'x'..size[2],size[1],size[2],'gbc',nil,true)
  end
  palettes.LOGO2[1]={248,232,248};palettes.MEWMON[1]=palettes.LOGO2[1]
  sample('sgb-paper',480,800,'gbc',nil,true)
  for _,mode in ipairs({'classic','og_inv','gbc_inv'})do sample(mode,480,800,mode)end
  for _,extra in ipairs({'custom','shade','zone','truecolor'})do sample(extra,800,480,'gbc',extra)end
  for _,mode in ipairs({'black','white','palette'})do
    Letterbox.setMode(mode);sample('override-'..mode,480,800,'gbc',mode,mode=='black')
  end
  Letterbox.setMode('auto')
  local fixed=Faithful.fixedDisplay;Faithful.fixedDisplay=function()return true end;Faithful.locked=true
  sample('faithful',480,800,'gbc','faithful',true)
  Faithful.fixedDisplay=fixed;Faithful.locked=false
  P.setShadeMap(nil);P.setCustomRamp(nil);forcedShade=nil;customZone=nil
  -- Existing overseas/custom title and unrelated opaque screens keep their
  -- generic letterbox contracts; the title exception does not rewrite options.
  local saveBefore=require('src.link.Json').encode(Game.save)
  local function otherScreen(state,label)
    Stack:clear();Stack:push(state)
    for _,mode in ipairs({'black','white','palette'})do
      Letterbox.setMode(mode);local image=render()
      local expected={0,0,0}
      if mode=='white' then expected={1,1,1}
      elseif mode=='palette' then expected={P.paperShade(data)} end
      check(same(rgb(image,2,2),expected),label..' preserves '..mode..' surround')
    end
    Faithful.fixedDisplay=function()return true end;Faithful.locked=true
    local image=render();check(same(rgb(image,2,2),{0,0,0}),label..' preserves Faithful black bars')
    Faithful.fixedDisplay=fixed;Faithful.locked=false;Letterbox.setMode('auto')
  end
  Version.set('red');data.constants.language='en';local overseas=Title.new(Game)
  check(overseas.surroundColor==nil and not overseas.preferTitleSurround,'overseas title surround unchanged')
  overseas.phase='loop';overseas.scy=0;otherScreen(overseas,'overseas title')
  local image=render();check(same(rgb(image,2,2),{0,0,0}),'overseas title still renders automatic black bars')
  Version.set('red_jp');data.constants.language='ja'
  data.field.boot={title={logo=data.field.title.logo}}
  local custom=Title.new(Game);custom.phase='loop';custom.scy=0
  check(not custom.preferTitleSurround and custom.surroundColor==nil,'custom MOD title is not opted into preferred surround')
  otherScreen(custom,'custom title')
  data.field.boot=nil;data.screens={TitleState={}}
  check(not Title.new(Game).preferTitleSurround,'registered MOD title is not opted into preferred surround')
  data.screens=nil
  local opening=require('src.ui.IntroMovie').new(Game,function()end);opening.phase=4;opening.timer=0
  otherScreen(opening,'opening movie')
  check(require('src.link.Json').encode(Game.save)==saveBefore,'surround presentation never rewrites saved settings')
  write('results.json',require('src.link.Json').encode({checks=checks,records=records,romUsed=false,
    runtime='actual TitleState + Game.draw + Renderer.endFrame',nativeTitlePixelsUnchanged=true}))
  print('PASS '..checks..' actual title surround checks')
end
function love.load()local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end;love.event.quit(ok and 0 or 1)end
