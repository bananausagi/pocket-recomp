-- Installed MOD and native Map/FX context. Artwork is handwritten test data.
return function(Game,Renderer,V,state,check,write)
 local g,fs=love.graphics,love.filesystem
 local H=V.require('VoxelHealMachine');local M=V.require('ChunkMesher')
 local P=require('src.render.Pipelines');local Palette=require('src.render.PaletteFX')
 local pixels=love.image.newImageData(128,128)
 pixels:mapPixel(function(x,y)local v=({1,.67,.33,0})[(math.floor(x/2)+math.floor(y/2))%4+1];return v,v,v,1 end)
 fs.write('jp42-center.png',pixels:encode('png'))
 local template
 for _,t in ipairs(V.data('voxel_heights').buildings.POKECENTER)do
  if t.id=='center_heal_machine_w'then template=t end
 end
 local ground,block={},{}
 for i=1,16 do ground[i]=0 end
 for _,row in ipairs(template.tiles)do for _,tile in ipairs(row)do block[#block+1]=tile end end
 Game.data.tilesets.POKECENTER={id='POKECENTER',image='jp42-center.png',imageWidth=128,imageHeight=128,
  tilesPerRow=16,blocks={ground,block},walkable={0},counterTiles={},doorTiles={},warpTiles={},waterTiles={},shoreTiles={}}
 local def={id='JP42_CENTER',index=2942,tileset='POKECENTER',width=6,height=6,outdoor=false,
  borderBlock=0,blocks={},warps={},connections={},objects={},signs={}}
 for i=1,36 do def.blocks[i]=0 end;def.blocks[8]=1;Game.data.maps[def.id]=def
 local map=require('src.world.MapLoader').load(Game.data,def.id)
 local Camera=require('src.render.Camera');local cam=Camera.new();cam.x,cam.y=3.25,5.625
 local ha={px=64,py=80,lit=6,visible=true,timer=11,balls=6,phase='fill'}
 local s={map=map,neighbors={},entities={},ghosts={},player={px=64,py=80,cellX=4,cellY=5,facing='up'},
  camera=cam,healAnim=ha,paletteNameFor=function()return 'PALLET'end}
 local art=love.image.newImageData(8,16)
 art:mapPixel(function(x,y)local v=({1,.67,.33,0})[(x+y)%4+1];return v,v,v,(y<8 or x>0 and x<7)and 1 or 0 end)
 s.healMachineImg=g.newImage(art)
 local source=assert(fs.read('src/world/OverworldController.lua'))
 local defs=assert(source:match('(local HEAL_BALL_XY =.-)\n%-%- scripts/VermilionDock'))
 local body=assert(source:match('  (local function fxHeal%(part%).-)\n  %-%- the Cut/boulder dust'))
 local make=assert(loadstring('return function(Game,PaletteFX,self,cam)\n'..defs..'\n'..body..'\nreturn fxHeal end'))()
 local fx=make(Game,Palette,s,cam)
 Game.overworld=s;Game.stack={top=function()return s end};Palette.mode='gbc'
 P.setLevel('voxel',3);local VS=V.require('VoxelState');VS.level=3;VS.angle=math.rad(50);VS.ready=true
 V.require('FirstPerson').blend=0
 M.request(map,true,nil,true);M.request(map,false,{},true);while M.pending()>0 do M.pump(false)end
 local ctx={state=s,cam=cam,fxCam=cam,vw=160,vh=90,width=640,height=360,scale=4,
  paletteFor=function()return nil end,spriteColors=function()return nil end,fx={heal=fx}}
 local dispatch=assert(source:match('    (ctx%.drawFx = function%(project, scale, handled%).-)\n    override = Pipelines.drawWorld'))
 local makeDispatch=assert(loadstring('return function(Game,PaletteFX,self,cam,ctx,pscale,vw,vh,fxHeal)\n'..dispatch..'\nreturn ctx.drawFx end'))()
 local flatCalls=0
 ctx.drawFx=makeDispatch(Game,Palette,s,cam,ctx,4,160,90,function()flatCalls=flatCalls+1;fx()end)
 local expected=assert(H.prepare(ctx)).canvas:newImageData():getString()
 H.prepare(nil)
 local original=H.prepare;local observed
 H.prepare=function(c)
  local ok,frame=pcall(original,c)
  check(ok,'installed healing preparation succeeds: '..tostring(frame))
  check(frame~=nil,'native Map template resolves to the machine')
  observed=frame.canvas:newImageData():getString();return frame
 end
 local canvas=P.drawWorld('voxel',ctx)
 H.prepare=original
 check(canvas~=nil,'installed pipeline renders the center')
 write('heal-integration.json',require('src.link.Json').encode({flatCopies=flatCalls,captureMatchesOriginalCamera=observed==expected}))
 write('center-installed.png',canvas:newImageData():encode('png'):getString())
 check(flatCalls==0,'all installed MOD wrappers retain the handled heal flag: no second floating overlay')
 check(observed==expected,'real framed camera captures the same heal pixels as the original FX camera')
 check(ctx.cam==cam and s.camera==cam,'pipeline restores the native camera')
 write('center-installed.png',canvas:newImageData():encode('png'):getString())
 H.prepare(nil);M.invalidate();Game.overworld=state
 require('tests.jp42_scenery_fade')(Game,Renderer,V,state,check,write)
end
