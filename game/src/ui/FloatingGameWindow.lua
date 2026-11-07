-- The native page keeps its own input/update owner and pixel coordinates.
-- Render the field/battle underneath once per open/resize, then reuse it.
local F={stats={captures=0}}
local cache
local ids={PartyMenu=true,SummaryMenu=true,SlotMachine=true,PokedexMenu=true,
  DexEntryMenu=true,TownMap=true,TrainerCard=true}
function F.context(game)
  if not require('src.ui.GameUILayout').enabled(game) then return end
  local stack=game.stack
  if not (stack and stack.states and stack.visibleBase)then return end
  local base=stack:visibleBase();local state=stack.states[base]
  local function page(s)return s and (s.floatingGameWindow or ids[s.screenId])end
  if not page(state)then return end
  local under,root
  for i=base-1,1,-1 do
    local s=stack.states[i]
    if s==game.overworld or s.isBattleState then under=i;break end
  end
  if not under then return end
  for i=under+1,base do if page(stack.states[i])then root=stack.states[i];break end end
  return {root=root,under=under,page=state}
end
function F.release()
  if cache and cache.canvas then cache.canvas:release()end
  cache=nil
end
function F.prepare(game,draw)
  local ctx=F.context(game)
  if not ctx then F.release();return end
  local g=love.graphics
  local w,h=g.getDimensions();local pw,ph=w,h
  if g.getPixelDimensions then pw,ph=g.getPixelDimensions()end
  if cache and cache.game==game and cache.root==ctx.root and cache.w==w and cache.h==h
      and cache.pw==pw and cache.ph==ph then return cache.canvas end
  F.release()
  local ok,canvas=pcall(g.newCanvas,w,h)
  cache={game=game,root=ctx.root,w=w,h=h,pw=pw,ph=ph}
  if not ok then return end
  canvas:setFilter('nearest','nearest')
  -- A read-only rendering view. The live stack is never replaced, entered,
  -- updated or popped: paused battle queues and callbacks retain ownership.
  local view=setmetatable({states={}}, {__index=game.stack})
  for i=1,ctx.under do view.states[i]=game.stack.states[i]end
  local viewport=require('src.render.GameViewport')
  local previous=viewport.outputTarget
  g.push('all');viewport.setOutputTarget(canvas)
  g.setCanvas(canvas);g.clear(0,0,0,1)
  local rendered,err=xpcall(function()draw(view)end,debug.traceback)
  viewport.setOutputTarget(previous);g.pop()
  if not rendered then
    canvas:release();F.error=err
    require('src.core.Logger').warn('floating page backdrop: %s',tostring(err))
    return
  end
  cache.canvas=canvas;F.stats.captures=F.stats.captures+1;F.error=nil
  return canvas
end
function F.drawBackdrop(canvas,r)
  local g=love.graphics
  local viewport=require('src.render.GameViewport')
  local rect=viewport.active() and viewport.rect
  g.push('all');g.origin();g.setShader();g.setBlendMode('alpha','premultiplied')
  g.setScissor(r.vux,r.vuy,r.vuw,r.vuh);g.setColor(1,1,1,1)
  g.draw(canvas,rect and -rect.x or 0,rect and -rect.y or 0)
  g.setBlendMode('alpha','alphamultiply')
  g.setColor(.02,.025,.04,.32);g.rectangle('fill',r.vux,r.vuy,r.vuw,r.vuh)
  local sx,sy=r.Ux,r.Uy
  -- Outside the native page: never cover a glyph, cursor, reel or HP bar.
  g.setColor(0,0,0,.28)
  g.rectangle('fill',r.uox+3*sx,r.uoy+4*sy,r.uvpw+3*sx,r.uvph+3*sy)
  g.setColor(.10,.13,.16,1)
  g.rectangle('fill',r.uox-2*sx,r.uoy-2*sy,r.uvpw+4*sx,r.uvph+4*sy)
  g.setColor(.94,.94,.87,1)
  g.rectangle('fill',r.uox-sx,r.uoy-sy,r.uvpw+2*sx,r.uvph+2*sy)
  g.pop()
end
return F
