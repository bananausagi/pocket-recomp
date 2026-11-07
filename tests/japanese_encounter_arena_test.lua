-- Encounter placement is pure presentation. Use marked synthetic maps, never a ROM.
local checks, authoredReads, foreignLoads = 0, 0, 0
local function check(value, label)
  assert(value, label); checks=checks+1; print('PASS '..label)
end
local V = {
  data=function() authoredReads=authoredReads+1; return {
    FIELD={map='OTHER_FLOOR', x=40,y=40}, REFUSED=false,
    LEGACY={x=4,y=4,shape='wide'},
  } end,
  require=function(name)
    if name=='BattleCam' then return {rig=function() return {eye={0,1000,0}} end} end
    if name=='VoxelScene' then return {groundAt=function()return 0 end} end
    error('unexpected dependency '..name)
  end,
}
package.loaded['src.core.Game']={data={}}
package.loaded['src.world.MapLoader']={load=function() foreignLoads=foreignLoads+1;error('foreign map requested') end}
local Arena=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/BattleArena.lua'))(V)
local function grid(w,h,fill,id)
  local m={widthCells=w,heightCells=h,id=id or 'FIELD',tiles={},queries=0}
  function m:inBounds(x,y)return x>=0 and y>=0 and x<w and y<h end
  function m:tile(x,y)return self.tiles[x..','..y] or fill or '.' end
  function m:isWalkableCell(x,y)self.queries=self.queries+1;local t=self:tile(x,y);return t=='.' or t=='g' or t=='W' end
  function m:isGrassCell(x,y)return self:tile(x,y)=='g' end
  function m:isWaterCell(x,y)return self:tile(x,y)=='~' end
  function m:warpAtCell(x,y)return self:tile(x,y)=='W' end
  function m:isWarpTileCell(x,y)return self:tile(x,y)=='D' end
  function m:set(x,y,value)self.tiles[x..','..y]=value end
  return m
end
local function validate(map,a,x,y,surf,blocked)
  check(a~=nil,'local encounter arena exists')
  check(a.map==map,'exact same map object retained')
  check(a.encounter==true and a.shape=='encounter','continuous presentation is explicitly tagged')
  check(a.origin.cellX==x and a.origin.cellY==y and a.origin.mapId==map.id,'encounter identity retained')
  check(a.origin.x==x*16+8 and a.origin.z==y*16+8,'origin uses the actual encounter cell center')
  check(a.mid[1]==(a.player[1]+a.enemy[1])/2 and a.mid[2]==(a.player[2]+a.enemy[2])/2,'camera target is the actor pair midpoint')
  check((a.playerCell[1]-x)^2+(a.playerCell[2]-y)^2<=4,'player staging stays within two cells')
  for _,key in ipairs({'player','enemy'})do
    local c=a[key..'Cell'];local p=a[key]
    check(p[1]==c[1]*16+8 and p[2]==c[2]*16+8,'actor mark is attached to its ground cell')
    check(map:inBounds(c[1],c[2]),'actor remains within current map')
    check(not map:warpAtCell(c[1],c[2]) and not map:isWarpTileCell(c[1],c[2]),'actor avoids door and warp')
    check(not blocked or not blocked(c[1],c[2]),'actor avoids occupied cells')
    check((surf and map:isWaterCell(c[1],c[2])) or (not map:isWaterCell(c[1],c[2]) and map:isWalkableCell(c[1],c[2])),'actor stands on valid terrain for travel mode')
  end
end
local function find(map,x,y,surf,opts)
  opts=opts or {};opts.encounter=true
  return Arena.find(map,x,y,surf,opts)
end
local field=grid(1000,1000,'g')
local a=find(field,700,700,false)
validate(field,a,700,700,false)
check(a.playerCell[1]==700 and a.playerCell[2]==700,'grass battle begins exactly underfoot')
check(a.enemyCell[1]==700 and a.enemyCell[2]==697,'open field preserves forward three-cell staging')
check(field.queries<200,'large map search uses bounded local probes')
check(authoredReads==0 and foreignLoads==0,'encounter path never loads authored or foreign-map data')
Arena.setOverride('FIELD',{map='OTHER_FLOOR',x=1,y=1})
a=find(field,810,230,false)
validate(field,a,810,230,false)
check(a.playerCell[1]==810 and a.playerCell[2]==230,'another encounter follows the new world position')
check(authoredReads==0 and foreignLoads==0,'manual authored stage does not move a JP encounter')
local refused=grid(12,12,'g','REFUSED')
validate(refused,find(refused,6,6,false),6,6,false)
for _,case in ipairs({{'up',0,-3},{'right',3,0},{'down',0,3},{'left',-3,0}})do
  local m=grid(14,14,'.');a=find(m,7,7,false,{facing=case[1]})
  check(a.playerCell[1]==7 and a.playerCell[2]==7,'facing never displaces the origin')
  check(a.enemyCell[1]==7+case[2] and a.enemyCell[2]==7+case[3],'opponent respects encounter facing '..case[1])
end
local room=grid(5,5,'#')
room:set(2,2,'.');room:set(3,2,'.')
a=find(room,2,2,false)
validate(room,a,2,2,false)
check(a.playerCell[1]==2 and a.playerCell[2]==2,'small room keeps player underfoot')
check(a.enemyCell[1]==3 and a.enemyCell[2]==2,'small room uses its available one-cell gap')
local corridor=grid(20,5,'#')
for x=0,19 do corridor:set(x,2,'.') end
validate(corridor,find(corridor,10,2,false),10,2,false)
local corner=grid(9,9,'#');corner:set(4,4,'.');corner:set(5,5,'.')
check(find(corner,4,4,false)==nil,'diagonal actors cannot cross two solid corners')
local single=grid(20,20,'#');single:set(10,10,'.')
check(find(single,10,10,false)==nil,'no local pair declines without inventing terrain')
local door=grid(20,20,'#');door:set(10,10,'W');door:set(10,9,'.');door:set(10,8,'D')
check(find(door,10,10,false)==nil,'warp and door tiles do not make a valid pair')
local water=grid(10,10,'~')
check(find(water,5,5,false)==nil,'land encounter never moves onto water')
validate(water,find(water,5,5,true),5,5,true)
local coast=grid(10,10,'~');for y=0,9 do coast:set(4,y,'.') end
validate(coast,find(coast,4,4,false),4,4,false)
local blocked=function(x,y)return y<6 end
local occupied=grid(12,12,'.')
a=find(occupied,6,6,false,{blocked=blocked})
validate(occupied,a,6,6,false,blocked)
check(a.playerCell[1]==6 and a.playerCell[2]==6,'nearby NPCs do not force the player off the encounter cell')
local displaced=grid(20,20,'#');displaced:set(10,10,'.');displaced:set(12,10,'.');displaced:set(13,10,'.')
a=find(displaced,10,10,false)
validate(displaced,a,10,10,false)
check(a.playerCell[1]==12 and a.playerCell[2]==10,'local fallback uses the nearest valid pair')
local far=grid(100,100,'#');far:set(50,50,'.');for x=0,10 do for y=0,10 do far:set(x,y,'.') end end
check(find(far,50,50,false)==nil,'remote open clearing is never substituted')
check(find(field,-1,2,false)==nil and find(field,1000,2,false)==nil,'out-of-map encounter origin declines')
check(find(field,0/0,2,false)==nil and find(field,math.huge,2,false)==nil,'invalid coordinates safely decline')
-- Raised banks may have no common plane for the solved camera/native FX.
local level=grid(20,20,'.')
local ground=function(x,y)return y<10 and 12 or 0 end
a=find(level,10,10,false,{facing='up',pairAllowed=function(px,py,ex,ey)
  return ground(px,py)==ground(ex,ey)
end})
check(a and ground(a.playerCell[1],a.playerCell[2])==ground(a.enemyCell[1],a.enemyCell[2]),
  'height callback selects a same-level pair beside a bank')
check(a.playerCell[1]==10 and a.playerCell[2]==10,'same-level pair still keeps encounter origin first')
check(find(level,10,10,false,{pairAllowed=function()return false end})==nil,
  'uneven local terrain declines to same-map native pictures')
local legacy=grid(16,16,'.','LEGACY')
local old=Arena.find(legacy,0,0,false)
check(old.x==4 and old.y==4 and old.shape=='wide' and not old.encounter,'non-JP authored-stage contract remains intact')
check(Arena.find(refused,6,6,false)==nil,'non-JP authored refusal remains intact')
check(not Arena.openCell(field,2,2,false),'legacy low-camera grass rule stays unchanged')
print('RESULT '..checks..' checks passed')
