-- Opt-in direct touch navigation. A release is accepted only by the state,
-- phase and viewport that owned its press. Drags never become confirm taps.
local T={}
local Input=require('src.core.Input')
local Areas=require('src.core.JapaneseTouchAreas')
local function areaOptions(game)return game and game.save and game.save.options and game.save.options.jpTouchAreas end
local function now()return love.timer.getTime()end
local function viewport()
  local r=require('src.render.GameViewport').rect
  if r then return r.x,r.y,r.width,r.height end
  local w,h=love.graphics.getDimensions();return 0,0,w,h
end
local function sameViewport(p)
  local x,y,w,h=viewport()
  return p.vx==x and p.vy==y and p.vw==w and p.vh==h
end
function T.configured(game)
  local o=game and game.save and game.save.options
  return o and (o.jpTouchOptimized==true or o.jpTouchOptimized=='buttons')
    and not (o.touchControls and o.touchControls.enabled==false)
    and game.data and game.data.constants and game.data.constants.language=='ja'
    and not require('src.core.TouchSkin').active
end
function T.buttons(game)
  return T.configured(game) and game.save.options.jpTouchOptimized=='buttons'
end
function T.enabled(game)
  return T.configured(game) and not game.sessionMenu
end
function T.field(game)
  return T.enabled(game) and game.overworld and game.stack
    and game.stack:top()==game.overworld and not game.overworld.transitioning
end
function T.stamp(game,x,y)
  local w,h=love.graphics.getDimensions()
  local top=game.stack and game.stack:top()
  local vx,vy,vw,vh=viewport()
  return {top=top,revision=game.stack and game.stack.pointerRevision,
    mode=game.save.options.jpTouchOptimized,map=game.overworld and game.overworld.map,phase=top and top.phase,
    current=top and top.current,menu=top and top.menu,submenu=top and top.submenu,session=game.sessionMenu,w=w,h=h,x=x,y=y,time=now(),
    vx=vx,vy=vy,vw=vw,vh=vh,areasKey=Areas.key(areaOptions(game)),slop=math.max(12,math.min(w,h)*.035)}
end
function T.sameContext(game,p)
  local w,h=love.graphics.getDimensions()
  local top=game.stack and game.stack:top()
  return T.configured(game) and game.sessionMenu==p.session and top==p.top and p.revision==(game.stack and game.stack.pointerRevision)
    and p.map==(game.overworld and game.overworld.map) and p.phase==(top and top.phase)
    and p.current==(top and top.current) and p.menu==(top and top.menu) and p.submenu==(top and top.submenu) and p.w==w and p.h==h and sameViewport(p)
    and p.mode==game.save.options.jpTouchOptimized and p.areasKey==Areas.key(areaOptions(game))
end
function T.valid(game,p)return T.enabled(game) and T.sameContext(game,p)end
function T.track(p,x,y)
  if (x-p.x)^2+(y-p.y)^2>p.slop^2 then p.dragged=true end
end
function T.flick(p,x,y)
  -- Android may coalesce all motion into the release event.
  T.track(p,x,y)
  local dx,dy=x-p.x,y-p.y
  -- One boundary separates a stable tap from a swipe. There is no band
  -- where finger wobble cancels a tap but is too small to move the cursor.
  if dx*dx+dy*dy<=p.slop*p.slop then return end
  return math.abs(dx)>=math.abs(dy) and (dx>0 and 'right' or 'left') or (dy>0 and 'down' or 'up')
end

-- A held movement pointer survives an adjacent map swap or the actual warp
-- transition immediately above its own overworld. Other stack changes still
-- cancel it, including a dialogue opened and closed between two input ticks.
function T.keepMovement(game,p)
  local w,h=love.graphics.getDimensions()
  local ow=game.overworld;local stack=game.stack
  if not T.enabled(game) or ow~=p.top or w~=p.w or h~=p.h or not sameViewport(p) or not stack
      or p.mode~=game.save.options.jpTouchOptimized or p.areasKey~=Areas.key(areaOptions(game)) then return false end
  local top=stack:top();local revision=stack.pointerRevision
  if top==ow then
    if p.transition then
      if not p.transition.done or revision~=(p.revision or 0)+1 then return false end
      p.transition=nil;p.revision=revision
    elseif revision~=p.revision then return false end
    if ow.map~=p.map or ow.transitioning then
      if not p.dragged then return false end
      p.map=ow.map
    end
    return true
  end
  if not p.dragged or not ow.transitioning or stack.states[#stack.states-1]~=ow
      or getmetatable(top)~=require('src.render.Transition') then return false end
  if p.transition then return top==p.transition and revision==p.revision end
  if revision~=(p.revision or 0)+1 then return false end
  p.transition=top;p.revision=revision
  return true
end
function T.isTap(p,x,y,slop)
  slop=slop or p.slop
  return not p.dragged and (not p.tapTimeout or now()-p.time<=p.tapTimeout)
    and (x-p.x)^2+(y-p.y)^2<=slop*slop
end
function T.tap(game,p,x,y,slop)return T.valid(game,p) and T.isTap(p,x,y,slop)end
function T.key(button)
  Input:sourcePress(button,'jp-touch-tap');Input:sourceRelease(button,'jp-touch-tap')
end
function T.confirm()T.key('a')end

-- Resolve the ordinary A interaction first. Only its no-target branch may
-- open the menu, and only during the input tick that owns this field tap.
function T.fieldTap(game,p)
  p.inputQueue=Input.pressQueue
  game.jpFieldTapPending=p
  T.confirm()
end
function T.beginFieldTapStep(game)
  local p=game.jpFieldTapPending
  game.jpFieldTapPending=nil;game.jpFieldTapActive=nil
  if p and p.inputQueue==game.input.pressQueue and T.field(game) and T.valid(game,p) then
    game.jpFieldTapActive=p
  end
end
function T.emptyFieldTap(game,ow)
  local p=game.jpFieldTapActive
  game.jpFieldTapActive=nil
  if not p or not T.field(game) or not T.valid(game,p) or ow~=game.overworld
      or not game.input:wasPressed('a') or ow.player.moving or ow.player.inputLocked then return end
  require('src.core.Sound').play(game.data,'Start_Menu')
  game:openSessionMenu()
end

-- Invisible areas follow the user's independent portrait/landscape layouts.
function T.navigation(game)
  return Areas.navigation(areaOptions(game or package.loaded['src.core.Game']))
end
function T.navHit(x,y,game)
  game=game or package.loaded['src.core.Game']
  for _,r in ipairs(T.navigation(game))do
    if x>=r.x and y>=r.y and x<r.x+r.w and y<r.y+r.h then
      local top=game and game.stack and game.stack:top()
      -- A visible choice always owns its tap, even beneath a custom area.
      if game and not game.sessionMenu then
        if T.battleCell(game,top,x,y)~=nil or require('src.ui.JapaneseTouchTargets').hit(game,x,y) then return end
        if top and top.floatingPanel and type(top.hit)=="function" and top:hit(x,y) then return end
        local panel=top and top.windowPanel
        if panel and panel.contentHit and panel:contentHit(x,y) then return end
      end
      return r.id
    end
  end
end
function T.navigate(game,control)
  if control=='touch-back' then T.key('b')
  elseif control=='touch-menu' then game:openSessionMenu('touch')end
end
local function battle(top)
  return top and type(top.chooseMenu)=='function' and type(top.chooseMove)=='function'
end
function T.battleSurface(game,top)
  if not battle(top) or top.demo or top.jpEncounterAwaitDraw
      or (top.introSlide or 0)>0 or top.blankForAskName then return end
  local phase=top.phase
  if phase~='menu' and phase~='moveSelect' and phase~='mimicSelect' then return end
  if top.bottomUIVisible and not top:bottomUIVisible() then return end
  local r=game.renderer and game.renderer:frameRects()
  if not r then return end
  -- Use the renderer's placement, including its exact-pixel display path.
  -- That path still draws the JP panel canvas but places it with native UI
  -- scales rather than the expanded battle frame.
  local m=r and r.battlePresentation
  local p,x,y,sx,sy
  if m then
    p=m.panels or m
    local dw,dh
    x,y,dw,dh,sx,sy=require('src.ui.GameUILayout').place(r,
      {anchor='battlePresentation',w=p.width,h=p.height})
  elseif require('src.battle.BattlePresentation').active(top) then
    x,y,sx,sy=r.uox,r.uoy,r.Ux,r.Uy
    m=require('src.battle.BattlePresentation').metrics(r);p=m.panels or m
  else return end
  x=math.max(r.vux,math.min(math.max(r.vux,r.vux+r.vuw-p.width*sx),x))
  y=math.max(r.vuy,math.min(math.max(r.vuy,r.vuy+r.vuh-p.height*sy),y))
  return {x=x,y=y,sx=sx,sy=sy,width=p.width,height=p.height,
    cells=require('src.battle.JapaneseBattlePanels').touchCells(p,phase),
    commands=require('src.battle.JapaneseBattlePanels').touchCommands(p,phase)}
end
local function sameSurface(a,b)
  if not a or not b then return false end
  for _,k in ipairs({'x','y','sx','sy','width','height'})do if a[k]~=b[k] then return false end end
  for i,c in ipairs(a.cells)do
    local d=b.cells[i]
    if not d or c.x~=d.x or c.y~=d.y or c.w~=d.w or c.h~=d.h then return false end
  end
  return true
end
local function cellAt(top,surface,x,y)
  if not surface then return end
  local lx,ly,inside=require('src.render.GameViewport').toLocal(x,y)
  if not inside then return end
  lx,ly=(lx-surface.x)/surface.sx,(ly-surface.y)/surface.sy
  for i,c in ipairs(surface.cells)do
    if lx>=c.x and ly>=c.y and lx<c.x+c.w and ly<c.y+c.h then
      if top.phase=='moveSelect' and not (top.player and top.player.curMoves[i]) then return false end
      if top.phase=='mimicSelect' and not (top.mimicMoves and top.mimicMoves[i]) then return false end
      return i
    end
  end
end
function T.battleCell(game,top,x,y)return cellAt(top,T.battleSurface(game,top),x,y)end
local function moveAt(top,i)
  if not i then return end
  if top.phase=='moveSelect' then return top.player and top.player.curMoves[i] end
  if top.phase=='mimicSelect' then return top.mimicMoves and top.mimicMoves[i] end
end
function T.previewBattleCell(game,top)
  if not T.enabled(game) then return end
  for _,p in pairs(game.jpTapPointers or {})do
    if not p.ignored and not p.dragged and p.cell and p.top==top and T.valid(game,p)
        and sameSurface(p.surface,T.battleSurface(game,top)) then return p.cell end
  end
end
function T.pressed(game,id,x,y)
  if not T.enabled(game) then return false end
  local _,_,inside=require('src.render.GameViewport').toLocal(x,y)
  if not inside and not require('src.ui.JapaneseTouchTargets').hit(game,x,y) then return false end
  local pointers=game.jpTapPointers or {};game.jpTapPointers=pointers
  local p=T.stamp(game,x,y)
  p.ignored=next(pointers)~=nil
  p.target=require('src.ui.JapaneseTouchTargets').hit(game,x,y)
  p.surface=T.battleSurface(game,p.top)
  p.cell=cellAt(p.top,p.surface,x,y);p.move=moveAt(p.top,p.cell)
  pointers[id]=p
  return true
end
function T.moved(game,id,x,y)
  local p=game.jpTapPointers and game.jpTapPointers[id]
  if not p then return false end
  T.track(p,x,y)
  return true
end
function T.released(game,id,x,y)
  local p=game.jpTapPointers and game.jpTapPointers[id]
  if not p then return false end
  game.jpTapPointers[id]=nil
  if p.ignored or not T.valid(game,p) then return true end
  if p.target and not require('src.ui.JapaneseTouchTargets').current(game,p.target) then return true end
  local direction=T.flick(p,x,y)
  if p.dragged then
    -- Menus and name entry keep the native four-way cursor. A swipe moves
    -- one step and can never also confirm a command when the finger lifts.
    if direction and not T.field(game) then T.key(direction)end
    return true
  end
  if not T.tap(game,p,x,y,p.slop) then return true end
  local top=p.top
  local H=require('src.ui.JapaneseTouchTargets')
  if p.target then H.queue(game,p);return true end
  if battle(top) then
    if top.demo then return true end
    if top.phase=='messages' then T.confirm();return true end
    local surface=T.battleSurface(game,top)
    if not sameSurface(p.surface,surface) then return true end
    if p.cell and p.move==moveAt(top,p.cell) then
      -- Capture the pressed target through small finger drift, including
      -- a nearby cell boundary. Only a real swipe releases that ownership.
      local i=p.cell
      require('src.core.Sound').play(top.data,'Press_AB')
      if top.phase=='menu' then
        top.menuIndex=i
        if top.safari then top:chooseSafari(({'ball','bait','rock','run'})[i])
        else top:chooseMenu(({'fight','party','item','run'})[i])end
      elseif top.phase=='moveSelect' then
        top.moveIndex=i
        if top.moveSwapIndex then top:swapMoves(top.moveSwapIndex,i);top.moveSwapIndex=nil
        else top:chooseMove(i)end
      elseif top.phase=='mimicSelect' then top:chooseMimic(i)end

    end
  elseif T.field(game) then T.fieldTap(game,p)
  else
    local f=H.frameFor(game)
    if not f or #f.targets==0 then T.confirm()end
  end
  return true
end
function T.cancel(game)
  game.jpPendingTouchChoice=nil;game.jpTapPointers=nil;game.jpFieldTapPending=nil;game.jpFieldTapActive=nil
end
return T
