local U=dofile(assert(os.getenv('JP_TEST_ROOT'))..'/tests/drivers/util.lua')
return function(game)
  local Naming=require('src.ui.NamingScreen')
  local function busy()
    local ow=game.overworld
    return game.stack:top()~=ow or (ow.runner and ow.runner:isRunning()) or #(ow.scriptMoves or {})>0 or ow.engaging or ow.emote~=nil
  end
  local function mash()
    if getmetatable(game.stack:top())==Naming then U.tap(game,'start') else U.tap(game,'a') end
    U.wait(8)
  end
  local dirs={{0,-1,'up'},{0,1,'down'},{-1,0,'left'},{1,0,'right'}}
  local function go(tx,ty)
    for tick=1,1800 do
      local ow=game.overworld;local p=ow.player;local map=ow.map
      if p.cellX==tx and p.cellY==ty and not p.moving then return end
      if busy() then mash()
      elseif not p.moving then
        local width,height=map.widthCells,map.heightCells
        local function id(x,y)return y*width+x end
        local blocks={}
        for _,n in ipairs(ow.npcs)do blocks[id(n.cellX,n.cellY)]=true end
        local start=id(p.cellX,p.cellY);local goal=id(tx,ty)
        local q,prev,head={start},{[start]=-1},1
        while q[head] do
          local v=q[head];head=head+1
          if v==goal then break end
          local x,y=v%width,math.floor(v/width)
          for _,d in ipairs(dirs)do
            local nx,ny=x+d[1],y+d[2];local ni=id(nx,ny)
            if nx>=0 and ny>=0 and nx<width and ny<height and not prev[ni]
              and not blocks[ni] and map:isWalkableCell(nx,ny)then
              prev[ni]=v;q[#q+1]=ni
            end
          end
        end
        if prev[goal] then
          local n=goal
          while prev[n]~=start do n=prev[n] end
          for _,d in ipairs(dirs)do
            if id(p.cellX+d[1],p.cellY+d[2])==n then U.tap(game,d[3]);break end
          end
        end
        U.wait(3)
      else U.wait(3) end
    end
    error('path timeout '..tx..','..ty..' in '..game.overworld.map.id)
  end
  game.save.player.name='レッド';game.save.rivalName='グリーン'
  U.teleport(game,'PALLET_TOWN',10,5,'up')
  go(10,1)
  for i=1,3000 do
    if game.overworld.map.id=='OAKS_LAB' and not busy() then break end
    mash()
  end
  assert(game.overworld.map.id=='OAKS_LAB','Oak escort failed')
  assert(game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB,'Oak escort event missing')
  print('JP STORY PASS: Oak escort')
  go(8,4);U.tap(game,'up');U.wait(15);U.tap(game,'a')
  for i=1,2000 do
    if #game.save.party>0 and not busy() then break end
    mash()
  end
  assert(#game.save.party==1,'starter not received')
  assert(game.save.flags.EVENT_GOT_STARTER,'starter event missing')
  print('JP STORY PASS: starter '..game.save.party[1].species)
  assert(U.shot(game,assert(os.getenv('SHOT_DIR'))..'/09-starter.png'))
  go(5,11)
  assert(not busy(),'first rival battle did not finish')
  print('JP STORY PASS: first rival battle finished')
  love.event.quit(0)
end
