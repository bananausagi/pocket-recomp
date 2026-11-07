-- Follow real battle input after the encounter reaches its command menu.
-- The small authored animation uses the engine's normal animation compiler.
return function(Game,Renderer,V,battle,tag,render,check,step)
  local g,fs=love.graphics,love.filesystem
  local Input,Stack=Game.input,Game.stack
  local P=require('src.battle.BattlePresentation')
  local Font=require('src.render.Font')
  local Sound=require('src.core.Sound')
  local Host=V.require('VoxelBattleStandalone')
  local arena=Host.session.context.arena
  local nickname=Game.save.party[1].nickname
  local result={}
  local function pulse(key)
    Input:sourcePress(key,'battle-actions-qa');step()
    Input:sourceRelease(key,'battle-actions-qa');step()
  end
  local function settle(predicate,limit)
    for _=1,limit or 120 do
      if predicate()then return true end
      step()
    end
    return predicate()
  end
  local function shot(label)
    local pixels,m=render('actions-'..tag..'-'..label)
    m=m.panels or m
    if Stack:top()==battle then
      local c=m.command
      local paper=Renderer.battlePresentationCanvas:newImageData()
      local r,g,b,a=paper:getPixel(c.x+c.w-6,c.y+6)
      check(r>.99 and g>.99 and b>.99 and a>.99,label..' keeps opaque original white windows')
      check(c.x==m.enemyHUD.x and c.x+c.w==m.playerHUD.x+m.playerHUD.w,
        label..' lower window remains aligned with the status-card outer edges')
    end
    return pixels,m
  end

  pulse('up');pulse('left');pulse('right');pulse('a')
  check(settle(function()return Stack:top().isPartyMenu end),tag..' actual PKMN command opens the party selector')
  shot('party')
  check(Renderer.jpLayout=='page',tag..' party selection retains its centred native page')
  pulse('b')
  check(settle(function()return Stack:top()==battle and battle.phase=='menu'end),tag..' B returns from party selection to the real command menu')
  check(Host.session.context.arena==arena,tag..' opening and closing party keeps the encounter camera and arena')
  shot('after-party')

  -- Build one eight-pixel OAM tile and three original-coordinate points.
  -- These are data inputs, not an injected animPlaying flag or a fake draw.
  local tile=g.newCanvas(8,8,{dpiscale=1})
  g.push('all');g.setCanvas(tile);g.clear(0,0,0,0)
  g.setColor(0,0,0,1);g.rectangle('fill',0,2,8,4);g.rectangle('fill',2,0,4,8)
  g.setColor(1,1,1,1);g.rectangle('fill',3,1,2,6);g.rectangle('fill',1,3,6,2)
  g.pop();fs.write('fixture/action-oam.png',tile:newImageData():encode('png'))
  tile:release()
  local data=battle.animPlayer.data
  data.tilesheets.QA_ACTION={path='fixture/action-oam.png',width=8,height=8,tiles=1}
  data.frameBlocks=data.frameBlocks or {}
  data.frameBlocks.QA_ACTION={{x=0,y=0,tile=0}}
  data.baseCoords.QA_PLAYER={x=30,y=104}
  data.baseCoords.QA_MIDDLE={x=84,y=88}
  data.baseCoords.QA_ENEMY={x=128,y=64}
  data.subanims.QA_ACTION={type='HVFLIP',blocks={
    {block='QA_ACTION',coord='QA_PLAYER',mode=4},
    {block='QA_ACTION',coord='QA_MIDDLE',mode=4},
    {block='QA_ACTION',coord='QA_ENEMY',mode=0}}}
  local firstMove=battle.player.curMoves[1]
  data.moveAnims[firstMove.id]={seq={{subanim='QA_ACTION',tileset='QA_ACTION',delay=12}},source='authored QA'}
  local moveDef=Game.data.moves[firstMove.id]
  local originalPower=moveDef.power;moveDef.power=1 -- keep the fixture fight alive after one real turn
  local ppBefore,hpBefore=firstMove.pp,battle.enemy.mon.hp
  local rawDraw=battle.animPlayer.drawSprites
  local drawCount,projectedCount=0,0
  local projectionError=0
  battle.animPlayer.drawSprites=function(self,sprites,colorFn,project)
    for _,s in ipairs(sprites)do
      if s.ts=='QA_ACTION' then
        drawCount=drawCount+1
        if project then
          local m=P.metrics(Renderer:frameRects())
          local x,y=s.x-4,s.y-12
          local actualX,actualY=project(x,y)
          local expectedX,expectedY=P.effectPoint(m,x,y)
          projectionError=math.max(projectionError,math.abs(actualX-expectedX),math.abs(actualY-expectedY))
          projectedCount=projectedCount+1
        end
      end
    end
    return rawDraw(self,sprites,colorFn,project)
  end

  pulse('up');pulse('left');pulse('a')
  check(battle.phase=='moveSelect',tag..' actual FIGHT input opens the move grid')
  local runs={};local rawText=Font.draw
  Font.draw=function(text,x,y,...)
    runs[#runs+1]={text=text,x=x,y=y,width=Font.width(text)}
    return rawText(text,x,y,...)
  end
  local _,m=shot('moves');Font.draw=rawText
  local ppVisible=false
  for _,run in ipairs(runs)do
    if tostring(run.text):match('^PP %d+/%d+$')then
      ppVisible=run.x>=m.command.x and run.x+run.width<=m.command.x+m.command.w
    end
  end
  check(ppVisible,tag..' complete PP fraction remains inside the move window')
  if battle.moveIndex>2 then pulse('up')end
  if battle.moveIndex%2==0 then pulse('left')end
  love.math.setRandomSeed(1818)
  pulse('a')
  local seenEffect,returned=false,false
  for frame=1,700 do
    if battle.phase=='messages' and frame%16==0 then Input:sourcePress('a','battle-actions-qa')
    elseif frame%16==1 then Input:sourceRelease('a','battle-actions-qa')end
    step();render()
    if drawCount>0 and not seenEffect then
      seenEffect=true;shot('move-effect')
    end
    if battle.phase=='menu' and Stack:top()==battle then returned=true;break end
  end
  Input:sourceRelease('a','battle-actions-qa')
  battle.animPlayer.drawSprites=rawDraw;moveDef.power=originalPower
  check(seenEffect and projectedCount>0 and projectionError<1e-8,
    tag..' real turn animation uses the same native coordinates as the enlarged actors')
  check(returned and firstMove.pp==ppBefore-1 and battle.enemy.mon.hp<hpBefore,
    tag..' actual selected move spends one PP, deals damage and returns to commands')
  check(Game.save.party[1].nickname==nickname,tag..' battle presentation preserves the player nickname')
  shot('after-move')
  result.move={draws=drawCount,projectedDraws=projectedCount,projectionError=projectionError,
    ppBefore=ppBefore,ppAfter=firstMove.pp,hpBefore=hpBefore,hpAfter=battle.enemy.mon.hp}

  -- Keep the original ball-use sound and path. Stop at the first actual toss
  -- frame: capture outcome/naming is unrelated to the presentation change.
  Game.data.items.POKE_BALL={id='POKE_BALL',index=4,name='モンスターボール',price=200,ball='POKE_BALL'}
  Game.save.inventory.POKE_BALL=2;Game.save.bagOrder={'POKE_BALL'}
  -- Use a real multi-tile object here: a one-tile placeholder cannot expose
  -- the split ball caused by projecting the OAM quadrants independently.
  local ball=g.newCanvas(16,16,{dpiscale=1})
  g.push('all');g.setCanvas(ball);g.clear(0,0,0,0)
  g.setColor(0,0,0,1);g.circle('fill',8,8,7)
  g.setColor(1,1,1,1);g.circle('fill',8,8,5)
  g.setColor(0,0,0,1);g.rectangle('fill',1,7,14,2)
  g.pop();fs.write('fixture/action-ball.png',ball:newImageData():encode('png'));ball:release()
  data.tilesheets.QA_BALL={path='fixture/action-ball.png',width=16,height=16,tiles=4}
  data.frameBlocks.QA_BALL={{x=0,y=0,tile=0},{x=8,y=0,tile=1},
    {x=0,y=8,tile=2},{x=8,y=8,tile=3}}
  data.subanims.QA_BALL={type='HVFLIP',blocks={
    {block='QA_BALL',coord='QA_PLAYER',mode=4},
    {block='QA_BALL',coord='QA_MIDDLE',mode=4},
    {block='QA_BALL',coord='QA_ENEMY',mode=4}}}
  data.moveAnims.TOSS_ANIM={seq={{subanim='QA_BALL',tileset='QA_BALL',delay=12}},source='authored QA'}
  local tosses=0;local rawSound=Sound.play
  Sound.play=function(d,name,...)
    local source=rawSound(d,name,...)
    if name=='Ball_Toss' and source then tosses=tosses+1 end
    return source
  end
  pulse('up');pulse('left');pulse('down');pulse('a')
  check(settle(function()return Stack:top()~=battle end),tag..' actual ITEM command opens the bag')
  shot('bag')
  for frame=1,300 do
    if frame%16==0 then Input:sourcePress('a','battle-actions-qa')
    elseif frame%16==1 then Input:sourceRelease('a','battle-actions-qa')end
    step();render()
    local st=battle.animPlayer.steps[battle.animPlayer.stepIndex]
    if tosses>0 and battle.animPlaying and st and #st.sprites==4 then break end
  end
  Input:sourceRelease('a','battle-actions-qa')
  Sound.play=rawSound
  check(tosses==1 and Game.save.inventory.POKE_BALL==1,
    tag..' actual ball use retains its original toss sound and consumes exactly one ball')
  local st=battle.animPlayer.steps[battle.animPlayer.stepIndex]
  check(st and #st.sprites==4 and st.sprites[1].ts=='QA_BALL',
    tag..' capture renders the actual four-tile ball after tileset-load delay')
  shot('capture-toss')
  local metrics=P.metrics(Renderer:frameRects())
  local scene=Renderer.battleSceneCanvas
  local px,py=P.effectPoint(metrics,30,96)
  check(scene and scene:getHeight()>py+7,
    tag..' widened field keeps the complete first throw below old144px canvas edge')
  local pixels=scene:newImageData()
  local opaque=0
  for y=math.floor(py)-7,math.floor(py)+7 do for x=math.floor(px)-7,math.floor(px)+7 do
    local _,_,_,a=pixels:getPixel(x,y)
    if a>.9 then opaque=opaque+1 end
  end end
  check(opaque>80,tag..' actual extended scene contains visible first-ball pixels')
  result.capture={tossSounds=tosses,remainingBalls=Game.save.inventory.POKE_BALL}
  return result
end
