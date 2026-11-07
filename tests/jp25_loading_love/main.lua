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
  local clone=require('src.link.Json')
  for i=1,4 do
    local d=clone.decode(clone.encode(Data.maps.FIX_ROUTE));d.id='FAR_'..i
    d.connections={};d.warps={};Data.maps[d.id]=d
  end
  local nearDef=clone.decode(clone.encode(Data.maps.FIX_ROUTE));nearDef.id='NEAR_WARP';nearDef.connections={};nearDef.warps={{x=2,y=2,destMap='FIX_TOWN',destWarp=1}}
  Data.maps.NEAR_WARP=nearDef
  Data.maps.FIX_TOWN.warps={{x=2,y=2,destMap='NEAR_WARP',destWarp=1}}
  Game.save={options=opts,player={map='FIX_TOWN',x=3,y=3},party={},flags={},pokedex={owned={},seen={}},modData={}}
  Game.overworld={}
  local top={isOpeningMovie=true};Game.stack={states={top},top=function()return top end}
  local Loader=require('src.mods.Loader');Game.mods=Loader.new({generation=1});Game.mods:load(Data)
  local loaded=Game.mods.mods.DRAMALESS_SHAPE
  check(loaded and loaded.state=='loaded','actual Dramaless loader accepts loading source')
  local V=Game.mods.exports.DRAMALESS_SHAPE.lib
  local Boot=V.require('VoxelBootWarmup');local Mesh=V.require('ChunkMesher')
  local Atlas=V.require('TerrainAtlas');local GPU=V.require('Voxel3D')
  local Assets=require('src.render.Assets');local MapLoader=require('src.world.MapLoader')
  local P=require('src.render.PaletteFX');P.setMode('gbc')
  local Pipelines=require('src.render.Pipelines');Pipelines.install(Data);Pipelines.setLevel('voxel',3)
  require('src.mods.Runtime').emit('game.ready',{game=Game})

  local Scene=V.require('VoxelScene');local Precache=V.require('VoxelPrecache')
  local mode=os.getenv('JP_QA_VERSION') or 'after'
  local map=MapLoader.load(Data,'FIX_TOWN')
  local ow={map=map,neighbors={},player={px=48,py=48,cellX=3,cellY=3},camera={x=0,y=0}}
  Game.overworld=ow;top=ow;Game.stack.states={ow}
  local results={version=mode,trials={},romUsed=false,renderInfo={g.getRendererInfo()}}
  for trial=1,4 do
    Mesh.invalidate();Atlas.invalidate();Precache.reset()
    local firstFrame,firstMs,firstPump,maxPump,fullFrame=0,0,0,0,0
    local start=love.timer.getTime();local totalPump=0
    for frame=1,10000 do
      Scene.prefetch(ow)
      local t=love.timer.getTime();Mesh.pump(true);local elapsed=love.timer.getTime()-t
      totalPump=totalPump+elapsed;maxPump=math.max(maxPump,elapsed)
      local surface=Scene.prefetch(ow)
      if surface and firstFrame==0 then firstFrame=frame;firstMs=(love.timer.getTime()-start)*1000;firstPump=totalPump*1000 end
      if Mesh.peek(map,false) then fullFrame=frame;break end
    end
    check(firstFrame>0 and fullFrame>0,'cold trial '..trial..' has initial and final terrain')
    if mode=='after' then check(Mesh.peek(map,true)~=nil,'cold trial '..trial..' retains real body mesh') end
    results.trials[#results.trials+1]={firstFrame=firstFrame,firstMs=firstMs,firstPumpMs=firstPump,fullFrame=fullFrame,maxPumpMs=maxPump*1000}
  end
  local target=MapLoader.load(Data,'FAR_4')
  local began=love.timer.getTime()
  local prewarmFrames=0
  if mode=='after' then
    check(Precache.prepareDestination(Game,'FAR_4'),'native destination pin accepted')
    for frame=1,32 do
      Scene.prefetch(ow);Precache.update(Game);Mesh.pump(true)
      prewarmFrames=frame
    end
    check(Scene.atlasReady(target),'32-frame fade finishes confirmed target atlas')
  end
  local oldBody,oldFull=Mesh.peek(target,true),Mesh.peek(target,false)
  ow.map=target;ow.neighbors={}
  local arrivalStart=love.timer.getTime();local firstArrival=0
  for frame=1,2000 do
    local visible=Scene.prefetch(ow)
    if visible then firstArrival=frame-1;break end
    if mode=='after' then Precache.update(Game) end
    Mesh.pump(true)
  end
  local arrivalMs=(love.timer.getTime()-arrivalStart)*1000
  check(Scene.prefetch(ow)~=nil,'destination becomes visible after actual map swap')
  local uploads,oldImage=0,g.newImage
  g.newImage=function(...)uploads=uploads+1;return oldImage(...)end
  if mode=='after' then Scene.warmAtlas(target) end
  g.newImage=oldImage
  if mode=='after' then check(uploads==0,'arrival atlas requires no synchronous texture upload') end
  results.confirmed={prewarmFrames=prewarmFrames,remainingCoveredFrames=firstArrival,arrivalCpuMs=arrivalMs,
    preparationAndArrivalCpuMs=(love.timer.getTime()-began)*1000,arrivalUploads=uploads}
  -- Finish every collection, then compare exact production vertex streams in
  -- the before/after JSON. No timing above includes this fidelity audit.
  for i=1,10000 do
    Scene.prefetch(ow);Mesh.pump(true)
    if Mesh.slotKnown(target,false) and not Mesh.jobPending(target.id,false) then break end
  end
  check(Mesh.slotKnown(target,false),'destination reaches complete final quality')
  local function signature(mesh)
    if not mesh then return {vertices=0,hash='empty'} end
    local parts=type(mesh)=='table' and mesh.voxelMeshParts or {mesh}
    local pieces,count={},0
    for _,part in ipairs(parts)do
      local vertexCount=part:getVertexCount();count=count+vertexCount
      for i=1,vertexCount do pieces[#pieces+1]=love.data.pack('string','<ffffff',part:getVertex(i)) end
    end
    return {vertices=count,hash=love.data.encode('string','hex',love.data.hash('sha256',table.concat(pieces)))}
  end
  local terrain,water=Mesh.pair(target,false)
  results.final={terrain=signature(terrain),water=signature(water),grass=signature(Mesh.grass(target)),flowers=signature(Mesh.flowers(target))}
  if mode=='after' then
    -- A fast title skip can use the start area before neighbouring maps and
    -- rings finish. Original palette, title, save and world state stay intact.
    Mesh.invalidate();Atlas.invalidate();Precache.reset();Boot.reset()
    Game.overworld={};top={isOpeningMovie=true};Game.stack.states={top}
    local saved=Save.encode(Game.save);local palette=P.effectiveColors(P.pal(Data,'ROUTE'))
    local firstBodyFrame,firstReadyFrame=0,0
    for frame=1,5000 do
      Boot.update(Game,3)
      if Mesh.peek(map,true) and firstBodyFrame==0 then firstBodyFrame=frame end
      if Mesh.peek(map,true) and Atlas.prepared(map,palette) and firstReadyFrame==0 then
        firstReadyFrame=frame
        check(not Mesh.peek(MapLoader.load(Data,'FIX_ROUTE'),true),'start area ready before neighbour geometry')
      end
      if Boot.status() and Boot.status().phase=='done' then break end
    end
    check(firstBodyFrame>0 and firstReadyFrame>0,'opening prepares starting body and atlas together')
    check(Boot.status().phase=='done' and not Boot.status().stats.error,'opening also completes original full neighbourhood')
    check(Save.encode(Game.save)==saved and not Game.overworld.map,'presentation preparation never updates world or save')
    local cached=Mesh.peek(map,false);local beforeUploads=0
    g.newImage=function(...)beforeUploads=beforeUploads+1;return oldImage(...)end
    Atlas.forMap(map,palette);g.newImage=oldImage
    check(cached~=nil and beforeUploads==0,'opening skip can reuse exact completed map and atlas')
    results.boot={firstBodyFrame=firstBodyFrame,firstReadyFrame=firstReadyFrame,status=Boot.status()}
  end
  results.checks=n
  write('results.json',require('src.link.Json').encode(results))
  print('PASS '..n..' loading GL checks')
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then love.graphics.setCanvas();print(err);love.event.quit(1)else love.event.quit(0)end
end
