-- SPDX-License-Identifier: GPL-3.0-only
-- One native-pixel battle overlay. Scene framing and hit coordinates belong to
-- BattlePresentation; this module only presents the live battle records.
local Font = require('src.render.Font')
local HudTiles = require('src.render.HudTiles')
local Strings = require('src.core.Strings')
local Growth = require('src.pokemon.Growth')
local TypeChart = require('src.battle.TypeChart')
local LevelDisplay = require('src.ui.LevelDisplay')
local Panels = {}
local C = {
  paper={1,1,1,1}, edge={0,0,0,1},
  ink={0,0,0,1}, muted={0,0,0,1}, accent={0,0,0,1},
  track={0.72,0.72,0.72,1}, green={0.31,0.87,0.56,1},
  amber={1,0.77,0.29,1}, red={1,0.38,0.40,1}, xp={0,0,0,1},
  empty={0.75,0.75,0.75,1}, fainted={0.35,0.35,0.35,1},
}
Panels.colors=C
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function finite(v,default)
  v=tonumber(v)
  if not v or v~=v or v==math.huge or v==-math.huge then return default end
  return v
end

-- Display truncation follows the loaded font's complete spans (including
-- composed kana); no nickname, move id, or save record is rewritten.
function Panels.fit(text,pixels)
  text=tostring(text or '')
  local spans=Font.split(text)
  local n=Font.spansFitting(spans,math.max(0,pixels))
  if n>=#spans then return text end
  local suffix=Font.width('..')<=pixels and '..' or ''
  n=Font.spansFitting(spans,math.max(0,pixels-Font.width(suffix)))
  return (n>0 and text:sub(1,spans[n].to) or '')..suffix
end

function Panels.health(battler)
  local mon=battler.mon or {}
  local actual=math.max(0,finite(mon.hp,0))
  local shown=finite(battler.shownHP,actual)
  shown=shown>actual and math.ceil(shown) or math.floor(shown)
  local maximum=math.max(1,math.floor(finite(mon.stats and mon.stats.hp,1)))
  shown=clamp(shown,0,maximum)
  -- The battle's animation advances the original 48-pixel HP counter. Use
  -- that same progress for this bar so damage and the low-HP warning agree.
  local ratio=battler.shownPx~=nil and finite(battler.shownPx,0)/48 or shown/maximum
  return shown,maximum,clamp(ratio,0,1)
end

function Panels.experience(battle,battler)
  local mon=battler.mon or {}
  local level=clamp(math.floor(finite(mon.level,1)),1,100)
  if level>=100 then return 1 end
  local data=battle.data or {}
  local species=data.pokemon and data.pokemon[mon.species] or battler.def or {}
  local lo=Growth.expForLevel(species.growthRate,level,data.growth_rates)
  local hi=Growth.expForLevel(species.growthRate,level+1,data.growth_rates)
  if hi<=lo then return 0 end
  return clamp((finite(mon.exp,lo)-lo)/(hi-lo),0,1)
end

-- These exact rectangles also serve the host's pointer/gamepad navigation.
function Panels.cells(m,phase)
  local r=m.command
  local gap,pad=4,8
  local width=math.floor((r.w-2*pad-gap)/2)
  local top=m.compact and 4 or ((phase=='moveSelect' or phase=='mimicSelect') and 8 or 24)
  local cells={}
  for i=1,4 do
    cells[i]={x=r.x+pad+((i-1)%2)*(width+gap),
      y=r.y+top+math.floor((i-1)/2)*16,w=width,h=16}
  end
  return cells
end

-- Fill the inner command band up to the midpoint between the visible
-- labels. The column gap and side padding are touchable, while the prompt
-- and PP/type description stay outside the four choices.
function Panels.touchCells(m,phase)
  local r=m.command;local cells=Panels.cells(m,phase)
  local left,right,mid=r.x+3,r.x+r.w-3,r.x+r.w/2
  local top,split=cells[1].y,cells[1].y+20
  local bottom=r.y+r.h-4
  if phase=='moveSelect' or phase=='mimicSelect' then
    bottom=math.min(cells[3].y+20,r.y+(m.compact and 36 or 44))
  end
  return {{x=left,y=top,w=mid-left,h=split-top},
    {x=mid,y=top,w=right-mid,h=split-top},
    {x=left,y=split,w=mid-left,h=bottom-split},
    {x=mid,y=split,w=right-mid,h=bottom-split}}
end

function Panels.touchCommands(m,phase)
  if not m.touchCommands or phase~='moveSelect' then return {} end
  local r=m.command;local width=(r.w-16)/2
  return {{id='back',label='もどる',key='b',x=r.x+4,y=r.y+r.h-22,w=width,h=18},
    {id='arrange',label='いれかえ',key='select',x=r.x+8+width,y=r.y+r.h-22,w=width,h=18}}
end

local function rect(x,y,w,h,color)
  if w<=0 or h<=0 then return end
  love.graphics.setColor(color)
  love.graphics.rectangle('fill',math.floor(x),math.floor(y),math.floor(w),math.floor(h))
end
local function frame(r)
  -- Original-style black double rule on completely opaque white paper.
  -- A narrow, stepped corner keeps this inside the existing compact HUD;
  -- the full eight-pixel Font.drawBox border would cover its HP/XP rows.
  rect(r.x,r.y,r.w,r.h,C.paper)
  for _,inset in ipairs({0,2}) do
    local x,y,w,h=r.x+inset,r.y+inset,r.w-2*inset,r.h-2*inset
    rect(x+2,y,w-4,1,C.edge);rect(x+2,y+h-1,w-4,1,C.edge)
    rect(x,y+2,1,h-4,C.edge);rect(x+w-1,y+2,1,h-4,C.edge)
    rect(x+1,y+1,1,1,C.edge);rect(x+w-2,y+1,1,1,C.edge)
    rect(x+1,y+h-2,1,1,C.edge);rect(x+w-2,y+h-2,1,1,C.edge)
  end
end
local function bar(x,y,w,h,ratio,color)
  rect(x,y,w,h,C.track)
  local fill=ratio>0 and math.max(1,math.floor(w*clamp(ratio,0,1))) or 0
  rect(x,y,fill,h,color)
end
local function queue(runs,text,x,y,color,width)
  if width then text=Panels.fit(text,width) end
  runs[#runs+1]={text=text,x=math.floor(x),y=math.floor(y),color=color or C.ink}
end
local function code(runs,glyph,x,y,color,clip)
  runs[#runs+1]={code=glyph,x=math.floor(x),y=math.floor(y),color=color or C.ink,clip=clip}
end
local function right(runs,text,rightX,y,color,width)
  if width then text=Panels.fit(text,width) end
  queue(runs,text,rightX-Font.width(text),y,color)
end
local function hpColor(ratio)
  return ratio<10/48 and C.red or ratio<24/48 and C.amber or C.green
end

local function statusPanel(battle,battler,r,player,runs)
  frame(r)
  local name=tostring(battler.name or battler.mon.nickname or '')
  local status=battler.shownStatus and battle:statusLabel({status=battler.shownStatus}) or ''
  local showLevel=LevelDisplay.visible(battler.mon,player and 'battle.player' or 'battle.enemy',battle.game)
  local level=tostring(battler.mon.level or 1)
  local nameWidth=r.w-16
  local caught=not player and battle.caughtMarkerVisible and battle:caughtMarkerVisible()
  if caught then nameWidth=nameWidth-8 end
  if player then
    -- The player's card ends above the command band without covering the
    -- enemy's feet. Match the original compact level/status slot, including
    -- level 100's three digits taking the place of the level prefix.
    local compactLevel=showLevel and status=='' and r.w<88 and (battler.mon.level or 1)<100
    local meta=status~='' and Panels.fit(status,24)
      or showLevel and (((battler.mon.level or 1)>=100 or compactLevel) and level or 'Lv'..level) or ''
    if meta~='' then
      local width=Font.width(meta)+(compactLevel and 8 or 0)
      nameWidth=math.max(0,r.w-12-width-4)
      right(runs,meta,r.x+r.w-8,r.y+12,C.ink,32)
      if compactLevel then
        -- The battle overlay's one-tile level sign leaves five kana intact
        -- in an 80px panel. Font's ordinary JP $6e is a different glyph.
        runs[#runs+1]={hudCode=0x6E,x=r.x+r.w-8-width,y=r.y+12,color=C.ink}
      end
    end
  else
    if showLevel then queue(runs,'Lv'..level,r.x+8,r.y+26,C.ink,r.w-16) end
    if status~='' then right(runs,status,r.x+r.w-8,r.y+26,C.ink,24) end
  end
  queue(runs,name,r.x+(player and 4 or 8),r.y+12,C.ink,nameWidth)
  if caught then
    -- jp.63: a 7 x 7 Poke Ball after the name (red top, white bottom, black
    -- rim and band with a white button), the "already caught" mark.
    local bx,by=r.x+r.w-15,r.y+12
    local rows={'..###..','.#RRR#.','#RRRRR#','###W###','#WWWWW#','.#WWW#.','..###..'}
    for yy=1,7 do for xx=1,7 do
      local ch=rows[yy]:sub(xx,xx)
      if ch~='.' then rect(bx+xx-1,by+yy-1,1,1,ch=='#' and C.edge or ch=='R' and C.red or C.paper) end
    end end
  end
  local hp,maxHP,ratio=Panels.health(battler)
  bar(r.x+8,r.y+(player and 24 or 35),r.w-16,1,ratio,hpColor(ratio))
  if player then
    local numbers=tostring(hp)..'/'..tostring(maxHP)
    if Font.width(numbers)<=r.w-32 then queue(runs,'HP',r.x+8,r.y+26,C.ink) end
    right(runs,numbers,r.x+r.w-8,r.y+26,C.ink,r.w-16)
    bar(r.x+8,r.y+35,r.w-16,1,Panels.experience(battle,battler),C.xp)
  end
end

local function partyPanel(party,r,runs)
  frame(r)
  for i=1,6 do
    local mon=party and party[i]
    if mon and mon.mon then mon=mon.mon end
    local x=r.x+8+(i-1)*12
    local color=not mon and C.empty or (mon.hp or 0)<=0 and C.fainted or C.ink
    rect(x+1,r.y+17,6,6,color);rect(x,r.y+18,8,4,color)
    rect(x,r.y+20,8,1,C.paper);rect(x+3,r.y+19,2,3,C.paper)
  end
end

local function hud(battle,m,runs)
  if battle.fieldCleared or (battle.introSlide or 0)~=0 then return end
  local visible=not battle.statusHUDVisible or battle:statusHUDVisible()
  if visible and battle.enemy and not battle.showEnemyTrainer and not battle.enemySendingOut
      and not battle.enemyHudPending and not battle.introBalls and not battle.enemy.fainted
      and not (battle.growInScale and battle:growInScale(battle.enemy)) then
    statusPanel(battle,battle.enemy,m.enemyHUD,false,runs)
  elseif battle.showEnemyBalls or (battle.introBalls and (battle.kind=='trainer' or battle.kind=='link')) then
    partyPanel(battle.enemyParty,m.enemyHUD,runs)
  end
  if visible and battle.player and not battle.safari and not battle.demo
      and not battle.showPlayerBack and not battle.player.fainted and not battle.introBalls then
    statusPanel(battle,battle.player,m.playerHUD,true,runs)
  elseif battle.introBalls then
    local party=battle.playerPartyView and battle:playerPartyView()
      or battle.playerParty or battle.game and battle.game.save and battle.game.save.party
    partyPanel(party,m.playerHUD,runs)
  end
end

local function selectionCell(r,label,selected,swap,runs,offset,pressed)
  if pressed then rect(pressed.x,pressed.y,pressed.w,pressed.h,{.88,.88,.88,1}) end
  local y=r.y+8+(offset or 0)
  if selected or swap then code(runs,selected and 0xED or 0xEC,r.x+2,y,C.ink) end
  queue(runs,label,r.x+12,y,C.ink,r.w-14)
end

local function moves(battle,m,runs)
  for _,a in ipairs(Panels.touchCommands(m,battle.phase))do
    queue(runs,a.label,a.x+4,a.y+5,C.ink,a.w-8)
  end
  local mimic=battle.phase=='mimicSelect'
  local moves=mimic and battle.mimicMoves or battle.player and battle.player.curMoves or {}
  local pressed=require('src.core.JapaneseTouchMode').previewBattleCell(battle.game,battle)
  local selected=pressed or (mimic and battle.mimicIndex or battle.moveIndex) or 1
  local cells=Panels.cells(m,battle.phase)
  local targets=pressed and Panels.touchCells(m,battle.phase)
  for i=1,4 do
    local move=moves and moves[i]
    local def=move and battle.data.moves[move.id]
    local label=move and (def and def.name or tostring(move.id)) or 'ー'
    selectionCell(cells[i],label,i==selected,
      not mimic and battle.moveSwapIndex==i and selected~=i,runs,
      m.compact and i>=3 and -1 or 0,pressed==i and targets[i])
  end
  local move=moves and moves[selected]
  local def=move and battle.data.moves[move.id]
  if not def then return end
  local r=m.command
  local detailY=r.y+(m.compact and 37 or 48)
  local maxPP=math.max(0,finite(def.pp,0)+(move.ppUps or 0)*math.floor(finite(def.pp,0)/5))
  local pp='PP '..tostring(math.max(0,math.floor(finite(move.pp,0))))..'/'..tostring(maxPP)
  right(runs,pp,r.x+r.w-8,detailY,C.ink,r.w-16)
  local detail=TypeChart.displayName(def.type,battle.data) or ''
  local category
  if not mimic and battle.player and battle.player.disabledSlot==selected then detail='かなしばり'
  elseif not mimic and battle.moveSwapIndex then detail='いれかえ'
  else
    local kind=def.category or ((def.power or 0)==0 and 'status') or TypeChart.category(def.type)
    category=kind=='status' and 'へんか' or kind=='physical' and 'ぶつり' or kind=='special' and 'とくしゅ'
  end
  local available=math.max(0,r.w-24-Font.width(pp))
  if category and available>=Font.width(category)+24 then
    local width=available-Font.width(category)-8
    queue(runs,detail,r.x+8,detailY,C.muted,width)
    queue(runs,category,r.x+16+width,detailY,C.muted)
  else queue(runs,detail,r.x+8,detailY,C.muted,available) end
end
local function commands(battle,m,runs)
  local r=m.command
  local prompt
  if battle.safari then prompt='のこり '..tostring(battle.safari.balls or 0)..'こ'
  elseif not battle.demo then
    prompt=Strings('What will %s do?',battle.player and battle.player.name or ''):gsub('\n',' ')
  end
  if prompt and not m.compact then queue(runs,prompt,r.x+8,r.y+12,C.ink,r.w-16) end
  local labels=battle.safari and {Strings('BALLx'),Strings('BAIT'),Strings('THROW ROCK'),Strings('RUN','battle')}
    or {Strings('FIGHT','battle'),'ポケモン',Strings('ITEM','battle'),Strings('RUN','battle')}
  local pressed=require('src.core.JapaneseTouchMode').previewBattleCell(battle.game,battle)
  local selected=pressed or (battle.demo and ((battle.demoTimer or 0)<=80 and 1 or 3)) or battle.menuIndex or 1
  local targets=pressed and Panels.touchCells(m,'menu')
  for i,cell in ipairs(Panels.cells(m,'menu')) do selectionCell(cell,labels[i],selected==i,false,runs,nil,pressed==i and targets[i]) end
end
local function messages(battle,m,runs)
  local r=m.command
  local clip={x=r.x+3,y=r.y+3,w=r.w-6,h=r.h-6}
  if battle.scrollPx and battle.scrollPx>0 then
    battle.scrollPx=battle.scrollPx-2
    if battle.scrollPx<=0 then battle.scrollPx=nil end
  end
  local offset=battle.scrollPx or 0
  for i,line in ipairs(battle.shown or {}) do
    local x=r.x+8
    for _,glyph in ipairs(line) do
      local lineY=m.compact and (i==1 and 12 or 28) or (i==1 and 24 or 40)
      if x+Font.advanceOf(glyph)<=r.x+r.w-8 then code(runs,glyph,x,r.y+lineY+offset,nil,clip) end
      x=x+Font.advanceOf(glyph)
    end
  end
  if (battle.msgWaiting or battle.msgPrompt) and (battle.frame or 0)%60<30 then
    code(runs,0xEE,r.x+r.w-16,r.y+(m.compact and 37 or 52),C.ink)
  end
end

function Panels.draw(battle,m)
  local g=love.graphics
  g.push('all')
  g.setShader();g.setBlendMode('alpha')
  local runs={}
  local messageDrawn=false
  hud(battle,m,runs)
  if not battle.bottomUIVisible or battle:bottomUIVisible() then
    frame(m.command)
    if battle.phase=='menu' then commands(battle,m,runs)
    elseif battle.phase=='moveSelect' or battle.phase=='mimicSelect' then moves(battle,m,runs)
    elseif battle.phase=='messages' and (battle.current or battle.animPlaying or battle.msgHold) then
      messages(battle,m,runs);messageDrawn=true
    end
  end
  -- Draw the player's extracted black ROM glyphs directly, at native size.
  local scissor={g.getScissor()}
  local previousClip
  for _,run in ipairs(runs) do
    if previousClip~=run.clip then
      if #scissor>0 then g.setScissor(unpack(scissor)) else g.setScissor() end
      if run.clip then
        local x,y=g.transformPoint(run.clip.x,run.clip.y)
        local x2,y2=g.transformPoint(run.clip.x+run.clip.w,run.clip.y+run.clip.h)
        g.intersectScissor(x,y,x2-x,y2-y)
      end
      previousClip=run.clip
    end
    g.setColor(run.color)
    if run.hudCode then HudTiles.tile(run.hudCode,run.x,run.y)
    elseif run.code then Font.drawCode(run.code,run.x,run.y)
    else Font.draw(run.text,run.x,run.y) end
  end
  g.pop()
  if messageDrawn and battle.acknowledgeIntroTextDrawn then
    battle:acknowledgeIntroTextDrawn()
  end
end

return Panels
