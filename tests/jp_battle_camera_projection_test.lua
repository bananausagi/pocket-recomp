package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP battle third-person-height camera projection')
local M=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/Mat4.lua'))()
local Cam=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/BattleCam.lua'))({})
local snapshot={};for id,rig in pairs(Cam.RIGS)do snapshot[id]={};for k,v in pairs(rig)do snapshot[id][k]=v end end
local thirdPersonEye=13+4+48*math.sin(math.rad(10))
local maxError=0
for _,spacing in ipairs({'normal','wide','wider'})do
 for _,compact in ipairs({false,true})do
  for i=0,7 do
   for _,gap in ipairs({16,32,48,math.sqrt(2)*16,math.sqrt(2)*48})do
    for _,ground in ipairs({0,12,96})do
     local angle=i*math.pi/4;local dx,dz=math.sin(angle)*gap/2,math.cos(angle)*gap/2
     local arena={mid={137,213},player={137+dx,213+dz},enemy={137-dx,213-dz},
       encounter=true,jpCompact=compact,jpMetrics={spacing=spacing}}
     local rig=Cam.rig(arena,ground,true)
     local eye,focus=rig.eye,rig.focus
     local x,y,z=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
     T.check(math.abs(eye[2]-ground-thirdPersonEye*gap/48)<1e-8,'eye matches normal 3RD height at the same arena scale')
     local down=math.deg(math.atan2(y,math.sqrt(x*x+z*z)))
     T.check(down>19 and down<28,'third-person eye frames the wider battlefield')
     T.check(math.abs(math.deg(rig.fov)-46)<1e-8,'canonical native lens is forty-six degrees')
     local vp=M.mul(M.perspective(rig.fov,160/144,.1,10000),M.lookAt(eye,focus,{0,1,0}))
     for _,side in ipairs({'player','enemy'})do
      local p=arena[side];local w=vp[13]*p[1]+vp[14]*ground+vp[15]*p[2]+vp[16]
      local px=(vp[1]*p[1]+vp[2]*ground+vp[3]*p[2]+vp[4])/w*80+80
      local py=72-(vp[5]*p[1]+vp[6]*ground+vp[7]*p[2]+vp[8])/w*72
      local tx=side=='player' and 42 or 124
      local ty=side=='player' and (compact and ({normal=112,wide=128,wider=144})[spacing] or ({normal=128,wide=152,wider=176})[spacing]) or (compact and 56 or 72)
      local error=math.max(math.abs(px-tx),math.abs(py-ty));maxError=math.max(maxError,error)
      T.check(w>0 and error<1e-8,side..' feet project onto the shared native FX target')
     end
    end
   end
  end
 end
end
for id,rig in pairs(Cam.RIGS)do for k,v in pairs(rig)do T.eq(v,snapshot[id][k],'shared canonical rig never mutated')end end
print('Maximum anchor error: '..maxError..' native pixels')
T.finish()
