-- Actual pinned Ascendant terrain/scene on handwritten map/art. No ROM data.
return function(Game,Renderer,V,check,write)
  local g,fs=love.graphics,love.filesystem
  local data=Game.data
  local img=love.image.newImageData(128,128)
  img:mapPixel(function(x,y)
    local tile=math.floor(y/8)*16+math.floor(x/8)
    local k=(x+y)%4==0 and .87 or 1
    if tile==55 then return .57*k,.35*k,.15*k,1 end
    return .38*k,.64*k,.26*k,1
  end)
  fs.createDirectory('fixture');assert(fs.write('fixture/ascendant-terrain.png',img:encode('png')))
  local ts={id='OVERWORLD',image='fixture/ascendant-terrain.png',tilesPerRow=16,
    imageWidth=128,imageHeight=128,walkable={44},waterTiles={},shoreTiles={},blocks={}}
  local def={id='JP_ASCENDANT_TERRACES',width=6,height=10,tileset='OVERWORLD',
    connections={},warps={},objects={},signs={},blocks={},borderBlock=0}
  local ids={}
  local function tile(x,y)
    local cy=math.floor(y/2)
    if y%2==1 and (cy==7 or cy==13) then return 55 end
    return 44
  end
  for by=0,def.height-1 do for bx=0,def.width-1 do
    local block={}
    for y=0,3 do for x=0,3 do block[#block+1]=tile(bx*4+x,by*4+y) end end
    local key=table.concat(block,',');local id=ids[key]
    if not id then id=#ts.blocks;ids[key]=id;ts.blocks[#ts.blocks+1]=block end
    def.blocks[#def.blocks+1]=id
  end end
  data.tilesets.OVERWORLD=ts;data.maps[def.id]=def
  data.field.ledges={{input='down',facing='down',standingTile=44,ledgeTile=55}}
  local map=require('src.world.MapLoader').load(data,def.id)
  local LE,Scene,Mesh=V.require('LedgeElevation'),V.require('VoxelScene'),V.require('ChunkMesher')
  local before=require('src.link.Json').encode(def)
  LE.setting:sync('world');LE.invalidate()
  local field=LE.map(map)
  local upper,middle,lower=field:at(4,4),field:at(4,10),field:at(4,17)
  check(upper>middle and middle>lower,'Ascendant WORLD derives cumulative authored terraces')
  check(upper-middle==6 and middle-lower==6,'Ascendant real ledges change floor by six units each')
  check(Scene.groundAt(map,4,4)==upper,'Ascendant actor floor follows terrace ground')
  LE.setting:sync('flat');LE.invalidate()
  local flat=LE.map(map)
  check(flat:at(4,4)==0 and flat:at(4,10)==0 and flat:at(4,17)==0,'explicit FLAT keeps level ground')
  LE.setting:sync('world');LE.invalidate();Mesh.invalidate()
  check(before==require('src.link.Json').encode(def),'elevation leaves gameplay map and collision bytes unchanged')
  local state={map=map,neighbors={},ghosts={},entities={},player={cellX=6,cellY=10,px=96,py=160},
    camera={x=16,y=88},paletteNameFor=function()return 'PALLET'end}
  Game.overworld=state
  local Voxel=V.require('VoxelState');Voxel.angle=.85;Voxel.level=4
  local canvas
  for _=1,250 do
    canvas=Scene.render(state,960,640,240,160,function()return nil end)
    if canvas then break end
    Mesh.pump(true,false,true)
  end
  check(canvas~=nil,'actual Ascendant world scene returns a GL canvas')
  if V.require('CanvasPresentation').OS=='Android' then
    for _=1,250 do
      Scene.stageMobileScenery(state);Mesh.pump(true,false,true)
      canvas=Scene.render(state,960,640,240,160,function()return nil end)or canvas
    end
    local receipt=V.require('MobileSceneryGate').status(map)
    check(receipt and not receipt.failed,'Android scenery resources do not fail for unbundled artwork')
    check(receipt and receipt.active,'Android procedural scenery reaches its complete active canvas')
    write('android-scenery.json',require('src.link.Json').encode(receipt))
  end
  g.setCanvas();write('ascendant-world-terraces.png',canvas:newImageData():encode('png'):getString())
  local count=0;local pixels=canvas:newImageData()
  for y=0,pixels:getHeight()-1,4 do for x=0,pixels:getWidth()-1,4 do
    local r,green,b=pixels:getPixel(x,y)
    if green>r*1.2 and green>b*1.2 then count=count+1 end
  end end
  check(count>100,'actual Ascendant scene contains rendered authored terrain')
  check(type(V.require('Voxel3D').shader())=='userdata','actual Ascendant GPU program compiles')
  write('world-results.json',require('src.link.Json').encode({romUsed=false,upper=upper,middle=middle,lower=lower,
    greenSamples=count,renderer={g.getRendererInfo()},source='Voxel Ascendant v3.0.36'}))
end
