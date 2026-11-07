-- jp.80 3D: dungeon floors as rooms, roof tiles on the roof (not the wall
-- top under the ridge), a steeper ridge on wide buildings, Gold/Silver
-- palettes for the 3D view and a calmer battle camera.
-- Everything here only runs with 3D on.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness').suite('JP80 3D')
local ok,Field3D=pcall(require,'src.world.gen2.Field3D')
T.check(ok,'Field3D loads: '..tostring(ok and '' or Field3D))
if ok then
  -- dungeon floors are rooms; caves and ice stay caves
  T.eq(Field3D.envKind({environment='DUNGEON',tileset='TILESET_TOWER'}),'room','tower floor is a room')
  T.eq(Field3D.envKind({environment='DUNGEON',tileset='TILESET_RUINS_OF_ALPH'}),'room','ruins chamber is a room')
  T.eq(Field3D.envKind({environment='DUNGEON',tileset='TILESET_UNDERGROUND'}),'room','underground is a room')
  T.eq(Field3D.envKind({environment='DUNGEON',tileset='TILESET_LIGHTHOUSE'}),'room','lighthouse is a room')
  T.eq(Field3D.envKind({environment='DUNGEON',tileset='TILESET_ICE_PATH'}),'cave','ice path stays a cave')
  T.eq(Field3D.envKind({environment='CAVE',tileset='TILESET_ICE_PATH'}),'cave','ice path (cave env) stays a cave')
  T.eq(Field3D.envKind({environment='CAVE',tileset='TILESET_FOREST'}),'box','Ilex keeps its trees')
  T.eq(Field3D.envKind({environment='INDOOR',tileset='TILESET_POKECENTER'}),'room','Pokemon Center inside is a room')
  T.eq(Field3D.envKind(nil),'box','no def keeps boxes')

  -- roofPlan keeps the width
  local function wall(i,j) return i>=0 and i<=5 and j>=0 and j<=3 end
  local roofs=Field3D.roofPlan(wall,{{2,4}})
  T.check(roofs['0,0'] and roofs['0,0'].w==6 and roofs['0,0'].top==0 and roofs['0,0'].eave==3,'roof keeps top, eave and width')

  -- the ridge: houses as before, the wide lab steeper
  T.eq(Field3D.roofRiseCap(4),10,'4 wide: rise cap 10 (unchanged)')
  T.eq(Field3D.roofRiseCap(nil),10,'unknown width: 10')
  T.eq(Field3D.roofRiseCap(6),18,'6 wide (the lab): 18')
  T.eq(Field3D.roofRiseCap(12),18,'wider: still 18')
  local house={top=0,eave=3,w=4}
  local lab={top=0,eave=3,w=6}
  local zr=1.5*16
  T.check(math.abs(Field3D.gableY(house,0,16,zr)-26)<1e-6,'house ridge at 16+10')
  T.check(math.abs(Field3D.gableY(lab,0,16,zr)-34)<1e-6,'lab ridge at 16+18')
  T.check(math.abs(Field3D.gableY(lab,0,16,0)-16)<1e-6,'eave stays at wall height')

  -- roof texture rows: New Bark lab column (rows 0,1 roof palette 7, row 2
  -- the window row in palette 6), a tower column all in palette 6
  local labPal={[0]=7,7,6,6}
  local function palLab(i,j) return labPal[j] end
  local r={top=0,eave=3}
  T.eq(Field3D.roofTexRow(palLab,4,0,r),0,'roof row keeps its own texture')
  T.eq(Field3D.roofTexRow(palLab,4,1,r),1,'second roof row keeps its own texture')
  T.eq(Field3D.roofTexRow(palLab,4,2,r),1,'window row under the ridge shows the roof row above')
  local function palMixed(i,j) if j==0 then return nil end return 7 end
  T.eq(Field3D.roofTexRow(palMixed,4,0,r),1,'no roof row above: the roof row below')
  local function palTower(i,j) return 6 end
  T.eq(Field3D.roofTexRow(palTower,4,2,{top=0,eave=8}),2,'tower in wall palette keeps its rows')
  T.eq(Field3D.roofTexRow(nil,4,2,r),2,'no palettes: own row')

  -- battle camera: calmer than jp.79, livelier than jp.78
  local A=Field3D.ACTION
  T.check(A.ORBIT>math.rad(3.2) and A.ORBIT<math.rad(5),'orbit between jp.78 and jp.79')
  T.check(A.PERIOD>16 and A.PERIOD<20,'orbit slower than jp.79')
  T.check(A.ATTENTION>.085 and A.ATTENTION<.12,'attention between jp.78 and jp.79')
  T.check(A.PUSH>.055 and A.PUSH<.08,'push-in between jp.78 and jp.79')

  -- Gold/Silver palettes: the jp.79 tree rule needs only cell palettes,
  -- which TileAttrs gives from tilePalettes without an attrGrid
  local okM,MapAttrGrid=pcall(require,'src.world.gen2.MapAttrGrid')
  T.check(okM,'MapAttrGrid loads')
  if okM then
    local ts={blocks={{0,1,0,1, 0,1,0,1, 0,1,0,1, 0,1,0,1}},tilePalettes={}}
    for t=0,255 do ts.tilePalettes[t+1]=(t==1) and 6 or 2 end
    local map={width=1,height=1,blocks={0},borderBlock=0}
    local okB,g=pcall(MapAttrGrid.build,map,ts)
    T.check(okB and type(g)=='table','grid builds from a tileset with no tileAttrs')
    if okB and type(g)=='table' then
      local a=MapAttrGrid.lookup(g,8,0)
      local b=MapAttrGrid.lookup(g,0,0)
      T.eq(a and a.attr and a.attr.palette,6,'tile palette from tilePalettes')
      T.eq(b and b.attr and b.attr.palette,2,'other tile palette from tilePalettes')
    end
  end
end
T.finish()
