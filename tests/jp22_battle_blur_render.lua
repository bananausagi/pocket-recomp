-- Real Game/loaded MOD/terrain depth/battle camera/HUD path. No ROM assets.
return function(Game,Renderer,V,state,check,write,render)
  local g=love.graphics
  local Host=V.require('VoxelBattleStandalone')
  local V3=V.require('Voxel3D')
  local Blur=V.require('TiltShift')
  local AA=V.require('AntiAlias')
  local Intro=V.require('BattleIntroFocus')
  local Blend=V.require('BattleCameraBlend')
  local Battle=require('src.battle.BattleState')
  local Json=require('src.link.Json')
  local root=assert(os.getenv('JP_QA_ROOT'))
  local Pipelines=require('src.render.Pipelines')
  local originalBlur=Blur.battleBackground
  local chosen,capture=0,nil
  local depthShader=g.newShader([[
    uniform LOVE_HIGHP_OR_MEDIUMP Image depthTex;
    uniform vec3 clipFocus;
    vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
      float n=clipFocus.x;float f=clipFocus.y;
      float distance=n/max(.000001,1.0-Texel(depthTex,uv).r*(1.0-n/f));
      return vec4(clamp(distance/(2.0*clipFocus.z),0.0,1.0),0.0,0.0,1.0);
    }
  ]])
  local depthOut
  local function imageOf(canvas)
    g.push('all');g.setCanvas();local result=canvas:newImageData();g.pop();return result
  end
  Blur.battleBackground=function(canvas,depth,opts)
    local before=imageOf(canvas)
    local w,h=canvas:getDimensions()
    if not depthOut or depthOut:getWidth()~=w or depthOut:getHeight()~=h then
      if depthOut then depthOut:release()end
      depthOut=g.newCanvas(w,h,{dpiscale=1})
    end
    g.push('all');g.origin();g.setCanvas(depthOut);g.setScissor();g.setDepthMode()
    g.setBlendMode('replace');g.setShader(depthShader);g.setColor(1,1,1,1)
    depthShader:send('depthTex',assert(depth,'production scene must expose actual readable depth'))
    depthShader:send('clipFocus',{opts.near,opts.far,opts.focus});g.draw(canvas)
    g.setCanvas();local distances=depthOut:newImageData();g.pop()
    local applied=originalBlur(canvas,depth,opts)
    capture={before=before,after=imageOf(canvas),depth=distances,focus=opts.focus,
      width=w,height=h,mode=Blur.lastBattleMode,applied=applied}
    return applied
  end
  local function differences(c)
    local near,nChanged,mid,midDelta,far,farDelta=0,0,0,0,0,0
    for y=0,c.height-1,3 do for x=0,c.width-1,3 do
      local d=c.depth:getPixel(x,y)*2
      local a,b,cc=c.before:getPixel(x,y);local p,q,r=c.after:getPixel(x,y)
      local delta=(math.abs(a-p)+math.abs(b-q)+math.abs(cc-r))/3
      if d<.89 then near=near+1;if delta>0 then nChanged=nChanged+1 end
      elseif d>=1.10 and d<=1.40 then mid=mid+1;midDelta=midDelta+delta
      elseif d>=1.40 and d<1.99 then far=far+1;farDelta=farDelta+delta end
    end end
    return {near=near,nearChanged=nChanged,mid=mid,midDelta=midDelta/math.max(1,mid),
      far=far,farDelta=farDelta/math.max(1,far),width=c.width,height=c.height,focus=c.focus}
  end
  local report={renderer={g.getRendererInfo()},cases={},romUsed=false,physicalAndroid=false}
  local oldAA=AA.setting.index
  local ok,err=xpcall(function()
    Game.save.options.jpDotMatrix=0
    require('src.render.DotMatrix').setLevel(0)
    Game.save.options.jpDialogScale=.75
    Game.save.options.jpBattleIntro='original'
    Pipelines.setLevel('tiltshift',0)
    for _,shape in ipairs({{972,1536,0},{800,480,0},{480,800,4}})do
      love.window.setMode(shape[1],shape[2],{vsync=0})
      AA.setting.index=shape[3]==4 and 3 or 1
      Host.finish('blur-next');Blend.cancel()
      Game.stack.states={state};Game.overworld=state;render()
      -- Same loaded pipeline on the same authored terrain before battle.
      -- The fixture uses Scene.render for its field camera, so suppress its
      -- battle-only pass and invoke the actual worldPresent registry path.
      local battleWrapper,fieldDraw=Blur.battleBackground,state.draw
      Blur.battleBackground=function()return false end
      state.draw=function(self)
        fieldDraw(self)
        Renderer:setWorldOverride(Pipelines.worldPresent(Renderer.worldOverride,{}))
      end
      for level=0,5 do
        Pipelines.setLevel('tiltshift',level)
        local image=render()
        write('field-'..shape[1]..'x'..shape[2]..'-aa'..shape[3]..'-level'..level..'.png',image:encode('png'):getString())
      end
      state.draw=fieldDraw;Blur.battleBackground=battleWrapper
      Pipelines.setLevel('tiltshift',0)
      local battle=Battle.newWild(Game,'FIXMON_C',10)
      Game.stack:push(battle)
      local arena=assert(Host.session).context.arena
      arena.presentationTime=10;arena.entryDuration=nil;arena.entryPose=nil
      Intro.finish(arena)
      battle.phase,battle.current,battle.queue='menu',nil,{}
      battle.introSlide,battle.introBalls,battle.showPlayerBack=0,false,false
      battle.enemyHudPending,battle.enemySendingOut=false,false
      local tag=shape[1]..'x'..shape[2]..'-aa'..shape[3]
      local images,stats={},{}
      local modes={0,1,2,3,4,5}
      for _,mode in ipairs(modes)do
        chosen=mode;Pipelines.setLevel('tiltshift',mode)
        Game.save.options.jpBattleBlur=mode==0 and 'strong' or 'off'
        local pixels=render()
        images[mode]=pixels;stats[mode]=differences(assert(capture))
        write('scene-'..tag..'-'..mode..'.png',pixels:encode('png'):getString())
        if mode==0 then
          check(not capture.applied and capture.before:getString()==capture.after:getString(),tag..' OFF is exact before actors')
        else
          check(capture.applied,tag..' '..mode..' actual scene blur applied despite legacy off')
          check(stats[mode].near>100 and stats[mode].nearChanged==0,tag..' '..mode..' nearby terrain remains pixel-exact')
        end
      end
      check(stats[5].mid>100,tag..' real terrain covers close background depth range')
      check(stats[5].midDelta>0 and stats[5].midDelta~=stats[3].midDelta,tag..' shared levels3 and5 use distinct radii')
      local actorPixels,changed=0,0
      local off,strong=images[0],images[5]
      local comparison=g.newCanvas(shape[1]*3,shape[2]+36,{dpiscale=1})
      g.push('all');g.setCanvas(comparison);g.origin();g.setShader();g.setScissor();g.setDepthMode()
      g.clear(.12,.12,.12,1);g.setColor(1,1,1,1);g.setFont(g.newFont(22))
      for i,mode in ipairs({0,3,5})do
        local pic=g.newImage(images[mode]);pic:setFilter('nearest','nearest')
        g.draw(pic,(i-1)*shape[1],36);g.print('LEVEL '..mode,(i-1)*shape[1]+12,5)
        pic:release()
      end
      g.setCanvas();write('comparison-'..tag..'.png',comparison:newImageData():encode('png'):getString())
      g.pop();comparison:release()
      for y=0,off:getHeight()-1 do for x=0,off:getWidth()-1 do
        local r,gg,b=off:getPixel(x,y)
        if (r>.45 and r<.65 and gg>.6 and gg<.8 and b>.1 and b<.3)
            or (r>.85 and gg>.6 and gg<.8 and b>.1 and b<.3)then
          actorPixels=actorPixels+1
          local a,bb,c=strong:getPixel(x,y)
          if r~=a or gg~=bb or b~=c then changed=changed+1 end
        end
      end end
      check(actorPixels>100 and changed==0,tag..' all authored actor colour pixels stay sharp and identical')
      Pipelines.setLevel('tiltshift',0);chosen=0
      local backOff=render()
      check(backOff:getString()==images[0]:getString(),tag..' live shared5 -> OFF returns exact original frame')
      local r=Renderer:frameRects();local m=require('src.battle.BattlePresentation').metrics(r)
      local panel=m.command
      local x0=math.max(0,math.ceil((m.x+panel.x*m.sx)*r.dpiX)+4)
      local y0=math.max(0,math.ceil((m.y+panel.y*m.sy)*r.dpiY)+4)
      local x1=math.min(off:getWidth()-1,math.floor((m.x+(panel.x+panel.w)*m.sx)*r.dpiX)-4)
      local y1=math.min(off:getHeight()-1,math.floor((m.y+(panel.y+panel.h)*m.sy)*r.dpiY)-4)
      local uiChanged,uiPixels=0,0
      for y=y0,y1 do for x=x0,x1 do
        local a,b,c,d=off:getPixel(x,y);local e,f,gg,h=strong:getPixel(x,y)
        if a~=e or b~=f or c~=gg or d~=h then uiChanged=uiChanged+1 end
        uiPixels=uiPixels+1
      end end
      check(uiPixels>100 and uiChanged==0,tag..' native command panel/font remains pixel-exact')
      report.cases[#report.cases+1]={tag=tag,depth=stats,actorPixels=actorPixels,
        actorChanged=changed,uiPixels=uiPixels,uiChanged=uiChanged}
      -- Intro close-up depth uses the live camera, not a stale world camera.
      if shape[3]==0 then
        Game.save.options.jpBattleIntro='focus';Pipelines.setLevel('tiltshift',3);chosen=3
        battle.phase='messages';battle.showPlayerBack=true
        Intro.begin(arena,battle);Intro.shown(arena)
        local values={}
        for _,t in ipairs({0,.65,1.2})do
          arena.focusIntro.time=t;render()
          local value=differences(capture)
          values[#values+1]=value
          check(capture.applied and capture.mode=='depth',tag..' closeup time'..t..' retains actual depth blur')
          check(value.nearChanged==0,tag..' closeup time'..t..' keeps nearby floor sharp')
        end
        report.cases[#report.cases].intro=values
        Game.save.options.jpBattleIntro='original'
      end
    end
    write('scene-results.json',assert(Json.encode(report)))
    check(#Game.mods.errors==0,'actual battle blur path produces no MOD runtime errors')
  end,debug.traceback)
  Blur.battleBackground=originalBlur;AA.setting.index=oldAA
  Host.finish('blur-finished');Blend.cancel()
  if not ok then error(err,0)end
end
