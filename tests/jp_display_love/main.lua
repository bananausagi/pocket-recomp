-- Real LÖVE/GL integration checks using only handwritten fixture data.
-- JP_QA_ROOT=repo JP_QA_OUT=output XDG_DATA_HOME=isolated-save love this-dir
-- jp.62: JP_QA_NOJIT=1 runs Lua like LÖVE on arm64 Android, where jitsetup.lua
-- switches LuaJIT's compiler off (interpreter only).
if os.getenv("JP_QA_NOJIT")=="1" and jit and jit.off then jit.off();jit.flush() end
local function run()
  local root=assert(os.getenv("JP_QA_ROOT"))
  local output=assert(os.getenv("JP_QA_OUT"))
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
  local renderer=require('tests.gles_context')(check)
  write('renderer.json',Json.encode({renderer=renderer,romUsed=false}))
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
  local rendererId=os.getenv('JP_QA_RENDERER') or 'DRAMALESS_SHAPE'
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
  if os.getenv("JP_QA_VENDOR_MODS")=="1" then
    local function copy(from,to)
      assert(fs.createDirectory(to))
      for _,name in ipairs(fs.getDirectoryItems(from)) do
        local a,b=from.."/"..name,to.."/"..name
        if fs.getInfo(a).type=="directory" then copy(a,b)
        else assert(fs.write(b,assert(fs.read(a)))) end
      end
    end
    copy("vendor/jp-mods/"..rendererId,"mods/"..rendererId)
    SaveData.setModEnabled(opts,'DRAMALESS_SHAPE',rendererId=='DRAMALESS_SHAPE','red_jp')
    SaveData.setModEnabled(opts,'VOXEL_ASCENDANT',rendererId=='VOXEL_ASCENDANT','red_jp')
    if rendererId=='VOXEL_ASCENDANT' then
      opts.modOptions.VOXEL_ASCENDANT={renderScale=2,daytime='day',shadows=false,
        water='sky',aa=0,terrainHeights='world',battleBack=true,voxel_2d_battles=true}
    end
    assert(SaveData.saveOptions(opts))
    check(true,"unpackaged vendor source copied into isolated QA install")
  end
  if os.getenv("JP_QA_SETTINGS35")=="1" then require("tests.jp39_menu").cold(opts,check)end
  local Game=require("src.core.Game")
  Game.data=data
  Game.save={version="red_jp",options=opts,party={},player={map="FIX_TOWN",x=3,y=3,facing="down"},modData={}}
  local Loader=require("src.mods.Loader")
  Game.mods=Loader.new({generation=1})
  if os.getenv('JP_QA_EMULATE_ANDROID')=='1' then
    love.system.getOS=function()return 'Android'end
  end
  Game.mods:load(data)
  local ids={rendererId,"running_shoes","erilab_bottomless_bag","SHINY_POKEMON","ACCESS_PC_ANYWHERE","CONTROLLER_RUMBLE","all_pokemon_catchable_151_mod"}
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
  if os.getenv('JP_QA_TOUCH54')=='1' then
    require('tests.jp54_touch_windows')(Game,Renderer,check,write)
    print(checks..' REAL LOVE JP54 TOUCH CHECKS PASSED');return
  end
  if os.getenv('JP_QA_PRODUCT48')=='1' or os.getenv('JP_QA_PRODUCT47')=='1' then
    require('tests.jp44_product')(Game,Renderer,check,write)
    require('tests.jp45_home_cloud')(Game,Renderer,check,write)
    require('tests.jp45_touch')(Game,Renderer,check,write)
    require('tests.jp46_touch')(Game,Renderer,check,write)
    require('tests.jp47_touch')(Game,Renderer,check,write)
    if os.getenv('JP_QA_PRODUCT48')=='1' then
      require('tests.jp48_touch_areas')(Game,Renderer,check,write)
      if os.getenv('JP_QA_EMPTY_TAP')=='1' then
        require('tests.jp51_field_tap')(Game,Renderer,check,write)
        print(checks..' REAL LOVE JP51 TOUCH CHECKS PASSED');return
      end
      print(checks..' REAL LOVE JP48 TOUCH CHECKS PASSED');return
    end
    print(checks..' REAL LOVE JP47 TOUCH CHECKS PASSED');return
  end
  if os.getenv('JP_QA_PRODUCT46')=='1' then
    require('tests.jp44_product')(Game,Renderer,check,write)
    require('tests.jp45_home_cloud')(Game,Renderer,check,write)
    require('tests.jp45_touch')(Game,Renderer,check,write)
    require('tests.jp46_touch')(Game,Renderer,check,write)
    print(checks..' REAL LOVE JP46 TOUCH CHECKS PASSED');return
  end
  if os.getenv('JP_QA_PRODUCT45')=='1' then
    require('tests.jp44_product')(Game,Renderer,check,write)
    require('tests.jp45_home_cloud')(Game,Renderer,check,write)
    require('tests.jp45_touch')(Game,Renderer,check,write)
    print(checks..' REAL LOVE JP45 HOME AND BACKUP CHECKS PASSED');return
  end
  if os.getenv('JP_QA_PRODUCT44')=='1' then
    require('tests.jp44_product')(Game,Renderer,check,write)
    print(checks..' REAL LOVE JP44 STARTUP CHECKS PASSED');return
  end
  if os.getenv('JP_QA_PRODUCT43')=='1' then
    require('tests.jp43_product')(Game,Renderer,check,write)
    print(checks..' REAL LOVE JP43 PRODUCT CHECKS PASSED');return
  end
  if os.getenv('JP_QA_SETTINGS35')=='1' then
    require('tests.jp39_menu').live(Game,check)
    require('tests.jp35_settings_render')(Game,Renderer,check,write)
    print(checks..' REAL LOVE JP35 SETTINGS CHECKS PASSED')
    return
  end
  if os.getenv('JP_QA_FOLLOWER_COLOR27')=='1' then
    require('tests.jp27_follower_color_render')(Game,Game.mods.exports[rendererId].lib,check,write)
    print(checks..' REAL LOVE FOLLOWER COLOR CHECKS PASSED')
    return
  end
  if os.getenv('JP_QA_FOLLOWER_ICON26')=='1' then
    require('tests.jp26_follower_icon_render')(Game,Game.mods.exports[rendererId].lib,check,write)
    print(checks..' REAL LOVE FOLLOWER ICON CHECKS PASSED')
    return
  end
  if os.getenv('JP_QA_FOLLOWER_CARD25')=='1' then
    require('tests.jp25_follower_render')(Game,Game.mods.exports[rendererId].lib,check,write)
    print(checks..' REAL LOVE FOLLOWER CARD CHECKS PASSED')
    return
  end
  if os.getenv("JP_QA_SETTINGS")=="1" then
    require("tests.jp_settings_render")(Game,Renderer,check,write)
    write("love-fixture-result.txt",checks.." real-LÖVE settings checks passed; no retail ROM used.\n")
    print(checks.." REAL LOVE SETTINGS CHECKS PASSED")
    return
  end
  check(require("src.inventory.Bag").capacity(data)==255,"bag capacity remains 255")
  local shiny=Game.mods.exports.SHINY_POKEMON
  check(shiny and require("src.pokemon.Stats").isShiny(shiny.makeShinyDVs(function()return 1 end)),"shiny DVs follow Gen 2 rules")
  local pcCalls=0
  Game.overworld={map={def={tileset=originals and "OVERWORLD" or "INTERIOR"}},openPC=function()pcCalls=pcCalls+1 end}
  local rows=require("src.mods.Runtime").call("ui.start_menu.items",function(_,items)return items end,Game,{})
  local pc
  for _,row in ipairs(rows) do if row.label==require("src.core.Strings")("PC") then pc=row end end
  check(pc~=nil,originals and "original PC command exists outdoors" or "PC command exists indoors with false option")
  pc.onSelect();check(pcCalls==1,"PC command opens the engine PC")
  if originals then
    local Runtime=require("src.mods.Runtime")
    local frames=Runtime.call("movement.speed",function(n)return n end,16,
      {input={isDown=function(_,key)return key=="b" end},player={}})
    check(frames==8,"original Running Shoes halves walking duration while B is held")
    local active,bench,fainted={hp=20,level=5},{hp=15,level=3},{hp=0,level=3}
    local awarded,announced={},0
    local options=Game.save.options
    local prior=options.expShare;options.expShare="gen5"
    local battle={game=Game,party={active,bench,fainted},
      sayNext=function()announced=announced+1 end}
    Runtime.call("battle.exp_award",function()error("EXP Share did not intercept the award")end,
      {battle=battle,participants=1,alive={active},
       applyShare=function(mon,split)awarded[mon]=split end})
    options.expShare=prior
    check(awarded[active]==1 and awarded[bench]==2 and awarded[fainted]==nil and announced==1,
      "original EXP Share awards full/half shares and skips a fainted party member")
    local info=Game.mods.exports.useful_move_info.infoText(data,
      {id="TACKLE",name="たいあたり",type="NORMAL",power=35,accuracy=95,effect="DAMAGE"},{})
    check(info:find("たいあたり",1,true) and info:find("PWR: 35",1,true),
      "original Useful Move Info accepts Japanese move names")
  end
  local function page(name,draw)
    local c=g.newCanvas(160,144,{dpiscale=1});g.setCanvas(c);g.clear(1,1,1,1);draw();g.setCanvas()
    local large=g.newCanvas(640,576,{dpiscale=1});g.setCanvas(large);g.clear(1,1,1,1);g.setColor(1,1,1,1);g.draw(c,0,0,0,4,4)
    shot(large,name)
  end
  local Manager=require("src.mods.ManagerState")
  local manager=Manager.new(Game);manager:enter()
  page("fixture-mod-list",function()manager:draw()end)
  manager.currentMod=manager.byId[rendererId];manager:goTo("detail")
  page("fixture-mod-detail",function()manager:draw()end)
  -- Exercise every detail action, including the below-fold options row.
  for _=1,#manager:rowsForScreen() do manager:moveCursor(1);manager:draw() end
  check(manager.cursor>=manager.scroll and manager.cursor<=manager.scroll+1,"detail cursor remains visible")
  manager:openConfirm({string.rep("せっていを かくにんしてください。",40)},function()end)
  page("fixture-mod-confirm",function()manager:draw()end)
  manager:updateOverlay({wasPressed=function(_,key)return key=="right" end})
  check(manager.overlay.page==2,"long confirmation scrolls by pages")
  manager.overlay=nil
  local Options=require("src.ui.OptionsMenu")
  page("fixture-display-settings",function()
    local options=Options.new(Game)
    local selected={}
    for _,row in ipairs(options.rows) do if row.id=="jpDotMatrix" or row.id=="jpDialogScale" or row.id=="colors" then selected[#selected+1]=row end end
    check(#selected==3,"display controls are exposed in settings")
    require("src.ui.OptionRows").draw(Game,selected,2,0,"B:DONE (NO RESTART)")
  end)
  -- Real GL shader compilation, pixel alignment, palette/color preservation.
  local grid=require("src.render.DotMatrix")
  local c=g.newCanvas(160,144,{dpiscale=1});g.setCanvas(c);g.clear(0.6,0.8,0.4,1)
  grid.setLevel(2);grid.draw({width=160,height=144,uiPixelScale=4,viewX=8,viewY=8,viewWidth=144,viewHeight=128})
  g.setCanvas();local pixels=c:newImageData()
  local r1,g1,b1=pixels:getPixel(9,9);local r2,g2,b2=pixels:getPixel(11,11)
  check(r2<r1 and g2<g1 and b2<b1,"LCD seam darkens only grid edges")
  check(math.abs(r1-0.6)<0.01 and math.abs(g1-0.8)<0.01,"LCD preserves the selected palette inside cells")
  check(select(1,pixels:getPixel(3,3))>0.59,"LCD stays inside game viewport")
  shot(c,"fixture-dot-matrix")
  if os.getenv('JP_QA_OAK_RUNNING')=='1' then
    require('tests.jp_oak_running_render')(Game,Renderer,check,write)
    write('love-fixture-result.txt',checks..' real-LÖVE Oak running checks passed; no retail ROM used.\n')
    print(checks..' REAL SEVEN-MOD OAK RUNNING CHECKS PASSED')
    return
  end
  -- Compose a smaller real textbox and choice over a colored scene. The
  -- sample outside the shrunken box used to retain the old white window.
  local Runtime=require("src.mods.Runtime")
  Runtime.hooks:wrap("render.viewport",function(next,ctx)local r=next(ctx);r.capture=true;return r end,0,"qa")
  local Viewport=require("src.render.GameViewport")
  Viewport.begin(1);Renderer.uiCentered=true;Renderer.dialogScale=1
  local fullRect=Renderer:frameRects()
  Renderer.dialogScale=0.5
  Renderer:beginFrame(true)
  local box=require("src.render.TextBox").new(Game,"はなす まどを\nちいさく しました。",nil,{instant=true})
  box:draw()
  require("src.ui.ChoiceBox").new(Game,function()end,{anchor="bottom"}):draw()
  local rect=Renderer:frameRects()
  local background=g.newCanvas(rect.pw,rect.ph,{dpiscale=1})
  g.setCanvas(background);g.clear(0.2,0.5,0.7,1)
  Renderer:setWorldOverride(background)
  Viewport.setTarget();g.clear(0.2,0.5,0.7,1)
  Renderer:endFrame()
  local surface=Viewport.target();g.setCanvas()
  local frame=surface:newImageData()
  local x=math.floor(fullRect.uox+4*fullRect.Up/fullRect.dpiX)
  local y=math.floor(fullRect.uoy+120*fullRect.Up/fullRect.dpiY)
  local rr,gg,bb=frame:getPixel(x,y)
  check(bb>rr+0.2,"no full-size textbox fragment remains after shrinking")
  shot(surface,"fixture-small-dialog")
  Renderer.dialogScale=1
  -- Exercise the real voxel arena renderer under both phone orientations.
  -- A reserved viewport is smaller than the OS window, reproducing the
  -- source of the reported battle cropping without an Android device.
  local V=Game.mods.exports[rendererId].lib
  if os.getenv('JP_QA_ASCENDANT_WORLD')=='1' then
    require('tests.jp19_ascendant_world_render')(Game,Renderer,V,check,write)
    return
  end
  local Scene=V.require("VoxelBattleScene")
  data.tilesets.FIX_OUT.tilesPerRow=love.image.newImageData(data.tilesets.FIX_OUT.image):getWidth()/8
  data.tilesets.FIX_OUT.walkable={0,1,2}
  local map=require("src.world.MapLoader").load(data,"FIX_TOWN")
  local state={map=map,neighbors={},player={cellX=8,cellY=8},paletteNameFor=function()return "PALLET" end}
  Game.overworld=state
  local arena=assert(V.require("BattleArena").find(map,8,8,false),"fixture has a battle clearing")
  for _=1,150 do
    if Scene.ready(state,arena) then break end
    V.require("ChunkMesher").pump(true)
  end
  check(Scene.ready(state,arena),"fixture voxel terrain is ready")
  if os.getenv('JP_QA_SCENE42')=='1' then
    require('tests.jp42_scene_regression')(Game,Renderer,V,state,check,write)
    print(checks..' REAL LOVE JP42 SCENE CHECKS PASSED');return
  end
  if os.getenv('JP_QA_AREA40')=='1' then
    require('tests.jp40_field_transition')(Game,Renderer,V,state,check,write)
    if os.getenv('JP_QA_NEIGHBOR41')=='1' then require('tests.jp41_atlas_queue')(Game,V,check,write)end
    print(checks..' REAL LOVE JP40 AREA CHECKS PASSED');return
  end
  if os.getenv('JP_QA_FIELD38')=='1' then
    require('tests.jp38_field_render')(Game,Renderer,V,state,check,write)
    write('love-fixture-result.txt',checks..' real-LÖVE field checks passed; no ROM used.\n')
    print(checks..' REAL LOVE FIELD38 CHECKS PASSED')
    return
  end
  if os.getenv('JP_QA_WINDOWS36')=='1' then
    require('tests.jp36_windows_render')(Game,Renderer,V,state,check,write)
    write('love-fixture-result.txt',checks..' real-LÖVE floating window checks passed; no ROM used.\n')
    print(checks..' REAL LOVE FLOATING WINDOW CHECKS PASSED')
    return
  end
  if os.getenv('JP_QA_FIRST_BATTLE58')=='1' then
    -- jp.58 first-battle cold-start timing (tests/jp58_first_battle_profile.lua).
    require('tests.jp_battle_presentation_render')(Game,Renderer,V,state,check,write)
    print(checks..' REAL LOVE JP58 FIRST BATTLE PROFILE CHECKS PASSED')
    return
  end
  if os.getenv('JP_QA_BATTLE_UI')=='1' then
    require('tests.jp_battle_presentation_render')(Game,Renderer,V,state,check,write)
    write('love-fixture-result.txt',checks..' real-LÖVE battle presentation checks passed; no retail ROM used.\n')
    print(checks..' REAL LOVE BATTLE PRESENTATION CHECKS PASSED')
    return
  end
  if os.getenv("JP_QA_FREE_CAMERA")=="1" then
    require("tests.jp_free_camera_render")(Game,Renderer,V,state,check,write)
    write("love-fixture-result.txt",checks.." real-LÖVE free-camera checks passed; no retail ROM used.\n")
    print(checks.." REAL LOVE FREE CAMERA CHECKS PASSED")
    return
  end
  if os.getenv("JP_QA_LAYOUT")=="1" then
    require("tests.jp_battle_sprite_render")(Game,check)
    require("tests.jp_layout_render")(Game,Renderer,V,state,check,write)
    write("love-fixture-result.txt",checks.." real-LÖVE layout checks passed; no retail ROM used.\n")
    print(checks.." REAL LOVE LAYOUT CHECKS PASSED")
    return
  end
  if os.getenv("JP_QA_PLAYER_CENTER")=="1" then
    require("tests.jp_player_center_render")(Game,Renderer,V,state,check,write)
    write("love-fixture-result.txt",checks.." real-LÖVE player-centre checks passed; no retail ROM or Android device used.\n")
    print(checks.." REAL LOVE PLAYER CENTRE CHECKS PASSED")
    return
  end
  local wanted
  Runtime.hooks:wrap("render.viewport",function()return wanted end,100,"qa-reserved")
  for _,size in ipairs({{480,800,480,480},{800,480,640,360},{600,960,540,640}}) do
    g.setCanvas();assert(love.window.setMode(size[1],size[2],{vsync=0}))
    wanted={x=0,y=0,width=size[3],height=size[4],capture=true}
    Viewport.begin(1)
    for _,uiw in ipairs({160,304}) do
      Renderer:setUISize(uiw,144);Renderer.uiFill=true
      arena.uiWide=uiw==304
      local focalPerPixel
      for _,factor in ipairs({0.5,0.75,1}) do
        Renderer.dialogScale=factor
        local expected=Renderer:frameRects()
        local actorPass=false
        local result=Scene.render(state,arena,function(ctx)
          actorPass=ctx.width>0 and ctx.height>0
          local m=ctx.vp
          local sx=math.sqrt(m[1]^2+m[2]^2+m[3]^2)*ctx.width
          local sy=math.sqrt(m[5]^2+m[6]^2+m[7]^2)*ctx.height
          check(math.abs(sx-sy)<0.0001,
            "3D battle projection keeps equal physical X/Y scale at window size "..factor)
          local focal=sx/expected.Up
          if focalPerPixel then
            check(math.abs(focal-focalPerPixel)<0.0001,
              "3D actor projection follows the same window size as native move FX")
          else focalPerPixel=focal end
        end)
        check(result and result:getWidth()==expected.pw and result:getHeight()==expected.ph,
          ("voxel arena uses %dx%d playfield inside %dx%d window (UI %d, scale %.2f)"):format(expected.pw,expected.ph,size[1],size[2],uiw,factor))
        check(actorPass,"battle actor pass runs at the reserved dimensions")
      end
    end
    check(g.getWidth()==size[1] and g.getHeight()==size[2],"compatibility never changes global window dimensions")
  end
  Renderer.dialogScale=1
  check(#Game.mods.errors==0,#ids.." MODs report no runtime errors")
  for _,entry in ipairs(originalEntries or {}) do
    local unchanged=true
    local different={}
    for path,hash in pairs(entry.sources) do
      -- The installer normalizes Windows ZIP separators without changing
      -- file bytes (Controller Rumble's published ZIP uses backslashes).
      local bytes=fs.read("mods/"..entry.id.."/"..path:gsub("\\","/"))
      local same=bytes~=nil and love.data.encode("string","hex",love.data.hash("sha256",bytes))==hash
      unchanged=unchanged and same
      if not same then different[#different+1]=path..(bytes and " (changed)" or " (missing)") end
    end
    check(unchanged,entry.id.." manifest and every Lua file remain byte-identical after execution "..table.concat(different,", "))
  end
  write("love-fixture-result.txt",checks.." real-LÖVE fixture checks passed; no retail ROM or Android device used.\n")
  print(checks.." REAL LOVE FIXTURE CHECKS PASSED")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1) else love.event.quit(0) end
end
