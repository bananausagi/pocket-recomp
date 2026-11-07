-- Pixel-sized game windows placed in the usable playfield, above touch
-- controls. The world camera and its zoom never depend on this geometry.
local Layout={}
local SafeArea=require("src.core.SafeArea")
local Viewport=require("src.render.GameViewport")
local UIScale=require("src.ui.JapaneseUIScale")

local function intersect(x,y,w,h,bx,by,bw,bh)
  local ex,ey=math.min(x+w,bx+bw),math.min(y+h,by+bh)
  x,y=math.max(x,bx),math.max(y,by)
  return x,y,math.max(1,ex-x),math.max(1,ey-y)
end

-- Window-space artwork bounds, not the wider touch hit slop. The normal
-- controls keep all artwork within w/2; a selected skin owns its geometry.
-- Read the live layout so orientation, editor dragging and scale apply at once.
function Layout.touchBounds()
  local Touch=require("src.core.TouchControls")
  if not (Touch.visible and Touch:visible()) then return {} end
  local game=require('src.core.Game')
  if Touch:optimized() and game.sessionMenu then return {} end
  local out={}
  local function add(x,y,w,h)
    if type(x)=="number" and type(y)=="number" and type(w)=="number" and type(h)=="number"
        and x==x and y==y and w>0 and h>0 and w<math.huge and h<math.huge then
      out[#out+1]={x=x,y=y,w=w,h=h}
    end
  end
  local Skin=require("src.core.TouchSkin")
  if Skin.active then
    local page=Skin.page()
    if page then
      local w,h,x,y=Touch.surfaceRect()
      for _,c in ipairs(page.controls or {}) do
        local cx,cy,hw,hh=Skin.controlGeometry(page,c,w,h,x,y)
        add(cx-hw,cy-hh,hw*2,hh*2)
      end
    end
  elseif Touch:optimized() then
    if Touch:optimizedButtons() then
      for _,name in ipairs({'a','b'})do
        local c=Touch:layout()[name];add(c.cx-c.w*.65,c.cy-c.w*.65,c.w*1.3,c.w*1.3)
      end
      -- jp.59: START/SELECT are shown in this mode too (half-height rubber keys).
      for _,name in ipairs({'start','select'})do
        local c=Touch:layout()[name];add(c.cx-c.w/2,c.cy-c.w*.25,c.w,c.w*.5)
      end
    end
    -- Invisible, freely placed gesture areas reserve no visual space.
    -- Visible choices take precedence over them in pointer routing.
  elseif Touch.layout then
    local controls=Touch:layout()
    for _,name in ipairs({"dpad","a","b","start","select"}) do
      local c=controls[name]
      if c and c.cx and c.cy and c.w then
        local h=c.h or c.w
        add(c.cx-c.w/2,c.cy-h/2,c.w,h)
      end
    end
    if Touch.hotbarShown and Touch:hotbarShown() then
      local c=controls.hotbar
      if c then add(c.cx-c.w*.58,c.cy-c.w*.58,c.w*1.16,c.w*1.16) end
      if Touch.hotbarOpen and not Touch.preview then
        for _,c in ipairs(Touch:hotbarStrip() or {}) do add(c.x,c.y,c.w,c.h) end
      end
    end
  end
  return out
end

local usableCache={}
local function copyRect(r)
  return {x=r.x,y=r.y,w=r.w,h=r.h,touchReserved=r.touchReserved}
end

-- Select a continuous empty rectangle. Portrait normally keeps the full
-- width above the controls; landscape can use the taller central corridor
-- between the thumb buttons instead of throwing away the whole lower band.
-- Maximise the native page's readable scale first, then useful area, with a
-- small preference for horizontal centring. There is no arbitrary minimum
-- height that can silently put a window back on top of a moved button.
local function emptyRect(b, obstacles)
  local xs={b.x,b.x+b.w}
  for _,c in ipairs(obstacles) do xs[#xs+1]=c.x;xs[#xs+1]=c.x+c.w end
  table.sort(xs)
  local edges={}
  for _,x in ipairs(xs) do if x~=edges[#edges] then edges[#edges+1]=x end end
  table.sort(obstacles,function(a,c)return a.y<c.y end)
  local best,bestScore
  local function consider(x,y,w,h)
    if w<1 or h<1 then return end
    local fit=math.min(w/160,h/144)
    local dx=math.abs(x+w/2-(b.x+b.w/2))/b.w
    local dy=math.abs(y+h/2-(b.y+b.h/2))/b.h
    local score=fit+.15*w*h/(b.w*b.h)-.1*dx-.025*dy
    if not bestScore or score>bestScore then
      best,bestScore={x=x,y=y,w=w,h=h,touchReserved=true},score
    end
  end
  for i=1,#edges-1 do for j=i+1,#edges do
    local left,right=edges[i],edges[j]
    local top=b.y
    for _,c in ipairs(obstacles) do
      if c.x<right and c.x+c.w>left then
        consider(left,top,right-left,c.y-top)
        top=math.max(top,c.y+c.h)
      end
    end
    consider(left,top,right-left,b.y+b.h-top)
  end end
  -- Fully covered custom layouts cannot fit a readable page; retain a valid
  -- rectangle rather than feeding a zero/negative surface into the renderer.
  return best or b
end

function Layout.usable(localSpace, bounds)
  local x,y,w,h=SafeArea.windowRect()
  local pad=math.max(2,math.min(6,math.min(w,h)*.008))
  local ox,oy=0,0
  if localSpace then
    x,y,w,h=Viewport.localSafeRect(x,y,w,h)
    if Viewport.active() and Viewport.rect then ox,oy=Viewport.rect.x,Viewport.rect.y end
  end
  if bounds then x,y,w,h=intersect(x,y,w,h,bounds.x,bounds.y,bounds.w,bounds.h) end
  local b={x=x,y=y,w=w,h=h,touchReserved=false}
  local obstacles,key={},{x,y,w,h,pad}
  for _,c in ipairs(Layout.touchBounds()) do
    local left,top=math.max(x,c.x-ox-pad),math.max(y,c.y-oy-pad)
    local right,bottom=math.min(x+w,c.x+c.w-ox+pad),math.min(y+h,c.y+c.h-oy+pad)
    if right>left and bottom>top then
      obstacles[#obstacles+1]={x=left,y=top,w=right-left,h=bottom-top}
      key[#key+1]=left;key[#key+1]=top;key[#key+1]=right;key[#key+1]=bottom
    end
  end
  if #obstacles==0 then return b end
  local space=localSpace and "local" or "window"
  key=table.concat(key,",")
  local cached=usableCache[space]
  if cached and cached.key==key then return copyRect(cached.rect) end
  local rect=emptyRect(b,obstacles)
  usableCache[space]={key=key,rect=rect}
  return copyRect(rect)
end

function Layout.windowScale(base,value)
  return UIScale.windowPixels(base,value)
end

function Layout.enabled(game)
  return game and game.data and game.data.constants
    and game.data.constants.language == "ja"
end

function Layout.metrics(rect, dx, dy, base, value, width, height)
  local margin=math.max(4,math.floor(math.min(rect.w*dx,rect.h*dy)*0.025))
  local fit=math.floor(math.min((rect.w*dx-2*margin)/(width or 160),
    (rect.h*dy-2*margin)/(height or 144)))
  return math.max(1,math.min(Layout.windowScale(base,value),math.max(1,fit))),margin
end

-- Keep the font independent of the world zoom and the camera's position.
-- Every ordinary page uses the same 160x144 baseline, including overlays.
function Layout.frame(r, value, page, centerPage, preferredScale)
  local rect=Layout.usable(true,{x=r.vux,y=r.vuy,w=r.vuw,h=r.vuh})
  -- Faithful mobile keeps its existing UI scale if it fits around the touch
  -- controls. Only the floating UI may step down; the world scale is separate.
  local base=preferredScale or math.max(1,math.floor(math.min(r.pw/160,r.ph/144)))
  local scale,margin=Layout.metrics(rect,r.dpiX,r.dpiY,base,preferredScale and 1 or value,
    r.uiw,math.max(144,r.uih))
  if preferredScale then
    local width,height=r.uiw,math.max(144,r.uih)
    local fit=math.floor(math.min(rect.w*r.dpiX/width,rect.h*r.dpiY/height))
    scale=math.min(preferredScale,math.max(1,fit))
    -- The usable rectangle already includes a gap around the buttons. Do
    -- not lose a whole pixel multiple solely to add another large margin.
    margin=math.max(0,math.min(margin,
      math.floor((rect.w*r.dpiX-width*scale)/2),
      math.floor((rect.h*r.dpiY-height*scale)/2)))
  end
  r.Up,r.Ux,r.Uy=scale,scale/r.dpiX,scale/r.dpiY
  r.uvpw,r.uvph=r.uiw*r.Ux,r.uih*r.Uy
  r.body,r.margin=rect,margin
  r.uox=math.floor((rect.x+(rect.w-r.uvpw)/2)*r.dpiX)/r.dpiX
  local y=page and not centerPage and rect.y+margin/r.dpiY or rect.y+(rect.h-r.uvph)/2
  r.uoy=math.floor(y*r.dpiY)/r.dpiY
end

function Layout.place(r,a)
  local b=r.body
  local battle=r.battlePresentation
  if battle and a.anchor=='battleScene' then
    local lens=battle.sceneLens
    local z=lens and lens.zoom or 1
    local x=battle.x+battle.native.x*battle.sx
    local y=battle.y+battle.native.y*battle.sy
    if lens then
      x=x+(1-z)*lens.x*battle.sx;y=y+(1-z)*lens.y*battle.sy
    end
    -- Scale the completed native picture/OAM surface once at output size.
    -- Palette scissors and whole multi-tile effects have already been drawn.
    return x,y,a.w*battle.sx*z,a.h*battle.sy*z,battle.sx*z,battle.sy*z
  end
  if battle and battle.panels and (a.anchor=='battlePresentation' or a.anchor=='battleOverlay') then
    local p=battle.panels
    local x,y=p.x,p.y
    if a.anchor=='battleOverlay' then
      x=x+((p.width-160)/2+a.x)*p.sx
      y=y+(p.command.y-96+a.y)*p.sy
    end
    local w,h=a.w*p.sx,a.h*p.sy
    return math.max(b.x,math.min(b.x+b.w-w,x)),
      math.max(b.y,math.min(b.y+b.h-h,y)),w,h,p.sx,p.sy
  end
  local mx,my=r.margin/r.dpiX,r.margin/r.dpiY
  local w,h=a.w*r.Ux,a.h*r.Uy
  local x,y=r.uox+a.x*r.Ux,r.uoy+a.y*r.Uy
  if a.anchor=="battlePresentation" and r.battlePresentation then
    local m=r.battlePresentation
    x,y=m.x,m.y
  elseif a.anchor=="battleOverlay" then
    -- Keep original 160px prompts/choices together at the command band's
    -- new baseline; their glyphs and relative overlap remain unchanged.
    if r.battlePresentation then y=y+(r.battlePresentation.field.h-96)*r.Uy end
  elseif a.anchor=="bottom" or a.anchor=="battleCommands" then
    y=b.y+b.h-my-(r.uih-a.y)*r.Uy
  elseif a.anchor=="battleMenu" then
    x=b.x+b.w-mx-w
    y=b.y+b.h-my-h
  elseif a.anchor=="topright" then
    x=b.x+b.w-mx-(r.uiw-a.x)*r.Ux
    y=b.y+my+a.y*r.Uy
  elseif a.anchor=="top" then
    y=b.y+my+a.y*r.Uy
  elseif a.anchor=="battleEnemy" then
    x,y=b.x+mx,b.y+my
  elseif a.anchor=="battlePlayer" then
    x=b.x+b.w-mx-w
    -- Keep a full dialogue below the player's status, even in short views.
    y=b.y+b.h-my-(r.battleBottomHeight or 48)*r.Uy-4*r.Uy-h
  end
  x=math.max(b.x,math.min(b.x+b.w-w,x))
  y=math.max(b.y,math.min(b.y+b.h-h,y))
  return math.floor(x*r.dpiX)/r.dpiX,math.floor(y*r.dpiY)/r.dpiY,w,h,r.Ux,r.Uy
end

-- The box may occupy only part of a 160x144 overlay (for example the pause
-- commands at 48,8,104,80). Position the visible box, not its unused canvas.
-- Large app panels keep integer 8px glyphs while using the available columns
-- and rows. This density is independent from the camera and world zoom.
function Layout.panelMetrics(game,opts)
  opts=opts or {}
  local g=love.graphics
  local ww,wh=g.getDimensions()
  local pw,ph=ww,wh
  if g.getPixelDimensions then pw,ph=g.getPixelDimensions() end
  local dx,dy=pw/math.max(1,ww),ph/math.max(1,wh)
  local rect=opts.rect or Layout.usable(false)
  local margin=math.max(8,math.floor(math.min(rect.w*dx,rect.h*dy)*0.03))
  local value=game and game.save and game.save.options and game.save.options.jpDialogScale
  -- App text follows the physical short edge, including high-DPI screens.
  -- The saved preference selects a readable density rather than multiplying
  -- an already-small scale. No fixed physical-pixel ceiling is appropriate.
  local scale=UIScale.panelPixels(math.min(pw,ph),value)
  local fit=math.floor(math.min((rect.w*dx-2*margin)/160,
    (rect.h*dy-2*margin)/(opts.minHeight or 112)))
  scale=math.max(1,math.min(scale,math.max(1,fit)))
  return {rect=rect,dpiX=dx,dpiY=dy,scale=scale,margin=margin,portrait=ph>pw,
    width=math.max(160,math.floor((rect.w*dx-2*margin)/scale/8)*8),
    height=math.max(112,math.floor((rect.h*dy-2*margin)/scale/8)*8)}
end

function Layout.overlay(game,opts)
  opts=opts or {}
  local g=love.graphics
  local ww,wh=g.getDimensions()
  local pw,ph=ww,wh
  if g.getPixelDimensions then pw,ph=g.getPixelDimensions() end
  local dx,dy=pw/math.max(1,ww),ph/math.max(1,wh)
  local rect=opts.rect or Layout.usable(false)
  local width,height=opts.width or 160,opts.height or 144
  local bx=opts.box and opts.box.x or 0
  local by=opts.box and opts.box.y or 0
  local bw=opts.box and opts.box.w or width
  local bh=opts.box and opts.box.h or height
  local value=game and game.save and game.save.options and game.save.options.jpDialogScale
  local base=math.max(1,math.floor(math.min(pw/160,ph/144)))
  local scale,margin=Layout.metrics(rect,dx,dy,base,value)
  if opts.scale then scale=math.max(1,math.floor(opts.scale)) end
  margin=opts.margin or margin
  local fit=math.floor(math.min((rect.w*dx-2*margin)/bw,(rect.h*dy-2*margin)/bh))
  scale=math.max(1,math.min(scale,math.max(1,fit)))
  local sx,sy=scale/dx,scale/dy
  local left=rect.x+(rect.w-bw*sx)/2
  local top=rect.y+margin/dy
  if opts.anchor=="topright" then left=rect.x+rect.w-margin/dx-bw*sx end
  if opts.anchor=="center" then top=rect.y+(rect.h-bh*sy)/2 end
  local x=math.floor((left-bx*sx)*dx)/dx
  local y=math.floor((top-by*sy)*dy)/dy
  return {x=x,y=y,w=width*sx,h=height*sy,sx=sx,sy=sy,dpiX=dx,dpiY=dy,
    scale=scale,width=width,height=height,rect=rect}
end

return Layout
