return function(Game,V,check,write)
  local g=love.graphics
  local v3,Mat=V.require('Voxel3D'),V.require('Mat4')
  local board=V.require('BattleBillboard')
  local function image(fn)
    local d=love.image.newImageData(16,16)
    d:mapPixel(fn);local t=g.newImage(d);t:setFilter('nearest','nearest');d:release();return t
  end
  local red=image(function(x,y)
    if x<3 or x>12 or y<3 and (x<6 or x>9) then return 0,0,0,0 end
    return 1,.08,.03,1
  end)
  local green=image(function()return .10,.80,.15,1 end)
  local pose={eye={0,15,40},focus={0,7,0},fov=.65,curve=0}
  local model=Mat.mul(Mat.translate(0,0,0),Mat.scale(9,14,1))
  local tree=Mat.mul(Mat.translate(0,0,5),Mat.scale(24,24,1))
  local atmosphere=Game.save.options.jpAtmosphere;Game.save.options.jpAtmosphere='off'
  local dark=v3.SHADOW_ALPHA;v3.SHADOW_ALPHA=0
  local function draw(blocker,protect,pressure)
    g.push('all');v3.camera=pose;v3.tint={1,1,1}
    assert(v3.beginScene(400,260,0,0,40,26,{.04,.05,.06,1},'battle'))
    v3.seams(false);v3.glass(false)
    if protect then v3.battleCards({{texture=red,model=model,pull=board.PULL,floor=0}})end
    if blocker then
      v3.effects({wind={0,0,0,0},step={0,5,18,pressure or 0},stepFloor=0})
      v3.foliage(true,true);v3.battleDecoration(true)
      v3.draw(board.mesh(),green,tree,board.PULL+3)
      v3.foliage(false);v3.battleDecoration(false)
    end
    v3.battleCards()
    if protect~=nil then v3.draw(board.mesh(),red,model,board.PULL)end
    local canvas=v3.endScene();local pixels=canvas:newImageData()
    g.pop();v3.camera=nil
    return pixels
  end
  local reference=draw(false,false)
  local hidden=draw(true,false)
  local visible=draw(true,true)
  local actor,kept,covered,outside=0,0,0,0
  for y=0,259 do for x=0,399 do
    local r,a,b=reference:getPixel(x,y)
    local rr,gg,bb=visible:getPixel(x,y)
    if r>.45 and r>a*3 and r>b*3 then
      actor=actor+1
      if math.abs(rr-r)<.015 and math.abs(gg-a)<.015 and math.abs(bb-b)<.015 then kept=kept+1 end
      local hr,hg,hb=hidden:getPixel(x,y)
      if hg>hr*2 then covered=covered+1 end
    elseif gg>rr*2 and gg>bb*2 then outside=outside+1 end
  end end
  check(actor>1000,'visibility fixture has a substantial actor silhouette')
  check(covered>actor*.9,'control case: foreground grass actually hides the actor')
  check(kept>=actor*.98,'VASC exact alpha/depth mask keeps the actor visible')
  check(outside>10000,'grass and trees remain outside the actor silhouette')
  write('visibility.png',visible:encode('png'):getString())
  local standing=draw(true,nil,0)
  local stepped=draw(true,nil,1)
  local restored=draw(true,nil,0)
  check(standing:getString()~=stepped:getString(),'VASC grass bends under a foot')
  check(standing:getString()==restored:getString(),'zero foot pressure restores exact grass pixels')
  write('grass-stepped.png',stepped:encode('png'):getString())
  v3.SHADOW_ALPHA=dark;Game.save.options.jpAtmosphere=atmosphere
  red:release();green:release()
end
