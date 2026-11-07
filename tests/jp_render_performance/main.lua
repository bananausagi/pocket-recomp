-- Real LÖVE/GL integration checks using only handwritten fixture data.
-- JP_PERF_ROOT=repo JP_PERF_OUT=output XDG_DATA_HOME=isolated-save love this-dir
local function run()
  local root=assert(os.getenv("JP_PERF_ROOT"))
  local output=assert(os.getenv("JP_PERF_OUT"))
  assert(love.filesystem.getInfo("src/core/Game.lua"),"run from a QA app with the repository assets mounted")
  package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local g,fs=love.graphics,love.filesystem
  g.setDefaultFilter("nearest","nearest")
  local checks=0
  local function check(ok,message)
    assert(ok,message); checks=checks+1; print("PASS "..message)
  end
  local function write(name,bytes)
    local f=assert(io.open(output.."/"..name,"wb")); f:write(bytes); f:close()
  end
  local function shot(canvas,name)
    g.setCanvas(); write(name..".png",canvas:newImageData():encode("png"):getString())
  end
  local Json=require("src.link.Json")
  local m=assert(Json.decode(fs.read("tools/rom_manifest_red_jp.json")))
  local Font=require("src.render.Font")
  -- Test-only kana atlas, rasterized from the bundled CC-BY Plain Pixel.
  -- It uses the real JP charmap/composite geometry, never cartridge pixels.
  local sheet=g.newCanvas(128,128,{dpiscale=1})
  g.setCanvas(sheet); g.clear(0,0,0,0)
  local kana=g.newFont(Font.PLAINPIXEL,10,"mono",1)
  g.setFont(kana); g.setColor(0,0,0,1)
  local tiles={}
  for _,entry in ipairs(m.fontCharmap) do
    tiles[#tiles+1]=entry.seq
    if entry.code<256 then
      local x,y=(entry.code%16)*8,math.floor(entry.code/16)*8
      g.setScissor(x,y,8,8); g.print(entry.seq,x,y+7-kana:getBaseline())
    end
  end
  g.setScissor()
  local function cell(code,fn)
    local x,y=(code%16)*8,math.floor(code/16)*8
    g.setScissor(x,y,8,8); g.setBlendMode("replace"); g.setColor(0,0,0,0)
    g.rectangle("fill",x,y,8,8); g.setBlendMode("alpha");g.setColor(0,0,0,1)
    fn(x,y);g.setScissor()
  end
  cell(0x7a,function(x,y)g.rectangle("fill",x,y+3,8,1)end)
  cell(0x7c,function(x,y)g.rectangle("fill",x+3,y,1,8)end)
  for _,c in ipairs({0x79,0x7b,0x7d,0x7e}) do cell(c,function(x,y)
    g.rectangle("fill",x,y+3,8,1);g.rectangle("fill",x+3,y,1,8)
  end) end
  cell(229,function(x,y)g.rectangle("fill",x+4,y+5,1,2);g.rectangle("fill",x+6,y+5,1,2)end)
  cell(228,function(x,y)g.rectangle("line",x+4,y+4,2,2)end)
  g.setCanvas();fs.write("fixture-font.png",sheet:newImageData():encode("png"))
  local data=require("tests.fixture_data").load()
  require("src.core.GameVersion").set("red_jp")
  require("src.core.Data").seedDefaults(data,"red_jp")
  data.constants.language="ja"
  data.constants.boxCount,data.constants.boxSize=8,30
  data.font={language="ja",image="fixture-font.png",mainBase=0,
    charmap=m.fontCharmap,composites=m.fontComposites,ttf={size=15,tiles=tiles}}
  require("tests.catchable151_fixture").apply(data,m)
  local SaveData=require("src.core.SaveData")
  local Pack=require("src.mods.JapaneseStarterPack")
  -- A supplied jp.2 .love allows a real ZIP-to-ZIP update regression.
  local old=os.getenv("JP_QA_PREVIOUS_LOVE")
  local oldGroup="jp2"
  local previousEntries,previousFiles
  if old then
    local previous=assert(io.open(old,"rb"));local bytes=previous:read("*a");previous:close()
    assert(fs.mount(fs.newFileData(bytes,"previous.love"),"previous",true))
    local entries=assert(Json.decode(fs.read("previous/assets/jp-mods/catalog.json")))
    previousEntries,previousFiles=entries,{}
    if fs.read("previous/src/core/Version.lua"):find("0.1.0-jp.3",1,true) then oldGroup="jp3" end
    local opts={jpStarterPackV1={},musicVol=3,modOptions={running_shoes={fx="off"},
      SHINY_POKEMON={shiny_rate="gen2",debug_ow=false},ACCESS_PC_ANYWHERE={overworld_only=false}},
      jpDotMatrix=0,jpDialogScale=1}
    SaveData.setModEnabled(opts,"running_shoes",false,"red_jp")
    for _,entry in ipairs(entries) do
      assert(require("src.mods.LauncherMods").installZip("previous/"..entry.archive,{expectId=entry.id}))
      opts.jpStarterPackV1[entry.id]=entry.version
      local function remember(path)
        for _,name in ipairs(fs.getDirectoryItems(path)) do
          local full=path.."/"..name
          if fs.getInfo(full).type=="directory" then remember(full)
          else previousFiles[full]=fs.read(full) end
        end
      end
      remember("mods/"..entry.id)
    end
    assert(SaveData.saveOptions(opts))
  end
  local installed,err=Pack.install();check(installed~=nil,"validated ZIP installation: "..tostring(err or "ok"))
  local opts=SaveData.loadOptions()
  if old then
    check(opts.musicVol==3 and opts.modOptions.running_shoes.fx=="off","existing options survive real upgrade")
    check(SaveData.modEnabled(opts,"running_shoes","red_jp")==false,"disabled mod survives real upgrade")
    check(opts.jpDotMatrix==0 and opts.jpDialogScale==1,"display choices survive real upgrade")
    local versions=require("src.mods.LauncherMods").installedVersions()
    local allUnchanged=true
    for _,entry in ipairs(previousEntries) do
      if versions[entry.id]~=entry.version then allUnchanged=false end
    end
    if allUnchanged then
      local same=true
      for path,bytes in pairs(previousFiles) do if fs.read(path)~=bytes then same=false end end
      check(same,"unchanged previous MOD files remain byte-identical")
      check(versions.all_pokemon_catchable_151_mod~=nil,"151 MOD added during update")
    else
      check(fs.getInfo("jp-mod-backups/"..oldGroup.."/DRAMALESS_SHAPE/manifest.json")~=nil,"real previous MOD backup exists")
    end
    SaveData.setModEnabled(opts,"running_shoes",true,"red_jp")
    assert(SaveData.saveOptions(opts))
  end
  check(opts.modOptions.SHINY_POKEMON.shiny_rate=="gen2","initial shiny rate is 1/8192")
  check(opts.modOptions.ACCESS_PC_ANYWHERE.overworld_only==false,"PC is available indoors by default")
  check(Pack.install()==false,"subsequent startup does not reset options")
  local originals=os.getenv("JP_QA_ORIGINAL_MODS")
  local originalEntries
  if originals then
    local f=assert(io.open(originals.."/provenance.json","rb"))
    originalEntries=assert(Json.decode(f:read("*a")));f:close()
    for _,entry in ipairs(originalEntries) do
      local archive=assert(io.open(originals.."/"..entry.file,"rb"))
      local bytes=archive:read("*a");archive:close()
      check(love.data.encode("string","hex",love.data.hash("sha256",bytes))==entry.sha256,
        entry.id.." is the original downloaded ZIP")
      local p="original-"..entry.id..".zip";assert(fs.write(p,bytes))
      local ok,err=require("src.mods.LauncherMods").installZip(p,{expectId=entry.id,replace=true})
      check(ok,entry.id.." imports unchanged: "..tostring(err))
    end
    check(Pack.install()==false,"starter pack does not overwrite original mods on next boot")
  end
  local Game=require("src.core.Game")
  Game.data=data
  Game.save={version="red_jp",options=opts,party={},player={map="FIX_TOWN",x=3,y=3,facing="down"},modData={}}
  local Loader=require("src.mods.Loader")
  Game.mods=Loader.new({generation=1})
  Game.mods:load(data)
  local ids={"DRAMALESS_SHAPE","running_shoes","erilab_bottomless_bag","SHINY_POKEMON","ACCESS_PC_ANYWHERE","CONTROLLER_RUMBLE","all_pokemon_catchable_151_mod"}
  if originalEntries then
    ids={};for _,entry in ipairs(originalEntries) do ids[#ids+1]=entry.id end
  end
  for _,id in ipairs(ids) do
    local mod=Game.mods.mods[id]
    check(mod and mod.state=="loaded",id.." loads with JP data ("..tostring(mod and mod.failure)..")")
  end
  Font.load(data)
  require("src.core.Strings").load(data)
  require("src.ui.Theme").load(data)
  require("src.render.Pipelines").install(data)
  local Renderer=require("src.render.Renderer")
  Renderer:init();Game.renderer=Renderer
  Game.stack={push=function(_,state)Game.lastScreen=state end,pop=function()end}
  Game.input={wasPressed=function()return false end}
  require("src.mods.Runtime").emit("game.ready",{game=Game})
  local V=Game.mods.exports.DRAMALESS_SHAPE.lib
  data.tilesets.FIX_OUT.tilesPerRow=love.image.newImageData(data.tilesets.FIX_OUT.image):getWidth()/8
  data.tilesets.FIX_OUT.walkable={0,1,2}
  local map=require("src.world.MapLoader").load(data,"FIX_TOWN")
  local Cam=require("src.render.Camera")
  local state={map=map,neighbors={},entities={},ghosts={},player={cellX=8,cellY=8,px=128,py=128},camera=Cam.new(),paletteNameFor=function()return "PALLET"end}
  Game.overworld=state
  Game.stack={states={state},top=function()return state end,visibleBase=function()return 1 end}
  local Scene=V.require("VoxelScene")
  local Pipeline=require("src.render.Pipelines")
  local Palette=require("src.render.PaletteFX")
  local Voxel=V.require("VoxelState")
  Pipeline.setLevel("voxel",2)
  Palette.setMode("classic")
  Voxel.angle=math.rad(25)
  for _=1,200 do
    if Scene.prefetch(state)then break end
    V.require("ChunkMesher").pump(true)
  end
  assert(Scene.prefetch(state),"3D world terrain must be ready")
  local function paletteFor()return Palette.pal(data,"PALLET")end
  local noop=function()end
  local modules={Renderer=Renderer,PaletteFX=Palette,Pipelines=Pipeline,Assets=require("src.render.Assets")}
  for _,name in ipairs({"VoxelScene","Voxel3D","ChunkMesher","TerrainAtlas","ShadowMap","Water","Sky","DayNight","Quality","Mat4","AntiAlias","TiltShift"})do modules[name]=V.require(name)end
  local prof,originals={},{ }
  local function profile(on)
    for name,m in pairs(modules)do
      if on then
        originals[name]={}
        for key,fn in pairs(m)do
          if type(fn)=="function"then
            local label=name.."."..key;local stat={name=label,calls=0,seconds=0,kb=0};prof[label]=stat;originals[name][key]=fn
            m[key]=function(...)
              local t=love.timer.getTime();local mem=collectgarbage("count");local a,b,c,d,e=fn(...);stat.kb=stat.kb+collectgarbage("count")-mem;stat.seconds=stat.seconds+love.timer.getTime()-t;stat.calls=stat.calls+1;return a,b,c,d,e
            end
          end
        end
      else for key,fn in pairs(originals[name]or{})do m[key]=fn end end
    end
  end
  local alloc={canvas=0,mesh=0,image=0,shader=0}
  for key,kind in pairs({newCanvas="canvas",newMesh="mesh",newImage="image",newShader="shader"})do
    local fn=g[key];g[key]=function(...)alloc[kind]=alloc[kind]+1;return fn(...)end
  end
  local ctx
  local lastStats
  local Pause=require("src.render.PausedFrame")
  local captured,capturedImages,pendingShot={},{},nil
  local function drawFrame(i,moving,cached)
    local Viewport=require("src.render.GameViewport");Viewport.begin(1)
    local hit=cached and Pause.begin(Game)
    if not hit then
    Renderer:beginFrame(true);Renderer:beginWorldPass()
    local vw,vh=Renderer:worldViewSize()
    local offset=moving and i%90/4 or 0
    state.camera.x=128-vw/2+offset;state.camera.y=128-vh/2
    ctx={state=state,paletteFor=paletteFor,drawFx=noop,scale=3,level=2,vw=vw,vh=vh,width=480,height=800}
    local canvas=assert(Pipeline.drawWorld("voxel",ctx),"real voxel world render declined")
    Renderer:setWorldOverride(canvas,vw,vh);Renderer:endWorldPass()
    g.setColor(1,1,1,1);Font.drawBox(2,12,16,5)
    Font.draw("ABC 012345",24,108);Font.draw("せってい",24,124)
    Viewport.setTarget()
    Renderer:endFrame();Viewport.finish(Game)
    if cached then Pause.finish() end
    end
    lastStats=g.getStats()
    if pendingShot then
      local name=pendingShot;pendingShot=nil
      g.captureScreenshot(function(data) captured[name]=data:getString();capturedImages[name]=data;write(name..".png",data:encode("png"):getString()) end)
    end
    g.present()
  end
  local report={renderer={g.getRendererInfo()},samples={},profile={},rom_used=false,fixture="handwritten FIX_TOWN terrain, no characters",settings={palette="classic",voxel=2,resolution="MOD default",window={480,800}}}
  local function sample(label,moving,cached,withGC)
    Pause.release()
    Game.sessionMenu=cached and {} or nil
    for i=1,25 do drawFrame(i,moving,cached)end
    collectgarbage("collect")
    for k in pairs(alloc)do alloc[k]=0 end
    if not withGC then collectgarbage("stop") end
    local before=collectgarbage("count");local t=love.timer.getTime();local cpu=os.clock()
    for i=1,120 do drawFrame(i,moving,cached)end
    local secs=love.timer.getTime()-t;local cpusecs=os.clock()-cpu;local after=collectgarbage("count")
    collectgarbage("restart")
    local rec={label=label,cached=cached or false,gc_enabled=withGC or false,frames=120,wall_ms=secs/120*1000,cpu_ms=cpusecs/120*1000,fps=120/secs,lua_kb_per_frame=(after-before)/120,graphics_allocations={}}
    for k,v in pairs(alloc)do rec.graphics_allocations[k]=v end
    rec.graphics_stats=lastStats;report.samples[#report.samples+1]=rec
    print(Json.encode(rec))
  end
  for i=1,3 do
    sample("stationary-live-"..i,false,false)
    sample("stationary-cached-"..i,false,true)
    sample("moving-live-"..i,true,false)
  end
  for i=1,3 do
    sample("gc-live-"..i,false,false,true)
    sample("gc-cached-"..i,false,true,true)
  end
  local function difference(first,second)
    local a,b=capturedImages[first],capturedImages[second]
    local w,h=a:getDimensions();local result={pixels=0,max_channel=0,ui_pixels=0}
    local r=Renderer:frameRects()
    local ux,uy=r.uox+16*r.Ux,r.uoy+96*r.Uy
    local uw,uh=128*r.Ux,40*r.Uy
    for y=0,h-1 do for x=0,w-1 do
      local ar,ag,ab,aa=a:getPixel(x,y);local br,bg,bb,ba=b:getPixel(x,y)
      local d=math.max(math.abs(ar-br),math.abs(ag-bg),math.abs(ab-bb),math.abs(aa-ba))
      if d>0 then
        result.pixels=result.pixels+1;result.max_channel=math.max(result.max_channel,d)
        result.min_x=math.min(result.min_x or x,x);result.min_y=math.min(result.min_y or y,y)
        result.max_x=math.max(result.max_x or x,x);result.max_y=math.max(result.max_y or y,y)
        if x>=ux and y>=uy and x<ux+uw and y<uy+uh then result.ui_pixels=result.ui_pixels+1 end
      end
    end end
    return result
  end
  report.direct_to_capture={}
  Pause.release();Game.sessionMenu={}
  for i=1,4 do drawFrame(i,false)end
  pendingShot="live-reference";drawFrame(1,false)
  pendingShot="live-second";drawFrame(1,false)
  pendingShot="cached-first";drawFrame(1,false,true)
  pendingShot="cached-repeat";drawFrame(1,false,true)
  check(captured["live-reference"]==captured["live-second"],"live render is deterministic")
  report.direct_to_capture.portrait=difference("live-reference","cached-first")
  check(report.direct_to_capture.portrait.ui_pixels==0,"native UI text and frame pixels are identical through first capture")
  check(report.direct_to_capture.portrait.pixels<=20,"only isolated GL nearest-sample world boundary pixels may differ")
  check(captured["cached-repeat"]==captured["cached-first"],"repeated paused frame is pixel-identical")
  Pause.invalidate();pendingShot="cached-invalidated";drawFrame(1,false,true)
  check(captured["cached-first"]==captured["cached-invalidated"],"invalidated capture remains pixel-identical")
  Palette.setMode("og");Pause.invalidate()
  pendingShot="changed-live";drawFrame(1,false)
  pendingShot="changed-cached";drawFrame(1,false,true)
  report.direct_to_capture.changed_palette=difference("changed-live","changed-cached")
  check(report.direct_to_capture.changed_palette.ui_pixels==0,"changed palette UI exactly matches live rendering")
  check(captured["changed-cached"]~=captured["cached-first"],"palette setting refresh changes visible pixels")
  
  Palette.setMode("classic");Pause.invalidate()
  love.window.setMode(800,480,{vsync=0})
  pendingShot="landscape-live";drawFrame(1,false)
  pendingShot="landscape-first";drawFrame(1,false,true)
  pendingShot="landscape-repeat";drawFrame(1,false,true)
  check(captured["landscape-first"]==captured["landscape-repeat"],"rotation refreshes a stable native landscape snapshot")
  report.direct_to_capture.landscape=difference("landscape-live","landscape-first")
  check(report.direct_to_capture.landscape.ui_pixels==0,"landscape UI pixels are unchanged")
  Pause.release()
  pendingShot="landscape-reopened";drawFrame(1,false,true)
  check(captured["landscape-first"]==captured["landscape-reopened"],"release then reopen renders the same native image")
  love.window.setMode(480,800,{vsync=0})
  Pause.release();Game.sessionMenu=nil
  collectgarbage("collect");collectgarbage("stop")
  profile(true)
  for i=1,30 do drawFrame(i,true)end
  profile(false)
  collectgarbage("restart")
  for _,stat in pairs(prof)do if stat.calls>0 then report.profile[#report.profile+1]=stat end end
  table.sort(report.profile,function(a,b)return a.seconds>b.seconds end)
  -- Exercise the actual Game:draw early return, not only the cache helper.
  local Touch=require("src.core.TouchControls")
  local originalTouchDraw=Touch.draw
  local worldDraws,controlsDraws,menuDraws=0,0,0
  Touch.draw=function()controlsDraws=controlsDraws+1 end
  state.draw=function()
    worldDraws=worldDraws+1
    Renderer:beginWorldPass()
    local vw,vh=Renderer:worldViewSize()
    state.camera.x,state.camera.y=128-vw/2,128-vh/2
    local canvas=assert(Pipeline.drawWorld("voxel",{state=state,cam=state.camera,
      vw=vw,vh=vh,paletteFor=paletteFor,drawFx=noop,scale=3,level=2,width=480,height=800}))
    Renderer:setWorldOverride(canvas,vw,vh);Renderer:endWorldPass()
  end
  Game.sessionMenu={draw=function()menuDraws=menuDraws+1 end}
  Game:draw();g.present();Game:draw();g.present()
  check(worldDraws==1,"actual Game:draw renders paused 3D world once")
  check(controlsDraws==2 and menuDraws==2,"actual Game:draw keeps controls and menu live")
  Pause.invalidate();Game:draw();g.present()
  check(worldDraws==2,"actual Game:draw refreshes invalidated settings preview")
  Game.sessionMenu=nil;Game:draw();g.present()
  check(worldDraws==3,"actual Game:draw resumes world rendering immediately")
  Touch.draw=originalTouchDraw
  Pause.release()
  report.pixel_checks=checks
  write("performance.json",Json.encode(report))
  print("RESULT benchmark complete")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then love.graphics.setCanvas();print(err);love.event.quit(1)else love.event.quit(0)end
end
