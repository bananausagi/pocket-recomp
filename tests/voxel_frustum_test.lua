package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness")
local F=require("src.render.VoxelFrustum")
local M=assert(loadfile("vendor/jp-mods/DRAMALESS_SHAPE/lib/Mat4.lua"))()
local identity=M.identity()
T.check(F.visible({-0.5,-0.5,-0.5,0.5,0.5,0.5},identity),"interior chunk is kept")
for axis=1,3 do for _,sign in ipairs({-1,1})do
  local box={-0.5,-0.5,-0.5,0.5,0.5,0.5}
  box[axis],box[axis+3]=sign>0 and 1.1 or -2,sign>0 and 2 or -1.1
  T.check(not F.visible(box,identity),"chunk beyond clip plane is skipped")
  box[axis],box[axis+3]=sign>0 and 0.999999 or -2,sign>0 and 2 or -0.999999
  T.check(F.visible(box,identity),"one-edge-visible chunk is kept")
end end
T.check(F.visible({-2,-2,-2,2,2,2},identity),"chunk enclosing frustum is kept even with all corners outside")
T.check(F.visible({-2,0,-2,2,0,2},identity,nil,0,0,1),"curved chunk retains visible interior between lowered corners")
T.check(F.visible({0,0,0,1,1,1},nil),"missing camera falls back to full draw")
local projective=M.identity();projective[16]=2
T.check(F.visible({1000,1000,1000,1001,1001,1001},identity,projective),"unknown projective model falls back to full draw")
T.check(F.visible({0,0,0,1,1,1},identity,nil,0,0,0/0),"nonfinite curve falls back to full draw")
local function point(m,x,y,z)
  return m[1]*x+m[2]*y+m[3]*z+m[4],m[5]*x+m[6]*y+m[7]*z+m[8],
    m[9]*x+m[10]*y+m[11]*z+m[12]
end
local function inClip(vp,x,y,z)
  local px,py,pz=point(vp,x,y,z)
  local w=vp[13]*x+vp[14]*y+vp[15]*z+vp[16]
  return w>=0 and px>=-w and px<=w and py>=-w and py<=w and pz>=-w and pz<=w
end
math.randomseed(904)
local cases,visibleSamples,pulledSamples=0,0,0
for _,aspect in ipairs({0.5,1,2})do
 for _,pitch in ipairs({0.01,0.6,1.3})do
  for _,k in ipairs({0,0.18/144,0.02})do
   local eye={40,300*math.cos(pitch),20+300*math.sin(pitch)}
   local vp=M.mul(M.perspective(1.2,aspect,1,3000),M.lookAt(eye,{40,0,20},{0,1,-0.01}))
   for i=1,80 do
    local x,y,z=math.random(-600,600),math.random(0,100),math.random(-600,600)
    local bounds={x,y,z,x+math.random(8,256),y+math.random(4,160),z+math.random(8,256)}
    local model=M.mul(M.translate(math.random(-40,40),0,math.random(-40,40)),
      M.mul(M.rotateY(math.random()*2),M.scale(i%2==0 and -1 or 1,1,1)))
    local kept=F.visible(bounds,vp,model,40,20,k)
    local pulledKept=F.visible(bounds,vp,model,40,20,k,17)
    for p=1,25 do
     local u,v,w=math.random(),math.random(),math.random()
     local wx,wy,wz=point(model,x+u*(bounds[4]-x),y+v*(bounds[5]-y),z+w*(bounds[6]-z))
     wy=wy-k*((wx-40)^2+(wz-20)^2)
     if inClip(vp,wx,wy,wz)then
      visibleSamples=visibleSamples+1
      assert(kept,"visible curved/rotated point lost from chunk")
     end
     local dx,dy,dz=eye[1]-wx,eye[2]-wy,eye[3]-wz
     local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
     if distance>0 and inClip(vp,wx+dx*17/distance,wy+dy*17/distance,wz+dz*17/distance)then
      pulledSamples=pulledSamples+1
      assert(pulledKept,"visible curved/rotated/pulled foliage point lost from chunk")
     end
    end
    cases=cases+1
   end
  end
 end
end
T.check(cases==2160 and visibleSamples>100,"camera/curve sweep keeps every visible sampled point")
T.check(pulledSamples>100,"camera-ray foliage pull keeps every visible sampled point")
print(cases.." transformed chunks, "..visibleSamples.." visible point witnesses")
print(pulledSamples.." additional pulled foliage point witnesses")
T.finish("conservative voxel frustum")
