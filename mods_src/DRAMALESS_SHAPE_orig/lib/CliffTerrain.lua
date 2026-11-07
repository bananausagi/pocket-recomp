-- Road-hop metadata is a local classification only; authored profile heights
-- own the original block geometry. There is
-- no elevation field, neighbour-map traversal, slope or height solver.
-- The engine still owns the original jump/collision/event rules.
local V=...
local Budget=V.require('BuildBudget')
local Terrain={RISE=0}
local cache={}
local DIR={down={0,1},left={-1,0},right={1,0}}
local function key(x,y)return (y+64)*4096+x+64 end
local function rulesFromGame()
  local ok,Game=pcall(require,'src.core.Game')
  return ok and Game.data and Game.data.field and Game.data.field.ledges or {}
end
function Terrain.isLedgeCell(map,x,y,rules)
  if not map or not map:inBounds(x,y) then return false end
  local tile=map:cellTile(x,y)
  for _,r in ipairs(rules or rulesFromGame())do
    local d=DIR[r.input]
    if d and r.facing==r.input and (r.tileset or 'OVERWORLD')==map.def.tileset and tile==r.ledgeTile then
      local sx,sy=x-d[1],y-d[2]
      if map:inBounds(sx,sy) and map:cellTile(sx,sy)==r.standingTile then return true end
    end
  end
  return false
end
function Terrain.build(map,S,ledges)
  local managed,seeds={},0
  for y=0,map.heightCells-1 do for x=0,map.widthCells-1 do
    Budget.tick()
    if Terrain.isLedgeCell(map,x,y,ledges or {})then
      seeds=seeds+1
      for dy=0,1 do for dx=0,1 do managed[key(x*2+dx,y*2+dy)]=true end end
    end
  end end
  local result=seeds>0 and {managed=managed,seeds=seeds,
    stats={cells=map.widthCells*map.heightCells,seeds=seeds,iterations=0}} or nil
  cache[map.id]=result
  return result
end
function Terrain.forMap(map)return map and cache[map.id]end
-- Keep the existing numeric API for battle/third-party consumers.
function Terrain.height()return 0 end
function Terrain.liftFoliage()end
function Terrain.invalidate(id)if id then cache[id]=nil else cache={}end end
return Terrain
