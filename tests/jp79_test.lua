-- jp.79 3D: roofs for houses that back onto the tree border (New Bark's
-- lab and Gold's house), rooms and caves, and the stronger battle camera.
-- Everything here only runs with 3D on.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness').suite('JP79 3D')
local ok,Field3D=pcall(require,'src.world.gen2.Field3D')
T.check(ok,'Field3D loads: '..tostring(ok and '' or Field3D))
if ok then
  T.check(type(Field3D.isTreePalette)=='function','has isTreePalette')
  T.check(Field3D.isTreePalette(function() return 3 end),'all four tiles green: tree')
  T.check(not Field3D.isTreePalette(function(dx,dy) return (dx==8 and dy==8) and 6 or 3 end),'one tile not green: not a tree')
  T.check(not Field3D.isTreePalette(function() return nil end),'unknown palette: not a tree')
  -- New Bark rows 0..5 (collision 07 = wall; palette 3333 = tree), map cells
  local coll={
    '07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07',
    '07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07',
    '07 07 00 00 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07 07',
    '07 07 00 07 07 07 71 07 07 07 07 07 07 07 07 07 07 07 07 07',
    '07 07 00 00 00 00 00 00 00 00 00 00 07 07 07 07 07 07 07 07',
    '07 07 00 00 00 00 00 00 00 00 00 07 07 71 07 07 07 07 07 07',
  }
  local pal={
    '3333 3333 3333 3333 7777 7777 7777 7777 7777 7777 3333 3333 3333 3333 3333 3333 3333 3333 3333 3333',
    '3333 3333 3333 3333 7777 7777 7777 7777 7777 7777 3333 3333 3333 3333 3333 3333 3333 3333 3333 3333',
    '3333 3333 3333 3333 6665 6656 6666 6666 6665 6656 3333 3333 7777 7777 7777 7777 3333 3333 3333 3333',
    '3333 3333 3333 1111 6666 6666 5566 6666 6666 6666 3333 3333 7777 7777 7777 7777 3333 3333 3333 3333',
    '3333 3333 3333 3333 1111 1111 1111 1111 1111 1111 3333 3333 6666 6666 6665 6656 3333 3333 3333 3333',
    '3333 3333 3333 3333 1111 1111 1111 1111 1111 1111 3333 1111 6666 5566 6666 6666 3333 3333 3333 3333',
  }
  local W,Hh={},{}
  for j,row in ipairs(coll) do local i=0 for b in row:gmatch('%x%x') do W[i..','..(j-1)]=(b=='07') i=i+1 end end
  for j,row in ipairs(pal) do local i=0 for s in row:gmatch('%d+') do Hh[i..','..(j-1)]=(s=='3333') i=i+1 end end
  local function wall(i,j) return W[i..','..j]==true end
  local function house(i,j) return wall(i,j) and not Hh[i..','..j] end
  local doors={{6,3},{13,5}}
  -- jp.78 rule (no palettes): the runs go on into the trees
  local rep0={}
  Field3D.roofPlan(wall,doors,nil,rep0)
  T.check(rep0[1]~='6,3:6x4' and rep0[2]~='13,5:4x4','jp.78 rule: wrong footprints ('..table.concat(rep0,' ')..')')
  -- jp.79: trees left out, the lab is 6x4 and Gold's house 4x4
  local rep={}
  local r1,s1=Field3D.roofPlan(house,doors,nil,rep)
  T.eq(rep[1],'6,3:6x4','lab: 6 wide, 4 rows')
  T.eq(rep[2],'13,5:4x4','Gold house: 4 wide, 4 rows')
  T.check(r1['4,0'] and r1['4,0'].top==0 and r1['4,0'].eave==3,'lab roof rows 0..2, eave on the door row')
  T.check(r1['12,2'] and r1['12,2'].top==2 and r1['12,2'].eave==5,'house roof rows 2..4')
  T.eq(r1['10,0'],nil,'the tree border stays unroofed')
  T.eq(s1['16,4'],nil,'the trees east of the house are not solid')
  T.eq(r1['6,3'],nil,'door cell has no roof')

  -- rooms and caves
  T.eq(Field3D.envKind({environment='TOWN'}),'out','town is outdoors')
  T.eq(Field3D.envKind({environment='ROUTE'}),'out','route is outdoors')
  T.eq(Field3D.envKind({environment='CAVE',tileset='TILESET_CAVE'}),'cave','cave tileset')
  T.eq(Field3D.envKind({environment='DUNGEON',tileset='TILESET_ICE_PATH'}),'cave','ice path tileset')
  T.eq(Field3D.envKind({environment='INDOOR',tileset='TILESET_LAB'}),'room','indoor room')
  T.eq(Field3D.envKind({environment='GATE'}),'room','gate')
  T.eq(Field3D.envKind(nil),'box','no def keeps boxes')
  -- a 6x5 room: border walls plus a free-standing shelf at (2,2)
  local room={
    'XXXXXX',
    'X....X',
    'X.X..X',
    'X....X',
    'XXXXXX',
  }
  local function blk(i,j) local r=room[j+1] return r~=nil and r:sub(i+1,i+1)=='X' end
  local sh=Field3D.shellOf(blk,0,0,5,4)
  T.check(sh['0,0'] and sh['5,4'] and sh['3,0'],'border walls are the shell')
  T.eq(sh['2,2'],nil,'free-standing shelf is furniture')
  T.eq(sh['1,1'],nil,'floor is not shell')
  local a,b=Field3D.caveJag(7,11),Field3D.caveJag(7,11)
  T.eq(a,b,'cave jag is fixed per corner')
  local lo,hi,diff=1e9,-1e9,false
  for gx=-20,20 do for gy=-20,20 do
    local v=Field3D.caveJag(gx,gy)
    if v<lo then lo=v end; if v>hi then hi=v end
    if v~=a then diff=true end
  end end
  T.check(lo>=0 and hi<=Field3D.CAVE.jag,'cave jag stays in 0..jag ('..lo..'..'..hi..')')
  T.check(diff,'cave jag varies')

  -- battle camera: livelier than jp.78, still gentle
  local A=Field3D.ACTION
  T.check(A.ORBIT>math.rad(3.2) and A.ORBIT<=math.rad(6),'orbit stronger than jp.78, at most 6 degrees')
  T.check(A.ATTENTION>.085 and A.ATTENTION<=.15,'attention stronger than jp.78')
  T.check(A.PUSH>.055 and A.PUSH<=.1,'push-in stronger than jp.78')
  T.check(A.PERIOD>=12 and A.PERIOD<20,'orbit a little faster')
end
T.finish()
