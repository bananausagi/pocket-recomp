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

  local SM=V.require('ShadowMap');local Mat=V.require('Mat4');local Vox=V.require('VoxelState')
  V.require('Shadows').setting:sync('high')
  Game.save.options.jpAtmosphere='off'
  Vox.angle=math.rad(50);Vox.level=4
  GPU.tint={1,1,1}
  local pixels=love.image.newImageData(16,16)
  for y=0,15 do for x=0,15 do pixels:setPixel(x,y,.9,.9,.9,1)end end
  local texture=g.newImage(pixels);texture:setFilter('nearest','nearest')
  local silhouette=love.image.newImageData(16,16)
  for y=0,15 do for x=0,15 do
    local opaque=x>=2 and x<=13 and y>=1 and y<=14 and not (x>=6 and x<=9 and y>=5 and y<=8)
    silhouette:setPixel(x,y,.9,.9,.9,opaque and 1 or 0)
  end end
  local spriteTexture=g.newImage(silhouette);spriteTexture:setFilter('nearest','nearest')
  local function quad(a,b,c,d)
    return GPU.newMesh({{a[1],a[2],a[3],0,0,1},{b[1],b[2],b[3],1,0,1},
      {c[1],c[2],c[3],1,1,1},{d[1],d[2],d[3],0,1,1}},{1,2,3,1,3,4})
  end
  local cases={
    {name='wall',mesh=quad({-80,0,0},{80,0,0},{80,96,0},{-80,96,0}),focus={0,40,0},eye={0,65,220}},
    {name='roof',mesh=quad({-80,0,64},{80,0,64},{80,64,0},{-80,64,0}),focus={0,30,30},eye={0,145,250}},
    {name='ground',mesh=quad({-90,0,-90},{90,0,-90},{90,0,90},{-90,0,90}),focus={0,0,0},eye={0,160,190}},
    {name='sprite',mesh=quad({-32,0,0},{32,0,0},{32,64,0},{-32,64,0}),focus={0,32,0},eye={0,54,130},snug=true},
  }
  local report={renderer={g.getRendererInfo()},cases={},checks=0}
  local suns={{-.85,-.55},{-2,-1.4},{-.3,-.7}}
  local DN=V.require('DayNight')
  for hour=0,23 do local x,z=DN.shearAt(DN.CYCLE*hour/24);suns[#suns+1]={x,z}end
  for _,case in ipairs(cases)do
    for si,sun in ipairs(suns)do
      SM.KX,SM.KZ=sun[1],sun[2]
      GPU.camera={eye=case.eye,focus=case.focus,fov=math.rad(50),up={0,1,0},curve=0}
      check(SM.begin(0,0,300,260),'actual shadow writer starts')
      local model=case.snug and SM.snug(nil) or nil
      local picture=case.snug and spriteTexture or texture
      SM.draw(case.mesh,picture,model);SM.finish('qa')
      local function render(dark)
        local alpha=GPU.SHADOW_ALPHA;GPU.SHADOW_ALPHA=dark
        check(GPU.beginScene(768,640,0,0,300,260,{.2,.25,.3,1}),'actual scene reader starts')
        GPU.glass(false);GPU.seams(false)
        GPU.draw(case.mesh,picture,nil,0,model)
        local image=GPU.endScene():newImageData();GPU.SHADOW_ALPHA=alpha
        return image
      end
      local on=render(.4);local off=render(0)
      local affected,total,maxDifference=0,0,0
      for y=0,639 do for x=0,767 do
        local a,b,c=on:getPixel(x,y);local d,e,f=off:getPixel(x,y)
        if d>.7 then
          total=total+1
          local diff=math.max(math.abs(a-d),math.abs(b-e),math.abs(c-f))
          maxDifference=math.max(maxDifference,diff)
          if diff>1/255 then affected=affected+1 end
        end
      end end
      local name=case.name..'-sun'..si
      write(name..'.png',on:encode('png'):getString())
      report.cases[#report.cases+1]={name=name,pixels=total,selfShadowPixels=affected,maxDifference=maxDifference,res=SM.res,bias=SM.bias,slack=SM.slack}
      check(total>1000,'surface occupies a measurable viewport area')
      if os.getenv('JP_QA_EXPECT_CLEAN')=='1' then check(affected==0,name..' has no self-shadow pixels') end
      print(name..' self-shadow '..affected..' / '..total..' max '..maxDifference)
    end
  end
  -- A separate opaque object must still cast its true shadow on the floor;
  -- removing the acne must not turn shading off or detach contact shadows.
  local floor=quad({-100,0,-100},{100,0,-100},{100,0,100},{-100,0,100})
  local card=quad({-16,0,0},{16,0,0},{16,32,0},{-16,32,0})
  GPU.camera={eye={90,140,180},focus={0,0,0},fov=math.rad(50),up={0,1,0},curve=0}
  SM.KX,SM.KZ=-.85,-.55
  check(SM.begin(0,0,300,260),'contact shadow writer starts')
  SM.draw(floor,texture);SM.draw(card,texture,SM.snug(nil));SM.finish('contact')
  local snug=SM.snug(nil)
  local function contact(dark)
    local alpha=GPU.SHADOW_ALPHA;GPU.SHADOW_ALPHA=dark
    check(GPU.beginScene(768,640,0,0,300,260,{.2,.25,.3,1}),'contact scene reader starts')
    GPU.glass(false);GPU.seams(false)
    GPU.draw(floor,texture);GPU.draw(card,texture,nil,0,snug)
    local pic=GPU.endScene():newImageData();GPU.SHADOW_ALPHA=alpha;return pic
  end
  local shadow,unshadowed=contact(.4),contact(0)
  local castPixels,deepPixels=0,0
  for y=0,639 do for x=0,767 do
    local r=shadow:getPixel(x,y);local ref=unshadowed:getPixel(x,y)
    if ref-r>.02 then castPixels=castPixels+1 end
    if ref-r>.30 then deepPixels=deepPixels+1 end
  end end
  print('CONTACT COUNTS '..castPixels..' '..deepPixels)
  write('retained-contact-shadow.png',shadow:encode('png'):getString())
  check(castPixels>250 and deepPixels>100,'actual object shadow remains present at its original strength')
  local contactHits=0
  for _,height in ipairs({1,2,3,4})do
    local x,y=GPU.project(-15.5+SM.KX*height,0,SM.KZ*height)
    x,y=math.floor(x),math.floor(y)
    if x>=0 and x<768 and y>=0 and y<640 then
      local r=shadow:getPixel(x,y);local ref=unshadowed:getPixel(x,y)
      if ref-r>.05 then contactHits=contactHits+1 end
    end
  end
  check(contactHits>=2,'cast shadow remains attached within four world pixels of the feet')
  report.contact={castPixels=castPixels,deepPixels=deepPixels,nearFootHits=contactHits,res=SM.res,slack=SM.slack}
  write('retained-contact-shadow.png',shadow:encode('png'):getString())
  for _,v in ipairs({{false,false},{true,false},{false,true},{true,true}})do
    check(GPU.shader(v[1],v[2])~=nil,'world/battle/grid shader variant compiles')
  end
  check(GPU.unlitShader()~=nil,'exact-colour unlit sprite variant still compiles')
  if os.getenv('JP_QA_EXPECT_CLEAN')=='1' then
  -- Runtime capability fallback must retain plain 3D, even if an ES2
  -- device cannot use derivatives or a driver rejects the corrected variant.
  local supported=g.getSupported
  g.getSupported=function()
    local caps={};for k,v in pairs(supported())do caps[k]=v end
    caps.shaderderivatives=false;return caps
  end
  local fallback=assert(loadfile(root..'/mods/DRAMALESS_SHAPE/lib/Voxel3D.lua'))(V)
  check(fallback.shader(false,false)~=nil,'plain 3D shader compiles without derivative capability')
  check(fallback.shader(false,true)~=nil,'battle 3D shader compiles without derivative capability')
  g.getSupported=supported
  local newShader=g.newShader;local rejected=0
  g.newShader=function(source,...)
    if type(source)=='string' and source:find('#define RECEIVER_PLANE_SHADOW',1,true) then
      rejected=rejected+1;error('injected receiver-plane compiler refusal')
    end
    return newShader(source,...)
  end
  fallback=assert(loadfile(root..'/mods/DRAMALESS_SHAPE/lib/Voxel3D.lua'))(V)
  check(fallback.shader(false,false)~=nil and rejected==1,'advertised feature compiler refusal falls back to valid plain 3D')
  g.newShader=newShader
  end
  report.checks=n
  write('results.json',require('src.link.Json').encode(report))
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then love.graphics.setCanvas();print(err);love.event.quit(1)else love.event.quit(0)end
end
