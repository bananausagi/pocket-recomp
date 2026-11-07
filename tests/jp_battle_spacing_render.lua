-- Final spacing/lens integration through the real MOD cards and GL camera.
return function(Game,Renderer,V,state,battle,check,write)
  local g=love.graphics
  local P=require('src.battle.BattlePresentation')
  local Stack=Game.stack
  local Viewport=require('src.render.GameViewport')
  local Touch=require('src.core.TouchControls')
  local Host=V.require('VoxelBattleStandalone')
  local Provider=V.require('VoxelBattleArenaProvider')
  local Cards=V.require('VoxelBattleCardProvider')
  local V3=V.require('Voxel3D')
  local report={cases={},physicalAndroid=false,assets='authored terrain and sprites; no ROM'}
  for _,size in ipairs({{480,800},{800,480}})do
    love.window.setMode(size[1],size[2],{vsync=0})
    require('src.core.ScreenPosition').setMode('center')
    Game.save.options.jpDialogScale=.75;Game.save.options.jpBattleSpacing='wide'
    Stack.states={state};Game:draw();g.setCanvas()
    Stack.states={state,battle}
    check(Host.begin(battle,Provider,Cards),'spacing matrix starts actual voxel battle')
    local context=Host.session.context
    context.arena.presentationTime=10
    for _,factor in ipairs({.75,1})do
      local previous,firstWindowScale
      Game.save.options.jpDialogScale=factor
      for _,spacing in ipairs({'normal','wide','wider'})do
        Game.save.options.jpBattleSpacing=spacing
        Game:draw();g.setCanvas()
        local r=Renderer:frameRects();local m=P.metrics(r)
        local tag=size[1]..'x'..size[2]..'-'..factor..'-'..spacing
        local body=r.body
        check(m.y>=body.y-.01 and m.y+m.height*m.sy<=body.y+body.h+.01,
          tag..' whole battle fits touch-free vertical bounds')
        -- Native composition snaps its origin down to one physical pixel.
        check(m.x>=body.x-1.001/r.dpiX and m.x+m.width*m.sx<=body.x+body.w+1.001/r.dpiX,
          tag..' whole battle fits touch-free horizontal bounds')
        local p,e=m.actor.player,m.actor.enemy
        local separation=(p.y-e.y)*m.sy
        check(not previous or separation>previous+1,tag..' spacing visibly increases physical distance')
        previous=separation
        firstWindowScale=firstWindowScale or m.windowScale
        check(m.windowScale==firstWindowScale,tag..' spacing preserves native text size')
        local scene=Renderer.battleSceneCanvas
        check(scene and scene:getWidth()==160
          and scene:getHeight()==math.max(144,math.ceil(m.height-m.native.y)),
          tag..' FX surface follows spacing/window/orientation without native144px crop')
        local expected=(m.compact and {normal=112,wide=128,wider=144}
          or {normal=128,wide=152,wider=176})[spacing]
        check(p.y-m.native.y==expected,tag..' uses requested larger field')
        local anchorError=0
        for _,side in ipairs({'player','enemy'})do
          local cell=context.arena[side]
          local x,y=context.services.project(cell[1],context.groundY,cell[2])
          local ratio=r.pw/context.services.renderSize.width
          local target=m.actor[side]
          anchorError=math.max(anchorError,math.abs(x*ratio-(m.x+target.x*m.sx-r.vux)*r.dpiX),
            math.abs(y*ratio-(m.y+target.y*m.sy-r.vuy)*r.dpiY))
        end
        check(anchorError<.1,tag..' 3D feet and original OAM targets stay aligned')
        local nativeFov=math.deg(2*math.atan(math.tan(V3.fovY/2)*144*r.Up/r.ph))
        check(math.abs(nativeFov-46)<.01,tag..' uses wider46-degree battle lens')
        g.push('all');g.setCanvas(Viewport.target());Touch:draw();g.pop()
        if factor==.75 then write('spacing-'..tag..'.png',Viewport.target():newImageData():encode('png'):getString())end
        report.cases[#report.cases+1]={size=size,factor=factor,spacing=spacing,
          sceneScale=m.scale,fontScale=m.windowScale,separationPixels=separation,
          nativeFov=nativeFov,anchorErrorPixels=anchorError}
        -- Simulate an overlay leaving a tiny scissor while an old frame
        -- contains opaque FX everywhere. The pass must clear the entire
        -- reusable canvas, not leave stale fragments outside that crop.
        local probeTarget=g.getCanvas()
        g.push('all');g.setCanvas(scene);g.setScissor();g.clear(1,0,1,1)
        g.setScissor(0,0,1,1)
        local previousTarget=Renderer:beginBattleScenePass(m)
        g.setCanvas()
        local cleared=scene:newImageData()
        local _,_,_,alpha=cleared:getPixel(159,scene:getHeight()-1)
        check(alpha==0,tag..' reused FX canvas clears beyond inherited scissor')
        Renderer:endBattleHUDPass(previousTarget);g.pop();g.setCanvas(probeTarget)
        local oldFx,oldFrame=battle.fx,battle.frame
        battle.fx={flash=2};battle.frame=0
        Game:draw();g.setCanvas()
        local flashed=Renderer.battleSceneCanvas:newImageData()
        local _,_,_,flashAlpha=flashed:getPixel(159,flashed:getHeight()-1)
        check(flashAlpha>.8,tag..' late native attack flash covers expanded field')
        battle.fx,battle.frame=oldFx,oldFrame
      end
    end
    Host.finish('spacing-qa')
  end
  write('spacing-results.json',assert(require('src.link.Json').encode(report)))
end
