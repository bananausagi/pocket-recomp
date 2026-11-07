package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('JP battle picture and FX presentation')
local Battle=require('src.battle.BattleState')
local P=require('src.battle.BattlePresentation')
local img
local b=setmetatable({data={pokemon={},battle_sprite_scales={}},
  player={sprite='back',mon={species='TEST'},isPlayer=true},
  enemy={sprite='front',mon={species='TEST'}},
  picImage=function()return img end},{__index=Battle})
local function frame(compact)
  local r={pw=compact and 800 or 480,ph=compact and 480 or 800,dpiX=1,dpiY=1,
    vux=0,vuy=0,vuw=480,vuh=800,uiw=160,uih=144,
    body={x=0,y=0,w=compact and 800 or 480,h=compact and 290 or 610}}
  P.frame(r,1);return P.metrics(r)
end
for _,size in ipairs({28,40,56,64})do
  img={getWidth=function()return size end,getHeight=function()return size end}
  for _,side in ipairs({'player','enemy'})do
    local x,y,w,h=b:pictureAnchor(side)
    local scale=Battle.resolveBattleScale(b.data,side=='player' and 'back' or 'front',side=='player' and 'back' or 'front','TEST')
    T.eq(w,size*scale,side..' picture uses actual artwork scale')
    if side=='player' then
      local left,top=Battle.backPlacement(size,size,0,0,scale)
      T.eq(x,left+w/2,'native/pinned back centre follows original placement')
      T.eq(y,top+h,'native/pinned back baseline follows original placement')
    end
    for _,compact in ipairs({false,true})do
      local m=frame(compact);local a=m.actor[side]
      local s=P.pictureScale(m,side,w,h,true)
      local l=a.x-m.native.x-w*s/2
      T.check(l>=-1e-8 and l+w*s<=160+1e-8,'whole '..side..' picture fits native surface')
      T.eq(l+w*s/2,a.x-m.native.x,'whole '..side..' picture centres on FX anchor')
      T.check(a.y-m.native.y-h*s>=-1e-8,'whole '..side..' picture clears top')
    end
  end
end
-- Check actual OAM drawing, including an unaligned tile spanning four SGB
-- cells. Moving tile centres must not change source-zone palette selection.
local Anim=require('src.battle.AnimPlayer')
local shader={send=function()end}
package.loaded['src.render.PaletteFX']={shader=function()return shader end}
local anim=Anim.new({})
anim.sheetImage=function()return {} end;anim.tileQuad=function()return {} end
local sprite={x=35,y=75,tile=0,ts='QA',xf=true,yf=true}
local function record(project)
  local draws,cells,clips={},{},{}
  local g=love.graphics
  g.draw=function(_,_,x,y,rot,sx,sy)draws[#draws+1]={x,y,rot,sx,sy}end
  g.getScissor=function()return nil end
  g.intersectScissor=function(x,y,w,h)clips[#clips+1]={x,y,w,h}end
  g.setScissor=function()end
  anim:drawSprites({sprite,{x=0,y=16,ts='QA',tile=0}},function(_,x,y)
    cells[#cells+1]={x,y};return {{x/160,y/144,0},{.4,.4,.4},{1,1,1}}
  end,project)
  return draws,cells,clips
end
local d0,c0,s0=record()
local d1,c1,s1=record(function(x,y)return x+13,y-7 end)
T.eq(#d0,4,'unaligned OAM tile draws four original attribute slices')
T.eq(#d1,#d0,'projection preserves OAM hardware clipping and slice count')
for i=1,#d0 do
  T.eq(d1[i][1],d0[i][1]+13,'FX moves horizontally as one original-size tile')
  T.eq(d1[i][2],d0[i][2]-7,'FX moves vertically as one original-size tile')
  T.eq(d1[i][4],-1,'horizontal mirror remains original 1x')
  T.eq(d1[i][5],-1,'vertical mirror remains original 1x')
  T.eq(c1[i][1],c0[i][1],'source SGB X cell is unchanged')
  T.eq(c1[i][2],c0[i][2],'source SGB Y cell is unchanged')
end
for i=1,#s0 do
  T.eq(s1[i][1],s0[i][1]+13,'palette slice X follows tile shift')
  T.eq(s1[i][2],s0[i][2]-7,'palette slice Y follows tile shift')
  T.eq(s1[i][3],8,'palette slice keeps eight original pixels')
  T.eq(s1[i][4],8,'palette slice keeps square artwork')
end
T.eq(sprite.x,35,'presentation never mutates source OAM X')
T.eq(sprite.y,75,'presentation never mutates source OAM Y')
T.finish()
