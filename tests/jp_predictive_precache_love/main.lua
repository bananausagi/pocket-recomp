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
  check(loaded and loaded.state=='loaded','actual Dramaless loader accepts new warmup source')
  local V=Game.mods.exports.DRAMALESS_SHAPE.lib
  local Boot=V.require('VoxelBootWarmup');local Mesh=V.require('ChunkMesher')
  local Atlas=V.require('TerrainAtlas');local GPU=V.require('Voxel3D')
  local Assets=require('src.render.Assets');local MapLoader=require('src.world.MapLoader')
  local P=require('src.render.PaletteFX');P.setMode('gbc')
  local Pipelines=require('src.render.Pipelines');Pipelines.install(Data);Pipelines.setLevel('voxel',3)
  require('src.mods.Runtime').emit('game.ready',{game=Game})

  local Precache=V.require('VoxelPrecache');local Scene=V.require('VoxelScene')
  local outRows={};local function now()return love.timer.getTime()end
  local function pumpUntilEmpty()
    for i=1,10000 do Mesh.pump(false,.002);if Mesh.pending()==0 then return end end
    error('queue did not drain')
  end
  local current=MapLoader.load(Data,'FIX_TOWN')
  local near=MapLoader.load(Data,'NEAR_WARP')
  local live={FIX_TOWN=true,NEAR_WARP=true,FIX_ROUTE=true}
  for i=1,4 do live['FAR_'..i]=true end
  Mesh.setLive(live)
  Mesh.request(current,false,Precache.masksFor(Data,current.id),true)
  local coldStart=now();local coldFrames,coldMax=0,0
  while Mesh.pending()>0 do
    local t=now();Mesh.pump(false);coldFrames=coldFrames+1;coldMax=math.max(coldMax,(now()-t)*1000)
    assert(coldFrames<10000,'cold fixture timeout')
  end
  local coldSeconds=now()-coldStart
  local currentMesh=Mesh.peek(current,false);check(currentMesh~=nil,'current full mesh initially ready')
  local player={targetX=2,targetY=2,cellX=2,cellY=2}
  Game.overworld={map=current,player=player,neighbors={},camera={x=0,y=0}}
  for i=1,4 do
    local map=MapLoader.load(Data,'FAR_'..i)
    Mesh.request(map,true,nil,false,1000000+i)
  end
  local imageCalls=0;local oldImage=g.newImage
  g.newImage=function(...)imageCalls=imageCalls+1;return oldImage(...)end
  local fullAt,imagesAt,farReadyAt,largest,maxPrecache=0,0,0,0,0
  local started=now();local after=os.getenv('JP_QA_VERSION')=='after'
  for frame=1,10000 do
    local beforeImage=imageCalls;local t=now();Precache.update(Game)
    local preMs=(now()-t)*1000;maxPrecache=math.max(maxPrecache,preMs)
    local j=now();Mesh.pump(false);local pumpMs=(now()-j)*1000
    largest=math.max(largest,pumpMs)
    local count=0;for i=1,4 do if Mesh.slotKnown(MapLoader.load(Data,'FAR_'..i),true) then count=count+1 end end
    outRows[#outRows+1]={frame=frame,precacheMs=preMs,pumpMs=pumpMs,images=imageCalls-beforeImage,farReady=count}
    if fullAt==0 and Mesh.peek(near,false) then
      fullAt=frame;imagesAt=imageCalls;farReadyAt=count
      local same=Mesh.peek(near,false)
      -- Promote to the live current slot exactly as Scene.prefetch does.
      Mesh.setLive({NEAR_WARP=true,FIX_TOWN=true});Mesh.request(near,false,{},true)
      check(Mesh.peek(near,false)==same,'seam promotion keeps identical completed full mesh')
      check(not Mesh.jobPending(near.id,false),'seam promotion queues zero rebuilds')
      -- Return original live set while gathering prediction completion.
      Mesh.setLive(live)
    end
    local done,total=Precache.progress()
    if fullAt>0 and done>=1 then break end
  end
  check(fullAt>0,'near warp full destination eventually ready')
  if after then
    check(farReadyAt<4,'near destination completes before far backlog')
    local perStep=true;for _,r in ipairs(outRows) do if r.images>1 then perStep=false end end
    check(perStep,'prediction uploads at most one atlas image per update')
  end
  local result={version=os.getenv('JP_QA_VERSION'),checks=n,nearReadyFrame=fullAt,farJobsFinishedBeforeNear=farReadyAt,
    maximumPumpMs=largest,maximumPrecacheMs=maxPrecache,totalSeconds=now()-started,steps=outRows,romUsed=false,
    cold={frames=coldFrames,totalSeconds=coldSeconds,maximumPumpMs=coldMax},
    exactMeshReuse=true,renderer={g.getRendererInfo()}}
  if after then
    Precache.reset();Atlas.invalidate()
    Game.overworld.map=current;Precache.update(Game)
    local beforeCross=imageCalls
    Game.overworld.map=near;Mesh.setLive({NEAR_WARP=true,FIX_TOWN=true})
    Precache.update(Game)
    check(imageCalls-beforeCross<=1,'crossing advances at most one partial atlas image')
    local beforeLive=imageCalls;Scene.warmAtlas(near)
    check(imageCalls==beforeLive,'first live render reuses partial static atlas with no synchronous flush')
    for i=1,16 do
      local before=imageCalls;Precache.update(Game)
      check(imageCalls-before<=1,'arrival finishes one atlas frame per update '..i)
    end
    local afterArrival=imageCalls;Scene.warmAtlas(near)
    check(imageCalls==afterArrival,'fully arrived live render reuses finished atlas')
    Precache.reset()
    Mesh.setLive({NEAR_WARP=true})
    Mesh.setLive({NEAR_WARP=true})
    check(Mesh.peek(current,false)==currentMesh,'repeated live-set calls retain previous neighbourhood')
    local oldNear=Mesh.peek(near,false);Mesh.refresh(near.id)
    check(Mesh.peek(near,false)==oldNear and not Mesh.slotKnown(near,false),'block refresh retains display but invalidates prediction verdict')
    Mesh.request(near,false,{},true)
    check(Mesh.jobPending(near.id,false),'refreshed near full mesh queues replacement')
    Mesh.setLive({FAR_1=true})
    check(Mesh.peek(current,false)==nil,'second distinct neighbourhood evicts unneeded old geometry')
    Mesh.invalidate()
    check(Mesh.pending()==0,'reset cancels all queued geometry')
    result.checks=n
  end
  write('results.json',require('src.link.Json').encode(result))
  print('METRICS '..require('src.link.Json').encode({nearReadyFrame=fullAt,farJobsFinishedBeforeNear=farReadyAt,
    maximumPumpMs=largest,maximumPrecacheMs=maxPrecache,totalSeconds=result.totalSeconds}))
end
function love.load()
  local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas()
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
