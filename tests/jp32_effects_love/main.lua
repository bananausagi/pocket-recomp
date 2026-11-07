-- Synthetic floor/forest/building geometry; real production scene, shader,
-- depth attachments and shared blur. No ROM or retail images are loaded.
local function run()
  local root,out=assert(os.getenv('JP_EFFECT_ROOT')),assert(os.getenv('JP_EFFECT_OUT'))
  package.path=root..'/?.lua;'..package.path
  local now=0;love.timer.getTime=function()return now end
  local g=love.graphics;g.setDefaultFilter('nearest','nearest')
  local T=require('tests.harness').suite('jp32 real GL individual effects')
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
    mods.WorldCurve={k=function()return 0 end,drop=function()return 0 end}
    mods.Sky={paint=function()end,invalidate=function()end}
    mods.GlassMask={blank=function()return blank end,texture=function()return blank end,invalidate=function()end}
    mods.DayNight={applyRig=function()end,tint=function()return {1,1,1}end,isCanopy=function()return false end,windowLight=function()return 0 end,
      body=function()return {dx=.25,dy=.7,dz=.25,moon=false}end}
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
  local r=runtime(root);local E=r.V.require('SceneEffects')
  local Prefs=require('src.core.JapaneseEffects')
  local opt=Game.save.options
  local function off()for _,row in ipairs(Prefs.rows)do opt[row.id]=false end end
  local function mesh(faces)
    local vertices,indices={},{}
    for _,face in ipairs(faces)do local n=#vertices
      for i,p in ipairs(face)do vertices[#vertices+1]={p[1],p[2],p[3],(i==2 or i==3) and 1 or 0,i>2 and 1 or 0,1}end
      for _,i in ipairs({1,2,3,1,3,4})do indices[#indices+1]=n+i end
    end
    return assert(r.v3.newMesh(vertices,indices))
  end
  local floor={};local blades={}
  for z=-96,96,8 do for x=-96,96,8 do
    floor[#floor+1]={{x,0,z},{x+8,0,z},{x+8,0,z+8},{x,0,z+8}}
    if z>=0 and z<=40 and x>=8 and x<=56 then
      blades[#blades+1]={{x,0,z},{x+2,0,z},{x+2,7,z},{x,7,z}}
    end
  end end
  r.base=mesh(floor);local grass=mesh(blades)
  r.mods.ChunkMesher.grass=function()return grass end
  local host={id='field',def={tileset='OVERWORLD'},texture=groundTex,
    inBounds=function()return true end,isWalkableCell=function()return true end,
    isGrassCell=function(self)return self.surface=='grass'end,
    isWaterCell=function(self)return self.surface=='water'end,cellTile=function()return 4 end}
  local state={map=host,neighbors={},paletteNameFor=function()return 'TEST'end}
  local arena={map=host,encounter=true,player={16,32},enemy={48,0},
    playerCell={1,2},enemyCell={3,0},mid={32,16},groundY=0}
  local b={game=Game,data={moves={EMBER={type='FIRE'},EARTHQUAKE={type='GROUND'}}},phase='menu',
    player={mon={species='PIKACHU'}},enemy={mon={species='GASTLY'},shownStatus='PSN'}}
  local cam={eye={76,62,100},focus={32,5,16},fov=.92,curve=0}
  local actor=mesh({{{-4,0,0},{4,0,0},{4,16,0},{-4,16,0}}})
  local Mat4=r.V.require('Mat4')
  local function draw()
    local canvas=assert(r.scene.render(state,arena,function()
      for i,side in ipairs({'player','enemy'})do
        local p=arena[side];local dx,dy,dz,sx,sy=E.pose(arena,b,side,false)
        local model=Mat4.mul(Mat4.translate(p[1]+dx,dy,p[2]+dz),Mat4.scale(sx,sy,1))
        r.v3.draw(actor,actorTex[i],model)
      end
    end,{pose=cam,pitch=.45}))
    return canvas:newImageData()
  end
  local function diff(a,b)
    local n=0
    for y=0,a:getHeight()-1 do for x=0,a:getWidth()-1 do
      local ar,ag,ab=a:getPixel(x,y);local br,bg,bb=b:getPixel(x,y)
      if math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)>.012 then n=n+1 end
    end end
    return n
  end
  local cases={}
  for _,size in ipairs({{800,480},{480,800}})do
    w,h=size[1],size[2];love.window.setMode(w,h,{vsync=0});cam.fov=w<h and 1.45 or .92
    off();arena.jpSceneEffects=nil
    local baseline=draw()
    for _,row in ipairs(Prefs.rows)do
      off();opt[row.id]=true;E.finish(arena);E.finish()
      b.phase='menu';b.jpFxHitSerial=nil;b.jpFxMoveSerial=nil;b.jpFxHitCritical=false;b.jpFxHitMoveName=nil
      host.def.tileset='OVERWORLD';host.surface=nil
      local s
      if row.group=='battleEffects' then
        now=now+.1;s=E.battle(arena,b)
        if row.id=='jpFxMoveLight' or row.id=='jpFxBattleEnvironment' then
          b.phase='messages';b.jpFxMoveSerial=1;b.jpFxMoveName=row.id=='jpFxMoveLight' and 'EMBER' or 'EARTHQUAKE';b.jpFxMoveTarget=b.enemy
        end
        if row.id=='jpFxHitReaction' or row.id=='jpFxBattleEnvironment' or row.id=='jpFxAfterglow' or row.id=='jpFxCritical' then
          b.jpFxHitSerial=1;b.jpFxHitTarget=b.enemy;b.jpFxHitCritical=row.id=='jpFxCritical'
          b.jpFxHitMoveName=row.id=='jpFxBattleEnvironment' and 'EARTHQUAKE' or 'EMBER'
        end
        local n=row.id=='jpFxStatus' and 9 or 2
        for _=1,n do now=now+.1;s=E.battle(arena,b)end
      else
        local ow={map=host,player={px=8,py=24,facing='down'}}
        if row.id=='jpFxAmbient' or row.id=='jpFxLightShafts' then host.def.tileset='FOREST' end
        if row.id=='jpFxGrass' then host.surface='grass' end
        if row.id=='jpFxWater' then host.surface='water' end
        now=now+.1;s=E.world(ow)
        ow.player.px=16
        if row.id=='jpFxWater' then ow.fishing={} end
        for _=1,row.id=='jpFxLightShafts' and 24 or row.id=='jpFxAmbient' and 8 or 2 do now=now+.1;s=E.world(ow)end
        arena.jpSceneEffects=s
      end
      local visible=draw();local changed=diff(baseline,visible)
      T.check(changed>0,w..'x'..h..' '..row.id..' changes actual world pixels ('..changed..')')
      picture(row.id..'-'..w..'x'..h,visible)
      cases[#cases+1]={effect=row.id,width=w,height=h,changedPixels=changed,particles=#s.particles}
      off();arena.jpSceneEffects=nil
      T.eq(diff(baseline,draw()),0,row.id..' OFF returns exact native pixels')
    end
    -- Real grass at both live combatant anchors; explicit actor bounds remain.
    arena.jpSceneEffects=nil;off()
    local grassBattle=draw();arena.encounter=false
    T.eq(diff(grassBattle,draw()),0,'grass at both feet is not flattened by entering battle '..w..'x'..h)
    arena.encounter=true
  end
  local shaderSource=assert(io.open(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/EffectParticles.lua')):read('*a'):match('local SHADER=%[%[(.-)%]%]')
  local valid,why=g.validateShader(true,shaderSource)
  T.check(valid,'particle shader validates for GLES '..tostring(why or ''))
  local allocations={};local original={}
  opt.jpFxStatus=true;arena.jpSceneEffects=nil;b.phase='menu'
  for _=1,12 do now=now+.1;E.battle(arena,b);draw()end
  for _,api in ipairs({'newImage','newMesh','newShader','newCanvas'})do
    allocations[api]=0;original[api]=g[api];g[api]=function(...)allocations[api]=allocations[api]+1;return original[api](...)end
  end
  for _=1,40 do now=now+.05;E.battle(arena,b);draw()end
  for api,fn in pairs(original)do g[api]=fn;T.eq(allocations[api],0,'warm effects allocate no '..api)end
  local report={actualGL=true,renderer=renderer,romUsed=false,cases=cases,allocations=allocations,checks=T.checks,failures=T.failures,messages=T.messages}
  write('results.json',Json.encode(report));T.finish()
end
function love.load()local ok,err=xpcall(run,debug.traceback);if not ok then print(err);love.event.quit(1)else love.event.quit(0)end end
