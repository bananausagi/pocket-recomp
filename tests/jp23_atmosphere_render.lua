-- Production scene shaders, terrain, source-map actors and battle cards.
-- Only the fixture art/PCM are synthetic. No ROM or physical Android claim.
return function(Game,Renderer,V,state,check,write,render)
  local g=love.graphics
  local A=V.require('Atmosphere')
  local V3=V.require('Voxel3D')
  local DN=V.require('DayNight')
  local Shadows=V.require('Shadows')
  local Host=V.require('VoxelBattleStandalone')
  local Blend=V.require('BattleCameraBlend')
  local Intro=V.require('BattleIntroFocus')
  local Pipelines=require('src.render.Pipelines')
  local Palette=require('src.render.PaletteFX')
  local report={cases={},renderer={g.getRendererInfo()},physicalAndroid=false,
    authoredAssets=true,fullScreenPasses=0}
  local function delta(a,b)
    local changed,total,maximum=0,0,0
    for y=0,a:getHeight()-1,2 do for x=0,a:getWidth()-1,2 do
      local ar,ag,ab=a:getPixel(x,y);local br,bg,bb=b:getPixel(x,y)
      local d=(math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb))/3
      if d>0 then changed=changed+1;total=total+d;maximum=math.max(maximum,d)end
    end end
    return {changed=changed,mean=total/math.max(1,changed),max=maximum}
  end
  local function snapshot(name)
    local pic=render();write(name..'.png',pic:encode('png'):getString());return pic
  end
  local initial=Game.save.options.jpAtmosphere
  local origContact=A.drawContact
  local oldTime=love.timer.getTime;local fixed=oldTime()
  love.timer.getTime=function()return fixed end
  local ok,err=xpcall(function()
    local source=assert(love.filesystem.read('vendor/jp-mods/DRAMALESS_SHAPE/lib/Voxel3D.lua'))
    local glsl=assert(source:match('local SHADER = %[%[(.-)%]%]'))
    for _,prefix in ipairs({'','#define VOXEL_GRID 1\n','#define BATTLE_OCCLUSION 1\n',
        '#define BATTLE_OCCLUSION 1\n#define VOXEL_GRID 1\n','#define UNLIT_ONLY 1\n'})do
      local valid,why=g.validateShader(true,prefix..glsl)
      check(valid,'GLES scene shader validates '..prefix..tostring(why or ''))
    end
    local contactSource=assert(love.filesystem.read('vendor/jp-mods/DRAMALESS_SHAPE/lib/Atmosphere.lua'))
    local contactGLSL=assert(contactSource:match('local CONTACT = %[%[(.-)%]%]'))
    local valid,why=g.validateShader(true,contactGLSL)
    check(valid,'GLES analytic contact shader validates '..tostring(why or ''))
    love.window.setMode(800,480,{vsync=0})
    Game.save.options.jpDialogScale=.75;Game.save.options.jpDotMatrix=0
    Game.save.options.jpBattleIntro='original'
    require('src.render.DotMatrix').setLevel(0)
    Pipelines.setLevel('tiltshift',0)
    Shadows.setting:sync('high')
    -- Full overworld pipeline, including source-map entity poses and culling.
    local OW=require('src.world.OverworldController')
    setmetatable(Game.data,{__index=require('src.core.Data')})
    Game.data.maps.FIX_ROUTE.outdoor=true
    Game.data.field.playerSprites={walk='SPRITE_FIX_PLAYER'}
    Game.data.field.flyWarps=Game.data.field.flyWarps or {}
    Game.data.field.waterTilesets=Game.data.field.waterTilesets or {}
    Game.data.field.forcedMovement=Game.data.field.forcedMovement or {tiles={}}
    Game.data.field.forcedMovement.tiles=Game.data.field.forcedMovement.tiles or {}
    local ow=setmetatable({},{__index=OW})
    ow:enter('FIX_ROUTE',8,12,'up',{via='boot',keepMusic=true})
    ow.paletteNameFor=state.paletteNameFor;ow.neighbors={}
    Game.stack.states={ow};Game.overworld=ow
    Game.save.options.pipelines={voxel=2,tiltshift=0};Pipelines.applyOptions(Game.save.options)
    DN.setting:sync('day')
    for _=1,60 do Pipelines.update(1/60);render()end
    for _,clock in ipairs({'day','night'})do
      DN.setting:sync(clock)
      check(DN.time()==DN.T[clock],'actual '..clock..' clock is selected')
      for _,color in ipairs({'redpp','redpp_soft'})do
        Game.save.options.colors=color;Palette.applyOptions(Game.save.options)
        local tag='field-'..clock..'-'..color
        Game.save.options.jpAtmosphere='off';render();local off=snapshot(tag..'-off')
        if clock=='day' and color=='redpp' then
          local baselinePath=os.getenv('JP_QA_ATMOSPHERE_BASELINE')
          if baselinePath then
            local f=assert(io.open(baselinePath,'rb'));local source=f:read('*a');f:close()
            local base=assert(source:match('local SHADER = %[%[(.-)%]%]'))
            local oldShader=V3.shader;local shaders={}
            V3.shader=function(grid,battle)
              local prefix=(grid and '#define VOXEL_GRID 1\n' or '')..(battle and '#define BATTLE_OCCLUSION 1\n' or '')
              shaders[prefix]=shaders[prefix] or g.newShader(prefix..base)
              return shaders[prefix]
            end
            local baseline=render();V3.shader=oldShader
            check(baseline:getString()==off:getString(),'atmosphere OFF matches actual jp22 scene shader pixel for pixel')
            for _,shader in pairs(shaders)do shader:release()end
          end
        end
        local beforeDraw=A.stats.contactDraws
        Game.save.options.jpAtmosphere='soft';local soft=snapshot(tag..'-soft')
        check(A.stats.contactDraws==beforeDraw,tag..' atmosphere adds no duplicate overworld contact')
        local d=delta(off,soft)
        check(d.changed>500 and d.mean<.10,tag..' atmosphere changes visible scenery gently')
        A.drawContact=function()return false end
        local without=render();A.drawContact=origContact
        local contact=delta(soft,without)
        check(contact.changed==0,tag..' field uses only existing actor cast shadows')
        Game.save.options.jpAtmosphere='off'
        check(render():getString()==off:getString(),tag..' live OFF restores exact prior pixels')
        report.cases[#report.cases+1]={tag=tag,difference=d,contact=contact,
          outdoor=require('src.world.Map').isOutdoor(ow.map.def),time=DN.time(),tint={unpack(V3.tint)}}
      end
    end
    check(not A.solidGround({isWaterCell=function()return true end},8,8),
      'water never receives new ground contacts')
    check(not A.solidGround(nil,8,8),'unknown ground never receives contacts')
    local language=Game.data.constants.language
    Game.data.constants.language='en'
    check(not A.enabled(),'non-Japanese games retain original presentation by default')
    Game.data.constants.language=language
    check(not A.solidGround({inBounds=function()return false end,isWaterCell=function()return false end},8,8),
      'out of bounds ground does not receive contacts')
    Game.save.options.jpAtmosphere='soft';Shadows.setting:sync('off')
    local n=A.stats.contactDraws;render()
    check(A.stats.contactDraws==n,'explicit shadows OFF suppresses all extra contact draws')
    Shadows.setting:sync('high')
    -- Battle shares exact same light controls, while actual Pokémon cards
    -- and every white command panel stay on their existing unlit path.
    Host.finish('atmosphere-battle');Blend.cancel()
    Game.save.options.colors='gbc';Palette.applyOptions(Game.save.options)
    local b=require('src.battle.BattleState').newWild(Game,'FIXMON_C',10)
    Game.stack:push(b)
    local a=assert(Host.session).context.arena
    a.presentationTime=10;a.entryDuration=nil;a.entryPose=nil;Intro.finish(a)
    b.phase,b.current,b.queue='menu',nil,{}
    b.introSlide,b.introBalls,b.showPlayerBack=0,false,false
    b.enemyHudPending,b.enemySendingOut=false,false
    for _,clock in ipairs({'day','night'})do
      DN.setting:sync(clock)
      local tag='battle-'..clock
      Game.save.options.jpAtmosphere='off';local off=snapshot(tag..'-off')
      local offUI=Renderer.battlePresentationCanvas:newImageData():getString()
      Game.save.options.jpAtmosphere='soft';local soft=snapshot(tag..'-soft')
      check(Renderer.battlePresentationCanvas:newImageData():getString()==offUI,
        tag..' entire white HUD/text canvas remains pixel-exact')
      local d=delta(off,soft)
      check(d.changed>500 and d.mean<.10,tag..' same subtle scenery response applies to battle')
      local actor,changed=0,0
      for y=0,off:getHeight()-1 do for x=0,off:getWidth()-1 do
        local r,gg,bb=off:getPixel(x,y)
        if (r>.2 and r<.65 and gg>r*1.1 and gg>.2 and bb<.35 and bb<r*.9)
            or (r>.85 and gg>.6 and gg<.8 and bb>.1 and bb<.3) then
          actor=actor+1;local p,q,s=soft:getPixel(x,y)
          if r~=p or gg~=q or bb~=s then changed=changed+1 end
        end
      end end
      check(actor>100 and changed==0,tag..' native actor colours remain exact and crisp')
      report.cases[#report.cases+1]={tag=tag,difference=d,actorPixels=actor,actorChanged=changed}
    end
    local originalCanvas,originalShader,originalMesh=g.newCanvas,g.newShader,g.newMesh
    local allocations,allAllocations,allocationSites=0,0,{}
    local function count()
      allAllocations=allAllocations+1
      local site=debug.traceback()
      allocationSites[#allocationSites+1]=site
      if site:find('Atmosphere.lua',1,true) then allocations=allocations+1 end
    end
    g.newCanvas=function(...)count();return originalCanvas(...)end
    g.newShader=function(...)count();return originalShader(...)end
    g.newMesh=function(...)count();return originalMesh(...)end
    render();render();render()
    g.newCanvas,g.newShader,g.newMesh=originalCanvas,originalShader,originalMesh
    check(allocations==0,'steady atmosphere allocates no canvases, shaders or meshes')
    check(A.stats.fullScreenPasses==0,'atmosphere adds no full-screen GPU pass')
    report.gpu={steadyAllocations=allocations,contactResources=A.stats.allocations,
      contactDraws=A.stats.contactDraws,fullScreenPasses=A.stats.fullScreenPasses,
      totalSceneAllocations=allAllocations,allocationSites=allocationSites}
    check(#Game.mods.errors==0,'atmosphere production path has no MOD runtime errors')
    require('tests.jp23_atmosphere_preview')(Game,V,write,check)
    write('results.json',assert(require('src.link.Json').encode(report)))
  end,debug.traceback)
  A.drawContact=origContact;love.timer.getTime=oldTime
  Game.save.options.jpAtmosphere=initial
  Host.finish('atmosphere-end');Blend.cancel()
  if not ok then error(err,0)end
end
