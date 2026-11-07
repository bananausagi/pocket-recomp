-- Focused actual-GL probes after the separate real-audio handoff assertions.
-- Fixed presentation times make the 360ms leap observable even on llvmpipe.
return function(V,battle,cast,walker,tag,render,check,write)
  local g=love.graphics
  local Host=V.require('VoxelBattleStandalone')
  local Cards=V.require('VoxelBattleCardProvider')
  local V3=V.require('Voxel3D')
  local Motion=V.require('WildEncounterMotion')
  local context=Host.session.context
  local arena=context.arena
  local rawTime,rawDraw=love.timer.getTime,V3.draw
  local rawHostDraw,insideHost=Host.draw,false
  local revealAt,back,picOff=arena.wildRevealAt,battle.showPlayerBack,battle.picOff
  local pinned=V.backSpritesSetting:get()
  local sessionCast,prepared=Host.session.cast,Host.session.prepared
  local nativePicOffset=battle.picOffset
  local rows,draws={},{}
  local mesh=V.require('BattleBillboard').mesh()
  local now=100
  love.timer.getTime=function()return now end
  Host.draw=function(...)
    insideHost=true
    local result=rawHostDraw(...)
    insideHost=false
    return result
  end
  V3.draw=function(m,texture,model,...)
    if insideHost and (m==mesh or texture==walker) then
      local r,b,c,a=g.getColor()
      local copy={};for i,v in ipairs(model or {})do copy[i]=v end
      draws[#draws+1]={card=m==mesh,alpha=a,model=copy}
    end
    return rawDraw(m,texture,model,...)
  end
  local function draw(label)
    draws={};Cards:update(context)
    local pixels=render()
    if label then write(label..'-'..tag..'.png',pixels:encode('png'):getString())end
    return draws
  end
  local ok,err=xpcall(function()
    V.backSpritesSetting:sync(false)
    battle.showPlayerBack=false
    arena.wildRevealAt=100
    local first,last,peak
    for _,t in ipairs({0,.09,.18,.27,.36,.72})do
      now=100+t
      local samples=draw((t==0 or t==.18 or t==.72) and ('wild-hop-'..t) or nil)
      local card
      for _,sample in ipairs(samples)do if sample.card then card=sample;break end end
      check(card and card.card,'wild hop draws a real enemy GL billboard at '..t..'s '..tag)
      local m=card.model
      local y=m[6]/3+m[8] -- texture anchor (80,96), in the real billboard
      local image=battle:picImage(battle.enemy.sprite)
      local top=(144-96+image:getHeight())/144
      local _,screenTop=V3.project(m[2]*top+m[4],m[6]*top+m[8],m[10]*top+m[12])
      local scale=math.sqrt(m[1]^2+m[5]^2+m[9]^2)
      rows[#rows+1]={time=t,footY=y,scale=scale,alpha=card.alpha,screenTop=screenTop}
      check(screenTop and screenTop>=1.99,'wild emergence keeps its complete head below viewport top '..t..'s '..tag)
      if t==0 then first=rows[#rows]elseif t==.18 then peak=rows[#rows]elseif t==.72 then last=rows[#rows]end
    end
    check(math.abs(first.footY-last.footY)<1e-5 and peak.footY>last.footY,
      'wild leap rises above its encounter ground and lands at the exact native feet '..tag)
    check(math.abs(first.scale/last.scale-.84)<1e-5 and first.alpha==1,
      'first cry frame already has a visible enemy; emergence grows from84 percent '..tag)
    check(math.abs(rows[5].footY-last.footY)<1e-5 and math.abs(rows[5].scale-last.scale)<1e-5,
      'hop has zero residual offset/scale from360ms onward '..tag)
    local retreats={}
    battle.showPlayerBack=true
    for _,offset in ipairs({0,-18,-36,-54,-68,-72})do
      battle.picOff={back={x=offset,to=-72,step=4}}
      local samples=draw((offset==0 or offset==-36 or offset==-72) and ('trainer-fade-'..(-offset)) or nil)
      local player,n=nil,0
      for _,sample in ipairs(samples)do
        if sample.card then n=n+1;if n==2 then player=sample;break end end
      end
      check(player and player.card,'trainer retreat retains the actual back card until native removal '..offset..' '..tag)
      retreats[#retreats+1]={offset=offset,alpha=player.alpha}
      check(battle:picOffset('back')==offset and battle.picOffset==nativePicOffset,
        'capturing intact trainer restores the original native slide state '..offset..' '..tag)
    end
    check(retreats[1].alpha==1 and retreats[#retreats].alpha==0
      and retreats[3].alpha==.5 and retreats[5].alpha<.01,
      'native trainer retreats through half-opacity and fully fades before removal '..tag)
    Host.session.cast=cast;Host.session.prepared=true
    local castRows={}
    for _,progress in ipairs({0,.12,.29,.46,1})do
      Host.session.cast=function()cast(Motion.castAlpha(progress,1))end
      local samples=draw((progress==0 or progress==.29 or progress==1) and ('map-player-fade-'..progress) or nil)
      local player
      for _,sample in ipairs(samples)do if not sample.card then player=sample end end
      castRows[#castRows+1]={progress=progress,alpha=player and player.alpha or 0}
    end
    check(castRows[1].alpha==1 and castRows[2].alpha==1
      and math.abs(castRows[3].alpha-.5)<1e-5 and castRows[4].alpha==0 and castRows[5].alpha==0,
      'actual overworld GL cast fades during camera travel and is absent well before handoff '..tag)
    write('wild-motion-'..tag..'.json',assert(require('src.link.Json').encode({hop=rows,
      trainer=retreats,overworld=castRows,clock='deterministic presentation probes; separate Source clock checks unchanged'})))
  end,debug.traceback)
  love.timer.getTime,V3.draw=rawTime,rawDraw
  Host.draw=rawHostDraw
  arena.wildRevealAt=revealAt
  battle.showPlayerBack,battle.picOff=back,picOff
  Host.session.cast,Host.session.prepared=sessionCast,prepared
  V.backSpritesSetting:sync(pinned)
  Cards:update(context)
  if not ok then error(err,0)end
end
