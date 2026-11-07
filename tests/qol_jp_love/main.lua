-- Unmodified author QoL ZIP with six pinned jp.5 companions and optional All151.
-- Real LÖVE/GL integration checks using only handwritten fixture data.
-- JP_QA_ROOT=repo JP_QA_OUT=output XDG_DATA_HOME=isolated-save love this-dir
local function run()
  local root=assert(os.getenv("JP_QA_ROOT"))
  local output=assert(os.getenv("JP_QA_OUT"))
  local withCatchable=os.getenv("JP_QOL_WITH_CATCHABLE")=="1"
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
  if withCatchable then require("tests.catchable151_fixture").apply(data,m) end
  local SaveData=require("src.core.SaveData")
  local Pack=require("src.mods.JapaneseStarterPack")
  local installed,err=Pack.install();check(installed~=nil,"validated ZIP installation: "..tostring(err or "ok"))
  local opts=SaveData.loadOptions()
  check(opts.modOptions.SHINY_POKEMON.shiny_rate=="gen2","initial shiny rate is 1/8192")
  check(opts.modOptions.ACCESS_PC_ANYWHERE.overworld_only==false,"PC is available indoors by default")
  check(Pack.install()==false,"subsequent startup does not reset options")
  local qf=assert(io.open(os.getenv("JP_QOL_ZIP"),"rb"));local qb=qf:read("*a");qf:close()
  assert(fs.write("quality_of_life-original.zip",qb))
  local ok,detail=require("src.mods.LauncherMods").installZip("quality_of_life-original.zip",{expectId="quality_of_life"})
  check(ok,"unmodified QoL 1.3.0 ZIP imports: "..tostring(detail))
  local Game=require("src.core.Game")
  Game.data=data
  Game.save={version="red_jp",options=opts,party={},player={map="FIX_TOWN",x=3,y=3,facing="down"},modData={}}
  local Loader=require("src.mods.Loader")
  Game.mods=Loader.new({generation=1})
  Game.mods:load(data)
  local ids={"DRAMALESS_SHAPE","running_shoes","erilab_bottomless_bag","SHINY_POKEMON","ACCESS_PC_ANYWHERE","CONTROLLER_RUMBLE","quality_of_life"}
  if withCatchable then ids[#ids+1]="all_pokemon_catchable_151_mod" end
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
  check(require("src.inventory.Bag").capacity(data)==255,"bag capacity remains 255")
  local shiny=Game.mods.exports.SHINY_POKEMON
  check(shiny and require("src.pokemon.Stats").isShiny(shiny.makeShinyDVs(function()return 1 end)),"shiny DVs follow Gen 2 rules")
  local pcCalls=0
  Game.overworld={map={def={tileset="INTERIOR"}},openPC=function()pcCalls=pcCalls+1 end}
  local rows=require("src.mods.Runtime").call("ui.start_menu.items",function(_,items)return items end,Game,{})
  local pc
  for _,row in ipairs(rows) do if row.label==require("src.core.Strings")("PC") then pc=row end end
  check(pc~=nil,"PC command exists indoors with false option")
  pc.onSelect();check(pcCalls==1,"PC command opens the engine PC")
  local function page(name,draw)
    local c=g.newCanvas(160,144,{dpiscale=1});g.setCanvas(c);g.clear(1,1,1,1);draw();g.setCanvas()
    local large=g.newCanvas(640,576,{dpiscale=1});g.setCanvas(large);g.clear(1,1,1,1);g.setColor(1,1,1,1);g.draw(c,0,0,0,4,4)
    shot(large,name)
  end
  local Manager=require("src.mods.ManagerState")
  local manager=Manager.new(Game);manager:enter()
  page("fixture-mod-list",function()manager:draw()end)
  manager.currentMod=manager.byId.DRAMALESS_SHAPE;manager:goTo("detail")
  page("fixture-mod-detail",function()manager:draw()end)
  -- Exercise every detail action, including the below-fold options row.
  for _=1,#manager:rowsForScreen() do manager:moveCursor(1);manager:draw() end
  check(manager.cursor>=manager.scroll and manager.cursor<=manager.scroll+1,"detail cursor remains visible")
  manager:openConfirm({string.rep("せっていを かくにんしてください。",12)},function()end)
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
  local V=Game.mods.exports.DRAMALESS_SHAPE.lib
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
  local wanted
  Runtime.hooks:wrap("render.viewport",function()return wanted end,100,"qa-reserved")
  for _,size in ipairs({{480,800,480,480},{800,480,640,360},{600,960,540,640}}) do
    g.setCanvas();assert(love.window.setMode(size[1],size[2],{vsync=0}))
    wanted={x=0,y=0,width=size[3],height=size[4],capture=true}
    Viewport.begin(1)
    for _,uiw in ipairs({160,304}) do
      Renderer:setUISize(uiw,144);Renderer.uiFill=true
      arena.uiWide=uiw==304
      local expected=Renderer:frameRects()
      local actorPass=false
      local result=Scene.render(state,arena,function(ctx)
        actorPass=ctx.width>0 and ctx.height>0
      end)
      check(result and result:getWidth()==expected.pw and result:getHeight()==expected.ph,
        ("voxel arena uses %dx%d playfield inside %dx%d window (UI %d)"):format(expected.pw,expected.ph,size[1],size[2],uiw))
      check(actorPass,"battle actor pass runs at the reserved dimensions")
    end
    check(g.getWidth()==size[1] and g.getHeight()==size[2],"compatibility never changes global window dimensions")
  end
  check(#Game.mods.errors==0,#ids.." MODs report no runtime errors")
  -- QoL-specific exercise; original MOD bytes and the shared source are unchanged.
  local qol=assert(Game.mods.exports.quality_of_life)
  local Runtime=require("src.mods.Runtime")
  check(qol.optionValue(Game,"qol_exp_bar")=="off","original XP bar defaults to OFF")
  check(qol.optionValue(Game,"qol_caught_indicator")=="off","original caught indicator defaults to OFF")
  check(qol.optionValue(Game,"qol_location_banners")==false,"original location banner defaults to OFF")
  local rows=Runtime.call("ui.options.rows",function(_,r)return r end,Game,{{id="MODS",label="MODS"}})
  local qolRow
  for _,row in ipairs(rows) do if row.id=="qol_later_gen" then qolRow=row end end
  check(qolRow and qolRow.label=="QUALITY OF LIFE","QoL configuration hook inserts original English label")
  local screen=require("src.ui.Screens").build(Game,qol.screenId)
  check(#screen.rows==4 and screen.rows[1].label=="XP BAR","QoL options screen builds under red_jp")
  Renderer:setUISize(160,144)
  Renderer.uiFill=false
  page("qol-options-original",function()screen:draw()end)
  local qopts={qol_exp_bar="on",qol_caught_indicator="gen2",qol_location_banners=2}
  Game.save.options.modOptions.quality_of_life=qopts
  check(qol.optionValue(Game,"qol_exp_bar")=="on","QoL setting is readable through original service")
  local Growth=require("src.pokemon.Growth")
  local low=Growth.expForLevel("MEDIUM_SLOW",5,data.growth_rates)
  local high=Growth.expForLevel("MEDIUM_SLOW",6,data.growth_rates)
  local mon={species="FIXMON_A",level=5,exp=low+math.floor((high-low)/2),hp=20,dvs={attack=1,defense=1,speed=1,special=1}}
  Game.save.pokedex={owned={FIXMON_B=true},seen={FIXMON_B=true}}
  local battle={game=Game,data=data,player={mon=mon,name="カナ"},enemy={name="ポケモン",mon={species="FIXMON_B",dvs=mon.dvs}},frame=0,kind="wild",phase="text",fx={},
    draw=function()end,wideLayout=function()return false end,growInScale=function()return nil end}
  local px=qol.expPixels(battle)
  check(px>0 and px<48,"XP fraction computes from real engine growth table")
  Runtime.emit("battle.started",{battle=battle,species="FIXMON_B"})
  check(battle.draw~=nil,"battle event attaches QoL overlays")
  local canvas=g.newCanvas(160,144,{dpiscale=1})
  local function drawBattle(name)
    g.setCanvas(canvas);g.clear(1,1,1,1);battle:draw();g.setCanvas()
    shot(canvas,name)
    return canvas:newImageData()
  end
  local pixels=drawBattle("qol-battle-original")
  local black=0
  for y=85,94 do for x=85,159 do if select(1,pixels:getPixel(x,y))<0.8 then black=black+1 end end end
  check(black>0,"enabled XP bar produces actual pixels")
  local caught=0
  for y=0,20 do for x=0,25 do if select(1,pixels:getPixel(x,y))<0.8 then caught=caught+1 end end end
  check(caught>0,"caught indicator renders beside Japanese species name")
  qopts.qol_exp_bar="off";qopts.qol_caught_indicator="off"
  pixels=drawBattle("qol-battle-disabled")
  check(select(1,pixels:getPixel(136,88))>0.99,"XP bar respects disable option")
  qopts.qol_exp_bar="on";qopts.qol_caught_indicator="gen2"
  local oldOW=Game.overworld
  Game.overworld={isOverworld=true,map={def={label="マサラタウン"}},drawUI=function()end}
  data.field.townMap={locations={FIX_TOWN={name="マサラタウン"}}}
  Runtime.emit("map.entered",{mapId="FIX_TOWN",map=Game.overworld.map})
  local gotLabel
  local drawFont=Font.draw
  Font.draw=function(text,...)gotLabel=text;return drawFont(text,...)end
  page("qol-location-japanese",function()Game.overworld:drawUI()end)
  Font.draw=drawFont
  check(gotLabel=="マサラタウン","location banner preserves Japanese map name")
  Game.overworld=oldOW
  local logger=require("src.core.Logger")
  for _,line in ipairs(logger.history) do
    assert(not line:find("battle overlay disabled",1,true),line)
  end
  check(#Game.mods.errors==0,#ids.." MODs have no loader/runtime errors after QoL events")
  if withCatchable then
    local evo=data.pokemon.KADABRA.evolutions[1]
    check(evo.method=="LEVEL" and evo.level==42 and evo.species=="ALAKAZAM",
      "All151 evolution patch remains active after QoL battle events")
    check(data.items.MOON_STONE.price==2100,
      "All151 item patch remains active alongside QoL")
  end
  local hashFile=assert(io.open(output.."/original-source-hashes.json","rb"))
  local sourceHashes=assert(Json.decode(hashFile:read("*a")));hashFile:close()
  for path,expected in pairs(sourceHashes) do
    local bytes=assert(fs.read("mods/quality_of_life/"..path))
    assert(love.data.encode("string","hex",love.data.hash("sha256",bytes))==expected,"QoL source altered: "..path)
  end
  check(true,"all eleven original QoL files remain byte-identical after installation and execution")
  print("NOTE original QoL 3D HUD lookup only names DRAMATIC_SHAPE; DRAMALESS_SHAPE-specific HUD snap integration is absent")

  write("love-fixture-result.txt",checks.." real-LÖVE fixture checks passed; no retail ROM or Android device used.\n")
  print(checks.." REAL LOVE FIXTURE CHECKS PASSED")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1) else love.event.quit(0) end
end
