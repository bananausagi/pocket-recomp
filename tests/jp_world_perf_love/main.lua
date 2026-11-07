-- Real LÖVE/GL integration checks using only handwritten fixture data.
-- JP_WORLD_ROOT=repo JP_WORLD_OUT=output XDG_DATA_HOME=isolated-save love this-dir
local function run()
  local root=assert(os.getenv("JP_WORLD_ROOT"))
  local output=assert(os.getenv("JP_WORLD_OUT"))
  assert(love.filesystem.getInfo("src/core/Game.lua"),"run from a QA app with the repository assets mounted")
  package.path=root.."/?.lua;"..root.."/?/init.lua;"..package.path
  local g,fs=love.graphics,love.filesystem
  -- Test-only access stays outside MOD code; actual MOD ffi denial is unchanged.
  local fixtureFFI=require("ffi")
  g.setDefaultFilter("nearest","nearest")
  local checks=0
  local function check(ok,message)
    assert(ok,message); checks=checks+1; print("PASS "..message)
  end
  require('tests.gles_context')(check)
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
  -- Starter-pack upgrade idempotence is covered by its independent suite.
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
  local modSource=assert(os.getenv("JP_WORLD_MOD"))
  local copied=0
  local function copyDir(path,rel)
    for _,name in ipairs(fs.getDirectoryItems(path)) do
      local from,to=path.."/"..name,"mods/DRAMALESS_SHAPE/"..rel..name
      if fs.getInfo(from,"directory") then fs.createDirectory(to);copyDir(from,rel..name.."/")
      else assert(fs.write(to,assert(fs.read(from))));copied=copied+1 end
    end
  end
  copyDir("perf-mod-source","")
  print("PERF MOD COPY",copied,modSource)
  assert(copied>50,"benchmark must copy requested MOD source")
  local installed=assert(fs.read("mods/DRAMALESS_SHAPE/lib/ChunkMesher.lua"))
  local expected=assert(fs.read("perf-mod-source/lib/ChunkMesher.lua"))
  assert(installed==expected,"MOD source must match requested source before loader")
  print("PERF PACKED CODE",installed:find("hasPacked",1,true)~=nil)
  local Loader=require("src.mods.Loader")
  Game.mods=Loader.new({generation=1})
  if os.getenv('JP_QA_EMULATE_ANDROID')=='1' then love.system.getOS=function()return 'Android'end end
  Game.mods:load(data)
  local ids={"DRAMALESS_SHAPE","running_shoes","erilab_bottomless_bag","SHINY_POKEMON","ACCESS_PC_ANYWHERE","CONTROLLER_RUMBLE","all_pokemon_catchable_151_mod"}
  if originalEntries then
    ids={};for _,entry in ipairs(originalEntries) do ids[#ids+1]=entry.id end
  end
  for _,id in ipairs(ids) do
    local mod=Game.mods.mods[id]
    check(mod and mod.state=="loaded",id.." loads with JP data ("..tostring(mod and mod.failure)..")")
  end
  if os.getenv("JP_WORLD_SCHEMA") then
    local f=assert(io.open(output.."/options-schema.json","wb"))
    f:write(Json.encode(Game.mods.optionSchemas.DRAMALESS_SHAPE));f:close()
    return
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
  local function digest(path)
    local bytes=assert(fs.read(path))
    return love.data.encode("string","hex",love.data.hash("sha256",bytes))
  end
  local sourceHashes={mod={},engine={},fixture={}}
  local function hashTree(path,prefix)
    for _,name in ipairs(fs.getDirectoryItems(path)) do
      local full=path.."/"..name
      if fs.getInfo(full,"directory") then hashTree(full,prefix..name.."/")
      else sourceHashes.mod[prefix..name]=digest(full) end
    end
  end
  hashTree("mods/DRAMALESS_SHAPE","")
  for _,path in ipairs({"src/mods/Loader.lua","src/render/PackedVoxelMesh.lua",
      "src/render/VoxelFrustum.lua","src/render/Renderer.lua","src/render/Pipelines.lua"}) do
    if fs.getInfo(path) then sourceHashes.engine[path]=digest(path) end
  end
  local scenario=os.getenv("JP_WORLD_CASE")=="adjacent" and "jp41_neighbor_preload" or "jp_world_perf"
  for _,path in ipairs({"tests/"..scenario..".lua","main.lua"}) do sourceHashes.fixture[path]=digest(path) end
  sourceHashes.manifest=assert(Json.decode(fs.read("mods/DRAMALESS_SHAPE/manifest.json")))
  require("tests."..scenario).run(Game,Renderer,V,data,output,sourceHashes,fixtureFFI)
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then love.graphics.setCanvas();print(err);love.event.quit(1)else love.event.quit(0)end
end
