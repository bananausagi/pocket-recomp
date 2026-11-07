-- Authored empty/blocked grids. Real placement, solved camera, projection and
-- provider wiring; no ROM, map asset, saved option reset or scene replacement.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP encounter camera continuity')
local lib='vendor/jp-mods/DRAMALESS_SHAPE/lib/'
local function module(name,V)return assert(loadfile(lib..name..'.lua'))(V)end
local M=module('Mat4')
local Cam=module('BattleCam',{})
local Arena=module('BattleArena',{require=function(name)
  if name=='VoxelScene'then return {groundAt=function()return 0 end}end
  if name=='BattleCam'then return Cam end
  error(name)
end})
local function map(fill)
  local m={id='AUTHORED_FIELD',def={tileset='OVERWORLD'},widthCells=32,heightCells=32,tiles={}}
  function m:inBounds(x,y)return x>=0 and y>=0 and x<32 and y<32 end
  function m:isWalkableCell(x,y)return self.tiles[x..':'..y] or fill or false end
  function m:isWaterCell()return false end
  function m:isWarpTileCell()return false end
  function m:warpAtCell()return nil end
  return m
end
local function delta(a,b)return math.abs((a-b+math.pi)%(2*math.pi)-math.pi)end
local function heading(p)return math.atan2(p.eye[1]-p.focus[1],p.eye[3]-p.focus[3])end
local function options(yaw,metrics)
  local r=Cam.rigFor({encounter=true,jpCompact=metrics.compact,jpMetrics=metrics})
  return {facing='up',cameraYaw=yaw,rigYaw=math.atan2(r.side-r.lookX,r.back)}
end
local field=map(true)
local thirdPersonEye=13+4+48*math.sin(math.rad(10))
local maxDelta=0
for _,spacing in ipairs({'normal','wide','wider'})do
 for _,compact in ipairs({false,true})do
  local metrics={spacing=spacing,compact=compact}
  for _,degrees in ipairs({0,15,45,70,90,135,180,-45,-130,-179})do
   local yaw=math.rad(degrees)
   local old=Arena.findEncounter(field,16,16,false,{facing='up'})
   local new=Arena.findEncounter(field,16,16,false,options(yaw,metrics))
   old.jpMetrics,old.jpCompact=metrics,compact;new.jpMetrics,new.jpCompact=metrics,compact
   local before,after=Cam.rig(old,12,true),Cam.rig(new,12,true)
   local change=delta(heading(after),yaw);maxDelta=math.max(maxDelta,change)
   T.check(change<=delta(heading(before),yaw)+1e-10,'safe ranking never increases entry rotation')
   T.check(change<=math.rad(22.5)+1e-10,'open ground selects nearest of eight camera bearings')
   T.eq(new.map,field,'keeps same map')
   T.same(new.playerCell,{16,16},'keeps encounter cell underfoot')
   T.eq(new.origin.cellX,16,'keeps encounter identity')
   local eye,focus=after.eye,after.focus
   local x,y,z=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
   local ax,az=new.player[1]-new.enemy[1],new.player[2]-new.enemy[2]
   T.check(math.abs(eye[2]-12-thirdPersonEye*math.sqrt(ax*ax+az*az)/48)<1e-8,'retains normal 3RD eye height at the selected arena scale')
   T.check(math.abs(math.deg(after.fov)-46)<1e-8,'uses the wider forty-six degree battle lens')
   local vp=M.mul(M.perspective(after.fov,160/144,.1,10000),M.lookAt(eye,focus,{0,1,0}))
   for _,side in ipairs({'player','enemy'})do
    local p=new[side];local w=vp[13]*p[1]+vp[14]*12+vp[15]*p[2]+vp[16]
    local sx=(vp[1]*p[1]+vp[2]*12+vp[3]*p[2]+vp[4])/w*80+80
    local sy=72-(vp[5]*p[1]+vp[6]*12+vp[7]*p[2]+vp[8])/w*72
    local tx=side=='player' and 42 or 124
    local ty=side=='player' and (compact and ({normal=112,wide=128,wider=144})[spacing] or ({normal=128,wide=152,wider=176})[spacing]) or (compact and 56 or 72)
    T.check(math.abs(sx-tx)<1e-8 and math.abs(sy-ty)<1e-8,'rotated safe pair keeps '..side..' native effects anchor')
   end
   if degrees==0 and spacing=='wide' and not compact then
    print(('North-facing field: before %.6f deg; after %.6f deg'):format(math.deg(delta(heading(before),yaw)),math.deg(change)))
    T.same(new.enemyCell,{19,13},'higher rig chooses the nearer northeast bearing to minimize entry rotation')
   end
  end
 end
end
local narrow=map(false)
narrow.tiles['16:16'],narrow.tiles['17:16']=true,true
local old=Arena.findEncounter(narrow,16,16,false,{facing='up'})
local new=Arena.findEncounter(narrow,16,16,false,options(0,{spacing='wide'}))
T.same(new.playerCell,old.playerCell,'narrow terrain retains only safe player cell')
T.same(new.enemyCell,old.enemyCell,'narrow terrain retains only safe enemy cell')
T.eq(Arena.findEncounter(map(false),16,16,false,options(0,{spacing='wide'})),nil,'no safe pair never invents terrain')
local expected=Arena.findEncounter(field,16,16,false,{facing='left'})
for _,yaw in ipairs({0/0,math.huge,-math.huge})do
 local got=Arena.findEncounter(field,16,16,false,{facing='left',cameraYaw=yaw,rigYaw=0})
 T.same(got.enemyCell,expected.enemyCell,'invalid camera data falls back to original facing choice')
end
local guarded=options(0,{spacing='wide'})
guarded.pairAllowed=function(px,py,ex,ey)return py==ey end
local level=Arena.findEncounter(field,16,16,false,guarded)
T.eq(level.playerCell[2],level.enemyCell[2],'camera preference cannot bypass equal-height pair validation')
guarded.pairAllowed=nil
guarded.blocked=function(x,y)return x>16 end
local occupied=Arena.findEncounter(field,16,16,false,guarded)
T.check(occupied.enemyCell[1]<=16,'camera preference cannot place opponent on occupied cell')

-- Actual provider uses the last rendered pose, not sprite facing or freecam
-- setting IDs. Normal, rotated and first/third-person poses take the same API.
local currentPose
local state={map=field,player={cellX=16,cellY=16,facing='up'}}
local fakeGame={overworld=state}
package.loaded['src.core.Game']=fakeGame
package.loaded['src.render.Renderer']={frameRects=function()return {
  vux=0,vuy=0,vuw=972,vuh=1536,pw=972,ph=1536,dpiX=1,dpiY=1,uiw=160,uih=144,
}end}
local camera={available=function()return true end}
local V={require=function(name)
 local deps={BattleArena=Arena,BattleCam=Cam,Voxel3D=camera,VoxelState={angle=.8},
   VoxelScene={groundAt=function()return 0 end},VoxelBattleScene={ready=function()return true end}}
 return assert(deps[name],name)
end}
local Provider=module('VoxelBattleArenaProvider',V)
local game={renderer={},data={constants={language='ja'}}}
local battle={game=game}
for _,case in ipairs({{0,100},{70,8},{-130,40}})do
 local yaw,height=math.rad(case[1]),case[2]
 camera.eye={264+60*math.sin(yaw),height,264+60*math.cos(yaw)}
 camera.focus={264,0,264};camera.fovY=.8;camera.camera={up={0,1,0}}
 local arena=Provider:arena({battle=battle})
 T.check(arena~=nil,'actual provider accepts safe same-map staging')
 arena.jpMetrics={spacing='wide'}
 T.check(delta(heading(Cam.rig(arena,0,true)),yaw)<=math.rad(22.5),'actual provider ranks from rendered view heading')
 T.same(arena.entryPose.eye,camera.eye,'entry retains exact world eye')
 T.check(arena.entryPose.eye~=camera.eye,'entry pose is copied without mutating world camera')
end
print(('Maximum open-field yaw change: %.6f deg'):format(math.deg(maxDelta)))
T.finish()
