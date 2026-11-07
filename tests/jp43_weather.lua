return function(Game,V,field,check,write)
 local g=love.graphics
 local W=V.require('FieldAtmosphere');local Particles=V.require('WeatherParticles')
 local C=V.require('Voxel3D');local Scene=V.require('VoxelScene')
 local opts=Game.save.options
 local function bytes(c)return c:newImageData():getString()end
 local colors={{184,209,107},{107,161,64},{51,97,46},{13,31,26}}
 local function palette()return colors end
 local fade=V.require('SceneryTransition');local fadeChoice=fade.setting:get();fade.setting:sync(false)
 local function render(mode,w,h,name)
  W.setting:sync(mode);W.setClock(12.3)
  local c=assert(Scene.render(field,w,h,160,160*h/w,palette))
  check(not W.lastError and not Particles.lastError,'world weather renders without shader error '..mode..' '..w..'x'..h)
  if name then write(name..'.png',c:newImageData():encode('png'):getString())end
  return bytes(c)
 end
 W.strengthSetting:sync(1);opts.reduceMotion=false;opts.jpReduceMotion=false
 V.require('DayNight').setting:sync('day')
 local observations={}
 for _,size in ipairs({{640,360},{360,640}})do
  local clear=render('clear',size[1],size[2],'weather-clear-'..size[1])
  for _,mode in ipairs({'rain','snow','fog','storm'})do
   local changed=render(mode,size[1],size[2],'weather-'..mode..'-'..size[1])
   check(changed~=clear,'weather visibly changes the world '..mode)
   check(Particles.stats.particles>0 and Particles.stats.particles<=Particles.LIMIT,'bounded depth geometry '..mode)
  end
 end
 local a={id='ROUTE_3',def={outdoor=true}};local b={id='PEWTER_CITY',def={outdoor=true}}
 for n=0,31 do check(W.modeAt(a,'auto',n*180)==W.modeAt(b,'auto',n*180),'adjacent routes share automatic weather '..n)end
 W.setting:sync('rain');W.setClock(20);check(W.frame(a).rain==1,'forced weather initializes predictably')
 W.setting:sync('snow');local f=W.frame(a);check(f.rain==1 and f.snow==0,'changing weather retains the outgoing first frame')
 for _=1,12 do W.update(.1)end
 f=W.frame(b);check(f.rain>.4 and f.rain<.6 and f.snow>.4 and f.snow<.6,'weather blends across a map boundary')
 for _=1,13 do W.update(.1)end
 f=W.frame(b);check(f.snow==1 and f.rain==0,'weather reaches the new state')
 W.setting:sync('clear');f=W.frame(a);check(f.snow==0 and f.rain==0,'explicit clear removes all particles immediately')
 W.setting:sync('storm');W.setClock(7.6);W.lightningSetting:sync(true)
 check(W.lightning()>.13 and W.lightning()<=.14,'lightning is one bounded soft pulse')
 W.lightningSetting:sync(false);check(W.lightning()==0 and W.frame(a).storm==1,'lightning OFF keeps storm rain')
 opts.reduceMotion=true;local clock=W.clock;W.update(.1);f=W.frame(a)
 check(W.clock==clock and f.storm==0 and W.lightning()==0,'reduced motion immediately disables animation and flashes')
 opts.reduceMotion=false;W.update(3);check(W.clock==clock,'resume does not jump after a long pause')
 W.setClock(12.3);W.setting:sync('rain')
 local room={id='ROOM',def={outdoor=false,tileset='POKECENTER'}}
 check(W.frame(room).rain==0,'no weather remains when entering a room')
 -- Coordinate continuity uses the exact connection offsets, not a rounded
 -- player tile; all rain/snow/ground impacts share this frame of reference.
 Particles.invalidate()
 Particles.observe({map=a,neighbors={{map=b,ox=192,oy=-32}}})
 Particles.observe({map=b,neighbors={{map=a,ox=-192,oy=32}}})
 check(Particles.originX==192 and Particles.originZ==-32,'particle lattice follows neighbor offsets')
 Particles.observe({map=a,neighbors={{map=b,ox=192,oy=-32}}})
 check(Particles.originX==0 and Particles.originZ==0,'turning back preserves the same lattice')
 -- Real depth buffer proof: a near opaque cover must hide every drop, then
 -- removing it exposes the same geometry. No readable-depth texture needed.
 local block=g.newShader([[
  #ifdef VERTEX
  vec4 position(mat4 t,vec4 p){return vec4(p.xy,-.999,1.0);}
  #endif
  #ifdef PIXEL
  vec4 effect(vec4 c,Image t,vec2 uv,vec2 sc){return vec4(.2,.4,.3,1.0);}
  #endif
 ]])
 local cover=g.newMesh({{-1,-1,0,0},{1,-1,1,0},{1,1,1,1},{-1,1,0,1}},'fan','static')
 W.setClock(12.3);local f=W.prepare(field)
 local function covered(draw,occlude)
  assert(C.beginScene(640,360,96,96,160,90,{.2,.4,.3,1}))
  if occlude then
   g.push('all');g.setShader(block);g.setDepthMode('always',true);g.setMeshCullMode('none');g.setColor(1,1,1,1);g.draw(cover);g.pop()
  end
  if draw then W.draw(field,f)end
  return bytes(C.endScene())
 end
 local hidden=covered(false,true);check(covered(true,true)==hidden,'opaque near geometry occludes precipitation pixel-for-pixel')
 check(covered(true,false)~=covered(false,false),'the same precipitation is visible without the occluder')
 block:release();cover:release()
 -- Steady state: weather reuses its single mesh and shader, no screen copy.
 render('storm',640,360)
 local allocations=Particles.stats.allocations
 local count=Particles.stats.draws
 local times={};for i=1,12 do local t=love.timer.getTime();Scene.render(field,640,360,160,90,palette);times[i]=(love.timer.getTime()-t)*1000 end
 check(Particles.stats.allocations==allocations,'steady weather allocates no new GPU objects')
 check(Particles.stats.draws-count==12,'weather costs one bounded particle draw per frame')
 table.sort(times);observations.weatherMedianMs=times[6];observations.particleCount=Particles.stats.particles
 W.setting:sync('clear');local t0={}
 for i=1,12 do local t=love.timer.getTime();Scene.render(field,640,360,160,90,palette);t0[i]=(love.timer.getTime()-t)*1000 end
 table.sort(t0);observations.clearMedianMs=t0[6]
 write('weather-metrics.json',require('src.link.Json').encode(observations))
 W.lightningSetting:sync(true);W.invalidate();fade.setting:sync(fadeChoice)
end
