local function run()
  local root,out=assert(os.getenv('JP_EFFECT_ROOT')),assert(os.getenv('JP_EFFECT_OUT'))
  package.path=root..'/?.lua;'..package.path
  local T=require('tests.harness').suite('jp36 real GLES glow isolation and fallback')
  local info=require('tests.gles_context')(T.check)
  local g=love.graphics
  local game={data={constants={language='ja'}},save={options={jpAtmosphere='off'}}}
  package.loaded['src.core.Game']=game
  local modules,V={},{}
  function V.require(n)
    if not modules[n]then modules[n]=assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/'..n..'.lua'))(V)end
    return modules[n]
  end
  local glow=V.require('SceneGlow')
  local function write(n,bytes)local f=assert(io.open(out..'/'..n,'wb'));f:write(bytes);f:close()end
  local results={}
  for _,size in ipairs({{800,480},{480,800}})do
    local w,h=unpack(size)
    local c=g.newCanvas(w,h,{dpiscale=1})
    local function scene()
      g.setCanvas(c);g.origin();g.setShader();g.setBlendMode('replace','premultiplied')
      g.clear(.10,.14,.18,1);g.setColor(.85,.90,.55,1)
      g.rectangle('fill',w*.28,h*.28,w*.30,h*.30)
      g.setColor(1,.9,.65,1);g.rectangle('fill',w*.46,h*.16,w*.025,h*.4)
      g.setCanvas();g.setColor(1,1,1,1)
      return c:newImageData():getString()
    end
    local before=scene();local allocations=glow.stats.allocations
    T.eq(glow.apply(c),false,'OFF skips glow')
    T.eq(c:newImageData():getString(),before,'OFF is pixel-identical')
    T.eq(glow.stats.allocations,allocations,'OFF creates no GPU resources')
    local samples={}
    for _,mode in ipairs({'gentle','soft'})do
      scene();game.save.options.jpAtmosphere=mode
      T.check(glow.apply(c),'actual driver renders '..mode..': '..tostring(glow.error))
      T.eq(g.getCanvas(),nil,'glow restores canvas binding')
      local min,mag=c:getFilter();T.eq(min,'linear','source filter is restored')
      local data=c:newImageData()
      local x,y=math.floor(w*.28)-2,math.floor(h*.40)
      local red,green,blue,alpha=data:getPixel(x,y)
      samples[mode]=red+green+blue
      T.eq(alpha,1,'scenery alpha preserved')
      T.check(data:getString()~=before,'glow changes scenery highlights')
      -- Mimic the production battle order: scenery, glow, actor/HUD.
      g.setCanvas(c);g.setShader();g.setBlendMode('replace','premultiplied')
      g.setColor(.2,.4,.6,1);g.rectangle('fill',w*.4,h*.4,32,40)
      g.setColor(.8,.2,.1,1);g.rectangle('fill',0,h-48,w,48)
      g.setCanvas();g.setColor(1,1,1,1)
      local shown=c:newImageData()
      local r,gg,b=shown:getPixel(math.floor(w*.4)+5,math.floor(h*.4)+5)
      T.check(math.abs(r-.2)<.005 and math.abs(gg-.4)<.005 and math.abs(b-.6)<.005,'actor stays crisp after glow')
      r,gg,b=shown:getPixel(5,h-5)
      T.check(math.abs(r-.8)<.005 and math.abs(gg-.2)<.005 and math.abs(b-.1)<.005,'HUD colours stay untouched')
      write(w..'x'..h..'-'..mode..'.png',shown:encode('png'):getString())
    end
    T.check(samples.soft>samples.gentle+.025,'HD-2D visibly exceeds gentle halo')
    local warm=glow.stats.allocations
    for _=1,20 do scene();glow.apply(c)end
    T.eq(glow.stats.allocations,warm,'warmed frames allocate no GPU objects')
    game.save.options.jpAtmosphere='off';scene()
    T.eq(glow.apply(c),false,'switching OFF is immediate')
    T.eq(c:newImageData():getString(),before,'switching OFF restores native image')
    results[#results+1]={width=w,height=h,halo=samples};c:release()
  end
  -- Compile errors must never suppress the otherwise healthy 3D renderer.
  game.save.options.jpAtmosphere='soft'
  local c=g.newCanvas(64,64);g.setCanvas(c);g.clear(.2,.3,.4,1);g.setCanvas()
  local original=c:newImageData():getString()
  local fallback=assert(loadfile(root..'/vendor/jp-mods/DRAMALESS_SHAPE/lib/SceneGlow.lua'))(V)
  local make=g.newShader;g.newShader=function()error('injected unsupported driver')end
  T.eq(fallback.apply(c),false,'shader failure degrades only glow')
  g.newShader=make
  T.eq(c:newImageData():getString(),original,'shader fallback preserves exact scene')
  T.eq(fallback.lastMode,'unavailable','fallback is observable')
  fallback:invalidate();glow.invalidate();c:release()
  write('results.json',require('src.link.Json').encode({renderer=info,checks=T.checks,
    failures=T.failures,cases=results,romUsed=false,androidDeviceUsed=false}))
  T.finish()
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err)end
  love.event.quit(ok and 0 or 1)
end
