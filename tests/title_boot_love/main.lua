-- Real title animation/rendering with synthetic geometric art and Misaki8x8.
-- No ROM graphics or TTF substitute is used; all sprite files are generated here.
local function run()
  local root, out = assert(os.getenv("TITLE_QA_ROOT")), assert(os.getenv("TITLE_QA_OUT"))
  package.path = root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local g, fs = love.graphics, love.filesystem
  g.setDefaultFilter("nearest", "nearest")
  local checks = 0
  local function check(ok, label) assert(ok, label); checks = checks + 1; print("PASS "..label) end
  local function write(name, bytes)
    local f = assert(io.open(out.."/"..name, "wb")); f:write(bytes); f:close()
  end
  local Classic = require("src.ui.ClassicUI")
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(fs.read("tools/rom_manifest_red_jp.json")))
  local function asset(name, w, h, draw)
    local c = g.newCanvas(w, h, {dpiscale=1})
    g.setCanvas(c); g.clear(0,0,0,0); g.setColor(0,0,0,1); draw(w,h)
    g.setScissor(); g.setCanvas()
    local path = "title-fixture-"..name..".png"
    fs.write(path,c:newImageData():encode("png")); c:release(); return path
  end
  local font = asset("font",128,128,function()
    for _, entry in ipairs(manifest.fontCharmap) do
      if entry.code < 256 then
        local x,y=entry.code%16*8,math.floor(entry.code/16)*8
        g.setScissor(x,y,8,8); Classic.bitmapText(entry.seq,x,y,1,{0,0,0,1})
      end
    end
    local function cell(code, draw)
      local x,y=code%16*8,math.floor(code/16)*8
      g.setScissor(x,y,8,8); g.setBlendMode("replace");g.setColor(0,0,0,0)
      g.rectangle("fill",x,y,8,8);g.setBlendMode("alpha");g.setColor(0,0,0,1);draw(x,y)
    end
    cell(0x7a,function(x,y)g.rectangle("fill",x,y+3,8,1)end)
    cell(0x7c,function(x,y)g.rectangle("fill",x+3,y,1,8)end)
    for _,code in ipairs({0x79,0x7b,0x7d,0x7e})do
      cell(code,function(x,y)g.rectangle("fill",x,y+3,8,1);g.rectangle("fill",x+3,y,1,8)end)
    end
    cell(0xe5,function(x,y)g.rectangle("fill",x+4,y+5,1,2);g.rectangle("fill",x+6,y+5,1,2)end)
    cell(0xe4,function(x,y)g.rectangle("line",x+4,y+4,2,2)end)
    cell(0xed,function(x,y)for i=0,5 do g.rectangle("fill",x+i,y+i/2,1,6-i)end end)
  end)
  local titleArt={
    logo=asset("logo",128,56,function(w,h)
      g.rectangle("line",1,1,w-2,h-2);g.rectangle("line",4,4,w-8,h-8)
      Classic.bitmapText("TITLE FIXTURE",12,16,1,{0,0,0,1})
      Classic.bitmapText("テストの タイトル",24,32,1,{0,0,0,1})
    end),
    versionRibbon=asset("ribbon",80,8,function()Classic.bitmapText("TEST TITLE",0,0,1,{0,0,0,1})end),
    player=asset("player",40,56,function()
      g.rectangle("line",10,0,20,24);g.rectangle("line",4,24,32,32)
      g.rectangle("fill",14,8,3,3);g.rectangle("fill",23,8,3,3)
    end),
    copyright={path=asset("copyright",152,8,function(w)
      for x=0,w-1,8 do g.rectangle("fill",x+1,2,6,4)end
    end)},
    gamefreakInc={path=asset("footer",72,8,function(w)
      for x=0,w-1,8 do g.rectangle("line",x+1,1,6,6)end
    end)},
    cycleSpecies={"FIXTURE"},
  }
  local mon=asset("mon",48,48,function()
    g.rectangle("line",4,4,40,40);g.rectangle("line",8,8,32,32)
    for i=0,3 do g.rectangle("fill",12+i*8,12+i*8,4,4)end
  end)
  local openingArt = {
    gamefreakLogo={path=asset("opening-logo",16,24,function()g.rectangle("line",2,2,12,20)end)},
    gamefreakText={path=asset("opening-text",80,8,function()Classic.bitmapText("INTRO TEST",0,0,1,{0,0,0,1})end)},
    bigStar={path=asset("star",16,16,function()g.rectangle("fill",6,1,4,14);g.rectangle("fill",1,6,14,4)end)},
    fallingStar={path=asset("small-star",8,8,function()g.rectangle("fill",2,2,4,4)end)},
    gengar={},nidorino={},
  }
  for i=1,3 do
    openingArt.gengar["frame"..i]={path=asset("fighter-left-"..i,56,56,function()
      g.rectangle("line",4,4,48,48);g.rectangle("fill",12+i*2,16,8,8);g.rectangle("fill",36,16+i*2,8,8)
    end)}
    openingArt.nidorino["frame"..i]={path=asset("fighter-right-"..i,56,56,function()
      g.rectangle("line",8,8,40,40);g.rectangle("fill",12,14+i*2,8,8);g.rectangle("fill",32+i*2,14,8,8)
    end)}
  end
  local data={constants={language="ja"},field={title=titleArt,intro=openingArt},
    pokemon={FIXTURE={spriteFront=mon}},
    font={language="ja",image=font,mainBase=0,
      charmap=manifest.fontCharmap,composites=manifest.fontComposites}}
  require("src.core.GameVersion").set("red_jp")
  local Font=require("src.render.Font");Font.load(data)
  require("src.core.Strings").load(data);require("src.ui.Theme").load(data)
  local Runtime=require("src.mods.Runtime")
  Runtime.install(require("src.mods.Events").new(),require("src.mods.Hooks").new())
  Runtime.hooks:wrap("render.viewport",function(next,ctx)local r=next(ctx);r.capture=true;return r end,0,"title-fixture")
  local Renderer=require("src.render.Renderer");Renderer:init()
  local Viewport=require("src.render.GameViewport")
  local Stack=require("src.core.StateStack");Stack:init()
  local Save=require("src.core.SaveData")
  local Game=require("src.core.Game")
  local Layout=require("src.ui.GameUILayout")
  local Touch=require("src.core.TouchControls")
  local Position=require("src.core.ScreenPosition")
  require("src.render.DotMatrix").setLevel(0)
  Touch:init();Touch.active=true
  check(Touch:ensureImages(),"actual touch control art loads")
  Position.setMode("center")
  local saved,key,writes,started,continued,settings=nil,nil,0,0,0,0
  Save.load=function()return saved end
  Save.save=function()writes=writes+1;return true end
  Game.data,Game.stack,Game.renderer=data,Stack,Renderer
  Game.save={options={jpDialogScale=0.75}}
  Game.input={wasPressed=function(_,button)return key==button end}
  Game.startNewGame=function()started=started+1 end
  Game.restoreSave=function(_,value,_,opts)
    check(value==saved and opts.continued and opts.freshBoot,"Continue preserves save and restoration contract")
    continued=continued+1
  end
  Game.openSessionMenu=function(_,page)check(page=="settings","settings opens requested page");settings=settings+1 end
  local function press(button)key=button;Stack:update(1/60);key=nil end
  local function boot()
    Game.save.options.jpSkipIntro=true -- explicit choice for title-layout cases
    Stack:clear();local title=Game:pushBootTitle()
    check(Stack:top()==title and title.isTitleScreen,"cold boot begins at actual TitleState")
    check(title.logo and title.logo:getWidth()==128,"title reads supplied asset through normal loader")
    for _=1,300 do if title.phase=="loop"then break end;Stack:update(1/60)end
    check(title.phase=="loop" and title.scy==0,"original logo animation settles without Game Freak intro")
    return title
  end
  local function menu(button)
    press(button or "a")
    for _=1,30 do if Stack:top().isPlayerStartMenu then break end;Stack:update(1/60)end
    check(Stack:top().isPlayerStartMenu,"A/START reaches JP commands through actual title transition")
    return Stack:top()
  end
  local records={}
  local function blackCount(image,x,y,w,h)
    local count=0
    for py=y,y+h-1 do for px=x,x+w-1 do
      local r,g,b,a=image:getPixel(px,py)
      if a>.5 and r<.5 and g<.5 and b<.5 then count=count+1 end
    end end
    return count
  end
  local function render(label,w,h,expectedFactor)
    love.window.setMode(w,h,{vsync=0})
    -- Exercise Android-like notch/navigation insets via the platform API.
    love.window.getSafeArea=function()return 12,24,w-24,h-40 end
    -- Exercise the production Game:draw state classification and placement,
    -- not a separately configured approximation of the renderer.
    Game:draw()
    check(Renderer.dialogScale==expectedFactor,label.." uses intended independent title/menu scale")
    local canvas=Viewport.target();g.setCanvas()
    -- The shipped controls are drawn in window space after GameViewport.
    g.setCanvas(canvas);Touch:draw();g.setCanvas()
    local pixels=canvas:newImageData()
    write(label.."-"..w.."x"..h..".png",pixels:encode("png"):getString())
    local r=Renderer:frameRects()
    check(r.uox>=0 and r.uoy>=0 and r.uox+160*r.Ux<=w+0.01 and r.uoy+144*r.Uy<=h+0.01,
      label.." composition fits viewport")
    check(math.abs(r.Ux-r.Uy)<0.001,label.." title/menu aspect ratio remains intact")
    local source=Renderer.canvas:newImageData()
    local nonwhite=blackCount(source,0,0,160,144)
    check(nonwhite>100,label.." renderer produces visible bitmap content")
    local top=Stack:top()
    if top.isPlayerStartMenu then
      check(Renderer.jpLayout=="page" and Renderer.jpPageCentered,label.." only start page requests centered placement")
      check(r.body~=nil,label.." derives usable playfield")
      local cx,cy=r.uox+r.uvpw/2,r.uoy+r.uvph/2
      check(math.abs(cx-(r.body.x+r.body.w/2))<=1 and math.abs(cy-(r.body.y+r.body.h/2))<=1,
        label.." entire start composition centered inside usable playfield")
      check(r.uoy>=r.body.y and r.uoy+r.uvph<=r.body.y+r.body.h,
        label.." start page stays clear of touch controls")
      records[#records+1]={label=label,width=w,height=h,scale=r.Up,
        x=r.uox,y=r.uoy,w=r.uvpw,h=r.uvph,usable=r.body}
    end
    if top.isTitleScreen and not top.menuOpen then
      check(blackCount(source,0,136,160,8)==0,label.." JP title footer contributes no pixels")
    end
    return source
  end
  local firstTitle=Game:pushBootTitle()
  check(Stack:top().isOpeningMovie,"first startup enters the original opening movie before title")
  check(not Game.save.options.jpIntroSeenByVersion,"first-start marker waits for movie completion")
  local firstPixels=render("opening-copyright",480,800,1)
  check(blackCount(firstPixels,80,88,72,8)>0,"first opening still draws synthetic studio copyright artwork")
  for _=1,300 do
    if Stack:top().phase==2 and Stack:top().timer>=70 then break end
    Stack:update(1/60)
  end
  check(Stack:top().phase==2,"original opening reaches shooting-star/studio animation")
  render("opening-studio",480,800,1)
  for _=1,700 do
    if Stack:top().phase==3 and Stack:top().timer>=90 then break end
    Stack:update(1/60)
  end
  check(Stack:top().phase==3,"original opening reaches animated monster fight")
  render("opening-fight",480,800,1)
  for _=1,2000 do if Stack:top()==firstTitle then break end;Stack:update(1/60)end
  check(Stack:top()==firstTitle,"completed original opening transitions to ROM title")
  check(Game.save.options.jpIntroSeenByVersion.red_jp,"only completed opening records first-start marker")
  check(Save.loadOptions().jpIntroSeenByVersion.red_jp,"first-start marker survives actual LÖVE filesystem write")
  check(writes==0,"watching the opening never writes game progress")
  for _,size in ipairs({{320,480},{480,800},{1080,720},{800,480}})do
    local w,h=size[1],size[2]
    saved=nil;local title=boot();render("title",w,h,1)
    local start=menu("start");render("new",w,h,0.75)
    press("down");press("a");check(settings>0,"settings remains available after title")
    press("b");check(Stack:top()==title and title.phase=="drop","B returns from commands to title")
    saved={player={name="レッド"},options={}};boot();start=menu("a")
    render("continue",w,h,0.75);press("a")
    check(continued>0,"Continue remains available after title")
    press("down");press("a");check(start.confirming,"existing save requires explicit new-game confirmation")
    render("confirm-new",w,h,0.75)
    local old=started;press("a");check(started==old and not start.confirming,"default confirmation safely returns")
    press("down");press("a");press("down");press("a")
    check(started==old+1,"explicit confirmation starts new game")
    check(writes==0,"title/menu navigation never overwrites existing report")
  end
  -- The new start-page alignment must not migrate all in-game pages.
  Stack.states={{isOpaque=true,draw=function()
    g.setColor(0,0,0,1);g.rectangle("fill",8,8,16,16)
  end}}
  render("ordinary-page",480,800,.75)
  local ordinary=Renderer:frameRects()
  check(Renderer.jpLayout=="page" and not Renderer.jpPageCentered,"ordinary page remains top-aligned")
  check(math.abs(ordinary.uoy-(ordinary.body.y+ordinary.margin/ordinary.dpiY))<=1,
    "ordinary page keeps existing margin placement")
  -- Direct image comparisons on the identical footer assets: no ROM-derived
  -- image is deleted, modified, or hidden from the opening's loader.
  local Title=require("src.ui.TitleState")
  local Version=require("src.core.GameVersion")
  local function footerPixels(title)
    local canvas=g.newCanvas(160,144,{dpiscale=1})
    g.setCanvas(canvas);g.clear(1,1,1,1);g.setColor(1,1,1,1)
    title:drawCopyright(136);g.setCanvas()
    local count=blackCount(canvas:newImageData(),0,136,160,8)
    canvas:release();return count
  end
  local original=Title.new(Game)
  check(original.copyImg and original.gfInc,"JP title still loads original copyright assets")
  check(footerPixels(original)==0,"JP default footer is suppressed at draw only")
  Version.set("red")
  check(footerPixels(Title.new(Game))>0,"same copyright images remain visible on overseas title")
  Version.set("red_jp")
  data.field.boot={title={gamefreakInc=titleArt.gamefreakInc}}
  check(footerPixels(Title.new(Game))>0,"explicit MOD footer image remains visible")
  data.field.boot=nil
  write("results.json",Json.encode({checks=checks,romUsed=false,font="Misaki8x8",art="synthetic geometry",startLayouts=records}))
  print(checks.." REAL TITLE BOOT CHECKS PASSED")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  love.graphics.setCanvas()
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
