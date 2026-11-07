-- Installed provider: retain real scene pixels, cooperatively prepare a map,
-- then expose its scene. No native black canvas or early destination entry.
return function(Game,Renderer,V,state,check,write)
 local g=love.graphics;local P=require('src.render.Pipelines')
 local M=V.require('ChunkMesher');local Pre=V.require('VoxelPrecache')
 local VS=V.require('VoxelState');local Scene=V.require('VoxelScene')
 local Veil=V.require('VoxelLoadingVeil');local Camera=require('src.render.Camera')
 local function bytes(c)return c:newImageData():getString()end
 love.window.setMode(640,360,{vsync=0})
 state.entities={};state.ghosts={};state.player={cellX=8,cellY=8,px=128,py=128,facing='down'}
 state.camera=Camera.new();state.camera:follow(128,128,160,90)
 Game.overworld=state;Game.stack={top=function()return state end}
 P.setLevel('voxel',3);VS.level=3;VS.angle=math.rad(50);VS.ready=true
 V.require('FirstPerson').blend=0
 local function draw(s)
  return P.drawWorld('voxel',{state=s,cam=s.camera,vw=160,vh=90,width=640,height=360,scale=4,
   paletteFor=function()return nil end,drawFx=function()end})
 end
 local old=assert(draw(state));local before=bytes(old)
 local nonblack=false;local d=old:newImageData()
 for y=0,359,12 do for x=0,639,12 do local r,gg,b=d:getPixel(x,y);if r+gg+b>.1 then nonblack=true end end end
 check(nonblack,'retained surface is a rendered field, not a black placeholder')
 local def={};for k,v in pairs(state.map.def)do def[k]=v end
 def.id='JP40_NEXT';def.index=2904;def.connections={};def.warps={};Game.data.maps[def.id]=def
 local nextMap=require('src.world.MapLoader').load(Game.data,def.id)
 local cold={map=nextMap,neighbors={},entities={},ghosts={},player=state.player,camera=state.camera,paletteNameFor=state.paletteNameFor}
 local prepare=Game.mods.exports.DRAMALESS_SHAPE.prepareMapTransition
 local ready=assert(prepare(def.id),'installed module exports area preparation')
 check(not ready(),'cold destination readiness remains false')
 local held=draw(cold)
 check(held~=nil and bytes(held)==before,'actual missing-mesh path returns every pixel of the previous world')
 for _=1,2000 do
  if ready()then break end
  Pre.update(Game);M.pump(true)
 end
 check(ready(),'cooperative destination geometry and atlas preparation finishes')
 check(Game.overworld.map==state.map,'preparing terrain does not enter the destination')
 check(Scene.atlasReady(nextMap),'destination texture atlas is ready before map switch')
 Game.overworld=cold;Game.stack={top=function()return cold end}
 local shown=draw(cold);check(shown~=nil,'prepared destination draws on its first frame')
 write('prepared-destination.png',shown:newImageData():encode('png'):getString())
 Veil.invalidate();check(Veil.get(640,360)==nil,'graphics invalidation drops borrowed surface')
 check(pcall(shown.getDimensions,shown),'retention never releases the renderer-owned canvas')
 write('area-transition.json',require('src.link.Json').encode({romUsed=false,previousPixelsExact=true,preparedBeforeEntry=true,renderer={g.getRendererInfo()}}))
end
