-- jp.78 3D: move effects and the slide-in on the battle cards, the action
-- camera, doors and roofs.  Everything here only runs with 3D on; the checks
-- make sure the jp.77 answers come back whenever the new inputs are absent.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness').suite('JP78 battle 3D')
local ok,Field3D=pcall(require,'src.world.gen2.Field3D')
T.check(ok,'Field3D loads: '..tostring(ok and '' or Field3D))
local function near(a,b,eps) return math.abs(a-b)<=(eps or 1e-9) end
local function sameVerts(a,b)
  if #a~=#b then return false end
  for i=1,#a do for k=1,9 do if not near(a[i][k],b[i][k]) then return false end end end
  return true
end
if ok then
  for _,name in ipairs({'actionStep','roofPlan','gableY','groundShade','cardQuads','battleRig'}) do
    T.check(type(Field3D[name])=='function','has '..name)
  end
  -- cardQuads: no shift (nil or 0) is the jp.77 card
  local a=Field3D.battleArena(100,200,'up'); a.focus=1
  local n0,q0=Field3D.cardQuads(a,0,1,0)
  a.shiftE,a.shiftP=0,0
  local n1,q1=Field3D.cardQuads(a,0,1,0)
  T.eq(n1,n0,'zero shift: same count')
  T.check(sameVerts(q0,q1),'zero shift: same quads')
  a.shiftE=56
  local _,q2=Field3D.cardQuads(a,0,1,0)
  T.check(near(q2[1][1]-q0[1][1],16,1e-6),'56 px shift moves the foe card one card width (16)')
  T.check(near(q2[7][1],q0[7][1]),'the player card stays put')
  a.shiftE=nil
  -- battleRig: no act (or weight 0) is the jp.77 rig
  local e0,t0,f0=Field3D.battleRig(a,0)
  a.act={time=3,w=0,aim=1,push=1}
  local e1,t1,f1=Field3D.battleRig(a,0)
  T.check(near(e0[1],e1[1]) and near(e0[2],e1[2]) and near(e0[3],e1[3]) and near(f0,f1),'weight 0: same camera')
  -- full weight, aim at the player: the view pans toward the player side
  a.act={time=0,w=1,aim=1,push=0}
  local e2,t2=Field3D.battleRig(a,0)
  local mx,mz=(a.px+a.ex)/2,(a.pz+a.ez)/2
  local d0=(t0[1]-a.px)^2+(t0[3]-a.pz)^2
  local d2=(t2[1]-a.px)^2+(t2[3]-a.pz)^2
  T.check(d2<d0,'aim +1 pans the target toward the player')
  local len0=math.sqrt((e0[1]-t0[1])^2+(e0[2]-t0[2])^2+(e0[3]-t0[3])^2)
  local len2=math.sqrt((e2[1]-t2[1])^2+(e2[2]-t2[2])^2+(e2[3]-t2[3])^2)
  T.check(near(len0,len2,1e-6),'the pan keeps the distance (no forward part)')
  a.act={time=0,w=1,aim=0,push=1}
  local e3,t3=Field3D.battleRig(a,0)
  local len3=math.sqrt((e3[1]-t3[1])^2+(e3[2]-t3[2])^2+(e3[3]-t3[3])^2)
  T.check(near(len3,len0*(1-Field3D.ACTION.PUSH),1e-6),'push-in is PUSH of the distance')
  -- during the close-up (focus 0) the action camera has no say
  a.focus=0; local c0=Field3D.battleRig(a,0)
  a.act=nil; local c1=Field3D.battleRig(a,0)
  T.check(near(c0[1],c1[1]) and near(c0[3],c1[3]),'focus 0: close-up untouched')
  -- actionStep
  local s=Field3D.actionStep(nil,0.1,true,'attack',-1)
  T.check(s.w>0 and s.w<1,'weight fades in')
  for _=1,60 do s=Field3D.actionStep(s,0.1,true,'attack',-1) end
  T.check(near(s.w,1) and s.aim<-0.99 and s.push>0.99,'settles on the target')
  for _=1,20 do s=Field3D.actionStep(s,0.1,false,'attack',-1) end
  T.eq(s.w,0,'fades out when not allowed')
  T.check(math.abs(s.aim)<=0.19,'idle aim stays small')
  -- roofPlan: a 4x3 house with a door under its middle
  local walls={}
  for i=2,5 do for j=1,3 do walls[i..','..j]=true end end
  local function isWall(i,j) return walls[i..','..j]==true end
  local roofs,solid=Field3D.roofPlan(isWall,{{3,4}})
  local nr,ns=0,0
  for _ in pairs(roofs) do nr=nr+1 end
  for _ in pairs(solid) do ns=ns+1 end
  T.eq(ns,12,'house cells solid')
  T.eq(nr,8,'roof over the two rows above the front row')
  T.check(roofs['2,1'] and roofs['2,1'].top==1 and roofs['2,1'].eave==3,'roof rows 1..2, front row 3')
  T.eq(roofs['3,3'],nil,'front row keeps its wall')
  -- a cliff line far over the cap is no house
  local cliff={}
  for i=0,40 do cliff[i..',0']=true; cliff[i..',1']=true end
  local r2,s2=Field3D.roofPlan(function(i,j) return cliff[i..','..j]==true end,{{5,2}})
  T.eq(next(r2),nil,'cliff: no roof'); T.eq(next(s2),nil,'cliff: not solid')
  T.eq(next((Field3D.roofPlan(isWall,{}))),nil,'no doors: no roofs')
  -- Gold's houses: the door sits in the front wall row, flanked by walls,
  -- and a fence runs on along the front row
  local g={}
  for i=2,5 do g[i..',1']=true end
  for i=0,9 do if i~=3 then g[i..',2']=true end end
  local rep={}
  local r3,s3=Field3D.roofPlan(function(i,j) return g[i..','..j]==true end,{{3,2}},nil,rep)
  local n3,m3=0,0
  for _ in pairs(r3) do n3=n3+1 end
  for _ in pairs(s3) do m3=m3+1 end
  T.eq(n3,4,'flanked door: one roof row, 4 wide')
  T.eq(m3,7,'flanked door: roof row + front row walls (door cell open)')
  T.check(r3['2,1'] and r3['2,1'].eave==2,'flanked door: eave on the door row')
  T.eq(rep[1],'3,2:4x2','report line')
  -- a house backed by a tree line taller than the cap: skipped
  local t={}
  for i=2,5 do for j=-10,2 do if not (i==3 and j==2) then t[i..','..j]=true end end end
  T.eq(next((Field3D.roofPlan(function(i,j) return t[i..','..j]==true end,{{3,2}}))),nil,'tree line behind: no roof')
  -- the gable
  local roof={top=1,eave=3}
  T.check(near(Field3D.gableY(roof,0,16,16),16),'eave at the north edge')
  T.check(near(Field3D.gableY(roof,0,16,48),16),'eave at the front row')
  T.check(near(Field3D.gableY(roof,0,16,32),16+math.min(10,16*0.9)),'ridge in the middle')
  -- ground shade stays in range
  local lo,hi=1,0
  for x=0,30 do for y=0,30 do local v=Field3D.groundShade(x,y,(x+y)%5) lo=math.min(lo,v) hi=math.max(hi,v) end end
  T.check(lo>=0.9*(1-0.36)-1e-9 and hi<=1,'ground shade in 0.58..1')
end
-- BattleState: the effect placer and the slide offsets
local okB,BattleState=pcall(require,'src.ui.gen2.BattleState')
if okB and type(BattleState)=='table' and BattleState.feetPlacer then
  T.eq(BattleState.feetPlacer(nil),nil,'no feet: no placer (2D placement)')
  local same=BattleState.feetPlacer({124,56,40,96})
  local x,y=same(60,30)
  T.eq(x,60,'identity feet keep x'); T.eq(y,30,'identity feet keep y')
  local moved=BattleState.feetPlacer({134,60,50,100})
  x,y=moved(60,30)
  T.eq(x,70,'translated feet move x'); T.eq(y,34,'translated feet move y')
  T.eq(BattleState.feetPlacer({50,50,50,50}),nil,'degenerate feet: no placer')
  local fake=setmetatable({},{__index=BattleState})
  local e,p=fake:slide3DOffsets()
  T.eq(e,0,'no anim view: no slide'); T.eq(p,0,'no anim view: no slide')
  local BAV=require('src.ui.gen2.BattleAnimView')
  fake.animView={}; fake.slideFrame=0
  e,p=fake:slide3DOffsets()
  T.eq(e,-144,'frame 0: foe 144 px left'); T.eq(p,144,'frame 0: player 144 px right')
  fake.slideFrame=BAV.SLIDE_FRAMES
  e,p=fake:slide3DOffsets()
  T.eq(e,0,'slide done: foe in place'); T.eq(p,0,'slide done: player in place')
else
  T.check(true,'BattleState not loadable headless; placer checked in shots')
end
T.finish()
