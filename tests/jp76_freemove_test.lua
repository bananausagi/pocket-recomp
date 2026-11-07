-- jp.76 3D free movement core (src/world/gen2/FreeMove.lua), headless.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness').suite('JP76 free move')
local FM=require('src.world.gen2.FreeMove')

-- 5x5 room, wall at (3,2), out of bounds outside 0..4
local walls={['3,2']=true}
local function canEnter(fx,fy,tx,ty,dir)
  if tx<0 or ty<0 or tx>4 or ty>4 then return 'edge' end
  if walls[tx..','..ty] then return false end
  return true
end
local function body(cx,cy) return {px=cx*16,py=cy*16,cellX=cx,cellY=cy,push=0} end

-- straight walk right commits cells
local b=body(0,2)
local crossed=0
for _=1,40 do local r=FM.advance(b,1,0,1,canEnter); if r.crossed then crossed=crossed+1 end end
T.eq(b.cellX,2,'walks right until the wall cell')
T.eq(b.cellY,2,'stays on its row')
T.eq(crossed,2,'two cell crossings reported as landed steps')
T.check(b.px+8+FM.RADIUS<=3*16+0.01,'body stops flush against the wall')
-- pushing on: push reported after PUSH_FRAMES
local pushed
for _=1,FM.PUSH_FRAMES+1 do local r=FM.advance(b,1,0,1,canEnter); pushed=pushed or r.push end
T.eq(pushed,'right','a firm push hands the direction to the grid')

-- diagonal into the wall slides along it
b=body(2,1)
b.py=1*16+6
local sy=b.py
for _=1,10 do FM.advance(b,0.7071,0.7071,1,canEnter) end
T.check(b.py>sy,'diagonal slide keeps moving along the free axis')

-- map edge pushes at once
b=body(0,0)
local r
for _=1,12 do r=FM.advance(b,-1,0,1,canEnter); if r.push then break end end
T.eq(r.push,'left','the map edge goes to the grid (connection) without a long push')

-- backing away from an overlap is always allowed
walls['1,0']=true
b=body(0,0); b.px=3  -- overlapping (1,0) a little
local px0=b.px
FM.advance(b,-1,0,1,canEnter)
T.check(b.px<px0,'can move away from a blocked cell it overlaps')
walls['1,0']=nil

-- doorway assist: off-centre push at a one-cell gap slides into it
walls={['1,1']=true,['3,1']=true}
b=body(2,2); b.px=2*16+5
for _=1,20 do FM.advance(b,0,-1,1,canEnter) end
T.eq(b.cellY,1,'off-centre push enters the gap between two walls')
T.check(math.abs(b.px-2*16)<=8-FM.RADIUS+0.01,'and fits inside the gap column')

-- a slightly diagonal stick at the gap still gets through (no jitter)
b=body(2,3); b.px=2*16+2
for _=1,55 do FM.advance(b,0.15,-0.99,1,canEnter) end
T.eq(b.cellY,0,'slightly diagonal push walks through the gap')

-- snap and offGrid
b={px=17,py=33,cellX=1,cellY=2,moving=false,freeMoving=true}
T.check(FM.offGrid(b),'offGrid notices an off-cell body')
FM.snap(b)
T.eq(b.px,16,'snap x'); T.eq(b.py,32,'snap y'); T.eq(b.freeMoving,nil,'snap clears freeMoving')

-- input vector priority and rotation
local input={stickAxis={x=0.1,y=0.1},isDown=function(_,k) return k=='up' end}
local x,y=FM.inputVector(input,{active=true,x=0.6,y=0})
T.eq(x,0.6,'touch stick wins over a dead stick'); T.eq(y,0,'touch y')
x,y=FM.inputVector(input,nil)
T.eq(y,-1,'d-pad fallback')
input.stickAxis={x=0,y=-0.9}
x,y=FM.inputVector(input,{active=true,x=1,y=0})
T.check(math.abs(y+0.9)<1e-9,'analog stick first')
x,y=FM.rotate(0,-1,math.rad(90))
T.check(math.abs(x-1)<1e-9 and math.abs(y)<1e-9,'camera yaw 90 turns up into right')
T.eq(FM.advance(body(1,1),0,0,1,canEnter).crossed,false,'no input, no move')

-- jp.76 3D weather: love-free particle builder and sky easing
do
  local okF,F3=pcall(require,'src.world.gen2.Field3D')
  T.check(okF,'Field3D loads without love')
  if okF then
    local n,v=F3.weatherParticles('rain',1.5,100,200,1,0)
    T.check(n>0 and n%6==0,'rain builds whole quads')
    local inside=true
    for i=1,n do
      local q=v[i]
      if q[1]<100-120-20 or q[1]>100+120+20 or q[3]<200-120-1 or q[3]>200+120+1 then inside=false end
    end
    T.check(inside,'drops stay in the box around the target')
    T.eq(F3.weatherParticles('fog',0,0,0,1,0),0,'unknown weather builds nothing')
    local st={}
    local t1=F3.skyFor(st,'DAY',nil)
    local t2=F3.skyFor(st,'NITE',nil)
    T.check(t2[3]<t1[3] and t2[3]>0.14,'sky eases toward night instead of jumping')
    local r=F3.skyFor({},'DAY','rain')
    T.check(r[3]<0.9,'rain greys the day sky')
    -- jp.76 shape profiles and camera-relative facing
    local out=F3.profileFor({tileset='__none__'})
    T.eq(F3.taperOf(nil,out),0,'void cells stay square')
    T.eq(F3.viewFacing('right',90),'up','facing the camera direction shows the back')
    T.eq(F3.viewFacing('up',90),'left','north turns to screen left when looking east')
    T.eq(F3.viewFacing('down',0),'down','no turn keeps the frame')
    T.eq(F3.viewFacing('left',180),'right','half turn mirrors')
    T.eq(F3.viewFacing(nil,90),nil,'unknown facing passes through')
    T.eq(F3.profileFor({environment='__x__'}).wallTaper,(F3.profileFor(nil).wall>=16) and 3 or 0,'taper follows wall height')
    T.eq(F3.profileFor({environment='INDOOR'}).wallTaper,0,'indoor walls stay square')
    T.eq(F3.profileFor({tileset='TILESET_JOHTO'}).wallTaper,3,'outdoor walls taper')
    T.eq(F3.profileFor({tileset='TILESET_JOHTO'}).treeTaper,5,'trees taper')
    -- jp.76 battle arena and rig (Gen 1 BattleCam encounter values)
    local a=F3.battleArena(100,200,'up')
    T.eq(a.ex,100,'foe stands straight ahead (x)'); T.eq(a.ez,152,'foe stands 48 ahead (z)')
    a.focus=1; a.t=0
    local eye,tgt,fov=F3.battleRig(a,0)
    T.check(math.abs(eye[1]-118.57)<1e-6 and math.abs(eye[2]-25.34)<1e-6 and math.abs(eye[3]-240.72)<1e-6,'encounter eye: back 40.72, side 18.57, up 25.34')
    T.check(math.abs(tgt[2]-6.67)<1e-6 and math.abs(tgt[3]-176)<1e-6,'looks at the pair middle')
    local d=math.sqrt((eye[1]-tgt[1])^2+(eye[2]-tgt[2])^2+(eye[3]-tgt[3])^2)
    T.check(math.abs(2*d*math.tan(fov/2)-43.56)<1e-6,'frame height 43.56')
    a.focus=0
    local e0,t0,f0=F3.battleRig(a,0)
    T.check(e0[3]<eye[3] and math.abs(e0[1]-100)<1e-6,'intro close-up starts nearer, behind the foe')
    local d0=math.sqrt((e0[1]-t0[1])^2+(e0[2]-t0[2])^2+(e0[3]-t0[3])^2)
    T.check(math.abs(2*d0*math.tan(f0/2)-34)<1e-6,'close-up frame height 34')
  end
end
T.finish()
