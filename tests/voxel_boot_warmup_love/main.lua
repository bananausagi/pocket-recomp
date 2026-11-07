local function run()
  local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local g,fs=love.graphics,love.filesystem
  local n,records=0,{}
  local function check(ok,why)assert(ok,why);n=n+1;print('PASS '..why)end
  local function write(name,body)local f=assert(io.open(out..'/'..name,'wb'));f:write(body);f:close()end
  local Game=require('src.core.Game');local Data=require('src.core.Data')
  local data=require('tests.fixture_data').load()
  require('src.core.GameVersion').set('red_jp');Data.seedDefaults(data,'red_jp')
  data.constants.language='ja'
  for k,v in pairs(data)do Data[k]=v end
  Data.palettes={palettes={ROUTE={{245,250,235},{170,205,130},{50,130,70},{10,25,20}}}}
  Game.data=Data
  local Save=require('src.core.SaveData');local opts=Save.defaultOptions()
  opts.colors='gbc';opts.renderPipelines={voxel=3}
  Save.setModEnabled(opts,'DRAMALESS_SHAPE',true,'red_jp');Save.saveOptions(opts)
  -- Independent grayscale atlas and water/flower animation; no ROM content.
  local pixels=love.image.newImageData(128,64)
  for y=0,63 do for x=0,127 do
    local shade=({1,.66,.33,0})[(x+y)%4+1];pixels:setPixel(x,y,shade,shade,shade,1)
  end end
  fs.createDirectory('fixture');fs.write('fixture/atlas.png',pixels:encode('png'))
  local ts=Data.tilesets.FIX_OUT;ts.image='fixture/atlas.png';ts.tilesPerRow=16
  ts.animatedTiles={{kind='hshift',tile=1,offsets={0,1,2,3,4,5,6,7},period=20}}
  Game.save={options=opts,player={map='FIX_TOWN',x=3,y=3},party={},flags={},pokedex={owned={},seen={}},modData={}}
  Game.overworld={}
  local top={isOpeningMovie=true};Game.stack={states={top},top=function()return top end}
  local Loader=require('src.mods.Loader');Game.mods=Loader.new({generation=1});Game.mods:load(Data)
  local loaded=Game.mods.mods.DRAMALESS_SHAPE
  check(loaded and loaded.state=='loaded','actual Dramaless loader accepts new warmup source')
  local V=Game.mods.exports.DRAMALESS_SHAPE.lib
  local Boot=V.require('VoxelBootWarmup');local Mesh=V.require('ChunkMesher')
  local Atlas=V.require('TerrainAtlas');local GPU=V.require('Voxel3D')
  local Assets=require('src.render.Assets');local MapLoader=require('src.world.MapLoader')
  local P=require('src.render.PaletteFX');P.setMode('gbc')
  local Pipelines=require('src.render.Pipelines');Pipelines.install(Data);Pipelines.setLevel('voxel',3)
  require('src.mods.Runtime').emit('game.ready',{game=Game})
  local imageCalls,shaderCalls=0,0
  local origImage,origShader=g.newImage,g.newShader
  g.newImage=function(...)imageCalls=imageCalls+1;return origImage(...)end
  g.newShader=function(...)shaderCalls=shaderCalls+1;return origShader(...)end
  local originalSave=Save.encode(Game.save)
  local direct=0;local originalGet=Mesh.get
  Mesh.get=function(...)direct=direct+1;return originalGet(...)end
  local maxAtlasUploads,meshSlices=0,{}
  local originalPump=Mesh.pump
  Mesh.pump=function(covered,seconds)
    meshSlices[#meshSlices+1]={covered=covered,seconds=seconds}
    return originalPump(covered,seconds)
  end
  local function tick(label)
    local status=Boot.status();local phase=status and status.phase or 'start'
    local a,b=imageCalls,shaderCalls;local t=love.timer.getTime()
    -- Actual registered pipeline update, including its graphics-state guard.
    Pipelines.update(1/60)
    local elapsed=love.timer.getTime()-t
    local created=imageCalls-a
    if phase=='atlas' or phase=='target' then maxAtlasUploads=math.max(maxAtlasUploads,created) end
    records[#records+1]={label=label,phase=phase,seconds=elapsed,images=created,shaders=shaderCalls-b}
    -- An opening can still render between every preparation step.
    local target=g.newCanvas(160,144,{dpiscale=1});g.push('all');g.setCanvas(target)
    g.clear(1,1,1,1);g.setColor(0,0,0,1);g.rectangle('fill',#records%144,40,16,16)
    g.pop();target:release()
  end
  for i=1,3000 do
    tick('opening')
    if Boot.status() and Boot.status().phase=='done' then break end
  end
  local done=Boot.status()
  check(done and done.phase=='done' and not done.stats.error,'opening reaches completed warmup')
  check(maxAtlasUploads<=1,'background atlas preparation uploads at most one image per update')
  check(#meshSlices>1,'actual geometry build spans multiple updates')
  local allSlices=true;for _,s in ipairs(meshSlices)do if s.covered~=false or (s.seconds<=0 or s.seconds>.002) then allSlices=false end end
  check(allSlices,'every opening mesh budget stays at most 2ms')
  check(direct==0,'boot never calls synchronous ChunkMesher.get')
  check(Save.encode(Game.save)==originalSave,'opening preparation leaves all save/options data unchanged')
  check(Game.overworld.map==nil,'opening never enters or updates overworld')
  if os.getenv('JP_QA_MEASURE_ONLY')=='1' then
    write('measurement-results.json',require('src.link.Json').encode({checks=n,romUsed=false,coldBoot=done,records=records,
      renderer={g.getRendererInfo()},maxAtlasUploads=maxAtlasUploads}))
    print('MEASURE mesh max ms '..(done.stats.stages.mesh.maxSeconds*1000))
    return
  end
  local map=MapLoader.load(Data,'FIX_TOWN');local cached=Mesh.peek(map,false)
  check(cached~=nil,'opening builds current map geometry')
  local palette=P.effectiveColors(P.pal(Data,'ROUTE'))
  local oldImages,oldShaders=imageCalls,shaderCalls
  local atlas=Atlas.forMap(map,palette);GPU.shader()
  check(imageCalls==oldImages and shaderCalls==oldShaders,'first live atlas/shader request reuses warmed GPU cache')
  check(MapLoader.load(Data,'FIX_TOWN')==map and Mesh.peek(map,false)==cached,'world enter reuses identical map and geometry objects')
  local aux=require('tests.voxel_boot_warmup_love.aux_compare')(V,MapLoader.load(Data,'FIX_ROUTE'),check,write)
  -- Borrow the title's existing decoded-save hint; no SaveData.load call here.
  top={isPlayerStartMenu=true,presentationWarmup={map='FIX_ROUTE'}}
  tick('title-saved-location');check(Boot.status().target=='FIX_ROUTE','title existing-save hint selects saved map')
  local reads=0;local oldLoad=Save.load;Save.load=function()reads=reads+1;error('warmup may not load saves')end
  tick('title-no-save-read');check(reads==0,'warmup does not read/recover/adopt a save');Save.load=oldLoad
  -- Cancel a real unfinished mesh and prove no further work occurs OFF.
  Assets.invalidate();top={isOpeningMovie=true};Game.overworld={}
  tick('restart');tick('map-queue')
  check(Mesh.pending()>0,'fixture has a queued boot mesh before cancellation')
  Pipelines.setLevel('voxel',0);tick('off')
  check(Boot.status()==nil and Mesh.pending()==0,'mode OFF cancels speculative boot mesh jobs')
  local imageOff=imageCalls;tick('off-idle');check(imageCalls==imageOff,'mode OFF does no texture work')
  -- Isolate a real partially prepared animation, then skip without flushing.
  Assets.invalidate();Pipelines.setLevel('voxel',3);top={isOpeningMovie=true};Game.overworld={}
  local atlasFrames=0
  for i=1,3000 do
    tick('skip-prepare');local s=Boot.status()
    if s and s.phase=='target' then
      atlasFrames=atlasFrames+1
      if atlasFrames==4 then break end
    end
  end
  local warmedMap=MapLoader.load(Data,'FIX_TOWN')
  local owned=Mesh.peek(warmedMap,false)
  check(not Atlas.prepared(warmedMap,palette),'skip fixture reaches actual unfinished starting atlas')
  local beforeSkip=imageCalls
  local partial=Atlas.forMap(warmedMap,palette)
  check(partial~=nil and imageCalls==beforeSkip,'unfinished animation returns correct cached static atlas with no synchronous flush')
  top={isOverworld=true};Game.stack.states={top}
  -- Avoid simulating movement: only the presentation module sees this state.
  Game.overworld={map=warmedMap,neighbors={},camera={x=0,y=0}}
  local completed=false
  for i=1,20 do
    local before=imageCalls
    Boot.update(Game,3)
    check(imageCalls-before<=1,'skip continues at most one animation frame upload per update')
    if Boot.status().phase=='done' then completed=true;break end
  end
  check(completed and Mesh.peek(warmedMap,false)==owned,'skip completes same cache without rebuilding the map')
  local afterSkip=imageCalls;Atlas.forMap(warmedMap,palette)
  check(imageCalls==afterSkip,'finished skipped animation is immediately reused by live render')
  Boot.reset();check(Boot.status()==nil,'explicit reset clears boot ownership')
  Assets.invalidate();check(Mesh.pending()==0,'asset reload clears pending geometry')
  -- Partial animation GPU objects are released on cancel, never reused stale.
  local pendingMap=MapLoader.load(Data,'FIX_TOWN')
  Atlas.prepare(pendingMap,palette,.002);Atlas.prepare(pendingMap,palette,.002)
  local allocated=g.getStats().texturememory
  Atlas.cancelPreparations();check(g.getStats().texturememory<allocated,'cancel releases unpublished animation GPU texture')
  local postCancel=Atlas.forMap(pendingMap,palette)
  check(postCancel~=nil,'cancelled partial atlas can be rebuilt normally')
  write('results.json',require('src.link.Json').encode({checks=n,romUsed=false,actualModLoader=true,actualRegisteredPipeline=true,
    coldBoot=done,maxAtlasUploads=maxAtlasUploads,records=records,meshSlices=meshSlices,auxiliaryMesh=aux}))
  print('PASS '..n..' startup warmup checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas()
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
