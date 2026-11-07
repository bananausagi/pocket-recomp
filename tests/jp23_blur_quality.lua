-- Synthetic sharp pixel terrain and slanted edges; no retail artwork.
return function(T,V,check,write)
  local g=love.graphics
  local report={cases={},romUsed=false,physicalAndroid=false}
  local root=assert(os.getenv('JP_QA_ROOT'))
  local previousPath=os.getenv('JP_QA_BLUR_JP22')
  local previous=previousPath and assert(loadfile(previousPath))(V)
  local Game=require('src.core.Game')
  local function pixels(canvas)
    g.push('all');g.setCanvas();local data=canvas:newImageData();g.pop();return data
  end
  local function sameRect(a,b,x,y,w,h)
    for py=y,y+h-1 do for px=x,x+w-1 do
      local aa,ab,ac,ad=a:getPixel(px,py);local ba,bb,bc,bd=b:getPixel(px,py)
      if aa~=ba or ab~=bb or ac~=bc or ad~=bd then return false end
    end end
    return true
  end
  local function gradientRoughness(data,y,cx,span)
    local gradient={}
    for x=cx-span,cx+span do
      gradient[#gradient+1]=data:getPixel(x+1,y)-data:getPixel(x,y)
    end
    local rough,maxSlope=0,0
    for i=2,#gradient do rough=rough+math.abs(gradient[i]-gradient[i-1]);maxSlope=math.max(maxSlope,gradient[i])end
    return rough, maxSlope
  end
  local function shaderScene(canvas,kind)
    local sh=g.newShader([[
      uniform float kind; uniform vec2 extent;
      vec4 effect(vec4 c,Image image,vec2 uv,vec2 sc){
        if(kind<.5){
          float p=mod(floor(sc.x/3.0)+floor(sc.y/3.0),2.0);
          float t=mod(floor((sc.x+sc.y*.73)/12.0),2.0);
          if(sc.x/extent.x<.33)return vec4(vec3(p),1.0);
          if(sc.x/extent.x<.66)return vec4(.14+.62*t,.24+.40*t,.17+.46*t,1.0);
          return vec4(step(.55,fract((sc.x+sc.y*.37)/68.0))*.75+.12,.2,.28,1.0);
        }
        if(kind<1.5)return vec4(vec3(step(.5,sc.x/extent.x)),1.0);
        if(kind<2.5)return vec4(.24,.45,.66,1.0);
        if(kind<3.5)return vec4(vec3(1.0-step(1.5,abs(sc.x-extent.x*.5))),1.0);
        return vec4(vec3(1.0-step(2.0,length(sc-vec2(extent.x*.5,extent.y*.07)))),1.0);
      }
    ]])
    g.push('all');g.setCanvas(canvas);g.origin();g.setScissor();g.setDepthMode();g.setShader(sh)
    g.setBlendMode('replace');g.setColor(1,1,1,1);sh:send('kind',kind);sh:send('extent',{canvas:getDimensions()})
    g.rectangle('fill',0,0,canvas:getDimensions());g.pop();sh:release()
  end
  for _,shape in ipairs({{960,640},{377,251},{972,1536}})do
    local w,h=shape[1],shape[2]
    local canvas=g.newCanvas(w,h,{dpiscale=1});canvas:setFilter('nearest','nearest')
    local base,field,battle,case
    case={width=w,height=h,levels={}}
    shaderScene(canvas,0);base=pixels(canvas)
    for level=0,5 do
      T.setLevel(level)
      local draws,fetchPixels,linearSamples=0,0,true
      local rawDraw=g.draw
      g.draw=function(image,...)
        draws=draws+1
        local target=g.getCanvas()
        if target then
          local tw,th=target:getDimensions()
          local iw,ih=image:getDimensions()
          if iw<tw or ih<th then linearSamples=linearSamples and image:getFilter()=='linear'end
          -- Bound estimated texture reads by actual target and shader stages.
          fetchPixels=fetchPixels+tw*th*(draws==1 and 4 or (draws<=3 and 9 or 2))
        end
        return rawDraw(image,...)
      end
      local result=T.apply(canvas);g.draw=rawDraw
      field=pixels(result)
      check((level==0 and draws==0)or(draws>=4 and draws<=7),w..'x'..h..' level'..level..' bounded blur passes')
      check(linearSamples,w..'x'..h..' level'..level..' coarse blur always magnified with linear interpolation')
      check(sameRect(base,field,0,math.ceil(h*.25),w,math.floor(h*.5)),w..'x'..h..' level'..level..' field focus retains source pixels')
      write('quality-field-'..w..'x'..h..'-level'..level..'.png',field:encode('png'):getString())
      shaderScene(canvas,0)
      local applied=T.battleBackground(canvas,nil,{focus=100,amount=1})
      battle=pixels(canvas)
      check(applied==(level>0),w..'x'..h..' battle follows same level'..level)
      if level==0 then check(base:getString()==battle:getString(),w..'x'..h..' shared OFF exact')end
      check(sameRect(base,battle,0,math.ceil(h*.5),w,math.floor(h*.5)),w..'x'..h..' level'..level..' fallback focus remains sharp')
      write('quality-battle-'..w..'x'..h..'-level'..level..'.png',battle:encode('png'):getString())
      case.levels[#case.levels+1]={level=level,worldDraws=draws,linearUpsample=linearSamples}
      shaderScene(canvas,0)
    end
    -- A flat patch may soften spatially but must never gain saturation.
    shaderScene(canvas,2);local flat=pixels(canvas)
    T.setLevel(5);local softened=pixels(T.apply(canvas))
    local a,b,c=flat:getPixel(0,0);local d,e,f=softened:getPixel(0,0)
    check(math.abs(a-d)<=1/255 and math.abs(b-e)<=1/255 and math.abs(c-f)<=1/255,w..'x'..h..' blur leaves uniform colour neutral')
    -- A vertical step exposes sparse-tap echo bands without hiding them in
    -- high-frequency tile art. Measure actual gradients, not shader text.
    shaderScene(canvas,1);local smooth=pixels(T.apply(canvas))
    local rough,slope=gradientRoughness(smooth,0,math.floor(w*.5),math.ceil(h*.11))
    case.edge={roughness=rough,maxSlope=slope}
    write('quality-step-'..w..'x'..h..'-new.png',smooth:encode('png'):getString())
    if previous then
      previous.setLevel(5);Game.save.options.jpBattleBlur='strong'
      local old=pixels(previous.apply(canvas))
      local oldRough,oldSlope=gradientRoughness(old,0,math.floor(w*.5),math.ceil(h*.11))
      case.edge.previous={roughness=oldRough,maxSlope=oldSlope}
      write('quality-step-'..w..'x'..h..'-jp22.png',old:encode('png'):getString())
      if h>=600 then check(rough<oldRough*.7,w..'x'..h..' continuous kernel removes coarse step/echo bands vs jp22')end
    end
    if w==960 then
      for _,probe in ipairs({{3,'line'},{4,'point'}})do
        shaderScene(canvas,probe[1]);T.battleBackground(canvas,nil,{focus=100})
        write('quality-'..probe[2]..'-new.png',pixels(canvas):encode('png'):getString())
        if previous then
          shaderScene(canvas,probe[1]);previous.battleBackground(canvas,nil,{focus=100})
          write('quality-'..probe[2]..'-jp22.png',pixels(canvas):encode('png'):getString())
        end
      end
    end
    report.cases[#report.cases+1]=case
    canvas:release()
  end
  -- Both draw paths read settings even when pipeline update is paused;
  -- there is no default strong battle mode or legacy-value override.
  local saved=package.loaded['src.render.Pipelines']
  local level=0
  package.loaded['src.render.Pipelines']={get=function(id)return id=='tiltshift' and {}end,level=function()return level end}
  local canvas=g.newCanvas(320,240,{dpiscale=1});shaderScene(canvas,0)
  local original=pixels(canvas):getString();T.setLevel(5)
  Game.save.options.jpBattleBlur='strong'
  check(T.apply(canvas)==canvas and not T.battleBackground(canvas,nil,{focus=100}), 'live field OFF overrides stale renderer level5 and legacy strong')
  check(pixels(canvas):getString()==original,'live OFF changes no colour pixels')
  level=3;T.setLevel(0);Game.save.options.jpBattleBlur='off'
  check(T.apply(canvas)~=canvas and T.battleBackground(canvas,nil,{focus=100}), 'live field3 overrides stale renderer OFF and legacy off immediately')
  level=0
  check(T.apply(canvas)==canvas and not T.battleBackground(canvas,nil,{focus=100}),'return from live3 to live0 needs no frame update')
  package.loaded['src.render.Pipelines']=saved
  canvas:release()
  if previous then previous.invalidate()end
  return report
end
