-- Actual OpenGL raster comparison for the OAM ball tearing regression.
-- Handwritten four-tile ball/poof only; no ROM or extracted graphics.
return function()
  local root=assert(os.getenv('JP_QA_ROOT'))
  local output=assert(os.getenv('JP_QA_OUT'))
  local g,fs=love.graphics,love.filesystem
  local Anim=require('src.battle.AnimPlayer')
  local P=require('src.battle.BattlePresentation')
  local previous=assert(loadfile(root..'/../source-jp20/src/battle/AnimPlayer.lua'))()
  local checks=0
  local function check(ok,msg)assert(ok,msg);checks=checks+1 end
  local function write(name,bytes)local f=assert(io.open(output..'/'..name,'wb'));f:write(bytes);f:close()end
  g.setDefaultFilter('nearest','nearest')
  local art=love.image.newImageData(16,16)
  for y=0,15 do for x=0,15 do
    local dx,dy=x-7.5,y-7.5
    if dx*dx+dy*dy<58 then
      local shade=(dx*dx+dy*dy>39 or y==7 or y==8) and 0 or y<7 and 1/3 or 1
      art:setPixel(x,y,shade,shade,shade,1)
    end
  end end
  fs.write('ball-fixture.png',art:encode('png'))
  local data={tilesheets={[0]={path='ball-fixture.png',width=16,height=16,tiles=4}},
    moveAnims={},subanims={},baseCoords={},frameBlocks={BALL={
      {x=0,y=0,tile=0},{x=8,y=0,tile=1},{x=0,y=8,tile=2},{x=8,y=8,tile=3}}}}
  local path={{24,96},{32,80},{40,64},{48,48},{64,36},{80,32},{96,36},{112,44},{124,64},
    {123,65},{122,64},{123,64},{124,64}}
  local sub={type='HVFLIP',blocks={}}
  for i,p in ipairs(path)do
    data.baseCoords[i]={x=p[1],y=p[2]}
    sub.blocks[#sub.blocks+1]={block='BALL',coord=i,mode=4}
  end
  data.subanims.BALL=sub
  for _,name in ipairs({'TOSS_ANIM','GREATTOSS_ANIM','ULTRATOSS_ANIM','SHAKE_ANIM','POOF_ANIM'})do
    data.moveAnims[name]={seq={{subanim='BALL',tileset=0,delay=2}}}
  end
  local palettes={{ {1,1,1},{.5,.5,.5},{0,0,0} },{ {1,.6,.1},{.4,.1,.5},{.1,.1,.4} }}
  local function colorFn(s,x,y)
    local a=palettes[(x>=80 or y>=56) and 2 or 1]
    if s.obp=='f0x' then return {a[2],a[1],a[3]}end
    return a
  end
  local canvas=g.newCanvas(256,224,{dpiscale=1})
  local function render(player,sprites,colors,project)
    g.push('all');g.setCanvas(canvas);g.clear(0,0,0,0);g.origin()
    g.setColor(1,1,1,1);g.setBlendMode('alpha');g.setShader()
    player:drawSprites(sprites,colors,project)
    g.pop()
    return canvas:newImageData()
  end
  local function bounds(img)
    local x0,y0,x1,y1=999,999,-1,-1
    for y=0,223 do for x=0,255 do
      local _,_,_,a=img:getPixel(x,y)
      if a>.01 then x0=math.min(x0,x);y0=math.min(y0,y);x1=math.max(x1,x);y1=math.max(y1,y)end
    end end
    return {x0,y0,x1-x0+1,y1-y0+1}
  end
  local function sameShape(a,b,aa,bb)
    if aa[3]~=bb[3] or aa[4]~=bb[4]then return false end
    for y=0,aa[4]-1 do for x=0,aa[3]-1 do
      local p={a:getPixel(aa[1]+x,aa[2]+y)}
      local q={b:getPixel(bb[1]+x,bb[2]+y)}
      for i=1,4 do if math.abs(p[i]-q[i])>1/255 then return false end end
    end end
    return true
  end
  local report={checks=0,cases=0,baselineTornCases=0,renderer=love.graphics.getRendererInfo(),
    physicalAndroid=false,assets='authored four-tile ball; no ROM',animations={}}
  for _,layout in ipairs({{128,72},{152,72},{176,72},{112,56},{128,56},{144,56}})do
    local metrics={actor={player={x=42,y=layout[1]},enemy={x=124,y=layout[2]}},native={x=0,y=0}}
    local function project(x,y)return P.effectPoint(metrics,x,y)end
    for _,name in ipairs({'TOSS_ANIM','GREATTOSS_ANIM','ULTRATOSS_ANIM','SHAKE_ANIM','POOF_ANIM'})do
      for _,side in ipairs({true,false})do
        local options={ball=name=='ULTRATOSS_ANIM' and 'ULTRA_BALL' or 'POKE_BALL'}
        if name=='SHAKE_ANIM'then options.shakes=3 end
        local current,old=Anim.new(data),previous.new(data)
        current:start(name,side,options);old:start(name,side,options)
        check(#current.steps==#old.steps,name..' preserves native step count')
        for i,step in ipairs(current.steps)do
          check(step.dur==old.steps[i].dur,name..' preserves native step duration')
          if #step.sprites>0 then
            for _,palette in ipairs({false,true})do
              local colors=palette and colorFn or nil
              local native=render(current,step.sprites,colors)
              local before=render(old,old.steps[i].sprites,colors)
              check(native:getString()==before:getString(),'unprojected OAM rendering remains byte-identical')
              local drawn=render(current,step.sprites,colors,project)
              local n,d=bounds(native),bounds(drawn)
              check(sameShape(native,drawn,n,d),name..' preserves complete multi-tile art and palette slices')
              local torn=render(old,old.steps[i].sprites,colors,project)
              if not sameShape(native,torn,n,bounds(torn))then report.baselineTornCases=report.baselineTornCases+1 end
              report.cases=report.cases+1
              if layout[1]==152 and name=='TOSS_ANIM' and side and not palette and i==7 then
                write('ball-before.png',torn:encode('png'):getString())
                write('ball-after.png',drawn:encode('png'):getString())
              end
            end
          end
        end
        local locked=current:finalSprites()
        check(locked and #locked==4,'caught ball keeps all four native OAM tiles')
        check(locked[1].projectionAnchor==locked[4].projectionAnchor,'locked ball preserves shared artwork origin')
        local a=render(current,locked,colorFn)
        local b=render(current,locked,colorFn,project)
        check(sameShape(a,b,bounds(a),bounds(b)),'resting captured ball remains unbroken')
        current:release();old:release()
      end
      report.animations[name]=true
    end
  end
  check(report.baselineTornCases>0,'comparison reproduces actual jp20 OAM tearing')
  -- Distinct mode-3 blocks are distinct pieces: they must not all teleport
  -- to the newest point, and their shared local origins survive OAM trails.
  for _,entry in ipairs(sub.blocks)do entry.mode=3 end
  local trail=Anim.new(data);trail:start('TOSS_ANIM',true)
  local last=trail:finalSprites()
  check(#last==#path*4,'persistent subanimation keeps every block')
  check(last[1].projectionAnchor~=last[5].projectionAnchor,'persistent objects have separate trajectory origins')
  check(last[1].x~=last[5].x,'native trail OAM positions preserved')
  trail:release()
  report.checks=checks
  write('results.json',assert(require('src.link.Json').encode(report)))
  print(checks..' ball raster checks passed; '..report.cases..' full block renders; jp20 torn '..report.baselineTornCases)
end
