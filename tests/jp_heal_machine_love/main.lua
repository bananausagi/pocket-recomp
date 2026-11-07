-- Actual production modules and fxHeal closure; all pixels are synthetic.
local function run()
 local root,out=assert(os.getenv('JP_QA_ROOT')),assert(os.getenv('JP_QA_OUT'))
 package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
 local g=love.graphics;g.setDefaultFilter('nearest','nearest')
 local checks,captures,views=0,0,0
 local function check(ok,msg)assert(ok,msg);checks=checks+1;print('PASS '..msg)end
 local function write(name,s)local f=assert(io.open(out..'/'..name,'wb'));f:write(s);f:close()end
 local function read(name)local f=assert(io.open(root..'/'..name,'rb'));local s=f:read('*a');f:close();return s end
 local V,modules={},{}
 function V.require(name)
  if not modules[name]then modules[name]=assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/'..name..'.lua'))(V)end
  return modules[name]
 end
 function V.data(name)return assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/data/'..name..'.lua'))()end
 local H,V3=V.require('VoxelHealMachine'),V.require('Voxel3D')
 local Palette=require('src.render.PaletteFX');require('src.core.GameVersion').set('red_jp')
 local source=read('src/world/OverworldController.lua')
 local defs=assert(source:match('(local HEAL_BALL_XY =.-)\n%-%- scripts/VermilionDock'))
 local body=assert(source:match('  (local function fxHeal%(part%).-)\n  %-%- the Cut/boulder dust'))
 local make=assert(loadstring('return function(Game,PaletteFX,self,cam)\n'..defs..'\n'..body..'\nreturn fxHeal,healMachineShader,HEAL_BALL_XY end'))()
 local profile=V.data('voxel_heights');local candidates={}
 for id,list in pairs(profile.buildings)do for _,t in ipairs(list)do
  if t.id=='center_heal_machine_w' or t.id=='center_heal_machine_e'then candidates[#candidates+1]={id=id,t=t}end
 end end
 check(#candidates>=4,'both machine orientations in both supported tilesets are present')
 local tx,ty=10,4
 local function mapFor(c)
  return {tileset={id=c.id},tileAt=function(_,x,y)local row=c.t.tiles[y-ty+1];return row and row[x-tx+1] or 0 end}
 end
 local ha={px=tx*8+32,py=ty*8+48,lit=0,visible=true,timer=11,balls=6,phase='fill'}
 for _,c in ipairs(candidates)do
  local a=H.anchor(mapFor(c),ha);check(a and a.template.id==c.t.id,c.id..' '..c.t.id..' exact match anchor')
  local faces=H.faces(a);check(#faces==2 and faces[2].top-faces[2].h>=0,'ball face stays above floor')
  check(math.abs(faces[2].w/faces[2].h-16/18)<1e-10,'ball face preserves source aspect')
  check(faces[1].z>a.z+c.t.parts[1].z+c.t.parts[1].depth and faces[2].z>a.z+c.t.desk.z+c.t.desk.depthPx,'faces sit just outside model surfaces')
 end
 local map=mapFor(candidates[1]);local state={map=map,healAnim=ha}
 local cam={x=19.625,y=13.25}
 local pixels=love.image.newImageData(8,16)
 for y=0,15 do for x=0,7 do
  local inside=y<8 or (x>=1 and x<=6 and y%8<=4)
  local v=({1,0.67,0.33,0})[(x+y)%4+1]
  pixels:setPixel(x,y,v,v,v,inside and 1 or 0)
 end end
 local img=g.newImage(pixels);state.healMachineImg=img
 local fx,flash,ballXY=make({data={field={overworldFx={}}}},Palette,state,cam)
 local colors={{255,244,210},{195,170,105},{90,80,45},{15,20,10}}
 local calls=0
 local ctx={state=state,cam=cam,spriteColors=function()return colors end,fx={heal=function(part)calls=calls+1;fx(part)end}}
 local function reference()
  local canvas=g.newCanvas(16,32,{dpiscale=1});g.push('all');g.setCanvas(canvas);g.origin();g.setScissor();g.setStencilTest();g.setDepthMode();g.clear(0,0,0,0);g.setColor(1,1,1,1);g.setBlendMode('alpha','alphamultiply')
  local shader=Palette.shader();g.setShader(shader);Palette.sendColors(shader,colors);flash(ha.visible)
  g.draw(img,g.newQuad(0,0,8,8,8,16),4,0)
  for i=1,ha.lit do local b=ballXY[i];local x,y=b[1]-40,b[2]-27+8
   g.draw(img,g.newQuad(0,8,8,8,8,16),x+(b[3]and 8 or 0),y,0,b[3]and -1 or 1,1)
  end
  g.setCanvas();g.pop();local data=canvas:newImageData();canvas:release();return data
 end
 -- Dirty transforms/scissor/depth/stencil/shader must not affect capture,
 -- and the caller must get each of those states back even on errors.
 local caller=g.newCanvas(32,32,{dpiscale=1});local hostile=g.newShader('vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){return vec4(1,0,1,1);}')
 local function hostileBegin()
  g.push('all');g.setCanvas({caller,stencil=true});g.origin();g.translate(9,17);g.scale(2,3);g.setScissor(1,2,3,4);g.setStencilTest('greater',1);g.setDepthMode('greater',false);g.setShader(hostile);g.setColor(.1,.2,.3,.4)
 end
 local function restored(label)
  local x,y=g.transformPoint(1,1);local sx,sy,sw,sh=g.getScissor();local st,sv=g.getStencilTest();local d,dw=g.getDepthMode();local r,gg,b,a=g.getColor()
  check(g.getCanvas()==caller and x==11 and y==20 and sx==1 and sy==2 and sw==3 and sh==4 and st=='greater'and sv==1 and d=='greater'and not dw and g.getShader()==hostile and math.abs(a-.4)<1e-5,label)
  g.setCanvas();g.pop()
 end
 local last
 for _,mode in ipairs({'gbc','og','og_inv','classic','gbc_inv','ogred'})do
  Palette.mode=mode
  for lit=1,6 do for _,visible in ipairs({true,false})do
   ha.lit,ha.visible=lit,visible;local before=calls;hostileBegin();local frame=assert(H.prepare(ctx));restored('capture state restore '..mode..' '..lit..' '..tostring(visible))
   local actual=frame.canvas:newImageData();local expected=reference()
   check(actual:getString()==expected:getString(),'actual fxHeal matches canonical palette/flash/balls '..mode..' '..lit..' '..tostring(visible));captures=captures+1
   check(ha.timer==11 and ha.phase=='fill'and ha.balls==6,'render leaves timing and party count unchanged')
   check(calls==before+2,'each changed animation frame captures only two parts')
   check(H.prepare(ctx)==frame and calls==before+2,'unchanged frame reuses texture and mesh')
   last=frame;actual:release();expected:release()
  end end
 end
 local before=calls;Palette.customRamp={{252,250,240},{220,50,70},{40,80,190},{5,10,20}}
 local custom=assert(H.prepare(ctx));check(calls==before+2,'custom ramp invalidates texture without source-palette change')
 local customExpected=reference();check(custom.canvas:newImageData():getString()==customExpected:getString(),'custom ramp matches original closure output');Palette.customRamp=nil
 -- Fractional camera movement changes capture transforms, never attachment.
 before=calls;cam.x,cam.y=37.75,44.875;local stable=assert(H.prepare(ctx));check(calls==before+2,'removing custom ramp recaptures colors')
 before=calls;cam.x,cam.y=73.125,-6.4;check(H.prepare(ctx)==stable and calls==before,'camera movement reuses map-space attached geometry')
 local frozen=stable.canvas:newImageData():getString();ha.lit=5;local normalfx=ctx.fx.heal;ctx.fx.heal=function()error('injected FX failure')end
 hostileBegin();local ok=pcall(H.prepare,ctx);restored('failed capture restores caller graphics state');check(not ok,'capture error is visible to pipeline fallback');ctx.fx.heal=normalfx
 ha.lit=6;local retry=assert(H.prepare(ctx));check(retry.canvas:newImageData():getString()==frozen,'failed partial capture cannot reuse an older matching signature')
 check(H.prepare(ctx)~=nil,'capture retries successfully after failure')
 state.healMachineImg=false;ha.lit=4;check(H.prepare(ctx)==nil,'missing art leaves original flat FX fallback active');state.healMachineImg=img
 check(H.prepare(ctx)~=nil,'art becoming readable can retry same frame')
 local good=map.tileAt;map.tileAt=function()return -1 end;check(H.prepare(ctx)==nil,'custom template mismatch retains flat fallback');map.tileAt=good
 local oldpx=ha.px;ha.px=oldpx+1;check(H.anchor(map,ha).x==tx*8,'fractional interaction still anchors to the real machine');ha.px=oldpx
 for _,offset in ipairs({-16,16,7.25})do ha.px=oldpx+offset;local a=H.anchor(map,ha);check(a and a.x==tx*8 and a.z==ty*8,'adjacent/fractional player cell cannot move machine FX '..offset)end;ha.px=oldpx
 check(H.draw(nil)==false,'absent face does not suppress ordinary overlay')
 -- The actual engine FX dispatcher must skip exactly the handled heal,
 -- retaining dust, cut and every other ordinary effect in their prior order.
 local dispatch=assert(source:match('    (ctx%.drawFx = function%(project, scale, handled%).-)\n    override = Pipelines.drawWorld'))
 local makeDispatch=assert(loadstring('return function(Game,PaletteFX,self,cam,ctx,pscale,vw,vh,fxHeal,fxDust,fxCutTree,fxEmote,fxBird,fxRod)\n'..dispatch..'\nreturn ctx.drawFx end'))()
 local counts={heal=0,dust=0,cut=0};local s={healAnim=ha,dustAnim={x=2,y=3},cutAnim={x=4,y=5}}
 local function hit(key)return function()counts[key]=counts[key]+1 end end
 local dispatchCtx={spriteColors=function()return colors end}
 local drawFx=makeDispatch({renderer={worldOverlayScale=function()return 1,1 end}},Palette,s,cam,dispatchCtx,1,160,144,hit('heal'),hit('dust'),hit('cut'))
 g.push('all');g.setCanvas(caller);g.origin();g.setScissor();g.setStencilTest();g.setShader()
 drawFx(function(x,y)return x,y end,1,{heal=true})
 check(counts.heal==0 and counts.dust==1 and counts.cut==1,'actual engine dispatcher suppresses only the attached heal')
 drawFx(function(x,y)return x,y end,1,{heal=false})
 check(counts.heal==1 and counts.dust==2 and counts.cut==2,'actual engine dispatcher retains heal fallback when unhandled')
 g.setCanvas();g.pop()
 Palette.mode='gbc';ha.lit=6;ha.visible=true;last=assert(H.prepare(ctx));local anchor=assert(H.anchor(map,ha));local faces=H.faces(anchor)
 check(last.mesh:getVertexCount()==8 and #last.mesh:getVertexMap()==12,'two quads contain eight vertices and twelve indices')
 local function backing(zshift)
  local vv,ii={},{}
  for n,f in ipairs(faces)do
   local x,y,z,w,h=f.x-1,f.top+1,f.z+zshift,f.w+2,f.h+2
   for _,v in ipairs({{x,y-h,z,0,1,1},{x+w,y-h,z,1,1,1},{x+w,y,z,1,0,1},{x,y,z,0,0,1}})do vv[#vv+1]=v end
   V3.pushQuad(ii,n-1)
  end
  return assert(V3.newMesh(vv,ii))
 end
 local back,front=backing(-.035),backing(.5)
 local bd=love.image.newImageData(1,1);bd:setPixel(0,0,.2,.8,.9,1);local tex=g.newImage(bd)
 local function render(w,h,yaw,pitch,overlay,occlude)
  local focus={anchor.x+16,14,anchor.z+25};local d=100;local cp=math.cos(pitch)
  V3.camera={eye={focus[1]+d*cp*math.sin(yaw),focus[2]+d*math.sin(pitch),focus[3]+d*cp*math.cos(yaw)},focus=focus,fov=math.rad(40),curve=0}
  g.origin();g.setScissor();g.setStencilTest();g.setBlendMode('alpha','alphamultiply')
  check(V3.beginScene(w,h,focus[1],focus[3],160,144),'real voxel depth scene starts')
  V3.draw(occlude and front or back,tex)
  local bounds={}
  for _,f in ipairs(faces)do local b={xmin=math.huge,ymin=math.huge,xmax=-math.huge,ymax=-math.huge}
   for _,p in ipairs({{f.x,f.top-f.h,f.z},{f.x+f.w,f.top-f.h,f.z},{f.x+f.w,f.top,f.z},{f.x,f.top,f.z}})do
    local x,y=V3.project(unpack(p));b.xmin=math.min(b.xmin,x);b.ymin=math.min(b.ymin,y);b.xmax=math.max(b.xmax,x);b.ymax=math.max(b.ymax,y)
   end;bounds[#bounds+1]=b
  end
  if overlay then check(H.draw(last),'healing faces rendered in actual voxel shader')end
  local canvas=V3.endScene();return canvas:newImageData(),bounds
 end
 for _,size in ipairs({{192,144},{384,288}})do for _,yaw in ipairs({-math.pi/3,0,math.pi/3})do for _,pitch in ipairs({math.rad(20),math.rad(50),math.rad(70)})do
  local w,h=size[1],size[2];local baseline=render(w,h,yaw,pitch,false);local actual,bounds=render(w,h,yaw,pitch,true);local changed,outside=0,0
  for y=0,h-1 do for x=0,w-1 do local r,gg,b,a=actual:getPixel(x,y);local rr,g0,b0,a0=baseline:getPixel(x,y)
   if r~=rr or gg~=g0 or b~=b0 or a~=a0 then changed=changed+1;local inside=false
    for _,q in ipairs(bounds)do if x>=q.xmin-1 and x<=q.xmax+1 and y>=q.ymin-1 and y<=q.ymax+1 then inside=true end end
    if not inside then outside=outside+1 end
   end
  end end
  check(changed>8 and outside==0,'camera '..yaw..'/'..pitch..' '..w..'x'..h..' FX stays on projected machine faces')
  if w==384 and yaw==0 and pitch==math.rad(50)then write('synthetic-heal-attached.png',actual:encode('png'):getString())end
  baseline:release();actual:release();views=views+1
 end end end
 local hiddenBase=render(384,288,0,math.rad(20),false,true);local hidden=render(384,288,0,math.rad(20),true,true)
 check(hiddenBase:getString()==hidden:getString(),'opaque machine surface ahead of FX occludes them through depth buffer')
 -- A finished animation must release its small native capture and references.
 local oldCanvas,oldMesh=last.canvas,last.mesh;state.healAnim=nil;check(H.prepare(ctx)==nil,'finished animation clears attachment')
 check(not pcall(oldCanvas.getWidth,oldCanvas) and not pcall(oldMesh.getVertexCount,oldMesh),'finished animation releases cached canvas and mesh')
 check(H.prepare(nil)==nil,'absent pipeline context is harmless')
 write('results.json',require('src.link.Json').encode({checks=checks,captureComparisons=captures,cameraViews=views,romUsed=false,syntheticArt=true,actualSourceClosure=true,actualVoxelShader=true}))
 print(checks..' HEAL MACHINE GL CHECKS PASSED')
end
function love.load()local ok,err=xpcall(run,debug.traceback);love.graphics.setCanvas();if not ok then print(err);love.event.quit(1)else love.event.quit(0)end end
