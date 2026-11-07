-- Real GL coverage and connected native map rendering, with synthetic art.
return function(Game,Renderer,V,restore,check,write)
 local g,fs=love.graphics,love.filesystem
 local C,F,Scene,M=V.require('Voxel3D'),V.require('SceneryTransition'),V.require('VoxelScene'),V.require('ChunkMesher')
 local function pixels(c)return c:newImageData()end
 local function shot(d,name)write(name..'.png',d:encode('png'):getString())end
 local opts=Game.save.options
 for _,r in ipairs(require('src.core.JapaneseEffects').rows)do opts[r.id]=false end
 opts.reduceMotion=false;opts.jpReduceMotion=false
 V.require('FieldAtmosphere').setting:sync('clear')
 V.require('Shadows').setting:sync('off')
 V.require('WorldCurve').setting:sync(0)
 -- Complementary coverage has no transparent/black gaps, the near field
 -- stays current, and subsequent actor draws never inherit the dissolve.
 local vv={};for _,p in ipairs({{-1000,-1000,0},{1000,-1000,0},{1000,1000,0},{-1000,1000,0}})do
  vv[#vv+1]={p[1],p[2],p[3],0,0,1}
 end
 local quad=assert(C.newMesh(vv,{1,2,3,1,3,4}))
 local function color(r,gg,b)local d=love.image.newImageData(1,1);d:setPixel(0,0,r,gg,b,1);local t=g.newImage(d);d:release();return t end
 local red,blue,green=color(1,0,0),color(0,0,1),color(0,1,0)
 C.camera={eye={0,0,100},focus={0,0,0},fov=math.rad(40),curve=0}
 local fractions={}
 for _,t in ipairs({0,.25,.5,.75,1})do
  check(C.beginScene(320,180,0,0,160,90,nil,'fade42'),'coverage scene opens '..t)
  C.lighting(false);C.sceneryDissolve(1,t);C.draw(quad,red)
  C.sceneryDissolve(-1,t);C.draw(quad,blue);C.sceneryDissolve(0)
  local d=pixels(C.endScene());local nr,nb,holes=0,0,0
  for y=0,63 do for x=0,319 do
   local r,gg,b,a=d:getPixel(x,y)
   if r>.99 then nr=nr+1 elseif b>.99 then nb=nb+1 else holes=holes+1 end
  end end
  fractions[#fractions+1]=nr/(nr+nb)
  check(holes==0 and math.abs(fractions[#fractions]-t)<.001,'old/new coverage exactly complements without dark holes '..t)
  local near=true
  for y=130,179 do for x=0,319 do local r,gg,b=d:getPixel(x,y);if r<.99 or b>.01 then near=false end end end
  check(near,'near field never retains the previous area '..t)
  shot(d,'coverage-'..t);d:release()
  C.beginScene(320,180,0,0,160,90,nil,'fade42');C.lighting(false)
  C.sceneryDissolve(-1,t);C.draw(quad,blue);C.sceneryDissolve(0);C.draw(quad,green)
  local actor=pixels(C.endScene());local allGreen=true
  for y=0,179,3 do for x=0,319,3 do local r,gg,b=actor:getPixel(x,y);if gg<.99 or r>.01 or b>.01 then allGreen=false end end end
  check(allGreen,'actor pass draws once with full coverage '..t);actor:release()
 end
 quad:release();red:release();blue:release();green:release();C.camera=nil
 -- The connection's asymmetric dimensions make root-owned forest rings
 -- genuinely differ, as on a town/route boundary. Both are fully preloaded.
 local img=love.image.newImageData(128,128);img:mapPixel(function()return 1,1,1,1 end)
 for y=0,7 do for x=0,7 do local c=(x+y)%4==0 and .66 or 1;img:setPixel(96+x,16+y,c,c,c,1)end end
 for y=0,15 do for x=0,15 do
  local radius=((x-7.5)/7)^2+((y-6.5)/6)^2;local c=1
  if radius<=1 then c=radius>.74 and 0 or ((x*3+y)%5==0 and .33 or .66)
  elseif y>=11 and x>=6 and x<=9 then c=.33 end
  img:setPixel(x,(y<8 and 32 or 40)+y%8,c,c,c,1)
 end end
 fs.write('jp42-trees.png',img:encode('png'));img:release()
 local ground,trees={},{};for y=0,3 do for x=0,3 do ground[#ground+1]=44;trees[#trees+1]=(y%2==0 and 64 or 80)+x%2 end end
 local ts={id='OVERWORLD',image='jp42-trees.png',imageWidth=128,imageHeight=128,tilesPerRow=16,
  blocks={},walkable={44},counterTiles={},doorTiles={},warpTiles={},waterTiles={},shoreTiles={}}
 for i=1,16 do ts.blocks[i]=ground end;ts.blocks[16]=trees;Game.data.tilesets.OVERWORLD=ts
 local function def(id,w,h,conn)
  local d={id=id,index=2943,tileset='OVERWORLD',width=w,height=h,outdoor=true,blocks={},borderBlock=15,
   connections=conn,warps={},objects={},signs={}}
  for i=1,w*h do d.blocks[i]=0 end;Game.data.maps[id]=d;return require('src.world.MapLoader').load(Game.data,id)
 end
 local a=def('FADE42_A',12,10,{east={map='FADE42_B',offset=3}})
 local b=def('FADE42_B',10,6,{west={map='FADE42_A',offset=-3}})
 require('src.render.TileRenderer').setVoidFill('trees');V.require('SceneryDistance').setting:sync(12)
 F.invalidate();M.invalidate()
 local cam=require('src.render.Camera').new();cam.x,cam.y=280,30
 local sa={map=a,neighbors={{map=b,ox=384,oy=96}},entities={},ghosts={},camera=cam,
  player={px=376.25,py=140.5,cellX=23,cellY=8},paletteNameFor=function()return 'PALLET'end}
 local cb=require('src.render.Camera').new();cb.x,cb.y=cam.x-384,cam.y-96
 local sb={map=b,neighbors={{map=a,ox=-384,oy=-96}},entities={},ghosts={},camera=cb,
  player={px=sa.player.px-384,py=sa.player.py-96,cellX=-1,cellY=2},paletteNameFor=sa.paletteNameFor}
 for _,s in ipairs({sa,sb})do Scene.prefetch(s);while M.pending()>0 do M.pump(false)end end
 V.require('VoxelState').level=5;V.require('VoxelState').angle=math.rad(65)
 local function render(s)
  Game.overworld=s;Game.stack={top=function()return s end}
  return assert(Scene.render(s,640,360,200,120,function()return {{240,248,220},{112,180,84},{48,100,40},{16,40,24}}end))
 end
 F.setting:sync(false);local old=pixels(render(sa));local new=pixels(render(sb))
 local function delta(d,e,y0,y1)
  local n=0;for y=y0,y1 do for x=0,639 do
   local r,gg,b=d:getPixel(x,y);local rr,g0,b0=e:getPixel(x,y);n=n+math.abs(r-rr)+math.abs(gg-g0)+math.abs(b-b0)
  end end;return n
 end
 local abrupt=delta(old,new,0,143)
 check(abrupt>100,'fully preloaded root change reproduces a visible distant scenery jump')
 shot(old,'seam-before');shot(new,'seam-after')
 F.setting:sync(true);F.invalidate();render(sa)
 local first=pixels(render(sb));local initial=delta(first,old,0,143)
 check(initial<abrupt*.02,'first seam frame retains outgoing distant scenery in the rebased live camera')
 local steps={};shot(first,'seam-fade-00');first:release()
 for i=1,6 do
  F.update(.1);local d=pixels(render(sb));steps[i]=delta(d,new,0,143)
  check(i==1 or steps[i]<=steps[i-1]+.01,'distant pixels approach the new scenery monotonically '..i)
  shot(d,'seam-fade-0'..i);d:release()
 end
 check(steps[6]<1,'completed dissolve equals normal destination rendering')
 -- Reverse at the same world position while fading. Mesh ownership and
 -- coverage reverse without snapping either to 0 or to 1.
 F.invalidate();render(sa);render(sb);F.update(.2)
 local beforeBack=pixels(render(sb));local afterBack=pixels(render(sa))
 check(delta(beforeBack,afterBack,0,143)<1,'mid-fade reversal preserves distant pixels')
 beforeBack:release();afterBack:release()
 local stationary=pixels(render(sa));cam.x=cam.x+6.25;local moving=pixels(render(sa))
 check(delta(stationary,moving,0,143)>10,'outgoing scenery follows live fractional camera movement instead of a frozen screenshot')
 cam.x=cam.x-6.25;stationary:release();moving:release()
 F.setting:sync(false);local off=pixels(render(sb));check(off:getString()==new:getString(),'OFF returns exact ordinary destination pixels');off:release()
 F.setting:sync(true);F.invalidate();render(sa);render(sb)
 opts.reduceMotion=true;local reduced=pixels(render(sb));check(reduced:getString()==new:getString(),'reduce motion bypasses the scenery dissolve');reduced:release();opts.reduceMotion=false
 -- Context loss/resize can drop the extra references without releasing
 -- pages still owned by the map cache.
 F.invalidate();check(pcall(M.peek(a,false).getVertexCount,M.peek(a,false)),'transition invalidation leaves cached terrain alive')
 render(sa);render(sb);local retained=M.peek(a,false);M.invalidate()
 check(retained:getVertexCount()>0,'cache eviction cannot free an outgoing mesh during its fade')
 F.invalidate();check(retained:getVertexCount()==0,'transition cleanup releases its final retained pages')
 old:release();new:release();Game.overworld=restore
 write('scenery-transition.json',require('src.link.Json').encode({fractions=fractions,oldToNewDelta=abrupt,
  initialDelta=initial,remainingDelta=steps,duration=F.DURATION,romUsed=false,androidDeviceUsed=false}))
end
