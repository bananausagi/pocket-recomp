-- jp.81 3D view controls (Gen 1's angle ladder, zoom, free look).
-- With 3D off (or a menu open) every new hook must say no, so 2D input and
-- the display hotkeys keep their jp.80 jobs.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness').suite('JP81 3D view')
local ok,Field3D=pcall(require,'src.world.gen2.Field3D')
T.check(ok,'Field3D loads: '..tostring(ok and '' or Field3D))
if ok then
  for _,name in ipairs({'preHotkey','wheel','cycleView','zoomStep','viewLabel',
      'ladderIndex','angleOf','zoomIndex','frameRoom','fieldFree'}) do
    T.check(type(Field3D[name])=='function','has '..name)
  end
  local off={world=nil,options={}}
  for _,k in ipairs({'v','-','=','kp-','kp+','1','f1'}) do
    T.eq(Field3D.preHotkey(off,k),false,'3D off: key '..k..' keeps its job')
  end
  T.eq(Field3D.wheel(off,1),false,'3D off: wheel keeps the 2D zoom')
  T.eq(Field3D.padPressed(off,'rightstick'),false,'3D off: R3 untouched')
  T.eq(Field3D.padAxis(off,'righty',1),false,'3D off: right stick Y untouched')
  T.eq(Field3D.keypressed(off,'r'),false,'3D off: R untouched')

  -- a live field with no menu over it
  local menu=nil
  local game={options={jp3D=true,jp3DCamera='above',jp3DAngle='35',jp3DZoom=3},
    phase='field',stack={top=function() return menu end}}
  local world={game=game,field3d={live=true,yaw=0,yawTarget=0}}
  game.world=world
  T.eq(Field3D.fieldFree(game),true,'live field is free')
  T.eq(Field3D.viewLabel(world),'うえから 35ど','label above 35')
  local seen={}
  for i=1,7 do
    T.eq(Field3D.preHotkey(game,'v'),true,'V steps the ladder '..i)
    seen[#seen+1]=Field3D.cameraMode(world)..':'..tostring(game.options.jp3DAngle)
  end
  T.eq(seen[1],'above:50','35 -> 50')
  T.eq(seen[2],'above:75','50 -> 75')
  T.eq(seen[3]:sub(1,6),'third:','75 -> behind')
  T.eq(seen[4]:sub(1,6),'first:','behind -> first person')
  T.eq(seen[5],'above:diorama','first person -> diorama')
  T.eq(seen[6],'above:15','diorama -> 15')
  T.eq(seen[7],'above:35','back round to 35')
  T.check(world.field3d.toast~=nil,'a change shows a toast')
  for _=1,9 do Field3D.preHotkey(game,'=') end
  T.eq(game.options.jp3DZoom,5,'zoom clamps at 5')
  for _=1,9 do Field3D.wheel(game,-1) end
  T.eq(game.options.jp3DZoom,1,'wheel zooms out, clamps at 1')
  -- free look only in the chase / first-person views
  T.eq(Field3D.keypressed(game,'r'),false,'R does nothing from above')
  game.options.jp3DCamera='third'
  T.eq(Field3D.keypressed(game,'f'),true,'F looks down behind')
  T.eq(world.field3d.lookPitch,10,'one step is 10 degrees')
  game.options.jp3DInvert=true
  Field3D.keypressed(game,'f')
  T.eq(world.field3d.lookPitch,0,'INVERT flips the step')
  T.eq(Field3D.padAxis(game,'righty',0.8),true,'stick Y held tilts behind')
  T.eq(world.field3d.stickY,0.8,'stick value kept for drawScene')
  T.eq(Field3D.padAxis(game,'righty',0.1),false,'deadzone lets go')
  T.eq(world.field3d.stickY,0,'deadzone clears the tilt')
  -- a menu takes everything back
  menu={}
  T.eq(Field3D.fieldFree(game),false,'menu open: field not free')
  T.eq(Field3D.preHotkey(game,'v'),false,'menu open: V not taken')
  T.eq(Field3D.wheel(game,1),false,'menu open: wheel not taken')
  T.eq(Field3D.padAxis(game,'righty',0.9),false,'menu open: stick scrolls the menu')
  T.eq(world.field3d.stickY,0,'menu open: no tilt left behind')
  T.eq(Field3D.padPressed(game,'rightstick'),false,'menu open: R3 not taken')
end
local okS,Save=pcall(require,'src.core.gen2.Save')
T.check(okS,'Save loads')
if okS then
  local d=Save.defaultOptions()
  T.eq(d.jp3DAngle,'35','default angle 35')
  T.eq(d.jp3DZoom,3,'default zoom 3')
  T.eq(d.jp3DInvert,false,'default not inverted')
  T.eq(d.jp3D,false,'3D still off by default')
end
T.finish()
