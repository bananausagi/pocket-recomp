-- A legible authored diorama for reviewing the production lighting shader.
-- This is QA art, not a screenshot of a retail map or a proposed map change.
return function(Game,V,write,check)
  local g=love.graphics
  local V3=V.require('Voxel3D');local A=V.require('Atmosphere')
  local DN=V.require('DayNight');local mats={}
  local function texture(rgb)
    local d=love.image.newImageData(1,1);d:setPixel(0,0,unpack(rgb))
    local t=g.newImage(d);mats[#mats+1]=t;return t
  end
  local grass=texture({.29,.48,.29,1});local path=texture({.66,.60,.43,1})
  local wall=texture({.73,.69,.52,1});local roof=texture({.56,.25,.19,1})
  local leaf=texture({.18,.33,.21,1});local wood=texture({.34,.26,.19,1})
  local stone=texture({.40,.47,.47,1})
  local scene={}
  local function quad(points,shade,tex)
    local verts={}
    for i,p in ipairs(points)do verts[i]={p[1],p[2],p[3],i==2 or i==3 and 1 or 0,i>=3 and 1 or 0,shade}end
    -- Texture is uniform; explicit numeric UVs avoid fixture-only booleans.
    for _,v in ipairs(verts)do v[4],v[5]=0,0 end
    local mesh=assert(V3.newMesh(verts,{1,2,3,1,3,4}))
    scene[#scene+1]={mesh,tex}
  end
  local function box(x,z,w,d,h,tex,top)
    quad({{x,0,z},{x+w,0,z},{x+w,h,z},{x,h,z}},.68,tex)
    quad({{x+w,0,z+d},{x,0,z+d},{x,h,z+d},{x+w,h,z+d}},.90,tex)
    quad({{x,0,z+d},{x,0,z},{x,h,z},{x,h,z+d}},.72,tex)
    quad({{x+w,0,z},{x+w,0,z+d},{x+w,h,z+d},{x+w,h,z}},.84,tex)
    quad({{x,h,z},{x+w,h,z},{x+w,h,z+d},{x,h,z+d}},1,top or tex)
  end
  quad({{-200,0,-520},{200,0,-520},{200,0,150},{-200,0,150}},1,grass)
  quad({{-11,.03,-520},{11,.03,-520},{11,.03,150},{-11,.03,150}},1,path)
  quad({{-140,.04,-50},{140,.04,-50},{140,.04,-34},{-140,.04,-34}},1,path)
  box(30,-67,42,30,28,wall,roof)
  box(25,-72,52,40,31,roof,roof)
  -- Leave the roof/walls visible instead of hiding them behind a huge box.
  -- A separate small cabin next to the path provides several face angles.
  box(-74,-55,30,24,20,wall,roof)
  for _,p in ipairs({{-53,15},{59,12},{-70,-140},{62,-175},{-95,-260},{87,-350}})do
    box(p[1]-2,p[2]-2,4,4,11,wood)
    box(p[1]-10,p[2]-9,20,18,27,leaf)
  end
  for i=1,5 do box(-140+(i-1)*58,-440,45,36,28+i*6,stone)end
  local actor=g.newImage('fixture/battle-front.png');actor:setFilter('nearest','nearest')
  -- A flat, nearest-filtered pixel card in the production scene shader.
  local card=assert(V3.newMesh({{-9,0,0,0,1,1},{9,0,0,1,1,1},
    {9,18,0,1,0,1},{-9,18,0,0,0,1}},{1,2,3,1,3,4}))
  V.require('ShadowMap').invalidate()
  local shots={}
  for _,clock in ipairs({'day','night'})do
    DN.setting:sync(clock);DN.applyRig(true)
    V3.tint=DN.tint(true);V3.glassMask=nil;V3.glassNight=0
    local p=DN.palette()[1];local sky={p[1]/255,p[2]/255,p[3]/255,1}
    for _,mode in ipairs({'off','soft'})do
      Game.save.options.jpAtmosphere=mode
      V3.camera={eye={68,88,130},focus={0,0,-40},fov=.92,curve=0}
      g.push('all')
      assert(V3.beginScene(960,640,0,-40,240,160,sky,'atmosphere-preview'))
      for _,item in ipairs(scene)do V3.draw(item[1],item[2])end
      A.drawContact(0,0,0,6,1)
      V3.glass(false);V3.lighting(false);V3.draw(card,actor,nil,.1);V3.lighting(true)
      local canvas=V3.endScene();g.setCanvas()
      local pixels=canvas:newImageData();g.pop()
      write('preview-'..clock..'-'..mode..'.png',pixels:encode('png'):getString())
      shots[#shots+1]={clock=clock,mode=mode,pixels=pixels}
    end
  end
  local compare=g.newCanvas(1920,1280,{dpiscale=1});g.push('all');g.setCanvas(compare)
  g.origin();g.setShader();g.setScissor();g.setDepthMode();g.setColor(1,1,1,1)
  for i,s in ipairs(shots)do local image=g.newImage(s.pixels);g.draw(image,(i-1)%2*960,math.floor((i-1)/2)*640);image:release()end
  g.setCanvas();write('preview-day-night-off-soft.png',compare:newImageData():encode('png'):getString());g.pop()
  compare:release();for _,item in ipairs(scene)do item[1]:release()end
  for _,t in ipairs(mats)do t:release()end;card:release();actor:release();V3.camera=nil
  check(true,'authored legible day/night diorama rendered by actual production shaders')
end
