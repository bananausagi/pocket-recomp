-- Keep the native HUD artwork and its palette pass, but composite it apart
-- from the 3D arena. Animation sprites remain in the battle scene; extracting
-- rectangles from the finished battle would also move pieces of an attack.
local Layout={}

function Layout.active(battle)
  return require('src.battle.BattlePresentation').active(battle)
end

function Layout.draw(battle,slide,sx,sy)
  local g=love.graphics
  local r=battle.game.renderer
  local metrics=require('src.battle.BattlePresentation').metrics(r:frameRects())
  g.push('all')
  local scenePrevious=r:beginBattleScenePass(metrics)
  g.origin()
  g.setScissor(0,-metrics.native.y,160,metrics.native.y+metrics.field.h)
  for _,side in ipairs({'enemy','player'})do
    local a=metrics.actor[side]
    local oldX,oldY,picW,picH=battle:pictureAnchor(side)
    local scale=1
    if picW then
      scale=require('src.battle.BattlePresentation').pictureScale(metrics,side,
        picW,picH,true)
    end
    g.push()
    g.translate(a.x-metrics.native.x,a.y-metrics.native.y)
    g.scale(scale,scale);g.translate(-oldX,-oldY)
    battle:drawPicsLayer(slide,sx,sy,side,true)
    g.pop()
  end
  g.setScissor()
  battle:drawAnimLayer(battle:colorMode(),function(x,y)
    return require('src.battle.BattlePresentation').effectPoint(metrics,x,y)
  end)
  r:endBattleHUDPass(scenePrevious)
  g.pop()
  g.push('all')
  local panels=metrics.panels or metrics
  local previous=r:beginBattlePresentationPass(panels)
  g.origin();g.setScissor();g.setShader();g.setDepthMode('always',false)
  require('src.battle.JapaneseBattlePanels').draw(battle,panels)
  r:endBattleHUDPass(previous)
  g.pop()
  local overlay=r:beginBattleCommandPass()
  r:endBattleHUDPass(overlay)
  r.jpBattleCommands=metrics.field.h
end

function Layout.drawLegacy(battle,slide,sx,sy)
  local g=love.graphics
  local r=battle.game.renderer
  local color=battle:colorMode()
  local previous=r:beginBattleHUDPass()
  local P=require("src.render.PaletteFX")
  local mono=P.mode=="og" or P.mode=="og_inv" or P.mode=="classic" or P.forcesRawGrays()
  if color and not mono then
    g.setColor(P.paperShade(battle.data))
  else g.setColor(1,1,1,1) end
  local status=battle:statusHUDVisible()
  if slide==0 and not battle.fieldCleared then
    if (status and battle.enemy and not battle.showEnemyTrainer
        and not battle.enemySendingOut and not battle.enemyHudPending
        and not battle:growInScale(battle.enemy) and not battle.introBalls
        and not battle.enemy.fainted) or battle.showEnemyBalls
        or (battle.introBalls and battle.enemyParty) then
      g.rectangle("fill",0,0,96,40)
    end
    if (status and battle.player and not battle.safari and not battle.demo
        and not battle.showPlayerBack and not battle.player.fainted)
        or battle.introBalls then
      g.rectangle("fill",70,48,90,48)
    end
  end
  local function layer(draw)
    if color then
      local target=g.getCanvas()
      g.setCanvas(battle.bgCanvas);g.clear(0,0,0,0)
      draw()
      g.setCanvas(target)
      -- The HUD's own shake is retained by its primitives. A global screen
      -- shake belongs to the scene and must not fill transparent HUD margins.
      battle:drawZonePass(battle.bgCanvas,0,0)
    else
      draw()
    end
  end
  layer(function() battle:drawHUDs(slide) end)
  r:endBattleHUDPass(previous)
  r:setBattleUIAnchor(0,0,96,40,"battleEnemy")
  r:setBattleUIAnchor(64,48,96,48,"battlePlayer")

  -- The provider suppresses only the sprites it owns. Retain fallback pics
  -- and the stock attack/capture sprites in their original scene positions.
  g.setScissor(0,0,160,96)
  -- The move list now sits in its own lower panel, so its old native y=64
  -- scissor must no longer cut the back sprite in half.
  battle:drawPicsLayer(slide,sx,sy,nil,true)
  g.setScissor()
  battle:drawAnimLayer(color)
  local commandPrevious=r:beginBattleCommandPass()
  r.jpBattleMenu=battle.phase=="menu" and not battle.safari and not battle.demo
  layer(function() battle:drawTextArea() end)
  r:endBattleHUDPass(commandPrevious)
  r.jpBattleCommands=(battle.phase=="moveSelect" or battle.phase=="mimicSelect")
    and 48 or 96
end

return Layout
