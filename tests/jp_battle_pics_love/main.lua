-- Synthetic art only: test white interior versus exterior transparency, and
-- exercise the real MOD image readback while unrelated graphics state is set.
local function run()
  local root=assert(os.getenv("JP_BATTLE_PICS_ROOT"))
  local output=assert(os.getenv("JP_BATTLE_PICS_OUT"))
  package.path=root.."/?.lua;"..package.path
  local g=love.graphics
  local Json=require("src.link.Json")
  local checks,results=0,{}
  local function check(ok,message)
    assert(ok,message);checks=checks+1;print("PASS "..message)
  end
  local function write(name,bytes)
    local f=assert(io.open(output.."/"..name,"wb"));f:write(bytes);f:close()
  end
  local function fixture()
    local data=love.image.newImageData(16,16)
    data:mapPixel(function()return 1,1,1,0 end)
    for x=4,11 do data:setPixel(x,3,0,0,0,1);data:setPixel(x,13,0,0,0,1) end
    for y=3,13 do data:setPixel(4,y,0,0,0,1);data:setPixel(11,y,0,0,0,1) end
    data:setPixel(5,4,1,1,1,1)
    return data
  end
  local function read(image)
    g.push("all");g.origin();g.setShader();g.setScissor();g.setStencilTest();g.setDepthMode()
    local c=g.newCanvas(16,16,{dpiscale=1})
    g.setCanvas(c);g.clear(0,0,0,0);g.setColor(1,1,1,1)
    g.setBlendMode("replace","premultiplied");g.draw(image)
    g.setCanvas();local data=c:newImageData();c:release();g.pop()
    return data
  end
  local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a)do if not same(v,b[k])then return false end end
    for k in pairs(b)do if a[k]==nil then return false end end
    return true
  end
  local function snapshot()
    return {canvas={g.getCanvas()},shader=g.getShader(),color={g.getColor()},
      blend={g.getBlendMode()},scissor={g.getScissor()},stencil={g.getStencilTest()},
      depth={g.getDepthMode()},origin={g.transformPoint(0,0)},point={g.transformPoint(3,7)}}
  end
  local shader=g.newShader("vec4 effect(vec4 c,Image t,vec2 p,vec2 s){return vec4(0.,0.,0.,0.);}")
  local target=g.newCanvas(48,48,{dpiscale=1})
  local cases={
    {name="clean",set=function()end},
    {name="shader",set=function()g.setShader(shader)end},
    {name="transform",set=function()g.translate(9,7);g.scale(2,3)end},
    {name="scissor",set=function()g.setScissor(0,0,2,2)end},
    {name="stencil",set=function()g.setStencilTest("equal",1)end},
    {name="depth",set=function()g.setDepthMode("greater",true)end},
    {name="all",set=function()
      g.setShader(shader);g.translate(9,7);g.scale(2,3);g.setScissor(0,0,2,2)
      g.setStencilTest("equal",1);g.setDepthMode("greater",true)
      g.setColor(.2,.4,.6,.3);g.setBlendMode("add","premultiplied")
    end},
  }
  local function module(path,...)return assert(loadfile(path))(... )end
  local function exercise(label,pics,requireSuccess)
    local out={}
    local reference
    for _,case in ipairs(cases)do
      pics.invalidate();g.reset();g.setDefaultFilter("nearest","nearest")
      local input=g.newImage(fixture())
      g.setCanvas({target,stencil=true,depth=true});g.clear(0,0,0,0,0,0)
      case.set();local before=snapshot()
      local ok,image=pcall(pics.filled,input,false)
      local restored=same(before,snapshot())
      g.reset()
      local pixels=ok and read(image) or nil
      local inside
      if pixels then local r,green,b; r,green,b,inside=pixels:getPixel(8,8) end
      local matches=reference and pixels and pixels:getString()==reference or case.name=="clean"
      if case.name=="clean" and pixels then reference=pixels:getString() end
      local success=ok and inside==1 and restored and matches
      out[#out+1]={case=case.name,passed=success,returned=ok,interior_alpha=inside,
        graphics_state_restored=restored,identical_to_clean=matches}
      if requireSuccess then check(success,label.." "..case.name.." fill and state restoration") end
      if pixels then write(label.."-"..case.name..".png",pixels:encode("png"):getString())end
      input:release();if pixels then pixels:release()end
    end
    return out
  end
  local before=assert(os.getenv("JP_BATTLE_PICS_BEFORE"))
  results.before=exercise("before",module(before),false)
  local failed=0
  for _,r in ipairs(results.before)do if not r.passed then failed=failed+1 end end
  check(failed>0,"original readback fails with inherited graphics state")
  local pics=module(root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/BattlePics.lua")
  results.after=exercise("after",pics,true)
  -- An unsuccessful first capture must remain retryable for the same image.
  pics.invalidate();g.reset();local input=g.newImage(fixture())
  g.setCanvas(target);g.translate(3,4);g.setScissor(1,2,3,4);g.setShader(shader)
  local failureState=snapshot()
  local original=g.newCanvas
  g.newCanvas=function()error("injected transient allocation failure")end
  local ok,first=pcall(pics.filled,input,false)
  g.newCanvas=original
  check(ok and first==input,"readback failure returns original image")
  check(same(failureState,snapshot()),"readback failure restores all inherited graphics state")
  g.reset()
  local second=pics.filled(input,false);local pixels=read(second)
  local _,_,_,a=pixels:getPixel(8,8)
  check(a==1,"same image is retried after a transient readback failure")
  check(pics.filled(input,false)==second,"successful fill reuses cached image")
  -- Engine repair occurs on the uncolored cartridge-derived pic. It preserves
  -- external alpha and existing ink, and does not turn all white into a box.
  local Matte=require("src.render.BattleSpriteMatte")
  local data=fixture()
  check(Matte.restoreInterior(data)==true,"engine restores an enclosed white body")
  local r,green,b,alpha=data:getPixel(8,8)
  check(r==1 and green==1 and b==1 and alpha==1,"engine restores exact shade zero before palette")
  _,_,_,a=data:getPixel(0,0);check(a==0,"engine leaves exterior transparent")
  r,green,b,a=data:getPixel(4,8);check(r==0 and green==0 and b==0 and a==1,"engine preserves original outline")
  check(Matte.restoreInterior(data)==false,"engine restoration is idempotent")
  local open=fixture();open:setPixel(4,8,1,1,1,0)
  Matte.restoreInterior(open);_,_,_,a=open:getPixel(8,8)
  check(a==0,"engine does not fill an exterior-connected opening")
  -- Capture-side isolation precedes BattlePics and must establish the same
  -- native coordinates even when the caller is drawing a transformed world.
  local savedState=package.loaded["src.battle.BattleState"]
  package.loaded["src.battle.BattleState"]={}
  local function providerCases(label,path,requireSuccess)
    local items,reference={},nil
    for _,case in ipairs(cases)do
      g.reset();local image=g.newImage(fixture())
      local captured,isolated
      local provider=module(path,{backSpritesSetting={get=function()return false end},require=function()return {}end})
      local battle={showEnemyTrainer=true,trainerPic=image,drawPicsLayer=function()
        captured=g.getCanvas()
        local x,y=g.transformPoint(3,7)
        local sc=g.getScissor();local st=g.getStencilTest()
        local depth,writeDepth=g.getDepthMode()
        isolated=x==3 and y==7 and not sc and (not st or st=="always") and not g.getShader()
          and (depth=="always" or depth==nil) and not writeDepth
        g.draw(image)
      end}
      g.setCanvas({target,stencil=true,depth=true});g.clear(0,0,0,0,0,0)
      case.set();local beforeState=snapshot()
      local ok=pcall(provider.update,provider,{battle=battle,services={}})
      local restored=same(beforeState,snapshot())
      g.reset()
      local pixels=captured and captured:newImageData()
      if case.name=="clean" and pixels then reference=pixels:getString()end
      local equal=pixels and pixels:getString()==reference or false
      local success=ok and isolated and restored and equal
      items[#items+1]={case=case.name,passed=success,isolated=isolated,
        returned=ok,graphics_state_restored=restored,identical_to_clean=equal}
      if requireSuccess and not success then print(Json.encode(items[#items]))end
      if requireSuccess then check(success,label.." "..case.name.." capture in native coordinates")end
      if pixels then write(label.."-"..case.name..".png",pixels:encode("png"):getString())end
    end
    g.reset()
    local provider=module(path,{require=function()return {}end})
    local image=g.newImage(fixture())
    local context={battle={showEnemyTrainer=true,trainerPic=image,drawPicsLayer=function()end},services={
      withNativeBattlePics=function()g.translate(11,2);g.setShader();error("injected service exception")end}}
    g.setCanvas(target);g.translate(2,3);g.setShader(shader)
    local prior=snapshot();local ok=pcall(provider.update,provider,context)
    local restored=same(prior,snapshot());g.reset()
    items[#items+1]={case="service_exception",passed=ok and restored,returned=ok,graphics_state_restored=restored}
    if requireSuccess then check(ok and restored,label.." native service exception restores graphics state")end
    return items
  end
  results.provider_before=providerCases("provider-before",before:gsub("BattlePics.lua$","VoxelBattleCardProvider.lua"),false)
  results.provider_after=providerCases("provider-after",root.."/vendor/jp-mods/DRAMALESS_SHAPE/lib/VoxelBattleCardProvider.lua",true)
  package.loaded["src.battle.BattleState"]=savedState
  results.checks=checks;results.original_failures=failed
  write("results.json",Json.encode(results));print(checks.." BATTLE WHITE CHECKS PASSED")
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
