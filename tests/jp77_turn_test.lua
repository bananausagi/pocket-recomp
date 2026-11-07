-- jp.77 3D camera turning without a drag (L/R, right stick, turn buttons).
-- With 3D off every hook must say no, so 2D input is untouched.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness').suite('JP77 3D turn')
local ok,Field3D=pcall(require,'src.world.gen2.Field3D')
T.check(ok,'Field3D loads: '..tostring(ok and '' or Field3D))
if ok then
  for _,name in ipairs({'padPressed','padAxis','turnButtons','turnButtonHit',
      'turnTouchPressed','turnTouchReleased','drawTurnButtons','playerCardPos'}) do
    T.check(type(Field3D[name])=='function','has '..name)
  end
  local off={world=nil,options={}}
  T.eq(Field3D.padPressed(off,'leftshoulder'),false,'3D off: L keeps its old job')
  T.eq(Field3D.padPressed(off,'rightshoulder'),false,'3D off: R keeps its old job')
  T.eq(Field3D.padPressed(off,'a'),false,'A is never taken')
  T.eq(Field3D.padAxis(off,'rightx',1),false,'3D off: right stick untouched')
  T.eq(Field3D.padAxis(off,'leftx',1),false,'left stick never taken')
  T.eq(Field3D.turnButtons(off),nil,'3D off: no turn buttons')
  T.eq(Field3D.turnTouchPressed(off,'t1',20,20),false,'3D off: a tap is not eaten')
  T.eq(Field3D.turnTouchReleased('t1'),false,'unknown touch release is ignored')
end
T.finish()
