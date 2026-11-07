-- Actual GL allocations: pending shared animations never batch-upload in draw
-- and do not leak when an unvisited prediction loses its last owner.
return function(Game,V,check,write)
 local A=V.require('TerrainAtlas');local g,fs=love.graphics,love.filesystem
 local pixels=love.image.newImageData(128,64)
 pixels:mapPixel(function(x,y)local c=({1,.66,.33,0})[(x+y)%4+1];return c,c,c,1 end)
 fs.write('jp41-atlas.png',pixels:encode('png'));pixels:release()
 local source=g.newImage('jp41-atlas.png')
 local ts={image='jp41-atlas.png',tilesPerRow=16,
  animatedTiles={{kind='hshift',tile=1,offsets={0,1,2,3,4,5,6,7},period=20}}}
 local a={id='QA_A',tileset=ts,renderer={image=source}}
 local b={id='QA_B',tileset=ts,renderer={image=source}}
 local colors={{245,250,235},{170,205,130},{50,130,70},{10,25,20}}
 A.invalidate();A.setLive({QA_A=true,QA_B=true})
 local uploads,images=0,{}
 local raw=g.newImage
 g.newImage=function(...)uploads=uploads+1;local image=raw(...);images[#images+1]=image;return image end
 A.queuePreparation(a,colors);A.queuePreparation(b,colors)
 check(uploads==0,'reserving two shared atlases performs zero texture uploads')
 local static=assert(A.forMap(a,colors))
 check(uploads==1 and not A.prepared(a,colors),'first field draw creates only correct static palette image')
 for _=1,20 do check(A.forMap(a,colors)==static,'unfinished animation keeps static field visible')end
 check(uploads==1,'repeated field draws do not create animation frames')
 A.prepare(a,colors,.001);A.prepare(a,colors,.001)
 check(uploads==2,'cooperative preparation uploads one animation frame')
 local partial=images[#images];A.cancelPreparation(a,colors)
 check(pcall(partial.getDimensions,partial),'another map keeps partially prepared shared atlas alive')
 local maxUploads=0
 for _=1,40 do
  local before=uploads;local ready=A.prepare(b,colors,.001)
  maxUploads=math.max(maxUploads,uploads-before)
  if ready then break end
 end
 check(A.prepared(a,colors) and A.prepared(b,colors),'remaining owner completes shared animation for both maps')
 check(maxUploads<=1 and uploads==9,'eight immutable frames finish without restart or batch upload')
 local before=uploads;assert(A.forMap(a,colors));check(uploads==before,'completed field animation selects cached texture only')
 A.invalidate();A.setLive({QA_A=true})
 A.queuePreparation(a,colors);A.prepare(a,colors,.001);A.prepare(a,colors,.001)
 local abandoned=images[#images]
 A.setLive({QA_B=true});check(pcall(abandoned.getDimensions,abandoned),'previous neighbourhood protects pending atlas')
 A.setLive({QA_C=true})
 check(not pcall(abandoned.getDimensions,abandoned),'leaving both retained neighbourhoods releases partial animation texture')
 g.newImage=raw;A.invalidate();source:release()
 write('atlas-queue.json',require('src.link.Json').encode({maxUploadsPerUpdate=maxUploads,sharedAtlasUploads=9,
  drawBatchUploads=0,abandonedResourcesReleased=true,romUsed=false}))
end
