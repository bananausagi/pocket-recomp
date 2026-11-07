-- One composition for the battle scene, its original animation coordinates,
-- status panels and lower controls. All rectangles below are native pixels.
local Presentation = {}

function Presentation.active(battle)
  local game=battle and battle.game
  return game and game.renderer and game.data and game.data.constants
    and game.data.constants.language=='ja' and not battle.blankForAskName
end

function Presentation.frame(r, value, spacing)
  local Layout=require('src.ui.GameUILayout')
  -- Scene projection, status and commands share one centred composition.
  -- Only visible controls reserve space. Invisible navigation areas must
  -- not shift the fight away from the centre. Retain OS safe insets.
  local viewport={x=r.vux,y=r.vuy,w=r.vuw,h=r.vuh}
  local b=Layout.usable(true,viewport)
  if not b.touchReserved then
    -- Centre the visible battle on the display, not on a one-sided inset.
    -- Make the safe fitting rectangle symmetric around that centre. This
    -- still protects cutouts, including after rotation, without moving the
    -- whole fight down by half the top inset. Visible thumb controls keep
    -- their own usable rectangle; invisible touch areas reserve no space.
    local cx,cy=viewport.x+viewport.w/2,viewport.y+viewport.h/2
    local halfW=math.min(cx-b.x,b.x+b.w-cx)
    local halfH=math.min(cy-b.y,b.y+b.h-cy)
    if halfW>0 and halfH>0 then
      b={x=cx-halfW,y=cy-halfH,w=2*halfW,h=2*halfH,touchReserved=false}
    end
  end
  -- Thumb artwork can leave fractional edges. Snap the shared bounds inward
  -- once so the final panel clamp cannot move only the HUD off the camera.
  local bx,by=math.ceil(b.x*r.dpiX-1e-9),math.ceil(b.y*r.dpiY-1e-9)
  local ex,ey=math.floor((b.x+b.w)*r.dpiX+1e-9),math.floor((b.y+b.h)*r.dpiY+1e-9)
  b.x,b.y,b.w,b.h=bx/r.dpiX,by/r.dpiY,math.max(1,ex-bx)/r.dpiX,math.max(1,ey-by)/r.dpiY
  local physicalW,physicalH=b.w*r.dpiX,b.h*r.dpiY
  local base=math.max(1,math.floor(math.min(r.pw/160,r.ph/144)))
  local fit=math.max(1,math.floor(math.min(physicalW/160,physicalH/216)))
  local compactFit=math.max(1,math.floor(math.min(physicalW/160,physicalH/160)))
  local compact=physicalW>physicalH and compactFit>fit
  if compact then fit=compactFit end
  if spacing~='normal' and spacing~='wider' then spacing='wide' end
  local spread=spacing=='normal' and 0 or spacing=='wider' and 2 or 1
  local touchCommands=require("src.core.JapaneseTouchMode").enabled(require("src.core.Game"))
  local commandHeight=(compact and 48 or 64)+(touchCommands and 20 or 0)
  -- The spacing setting separates the participants, not just the status
  -- boxes. Keep the closest setting familiar; each step adds enough ground
  -- to read clearly between the foreground back pic and the opponent.
  local fieldHeight=compact and 112+16*spread or 128+24*spread
  -- Start at the first visible status panel. Counting transparent top
  -- padding as part of the group leaves its visible centre below the screen
  -- centre even when the canvas itself is centred. SafeArea owns the inset.
  local top=0
  -- Small windows change the text density, not the size of the battlers.
  -- Fit the requested field plus the separate command band at the user's
  -- original integer glyph scale. Only the scene may use
  -- a fractional fit: losing a few pixels to thumb buttons must not shrink
  -- every battler from three times to twice its native size.
  local windowScale=math.max(1,math.min(Layout.windowScale(base,value),fit))
  local scale=math.max(1,math.min(physicalW/160,
    (math.floor(physicalH/windowScale)-commandHeight)*windowScale/(top+fieldHeight)))
  r.Up,r.Ux,r.Uy=scale,scale/r.dpiX,scale/r.dpiY
  r.body=b
  local width=math.max(160,math.floor(physicalW/scale/8)*8)
  local panelWidth=math.max(160,math.floor(physicalW/windowScale/8)*8)
  local panelCommandY=math.ceil((top+fieldHeight)*scale/windowScale-1e-9)
  local panelHeight=panelCommandY+commandHeight
  local height=panelHeight*windowScale/scale
  local x=math.floor((b.x+(b.w-width*r.Ux)/2)*r.dpiX+1e-9)/r.dpiX
  local y=math.floor((b.y+(b.h-panelHeight*windowScale/r.dpiY)/2)*r.dpiY+1e-9)/r.dpiY
  local nx=math.floor((width-160)/2)
  local commandY=panelCommandY*windowScale/scale
  local ny=top
  local px,py,ex,ey=42,fieldHeight,124,compact and 56 or 72
  local gap=8+spread*24
  -- Keep the original compact white windows centred as the scene expands.
  local commandWidth=math.min(panelWidth,160+2*gap)
  local commandX=math.floor((panelWidth-commandWidth)/2)
  local panels={width=panelWidth,height=panelHeight,scale=windowScale,
    sx=windowScale/r.dpiX,sy=windowScale/r.dpiY,compact=compact,spacing=spacing,
    x=math.floor((b.x+(physicalW-panelWidth*windowScale)/2/r.dpiX)*r.dpiX+1e-9)/r.dpiX,y=y,
    touchCommands=touchCommands,
    command={x=commandX,y=panelCommandY,w=commandWidth,h=commandHeight},
    enemyHUD={x=commandX,y=0,w=80,h=40},
    playerHUD={x=commandX+commandWidth-80,y=panelCommandY-40,w=80,h=40}}
  local function sceneRect(rect)
    return {x=(panels.x-x)/r.Ux+rect.x*windowScale/scale,
      y=rect.y*windowScale/scale,w=rect.w*windowScale/scale,h=rect.h*windowScale/scale}
  end
  r.battlePresentation={width=width,height=height,scale=scale,sx=r.Ux,sy=r.Uy,x=x,y=y,compact=compact,spacing=spacing,
    panels=panels,windowScale=windowScale,
    command=sceneRect(panels.command),
    enemyHUD=sceneRect(panels.enemyHUD),playerHUD=sceneRect(panels.playerHUD),
    field={x=nx,y=ny,w=160,h=fieldHeight},
    viewportField={x=0,y=0,w=width,h=commandY},
    actor={player={x=nx+px,y=ny+py},enemy={x=nx+ex,y=ny+ey}},
    native={x=nx,y=ny,scale=1}}
  r.uox,r.uoy=x+nx*r.Ux,y+ny*r.Uy
  r.uvpw,r.uvph=r.uiw*r.Ux,r.uih*r.Uy
end

-- Transform animation positions only: AnimPlayer maps the shared centre of
-- each frame block and preserves the tile offsets inside its artwork. This
-- continuous mapping carries a whole capture ball between the new feet
-- without shearing its halves or changing anchors halfway through its path.
function Presentation.effectPoint(m,x,y)
  local actors=m.sceneLens and m.sceneLens.actors or m.actor
  local p,e=actors.player,actors.enemy
  local t=(x-26)/98
  return p.x-m.native.x+t*(e.x-p.x),
    y+p.y-m.native.y-96+t*((e.y-m.native.y-56)-(p.y-m.native.y-96))
end

function Presentation.pictureScale(m,side,w,h,nativeSurface)
  local a=m.actor[side]
  local x=a.x-m.native.x
  local height=a.y-(nativeSurface and m.native.y or 0)
  local limit=side=='enemy' and (m.compact and 54 or 72) or (m.compact and 84 or 96)
  -- A tall/narrow back picture must also fit below the opposite status
  -- window. The status has its own glyph scale, so a fixed height cap is
  -- insufficient on short screens or with the largest window preference.
  if side=='player' and m.enemyHUD then
    limit=math.min(limit,math.max(1,a.y-m.enemyHUD.y-m.enemyHUD.h-4))
  end
  local sideRoom=side=='player' and m.playerHUD
    and math.max(1,2*(m.playerHUD.x-a.x-2))/math.max(1,w) or math.huge
  return math.min(side=='player' and 3 or 1.5,limit/math.max(1,h),sideRoom,
    2*math.min(x,160-x)/math.max(1,w),height/math.max(1,h))
end

function Presentation.metrics(r)
  if not r.battlePresentation then Presentation.frame(r,1) end
  return r.battlePresentation
end

-- Film-plane translation in clip coordinates. The 3D arena uses the same
-- native centre as the original 2D move/capture animation, including touch
-- reservations and screen positioning. Scaling remains uniform.
function Presentation.filmOffset(r)
  local m=Presentation.metrics(r)
  local cx=(m.x+m.native.x*m.sx+80*m.sx-r.vux)*r.dpiX
  local cy=(m.y+m.native.y*m.sy+72*m.sy-r.vuy)*r.dpiY
  return 2*cx/r.pw-1,2*cy/r.ph-1
end

return Presentation
