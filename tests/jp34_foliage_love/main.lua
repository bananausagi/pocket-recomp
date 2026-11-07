-- Synthetic floor/forest/building geometry; real production scene, shader,
-- depth attachments and shared blur. No ROM or retail images are loaded.
local function run()
  local root,out=assert(os.getenv('JP_EFFECT_ROOT')),assert(os.getenv('JP_EFFECT_OUT'))
  package.path=root..'/?.lua;'..package.path
  local now=0;love.timer.getTime=function()return now end
  local g=love.graphics;g.setDefaultFilter('nearest','nearest')
  local T=require('tests.harness').suite('jp34 battler sight lines and grass footprints')
  local renderer=require('tests.gles_context')(T.check)
  local Json=require('src.link.Json')
  local Game={data={constants={language='ja'}},save={options={jpAtmosphere='off'}}}
  package.loaded['src.core.Game']=Game
  package.loaded['src.render.PaletteFX']={pal=function()return {}end}
  package.loaded['src.world.Map']={isOutdoor=function()return true end}
  local w,h=800,480
  package.loaded['src.render.Renderer']={frameRects=function()return {pw=w,ph=h,Up=h/144}end}
  package.loaded['src.battle.BattlePresentation']={metrics=function()return {}end,filmOffset=function()return 0,0 end}
  local function write(name,data)local f=assert(io.open(out..'/'..name,'wb'));f:write(data);f:close()end
  local function picture(name,id)write(name..'.png',id:encode('png'):getString())end
  local function tex(r,green,b,checker)
    local data=love.image.newImageData(8,8)
    for y=0,7 do for x=0,7 do local c=checker and ((x+y)%2==0) and .6 or 1;data:setPixel(x,y,r*c,green*c,b*c,1)end end
    return g.newImage(data)
  end
  local blank=tex(0,0,0)
  local groundTex=tex(.64,.71,.48,true)
  local treeTex=tex(.13,.33,.08,true)
  local buildingTex=tex(.5,.3,.13,true)
  local actorTex={tex(1,.16,.02),tex(.7,.05,1)}
  local runtimes={}
  local function runtime(path)
    local mods,V={},{}
    function V.require(name)
      if not mods[name]then mods[name]=assert(loadfile(path..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/'..name..'.lua'))(V)end
      return mods[name]
    end
    mods.VoxelState={angle=.8,FOCAL=2}
    mods.ShadowMap={active=function()return false end,texture=function()return blank end,bias=.001,res=16,KX=0,KZ=0,invalidate=function()end}
    mods.VoxelGrid={enabled=function()return false end,DARK=.3,width=function()return 1 end}
    mods.WorldCurve={k=function()return 0 end,drop=function(k,x,z,px,pz)
      return ((px-x)^2+(pz-z)^2)*k end}
    mods.Sky={paint=function()end,invalidate=function()end}
    mods.GlassMask={blank=function()return blank end,texture=function()return blank end,invalidate=function()end}
    mods.DayNight={applyRig=function()end,tint=function()return {1,1,1}end,isCanopy=function()return false end,windowLight=function()return 0 end}
    mods.Water={invalidate=function()end}
    mods.AntiAlias={expand=function(a,b)return a,b end,resolve=function(c)return c end}
    mods.BattleCam={frameH=function()return 144 end}
    mods.BattleIntroFocus={pose=function(_,cam)return cam end}
    mods.BattleActionCamera={pose=function(_,cam)return cam end,finish=function()end}
    mods.BattleCameraBlend={copy=function(cam)return cam end}
    mods.VoxelBattleCardProvider={presentationBounds=function()return {width=32,height=40}end}
    local r={V=V,mods=mods,casts=0}
    r.v3=V.require('Voxel3D');r.blur=V.require('TiltShift')
    T.check(r.v3.available() and r.v3.shader(false,true)~=nil,path..' actual GL battle shader compiles')
    mods.Structures={forMap=function(map)return map.structure or {shapeAt={}} end}
    mods.TerrainAtlas={forMap=function(map)return map.texture end}
    mods.ChunkMesher={grass=function()end,flowers=function()end}
    mods.VoxelScene={prefetch=function()return r.base,r.obstacles and {r.obstacles} or {},nil,{}end,
      groundAt=function()return 0 end,_modeColors=function()return {}end,
      skyColor=function()return {.52,.68,.8,1}end,pull=function()return 0 end,
      castBattleShadows=function()r.casts=r.casts+1 end}
    r.scene=V.require('VoxelBattleScene');runtimes[#runtimes+1]=r;return r
  end
  local r=runtime(root);local E=r.V.require('SceneEffects');local Billboard=r.V.require('BattleBillboard')
  local Prefs=require('src.core.JapaneseEffects')
  for _,row in ipairs(Prefs.rows)do Game.save.options[row.id]=false end
  local opt=Game.save.options
  local function mesh(faces)
    local verts,indices={},{}
    for _,f in ipairs(faces)do local n=#verts
      for i,p in ipairs(f)do verts[#verts+1]={p[1],p[2],p[3],(i==2 or i==3) and 1 or 0,i>2 and 1 or 0,1}end
      for _,i in ipairs({1,2,3,1,3,4})do indices[#indices+1]=n+i end
    end
    return assert(r.v3.newMesh(verts,indices))
  end
  local floor={}
  for z=-160,144,16 do for x=-160,144,16 do floor[#floor+1]={{x,0,z},{x+16,0,z},{x+16,0,z+16},{x,0,z+16}}end end
  r.base=mesh(floor)
  local groundMesh=r.base
  local emptyGround=mesh({{{0,-10000,0},{1,-10000,0},{1,-10000,1},{0,-10000,1}}})
  local front=mesh({{{-46,0,28},{54,0,28},{54,55,28},{-46,55,28}}})
  local back=mesh({{{-46,0,-42},{54,0,-42},{54,55,-42},{-46,55,-42}}})
  local blades={}
  for z=-16,40,4 do for x=-36,44,4 do
    blades[#blades+1]={{x,0,z},{x+2,0,z},{x+2,26,z},{x,26,z}}
  end end
  local grass=mesh(blades)
  local host={id='host',def={tileset='OVERWORLD'},texture=groundTex,
    inBounds=function()return true end,isGrassCell=function()return true end}
  local nb={map={id='trees',def={},texture=treeTex},ox=0,oy=0}
  local state={map=host,neighbors={nb},paletteNameFor=function()return 'TEST'end}
  local arena={map=host,encounter=true,player={-35,28},enemy={4,0},playerCell={-3,1},enemyCell={0,0},mid={0,12}}
  local cam={eye={12,34,100},focus={0,10,0},fov=.85,curve=0}
  local function sprite(side)
    local data=love.image.newImageData(160,144)
    for y=76,95 do for x=73,86 do
      -- Small irregular picture with transparent corners and a real gap.
      if math.abs(x-80)<(96-y)*.28+1 and not (x==79 and y>81 and y<86) then
        data:setPixel(x,y,side=='enemy' and 1 or .05,side=='enemy' and .05 or .4,1,1)
      end
    end end
    return g.newImage(data)
  end
  local images={player=sprite('player'),enemy=sprite('enemy')}
  local models,protect,hideEnemy,hidePlayer,actors,withGrass={},true,false,false,true,false
  r.mods.ChunkMesher.grass=function(map)return withGrass and map==host and grass or nil end
  r.mods.VoxelBattleCardProvider.terrainCards=function()
    local cards={}
    for i,side in ipairs({'player','enemy'})do
      local p=arena[side]
      models[side]=Billboard.matrix(images[side],80,96,p[1],0,p[2],false,1,{faceCamera=true,worldPerPixel=1})
      if not (side=='enemy' and hideEnemy or side=='player' and hidePlayer) then
        cards[i]={texture=images[side],model=models[side],pull=Billboard.PULL,floor=0,
          foot={p[1],p[2],0,radius=12,pressure=1}}
      end
    end
    return protect and cards or nil
  end
  local function draw()
    local canvas=assert(r.scene.render(state,arena,function()
      if actors then r.v3.lighting(false)
        for _,side in ipairs({'enemy','player'})do
          if not (side=='enemy' and hideEnemy)then r.v3.draw(Billboard.mesh(),images[side],models[side],Billboard.PULL)end
        end
        r.v3.lighting(true)
      end
    end,{pose=cam,pitch=.35}))
    return canvas:newImageData()
  end
  local function purple(id,x,y)
    local a,b,c=id:getPixel(x,y);return a>.95 and b<.12 and c>.95
  end
  local function difference(a,b)
    local n=0
    for y=0,a:getHeight()-1 do for x=0,a:getWidth()-1 do
      local ar,ag,ab=a:getPixel(x,y);local br,bg,bb=b:getPixel(x,y)
      if math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)>.03 then n=n+1 end
    end end
    return n
  end
  local cases={}
  for _,size in ipairs({{800,480},{480,800}})do
    w,h=size[1],size[2];love.window.setMode(w,h,{vsync=0});cam.fov=w<h and 1.15 or .85
    for _,curve in ipairs({0,.0004})do for _,bearing in ipairs({-.35,.3})do
      cam.eye={math.sin(bearing)*104,34,math.cos(bearing)*104};cam.curve=curve
      local tag=w..'x'..h..'-'..bearing..'-'..curve
      withGrass=false;r.obstacles=nil;protect=true
      local reference=draw();local points={}
      -- Measure the actual projected picture alpha independently of terrain.
      -- During the curved entry pose the floor can cover a few foot pixels;
      -- those pixels are still inside the picture, not a rectangular hole.
      r.base=emptyGround;local silhouette=draw();r.base=groundMesh
      for y=0,h-1 do for x=0,w-1 do if purple(reference,x,y)then points[#points+1]={x,y}end end end
      T.check(#points>20,'small irregular enemy has visible reference pixels '..tag)
      for _,kind in ipairs({'tree','grass'})do
        r.obstacles=kind=='tree' and front or nil;withGrass=kind=='grass'
        protect=false;local blocked=draw();protect=true;local rescued=draw()
        local before,after=0,0
        for _,p in ipairs(points)do
          if purple(blocked,p[1],p[2])then before=before+1 end
          if purple(rescued,p[1],p[2])then after=after+1 end
        end
        T.check(before<#points*.25,tag..' '..kind..' reproduces almost completely hidden opponent')
        T.check(after>=#points*.98,tag..' '..kind..' recovers opponent silhouette: '..after..'/'..#points)
        -- Every changed pixel must be within a real nontransparent card;
        -- empty sprite corners and the surrounding tree/grass remain exact.
        local outside,edgePixels=0,0
        for y=0,h-1 do for x=0,w-1 do
          local ar,ag,ab=rescued:getPixel(x,y);local br,bg,bb=blocked:getPixel(x,y)
          if math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)>.03
              and not (select(3,silhouette:getPixel(x,y))>.95
                and (select(1,silhouette:getPixel(x,y))>.95 or select(1,silhouette:getPixel(x,y))<.12))then
            -- Different interpolation precision can round one raster-edge
            -- texel differently. It may never produce a hole away from art.
            local edge=false
            for yy=math.max(0,y-1),math.min(h-1,y+1)do for xx=math.max(0,x-1),math.min(w-1,x+1)do
              local cr,cg,cb=silhouette:getPixel(xx,yy)
              if cb>.95 and (cr>.95 or cr<.12)then edge=true end
            end end
            if edge then edgePixels=edgePixels+1 else outside=outside+1 end
          end
        end end
        T.eq(outside,0,tag..' '..kind..' scenery outside actual card alpha is unchanged')
        cases[#cases+1]={size=tag,occluder=kind,reference=#points,before=before,after=after,outsideChanges=outside,edgePixels=edgePixels}
        if bearing==.3 then
          picture('before-'..kind..'-'..w..'x'..h..'-'..curve,blocked)
          picture('after-'..kind..'-'..w..'x'..h..'-'..curve,rescued)
          picture('reference-'..w..'x'..h..'-'..curve,reference)
        end
      end
      withGrass=false;r.obstacles=back;protect=false;local behind=draw();protect=true
      T.eq(difference(behind,draw()),0,'scenery behind the opponent is unchanged '..tag)
      hideEnemy=true;hidePlayer=true;actors=false;r.obstacles=front;protect=false;local hidden=draw();protect=true
      T.eq(difference(hidden,draw()),0,'empty picture creates no rectangular clearing '..tag)
      hideEnemy=false;hidePlayer=false;actors=true
    end end
  end
  -- Real shader geometry: isolated walking press, recovery and battle feet.
  w,h=800,480;love.window.setMode(w,h,{vsync=0});cam={eye={12,50,90},focus={0,0,0},fov=.9,curve=0}
  r.obstacles=nil;withGrass=true;actors=false;protect=false;arena.jpSceneEffects=nil
  local resting=draw()
  local ow={map=host,player={px=-4,py=-8,stepFrames=16}}
  now=10;E.finish();opt.jpFxGrass=true;E.world(ow)
  ow.player.px=4;now=now+.1;local fx=E.world(ow);arena.jpSceneEffects=fx
  T.check(fx.step[4]>0 and #fx.particles>0,'walking in grass starts depression and rustling leaves')
  local pressed=draw();T.check(difference(resting,pressed)>100,'walking visibly presses actual grass geometry')
  picture('walking-pressed',pressed)
  opt.jpFxGrass=false;now=now+.1;E.world(ow)
  T.eq(difference(resting,draw()),0,'grass OFF restores untouched geometry and removes leaves')
  opt.jpFxGrass=true;ow.player.px=12;now=now+.1;E.world(ow)
  for _=1,10 do now=now+.1;E.world(ow)end
  T.eq(difference(resting,draw()),0,'grass springs back after the walker leaves')
  arena.jpSceneEffects={options=opt,battle={},particles={}};protect=true
  opt.jpFxBattleEnvironment=false;local unpressed=draw()
  opt.jpFxBattleEnvironment=true;local feet=draw()
  T.check(difference(unpressed,feet)>50,'both grounded battle feet depress nearby blades')
  picture('battle-feet-pressed',feet)
  opt.jpFxBattleEnvironment=false;T.eq(difference(unpressed,draw()),0,'battle environment OFF restores blades')
  local report={renderer=renderer,checks=T.checks,failures=T.failures,messages=T.messages,cases=cases,romUsed=false}
  write('results.json',require('src.link.Json').encode(report));T.finish()
end
function love.load()local ok,err=xpcall(run,debug.traceback);if not ok then print(err)end;love.event.quit(ok and 0 or 1)end
