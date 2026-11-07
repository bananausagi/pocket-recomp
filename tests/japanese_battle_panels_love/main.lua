-- ROM-free authored font-page/terrain fixtures exercise the real Font and HUD.
local function run()
  local root,out=assert(os.getenv('JP_PANELS_ROOT')),assert(os.getenv('JP_PANELS_OUT'))
  package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
  local g,fs=love.graphics,love.filesystem
  g.setDefaultFilter("nearest","nearest")
  local T=require('tests.harness').suite('Japanese battle panels')
  local Json=require('src.link.Json')
  local manifest=Json.decode(fs.read('tools/rom_manifest_red_jp.json'))
  local map=Json.decode(fs.read('assets/fonts/misaki/glyphs.json'))
  local atlas=g.newImage('assets/fonts/misaki/misaki8x8.png');atlas:setFilter('nearest','nearest')
  local function fontPage(base,count,path)
    local canvas=g.newCanvas(128,count/16*8,{dpiscale=1})
    g.setCanvas(canvas);g.clear(0,0,0,0);g.setColor(0,0,0,1)
    local drawn={}
    local authored={[0xE4]=true,[0xE5]=true,[0xEC]=true,[0xED]=true,[0xEE]=true}
    for _,e in ipairs(manifest.fontCharmap)do
      if e.code>=base and e.code<base+count and map[e.seq] and not drawn[e.code] and not authored[e.code] then
        drawn[e.code]=true
        local i,n=map[e.seq],e.code-base
        g.draw(atlas,g.newQuad(i%128*8,math.floor(i/128)*8,8,8,atlas:getDimensions()),n%16*8,math.floor(n/16)*8)
      end
    end
    -- A cartridge page stores one base glyph per code. Voiced kana are
    -- composed by Font with a separate mark in the lower part of the tile
    -- above the baseline; an ordinary Unicode spacing mark sits too high.
    for _,value in ipairs({0xE4,0xE5})do
      if value>=base and value<base+count then
        local n=value-base;local x,y=n%16*8,math.floor(n/16)*8
        if value==0xE5 then
          for _,p in ipairs({{3,5},{4,6},{6,5},{7,6}})do g.rectangle('fill',x+p[1],y+p[2],1,1)end
        else
          for _,p in ipairs({{5,4},{4,5},{6,5},{5,6}})do g.rectangle('fill',x+p[1],y+p[2],1,1)end
        end
      end
    end
    -- Independently drawn hardware cursor slots for the selection regression.
    for _,code in ipairs({0xEC,0xED,0xEE})do
      if code>=base and code<base+count then
        local n=code-base;local x,y=n%16*8,math.floor(n/16)*8
        for row=0,5 do g.rectangle('fill',x,y+row,math.min(row+1,6-row),1)end
      end
    end
    g.setCanvas();fs.createDirectory('fixture');fs.write(path,canvas:newImageData():encode('png'));canvas:release()
  end
  fontPage(0x80,128,'fixture/font.png');fontPage(0x60,32,'fixture/extra.png')
  local data={constants={language='ja'},font={language='ja',image='fixture/font.png',imageExtra='fixture/extra.png',mainBase=0x80,extraBase=0x60,charmap=manifest.fontCharmap,composites=manifest.fontComposites},
    pokemon={FIX={growthRate='MEDIUM_FAST'}},moves={
      GROWL={name='なきごえ',type='NORMAL',pp=40,power=0},
      THUNDER={name='かみなりパンチ',type='ELECTRIC',pp=15,power=75},
      CUSTOM={name='がぎぐげご がぎぐげご',type='CUSTOM',pp=5,power=40},
      NORMAL={name='たいあたり',type='NORMAL',pp=35,power=35}},
    type_chart={types={CUSTOM={name='MOD 100%',category='special'}}}}
  local Font=require('src.render.Font');Font.load(data)
  -- Authored one-tile battle level sign. The ordinary JP $6e font code is
  -- small kana, so compact cards must resolve this through HudTiles.
  local hudPage=g.newCanvas(24,8,{dpiscale=1})
  g.setCanvas(hudPage);g.clear(0,0,0,0);g.setColor(0,0,0,1)
  g.rectangle('fill',8,1,1,6);g.rectangle('fill',8,6,3,1)
  g.rectangle('fill',12,3,1,3);g.rectangle('fill',14,3,1,3);g.rectangle('fill',13,6,1,1)
  g.setCanvas();fs.write('fixture/hud1.png',hudPage:newImageData():encode('png'));hudPage:release()
  data.font.pages={battle_hud_1={image='fixture/hud1.png',base=0x6D}}
  require('src.core.Data').font=data.font
  local HudTiles=require('src.render.HudTiles');HudTiles.invalidate()
  local Strings=require('src.core.Strings');Strings.load(data)
  local Status=require('src.battle.Status')
  local Panels=require('src.battle.JapaneseBattlePanels')
  local Presentation=require('src.battle.BattlePresentation')
  local Growth=require('src.pokemon.Growth')
  local player={name='ピカチュウ',shownHP=123,shownPx=35,mon={species='FIX',nickname='ピカチュウ',hp=123,level=50,exp=128000,stats={hp=168}},curMoves={{id='GROWL',pp=40},{id='THUNDER',pp=0,ppUps=3},{id='CUSTOM',pp=3},{id='NORMAL',pp=35}}}
  local enemy={name='フシギバナ',shownHP=100,mon={species='FIX',hp=100,level=55,stats={hp=160}}}
  local battle={data=data,player=player,enemy=enemy,phase='menu',menuIndex=1,moveIndex=1,frame=0,kind='wild'}
  battle.game={data=data,save={options={colors='classic'},party={player.mon}}}
  function battle:statusHUDVisible()return self.visible~=false end
  function battle:bottomUIVisible()return self.bottom~=false end
  function battle:statusLabel(mon)return Status.hudLabelFor(nil,mon.status)end
  function battle:growInScale()return false end
  function battle:caughtMarkerVisible()return self.caught==true end
  function battle:playerPartyView()return self.game.save.party end
  local function clone(t)local r={}for k,v in pairs(t)do r[k]=type(v)=='table'and clone(v)or v end return r end
  local original=clone(player)
  local function near(a,b)T.check(math.abs(a-b)<1e-9,'numeric fraction '..tostring(a)..' == '..tostring(b))end
  for _,hp in ipairs({0,1,83,168})do
    player.mon.hp,player.shownHP,player.shownPx=hp,hp,nil
    local shown,maximum,ratio=Panels.health(player)
    T.eq(shown,hp,'shown HP endpoint');T.eq(maximum,168,'max HP preserved');near(ratio,hp/168)
  end
  player.mon.hp=1;player.shownHP=1.2;player.shownPx=24
  local shown,maximum,ratio=Panels.health(player);T.eq(shown,2,'draining HP rounds toward actual');near(ratio,0.5)
  player.mon.hp=100;player.shownHP=99.8;player.shownPx=nil
  T.eq(Panels.health(player),99,'healing HP rounds down')
  for _,v in ipairs({{-10,0},{0,0},{0.5,0.5},{1,1},{2,1}})do
    local lo,hi=Growth.expForLevel('MEDIUM_FAST',50),Growth.expForLevel('MEDIUM_FAST',51)
    player.mon.exp=lo+(hi-lo)*v[1];near(Panels.experience(battle,player),v[2])
  end
  player.mon.level=100;near(Panels.experience(battle,player),1)
  player.mon.level=50
  data.growth_rates={MEDIUM_FAST={expForLevel=function(n)return n*100 end}}
  player.mon.exp=5050;near(Panels.experience(battle,player),0.5);data.growth_rates=nil
  player=clone(original);battle.player=player
  T.eq(Panels.fit('がぎぐげご',32),'がぎ..','name clipping keeps composed kana whole')
  T.eq(Panels.fit('Name 100%',160),'Name 100%','literal percent names preserved')
  T.eq(Panels.fit('ピカチュウ',72),'ピカチュウ','native five-character name fits')
  local catalog={'ピカチュウ','フシギバナ','へんか','ぶつり','とくしゅ','かなしばり','いれかえ','ポケモン'}
  for _,text in ipairs(catalog)do
    local okay=true
    for _,span in ipairs(Font.split(text))do if not span.code then okay=false end end
    T.check(okay,'ROM charmap covers panel label '..text)
  end
  local forcedHUDWidth
  local function geometry(W,H,body)
    local r={pw=W,ph=H,dpiX=1,dpiY=1,vux=0,vuy=0,vuw=W,vuh=H,uiw=160,uih=144,body=body or {x=0,y=0,w=W,h=H}}
    Presentation.frame(r,1)
    local m=Presentation.metrics(r)
    if forcedHUDWidth then m.playerHUD.w=forcedHUDWidth;m.enemyHUD.w=forcedHUDWidth end
    return m
  end
  local function scene(m)
    g.setColor(0.17,0.26,0.24,1);g.rectangle('fill',0,0,m.width,m.height)
    for y=0,m.height,8 do for x=0,m.width,8 do
      g.setColor((x+y)%16==0 and 0.27 or 0.25,0.38,0.27,1)
      g.rectangle('fill',x,y,8,8)
      g.setColor(0.41,0.48,0.29,1);g.rectangle('fill',x+2,y+3,2,1)
    end end
    local a,b=m.actor.player,m.actor.enemy
    -- Authored geometric stand-ins, intentionally not retail sprite assets.
    g.setColor(0.1,0.16,0.14,0.5);g.ellipse('fill',a.x,a.y-3,24,5);g.ellipse('fill',b.x,b.y-2,20,4)
    g.setColor(0.73,0.58,0.22,1);g.rectangle('fill',a.x-16,a.y-32,32,32)
    g.rectangle('fill',a.x-16,a.y-45,8,16);g.rectangle('fill',a.x+8,a.y-45,8,16)
    g.setColor(0.46,0.32,0.16,1);g.rectangle('fill',a.x-9,a.y-20,18,4);g.rectangle('fill',a.x-9,a.y-10,18,4)
    g.setColor(0.18,0.48,0.43,1);g.rectangle('fill',b.x-19,b.y-24,38,24)
    g.setColor(0.61,0.25,0.4,1);g.rectangle('fill',b.x-15,b.y-40,30,18)
    g.setColor(0.05,0.10,0.12,1);g.rectangle('fill',b.x-12,b.y-18,4,3);g.rectangle('fill',b.x+9,b.y-18,4,3)
  end
  local frames={}
  local function render(W,H,label,body)
    love.window.setMode(W,H,{vsync=0})
    local m=geometry(W,H,body)
    local target=g.newCanvas(W,H,{dpiscale=1});g.setCanvas(target);g.clear(0,0,0,1)
    g.push('all');g.translate(m.x,m.y);g.scale(m.sx,m.sy);scene(m)
    local runs,base,baseHud={},Font.draw,HudTiles.tile
    Font.draw=function(text,x,y)
      runs[#runs+1]={text=text,x=x,y=y,width=Font.width(text),color={g.getColor()}}
      return base(text,x,y)
    end
    HudTiles.tile=function(code,x,y,tint)
      runs[#runs+1]={hudCode=code,x=x,y=y,width=8,color={g.getColor()}}
      return baseHud(code,x,y,tint)
    end
    local sentinel=g.newShader([[vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc){return vec4(1.0,0.0,1.0,1.0);}]])
    g.setScissor(0,0,W,H)
    g.setShader(sentinel);g.setColor(0.2,0.4,0.6,0.8);g.setBlendMode('alpha','premultiplied')
    local beforeX,beforeY=g.transformPoint(2,3)
    Panels.draw(battle,m)
    T.check(g.getShader()==sentinel,'draw restores caller shader')
    local sx,sy,sw,sh=g.getScissor();T.check(sx==0 and sy==0 and sw==W and sh==H,'draw restores caller scissor')
    local cr,cg,cb,ca=g.getColor();T.check(math.abs(cr-0.2)<1e-6 and math.abs(cg-0.4)<1e-6 and math.abs(cb-0.6)<1e-6 and math.abs(ca-0.8)<1e-6,'draw restores caller color')
    local bm,am=g.getBlendMode();T.check(bm=='alpha'and am=='premultiplied','draw restores caller blend')
    local ax,ay=g.transformPoint(2,3);T.check(ax==beforeX and ay==beforeY,'draw restores caller transform')
    Font.draw=base;HudTiles.tile=baseHud
    g.pop();g.setCanvas()
    local id=target:newImageData();local bytes=id:encode('png'):getString()
    if label then local f=assert(io.open(out..'/'..label..'.png','wb'));f:write(bytes);f:close()end
    local okay=true;local bad={}
    for _,r in ipairs(runs)do
      if r.x<0 or r.y-8<0 or r.x+r.width>m.width or r.y+8>m.height then okay=false;bad[#bad+1]=r.text end
    end
    T.check(okay,'native text bounds '..(label or '')..' '..table.concat(bad,','))
    local black=true
    for _,r in ipairs(runs)do
      black=black and r.color[1]==0 and r.color[2]==0 and r.color[3]==0 and r.color[4]==1
    end
    T.check(black,'all primary, auxiliary and status text uses opaque black ink')
    for _,cell in ipairs(Panels.cells(m,battle.phase))do
      T.check(cell.x>=m.command.x and cell.x+cell.w<=m.command.x+m.command.w and cell.y>=m.command.y and cell.y+cell.h<=m.command.y+m.command.h,'pointer cells contained in command band')
    end
    local function pixel(x,y)
      return {id:getPixel(math.floor(m.x+(x+0.5)*m.sx),math.floor(m.y+(y+0.5)*m.sy))}
    end
    local probes={hpLeft=pixel(m.playerHUD.x+8,m.playerHUD.y+24),hpRight=pixel(m.playerHUD.x+m.playerHUD.w-9,m.playerHUD.y+24),
      xpLeft=pixel(m.playerHUD.x+8,m.playerHUD.y+35),xpRight=pixel(m.playerHUD.x+m.playerHUD.w-9,m.playerHUD.y+35)}
    frames[#frames+1]={label=label,width=W,height=H,metrics=m,runs=runs,probes=probes}
    target:release();id:release();sentinel:release()
    return runs,bytes,m,probes
  end
  local function seen(runs,text)for _,r in ipairs(runs)do if r.text==text then return true end end return false end
  for _,size in ipairs({{480,800},{800,480},{1536,1160}})do
    local W,H=size[1],size[2]
    battle.phase='menu';battle.menuIndex=1
    local rows=render(W,H,'commands-'..W..'x'..H)
    for _,text in ipairs({'たたかう','ポケモン','どうぐ','にげる','ピカチュウ','フシギバナ'})do T.check(seen(rows,text),'command/HUD label '..text)end
    battle.phase='moveSelect';battle.moveIndex=1
    rows=render(W,H,'moves-'..W..'x'..H)
    T.check(seen(rows,'へんか'),'zero-power move displays status category');T.check(seen(rows,'PP 40/40'),'PP details readable')
  end
  for _,status in ipairs({'PSN','PAR','BRN','FRZ','SLP','FNT'})do
    player.shownStatus,enemy.shownStatus=status,status
    local rows=render(480,800,'status-'..status)
    T.check(seen(rows,battle:statusLabel({status=status})),'Japanese status shown '..status)
    T.check(seen(rows,'ピカチュウ'),'five-kana player name remains whole with status '..status)
    T.check(seen(rows,'Lv55'),'enemy level remains visible alongside status '..status);T.check(not seen(rows,'Lv50'),'player compact status replaces its level '..status)
  end
  player.shownStatus,enemy.shownStatus=nil,nil
  forcedHUDWidth=80
  for _,level in ipairs({1,50,100})do
    player.mon.level=level
    local rows=render(480,800)
    local tiles=0
    for _,r in ipairs(rows)do if r.hudCode==0x6E then tiles=tiles+1 end end
    T.check(seen(rows,'ピカチュウ'),'80px card preserves all five kana at level '..level)
    T.check(seen(rows,tostring(level)),'80px card preserves complete level '..level)
    T.eq(tiles,level<100 and 1 or 0,'80px card uses one battle level tile below 100 only')
    local name,meta
    for _,r in ipairs(rows)do
      if r.text=='ピカチュウ' then name=r end
      if r.hudCode==0x6E or r.text=='100' then meta=r end
    end
    T.check(name and meta and meta.x>=name.x+name.width+4,'80px card keeps four pixels between name and level')
  end
  for _,status in ipairs({'PSN','PAR','BRN','FRZ','SLP','FNT'})do
    player.shownStatus=status
    local rows=render(480,800)
    T.check(seen(rows,'ピカチュウ') and seen(rows,battle:statusLabel({status=status})),'80px card preserves full name and status '..status)
  end
  forcedHUDWidth=nil;player.shownStatus=nil;player.mon.level=50
  player.name='がぎぐげご がぎぐげご 100%'
  enemy.name='MOD 100% がぎぐげご'
  battle.phase='moveSelect';battle.moveIndex=2
  battle.caught=true;render(480,800,'caught-marker');battle.caught=nil -- jp.63: the caught ball after the wild Pokemon's name
  local rows=render(480,800,'empty-pp-long-names')
  T.check(seen(rows,'PP 0/24'),'PP Ups and zero PP displayed')
  T.eq(player.name,'がぎぐげご がぎぐげご 100%','user nickname remains unchanged')
  T.eq(enemy.name,'MOD 100% がぎぐげご','custom enemy name remains unchanged')
  T.check(seen(rows,'がぎぐげご..'),'long move name truncates on font spans')
  battle.moveIndex=3;battle.moveSwapIndex=1
  rows=render(480,800,'move-swap');T.check(seen(rows,'いれかえ'),'move reorder label shown')
  battle.moveSwapIndex=nil;player.disabledSlot=3
  rows=render(480,800,'disabled-move');T.check(seen(rows,'かなしばり'),'disabled state shown')
  player.disabledSlot=nil;battle.phase='mimicSelect';battle.mimicMoves=player.curMoves;battle.mimicIndex=1
  rows=render(480,800,'mimic');T.check(seen(rows,'PP 40/40'),'Mimic uses selected move details')
  local function colorIs(pixel,color)
    return math.abs(pixel[1]-color[1])<0.01 and math.abs(pixel[2]-color[2])<0.01 and math.abs(pixel[3]-color[3])<0.01
  end
  battle.phase='menu';player.name='ピカチュウ';enemy.name='フシギバナ'
  player.mon.hp,player.shownHP,player.shownPx,player.mon.level=0,0,0,50
  player.mon.exp=Growth.expForLevel('MEDIUM_FAST',50)
  local _,_,_,probes=render(480,800,'hp-xp-empty')
  T.check(colorIs(probes.hpLeft,Panels.colors.track) and colorIs(probes.hpRight,Panels.colors.track),'0 HP draws no colored HP pixels')
  T.check(colorIs(probes.xpLeft,Panels.colors.track) and colorIs(probes.xpRight,Panels.colors.track),'0 XP draws no colored XP pixels')
  player.mon.hp,player.shownHP,player.shownPx,player.mon.level=999,999,48,100;player.mon.stats.hp=999
  local rows,_,_,probes=render(480,800,'hp-xp-full-level100')
  T.check(colorIs(probes.hpLeft,Panels.colors.green) and colorIs(probes.hpRight,Panels.colors.green),'full HP reaches both bar ends')
  T.check(colorIs(probes.xpLeft,Panels.colors.xp) and colorIs(probes.xpRight,Panels.colors.xp),'max-level XP fills the track')
  T.check(seen(rows,'999/999'),'3-digit HP numbers fit the integrated panel')
  T.check(seen(rows,'100'),'level 100 fits its native three-digit slot')
  player.mon.hp,player.shownHP,player.shownPx=1,1,1
  local _,_,_,probes=render(480,800,'hp-critical')
  T.check(colorIs(probes.hpLeft,Panels.colors.red) and colorIs(probes.hpRight,Panels.colors.track),'critical HP uses a visible red pixel')
  player=clone(original);battle.player=player
  battle.phase='messages';battle.current={};battle.shown={Font.encode('ピカチュウは'),Font.encode('なきごえを つかった！')};battle.msgWaiting=true;battle.scrollPx=16
  render(480,800,'scrolling-message');T.eq(battle.scrollPx,14,'scroll advances exactly once per draw')
  battle.scrollPx=nil;battle.current=nil;battle.phase='menu';player.name='ピカチュウ';enemy.name='フシギバナ'
  battle.game.save.options.colors='classic';local _,a=render(480,800)
  battle.game.save.options.colors='og_inv';local _,b=render(480,800)
  T.eq(a,b,'world palette does not recolor the battle overlay')
  -- The real landscape touch layout reserves all but 290 physical rows.
  -- A fixed 64-pixel band would force the entire battle down to scale 1.
  local compactBody={x=0,y=0,w=800,h=290}
  battle.phase='menu';battle.menuIndex=4
  local rows,_,cm=render(800,480,nil,compactBody)
  T.check(cm.compact and cm.scale==2 and cm.command.h==48,'short landscape retains two physical pixels per native pixel')
  T.eq(cm.field.h,96,'compact mode retains the original actor and attack field')
  T.check(not seen(rows,'ピカチュウは どうする？'),'compact command omits the prompt only')
  for _,text in ipairs({'たたかう','ポケモン','どうぐ','にげる'})do T.check(seen(rows,text),'compact command retains '..text)end
  battle.phase='moveSelect';battle.moveIndex=3;battle.moveSwapIndex=1
  data.moves.CUSTOM.type='DRAGON'
  rows=render(800,480,nil,compactBody);T.check(seen(rows,'いれかえ'),'compact move reorder retains its label')
  battle.moveSwapIndex=nil
  local rows,_,cm=render(800,480,'compact-moves-800x480',compactBody)
  T.check(seen(rows,'ドラゴン'),'compact type retains voiced kana')
  T.check(seen(rows,'PP 3/5'),'compact details retain PP')
  local upper,lower=true,true
  for _,r in ipairs(rows)do if r.y>=cm.command.y then
    upper=upper and r.y-8>=cm.command.y+4
    lower=lower and r.y+8<=cm.command.y+cm.command.h-2
  end end
  T.check(upper,'compact glyph slots retain four-pixel upper-mark clearance')
  T.check(lower,'compact text ends before the lower frame')
  -- Compare the actual alpha pixels of the second move row and the footer.
  -- Their glyph slots overlap, but the extracted mark tile has its ink at
  -- the bottom; no printed dakuten may collide with the preceding move.
  local function textMask(y)
    local c=g.newCanvas(cm.width,cm.height,{dpiscale=1})
    g.push('all');g.origin();g.setScissor();g.setCanvas(c);g.clear(0,0,0,0);g.setShader();g.setColor(0,0,0,1)
    for _,r in ipairs(rows)do if r.y==y then Font.draw(r.text,r.x,r.y)end end
    g.setCanvas();g.pop();local p=c:newImageData();c:release();return p
  end
  local second,footer=textMask(cm.command.y+27),textMask(cm.command.y+37)
  local overlaps=0
  for y=0,cm.height-1 do for x=0,cm.width-1 do
    local _,_,_,a=second:getPixel(x,y);local _,_,_,b=footer:getPixel(x,y)
    if a>0 and b>0 then overlaps=overlaps+1 end
  end end
  T.eq(overlaps,0,'compact voiced footer does not collide with the second move row')
  second:release();footer:release();data.moves.CUSTOM.type='CUSTOM'
  battle.phase='messages';battle.current={};battle.shown={Font.encode('ピカチュウは'),Font.encode('なきごえを つかった！')};battle.msgWaiting=true;battle.scrollPx=16
  render(800,480,nil,compactBody);T.eq(battle.scrollPx,14,'compact messages retain one scroll decrement')
  battle.phase='menu';battle.current=nil;battle.scrollPx=nil
  local m=geometry(480,800)
  local transparent=g.newCanvas(m.width,m.height,{dpiscale=1})
  g.push('all');g.origin();g.setCanvas(transparent);g.clear(0,0,0,0);g.setScissor()
  Panels.draw(battle,m);g.setCanvas();g.pop()
  local pixels=transparent:newImageData()
  local function isPixel(x,y,color)
    local r,g,b,a=pixels:getPixel(x,y)
    return math.abs(r-color[1])<0.01 and math.abs(g-color[2])<0.01
      and math.abs(b-color[3])<0.01 and math.abs(a-color[4])<0.01
  end
  local paper,ink=Panels.colors.paper,Panels.colors.ink
  T.check(isPixel(m.enemyHUD.x+6,m.enemyHUD.y+6,{1,1,1,1}),'panel interior is completely opaque white')
  for _,panel in ipairs({m.enemyHUD,m.playerHUD,m.command})do
    local opaque=true
    for y=panel.y,panel.y+panel.h-1 do for x=panel.x,panel.x+panel.w-1 do
      local _,_,_,alpha=pixels:getPixel(x,y);if alpha~=1 then opaque=false end
    end end
    T.check(opaque,'every pixel of the whole white panel is opaque')
    T.check(isPixel(panel.x+10,panel.y,ink) and isPixel(panel.x+10,panel.y+1,paper)
      and isPixel(panel.x+10,panel.y+2,ink),'double rule has black-white-black native rows')
    T.check(isPixel(panel.x+1,panel.y+1,ink) and isPixel(panel.x+3,panel.y+3,ink),'double rule includes stepped native corners')
  end
  T.check(isPixel(m.playerHUD.x+8,m.playerHUD.y+36,paper),'XP line has white clearance before the inner frame')
  T.check(isPixel(m.enemyHUD.x+8,m.enemyHUD.y+36,paper),'enemy HP has white clearance before the inner frame')
  local _,_,_,empty=pixels:getPixel(m.field.x+1,m.field.y+48)
  T.eq(empty,0,'scene between panels remains completely transparent')
  local _,_,_,outside=pixels:getPixel(m.enemyHUD.x+m.enemyHUD.w,m.enemyHUD.y+10)
  T.eq(outside,0,'no shadow spills outside the white panel')
  local chosen=Panels.cells(m,'menu')[battle.menuIndex or 1]
  T.check(isPixel(chosen.x+1,chosen.y+1,paper),'selection keeps white paper without a colored band')
  T.check(isPixel(chosen.x+2,chosen.y+8,ink),'selected command has the native black triangle cursor')
  local found=false
  for y=m.playerHUD.y+12,m.playerHUD.y+19 do for x=m.playerHUD.x+4,m.playerHUD.x+43 do
    if isPixel(x,y,ink) then found=true end
  end end
  T.check(found,'original ROM glyphs draw directly as black native ink')
  pixels:release();transparent:release()
  local file=assert(io.open(out..'/results.json','wb'));file:write(Json.encode({checks=T.checks,failures=T.failures,messages=T.messages,frames=frames}));file:close()
  T.finish()
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then print(err);love.event.quit(1)else love.event.quit(0)end
end
