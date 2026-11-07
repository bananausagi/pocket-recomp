package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('jp48 battle center and DPI')
local P=require('src.battle.BattlePresentation')
local L=require('src.ui.GameUILayout')
local Safe=require('src.core.SafeArea')
local Touch=require('src.core.TouchControls')
Touch.visible=function()return false end
for _,size in ipairs({{320,480},{972,1536},{2160,3414},{1536,1160},{800,480}})do
  local w,h=size[1],size[2]
  for _,dpi in ipairs({{1,1},{1.25,1.5},{2,2}})do
    for _,inset in ipairs({0,16})do
      Safe.windowRect=function()return inset,inset,w-2*inset,h-3*inset end
      for _,factor in ipairs({.375,.75,1.5})do
        for _,spacing in ipairs({'normal','wide','wider'})do
          local r={pw=w*dpi[1],ph=h*dpi[2],dpiX=dpi[1],dpiY=dpi[2],
            vux=0,vuy=0,vuw=w,vuh=h,uiw=160,uih=144}
          P.frame(r,factor,spacing)
          local m,p=r.battlePresentation,r.battlePresentation.panels
          local x,y,_,_,sx,sy=L.place(r,{anchor='battlePresentation',w=p.width,h=p.height})
          local top=y+p.enemyHUD.y*sy;local bottom=y+(p.command.y+p.command.h)*sy
          local cx=x+(p.command.x+p.command.w/2)*sx
          T.check(math.abs(cx-w/2)*dpi[1]<1.01 and math.abs((top+bottom)/2-(h-inset)/2)*dpi[2]<1.01,
            'visible composition centers inside actual safe area')
          T.check(top>=inset-.01 and bottom<=h-2*inset+.01,'visible bounds fit safe edges')
          T.check(math.abs(x-p.x)<.01 and math.abs(y-p.y)<.01,'placement does not reclamp the composition')
          T.check(math.abs(m.sx*dpi[1]-m.sy*dpi[2])<1e-8,'anisotropic DPI preserves battler proportions')
          T.check(p.scale==math.floor(p.scale) and math.abs(sx*dpi[1]-sy*dpi[2])<1e-8,'glyphs remain square physical pixels')
          for _,side in ipairs({'enemy','player'})do
            local ax,ay=P.effectPoint(m,side=='player' and 26 or 124,side=='player' and 96 or 56)
            T.check(math.abs(ax+m.native.x-m.actor[side].x)<1e-8
              and math.abs(ay+m.native.y-m.actor[side].y)<1e-8,'attack endpoints retain battler anchors')
            for _,wh in ipairs({{28,28},{40,56},{56,56},{64,64}})do
              local scale=P.pictureScale(m,side,wh[1],wh[2],true)
              local a=m.actor[side];local left,top=a.x-wh[1]*scale/2,a.y-wh[2]*scale
              T.check(top>=m.native.y-1e-8,'complete battler fits below safe top')
              for _,hud in ipairs({m.enemyHUD,m.playerHUD})do
                T.check(not (left<hud.x+hud.w and left+wh[1]*scale>hud.x
                  and top<hud.y+hud.h and a.y>hud.y),'battler remains clear of status windows')
              end
            end
          end
        end
      end
    end
  end
end
T.finish()
