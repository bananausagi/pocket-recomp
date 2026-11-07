package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Japanese battle presentation')
local P=require('src.battle.BattlePresentation')
local Cam=assert(loadfile('vendor/jp-mods/DRAMALESS_SHAPE/lib/BattleCameraBlend.lua'))()
for _,size in ipairs({{320,480},{972,1536},{2160,3414},{1536,1160},{800,480},{800,320}})do
  for _,dpi in ipairs({{1,1},{1.25,1.5},{2,2}})do
    for _,factor in ipairs({.5,.75,1})do
      local W,H=size[1],size[2]
      local r={pw=W*dpi[1],ph=H*dpi[2],dpiX=dpi[1],dpiY=dpi[2],vux=0,vuy=0,vuw=W,vuh=H,uiw=160,uih=144,
        body={x=4,y=12,w=W-8,h=math.max(160,H-180)}}
      local previousScale
      for _,spacing in ipairs({'normal','wide','wider'})do
      P.frame(r,factor,spacing);local m=P.metrics(r)
      if previousScale then T.eq(m.scale,previousScale,'spacing never resizes glyphs')end
      previousScale=m.scale
      T.check(math.abs(r.Ux*dpi[1]-r.Uy*dpi[2])<1e-8,'anisotropic DPI never stretches the scene')
      T.eq(m.panels.sx*dpi[1],m.panels.sy*dpi[2],'anisotropic DPI never stretches glyphs')
      T.check(m.x>=r.body.x and m.x+m.width*m.sx<=r.body.x+r.body.w+.001,'canvas fits body width')
      T.check(m.y>=r.body.y-.001 and m.y+m.height*m.sy<=r.body.y+r.body.h+.001,'canvas fits body height')
      T.check(m.command.y>=m.native.y+m.field.h-1e-8 and
        (m.command.y-m.native.y-m.field.h)*m.scale<m.windowScale+.001,
        'back sprite bottom meets the command surface within one glyph pixel')
      T.check(m.actor.enemy.y<=m.playerHUD.y,'enemy feet never intersect player status')
      T.check(m.enemyHUD.x+m.enemyHUD.w<=m.native.x+96,'enemy status stays beside front sprite')
      T.check(math.abs(m.playerHUD.y+m.playerHUD.h-m.command.y)<1e-8,'player status meets command surface')
      T.eq(m.command.x,m.enemyHUD.x,'lower window starts at enemy status outer edge')
      T.check(math.abs(m.command.x+m.command.w-m.playerHUD.x-m.playerHUD.w)<1e-8,'lower window ends at player status outer edge')
      T.check(math.abs(m.x+(m.command.x+m.command.w/2)*m.sx-(r.body.x+r.body.w/2))*r.dpiX<1.001,
        'lower window remains horizontally centred')
      T.check(m.panels.command.w>=160 and m.panels.command.w<=208,'lower window retains native dialogue capacity without stretching')
      T.check(math.abs((m.y+m.height*m.sy/2)-(r.body.y+r.body.h/2))*r.dpiY<1.001,'whole battle group is centred')
      T.check(m.panels.enemyHUD.y>=2,'top frame has a native safe inset')
      T.eq(m.panels.scale,math.floor(m.panels.scale),'window font retains integer physical pixels')
      T.check(m.scale>=m.panels.scale,'small window preference never shrinks the scene below the text')
      T.eq(m.actor.player.y-m.actor.enemy.y,m.compact and 56 or ({normal=56,wide=64,wider=72})[spacing],'actors keep selected vertical separation')
      for _,side in ipairs({'player','enemy'})do
        for _,wh in ipairs({{28,28},{40,56},{56,56},{64,64},{128,128}})do
          local sc=P.pictureScale(m,side,wh[1],wh[2],true)
          local a=m.actor[side];local x=a.x-m.native.x
          T.check(x-wh[1]*sc/2>=-1e-8 and x+wh[1]*sc/2<=160+1e-8,
            side..' wide artwork fits native horizontal surface')
          T.check(a.y-m.native.y-wh[2]*sc>=-1e-8,side..' full artwork fits native top')
          for _,hud in ipairs({m.enemyHUD,m.playerHUD})do
            local left,top=a.x-wh[1]*sc/2,a.y-wh[2]*sc
            local overlap=left<hud.x+hud.w and left+wh[1]*sc>hud.x
              and top<hud.y+hud.h and a.y>hud.y
            T.check(not overlap,side..' complete head and body clear both HUDs')
          end
        end
      end
      for _,side in ipairs({'player','enemy'})do
        local x,y=P.effectPoint(m,side=='player' and 26 or 124,side=='player' and 96 or 56)
        T.eq(x,m.actor[side].x-m.native.x,'FX endpoint X meets '..side)
        T.eq(y,m.actor[side].y-m.native.y,'FX endpoint Y meets '..side)
      end
      local fx,fy=P.filmOffset(r)
      T.check(math.abs((fx+1)*r.pw/2-(r.uox+80*r.Ux-r.vux)*r.dpiX)<1e-8,'3D and native FX share centre X')
      T.check(math.abs((fy+1)*r.ph/2-(r.uoy+72*r.Uy-r.vuy)*r.dpiY)<1e-8,'3D and native FX share centre Y')
      end
    end
  end
end
local function same(a,b)
  for _,k in ipairs({'eye','focus','up'})do for i=1,3 do if math.abs(a[k][i]-b[k][i])>1e-9 then return false end end end
  return math.abs(a.fov-b.fov)<1e-9
end
local a={eye={16,100,20},focus={16,0,20},up={0,0,-1},fov=.8,filmX=0,filmY=0,curve=.02}
local b={eye={60,15,50},focus={32,0,20},up={0,1,0},fov=.45,filmX=.2,filmY=.25,curve=0}
T.check(same(Cam.mix(a,b,0),a),'entry first frame preserves actual world pose')
T.check(same(Cam.mix(a,b,1),b),'entry endpoint reaches canonical battle pose')
local prev=Cam.mix(a,b,0)
for i=1,60 do
  local p=Cam.mix(a,b,i/60)
  local finite=true;for _,k in ipairs({'eye','focus','up'})do for j=1,3 do finite=finite and p[k][j]==p[k][j] and math.abs(p[k][j])<1000 end end
  T.check(finite,'camera frame '..i..' stays finite')
  T.check(math.abs(p.eye[1]-prev.eye[1])<5 and math.abs(p.eye[2]-prev.eye[2])<5,'camera frame '..i..' is continuous')
  prev=p
end
local opposite={eye={16,-100,20},focus={16,0,20},up={0,1,0},fov=.8}
local mid=Cam.mix(a,opposite,.5)
local d=0;for i=1,3 do d=d+(mid.eye[i]-mid.focus[i])^2 end
T.check(d>9900,'opposite view directions never pass through focus')
Cam.returnFrom(b,.4)
T.check(same(Cam.applyReturn(a),b),'return starts at last battle camera')
Cam.update(.2);T.check(Cam.active() and not same(Cam.applyReturn(a),a),'return has an intermediate pose')
Cam.update(.2);T.check(same(Cam.applyReturn(a),a) and not Cam.active(),'return restores live world camera')
T.eq(a.eye[1],16,'source pose never mutated')
T.eq(b.filmY,.25,'destination film offset never mutated')
T.finish()
