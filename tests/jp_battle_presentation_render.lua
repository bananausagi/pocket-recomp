-- Actual Game -> loaded MOD -> GL scene and native overlay, with authored art.
return function(Game,Renderer,V,state,check,write)
  local g,fs=love.graphics,love.filesystem
  local Font=require('src.render.Font')
  require('tests.jp_battle_bitmap_font')(Game.data)
  require('src.core.Data').font=Game.data.font
  local Battle=require('src.battle.BattleState')
  local Pokemon=require('src.pokemon.Pokemon')
  local Save=require('src.core.SaveData')
  local Stack=require('src.core.StateStack');Stack:init();Game.stack=Stack
  local Touch=require('src.core.TouchControls');Touch:init();Touch.active=true
  check(Touch:ensureImages(),'actual touch artwork loads')
  local Viewport=require('src.render.GameViewport')
  local P=require('src.battle.BattlePresentation')
  local Host=V.require('VoxelBattleStandalone')
  local Provider=V.require('VoxelBattleArenaProvider')
  local Cards=V.require('VoxelBattleCardProvider')
  local Scene=V.require('VoxelBattleScene')
  local Blend=V.require('BattleCameraBlend')
  local V3=V.require('Voxel3D')
  local Cam=V.require('BattleCam')
  local oldOpts=Game.save.options
  Game.save=Save.newGame();Game.save.options=oldOpts
  Game.save.version='red_jp';Game.save.options.colors='gbc'
  require('src.render.PaletteFX').setMode('gbc')
  Game.save.party={Pokemon.new(Game.data,'FIXMON_A',12)}
  Game.save.party[1].nickname='ピカチュウ'
  Game.data.moves.FIX_TACKLE.name='たいあたり'
  Game.data.moves.FIX_EMBERISH.name='かえんほうしゃ'
  Game.data.moves.FIX_SCRATCH.name='ひっかく'
  Game.data.moves.FIX_CUT.name='いあいぎり'
  Game.data.type_chart.typeNames={NORMAL='ノーマル',FIRE='ほのお'}
  for id,name in pairs(Game.data.type_chart.typeNames)do
    if Game.data.type_chart.types and Game.data.type_chart.types[id] then Game.data.type_chart.types[id].name=name end
  end
  Game.input=require('src.core.Input');Game.input:init()
  local function art(path,back)
    local canvas=g.newCanvas(56,56,{dpiscale=1})
    g.setCanvas(canvas);g.clear(0,0,0,0)
    g.setColor(.15,.25,.20,1);g.rectangle('fill',8,10,40,back and 46 or 38)
    g.setColor(back and .95 or .55,.7,.2,1);g.rectangle('fill',10,12,36,back and 44 or 34)
    g.rectangle('fill',12,2,8,18);g.rectangle('fill',36,2,8,18)
    g.setColor(.05,.1,.08,1)
    if back then g.rectangle('fill',14,28,28,5);g.rectangle('fill',14,42,28,5)
    else g.rectangle('fill',15,22,5,5);g.rectangle('fill',36,22,5,5)end
    g.setCanvas();fs.write(path,canvas:newImageData():encode('png'));canvas:release()
  end
  art('fixture/battle-back.png',true);art('fixture/battle-front.png',false)
  Game.data.pokemon.FIXMON_A.spriteBack='fixture/battle-back.png'
  Game.data.pokemon.FIXMON_A.battleScaleBack=1
  Game.data.pokemon.FIXMON_C.spriteFront='fixture/battle-front.png'
  Game.data.pokemon.FIXMON_C.frontSize=7
  Battle.invalidate()
  if os.getenv('JP_QA_FIRST_BATTLE58')=='1' then
    return require('tests.jp58_first_battle_profile')(Game,Renderer,V,state,check,write)
  end
  if os.getenv('JP_QA_TRAINER_ORIGINAL')=='1' then
    return require('tests.jp_trainer_original_render')(Game,Renderer,V,state,check,write)
  end
  if os.getenv('JP_QA_BATTLE_INTRO')=='1' then
    return require('tests.jp_battle_intro_occlusion_render')(Game,Renderer,V,state,check,write)
  end
  local battle=Battle.newWild(Game,'FIXMON_C',10)
  battle.player.name,battle.enemy.name='ピカチュウ','フシギダネ'
  battle.player.curMoves={{id='FIX_TACKLE',pp=20},{id='FIX_EMBERISH',pp=0},{id='FIX_SCRATCH',pp=20},{id='FIX_CUT',pp=10,ppUps=2}}
  battle.player.mon.moves=battle.player.curMoves
  battle.phase,battle.menuIndex,battle.frame='menu',1,0
  -- The fixture skips the scripted introduction; retain enter()'s opacity.
  battle.isOpaque=battle:bgMode()~='world'
  battle.introSlide,battle.introBalls,battle.showPlayerBack=0,false,false
  battle.enemyHudPending,battle.enemySendingOut=false,false
  state.isOpaque,state.isOverworld=true,true
  state.player.facing='up'
  local worldArena={map=state.map,mid={136,136},player={136,136},enemy={136,88},playerCell={8,8},cam='wide'}
  local worldPose={eye={136,130,200},focus={136,0,130},fov=.8,up={0,1,0},curve=0}
  function state:draw()
    local canvas=Scene.render(self,worldArena,function()end,{pose=worldPose,pitch=.7})
    if canvas then Renderer:setWorldOverride(canvas) end
    V3.camera=worldPose
  end
  Game.overworld=state;Host.install()
  local oldEnd=Renderer.endFrame
  local hadTerrain,renderFrame,panelPixels,nativePixels
  Renderer.endFrame=function(self,...)
    hadTerrain=self.worldOverride~=nil
    renderFrame=self:frameRects()
    panelPixels=self.jpBattleModern and self.battlePresentationCanvas:newImageData() or nil
    local active=g.getCanvas();g.setCanvas()
    nativePixels=self.jpBattleModern and self.canvas:newImageData() or nil
    g.setCanvas(active)
    return oldEnd(self,...)
  end
  local function snapshot(label,page)
    Game:draw();g.setCanvas()
    local r=renderFrame;local m=not page and P.metrics(r)
    local canvas=Viewport.target()
    g.setCanvas(canvas);Touch:draw();g.setCanvas()
    local pixels=canvas:newImageData()
    write(label..'.png',pixels:encode('png'):getString())
    if page then
      check(Renderer.jpLayout=='page',label..' preserves opaque native page ownership')
      return r,nil,pixels
    end
    check(hadTerrain,label..' uses real GL same-map terrain')
    check(m.y+m.height*m.sy<=r.vuy+r.vuh+.001,label..' full battle stays inside actual viewport')
    check(math.abs((m.y+m.height*m.sy/2)-(r.vuy+r.vuh/2))*r.dpiY<1.001,label..' whole composition is physically centred')
    check(m.actor.enemy.y<=m.playerHUD.y,label..' enemy feet above player status')
    check(m.native.y+m.field.h==m.command.y,label..' back crop is covered by command band')
    check(Renderer.uiWidth==160,label..' native move and capture coordinates stay 160px')
    local pr,pg,pb,pa=panelPixels:getPixel(m.command.x+m.command.w-6,m.command.y+6)
    check(pr>.99 and pg>.99 and pb>.99 and pa>.99,label..' command uses opaque white paper')
    local br,bg,bb,ba=panelPixels:getPixel(m.command.x,m.command.y+16)
    check(br<.01 and bg<.01 and bb<.01 and ba>.99,label..' command keeps its black original-style frame')
    local context=Host.session and Host.session.context
    if context and (context.arena.presentationTime or 0)>=.55 then
      local ratio=r.pw/context.services.renderSize.width
      for _,side in ipairs({'player','enemy'})do
        local cell=context.arena[side]
        local px,py=context.services.project(cell[1],context.groundY,cell[2])
        local target=m.actor[side]
        check(math.abs(px*ratio-(m.x+target.x*m.sx-r.vux)*r.dpiX)<.1
          and math.abs(py*ratio-(m.y+target.y*m.sy-r.vuy)*r.dpiY)<.1,
          label..' '..side..' actual projection matches native effect anchor')
      end
    end
    return r,m,pixels
  end
  if os.getenv('JP_QA_BATTLE_BACKGROUND')=='1' then
    require('tests.jp_battle_background_render')(Game,Renderer,V,state,battle,check,write)
    Renderer.endFrame=oldEnd
    return
  end
  if os.getenv('JP_QA_BATTLE_SPACING')=='1' then
    require('tests.jp_battle_spacing_render')(Game,Renderer,V,state,battle,check,write)
    Renderer.endFrame=oldEnd
    return
  end
  if os.getenv('JP_QA_BATTLE_CENTER49')=='1' then
    require('tests.jp49_battle_center')(Game,Renderer,V,state,battle,check,write)
    Renderer.endFrame=oldEnd
    return
  end
  if os.getenv('JP_QA_BATTLE_CENTER')=='1' then
    require('tests.jp48_battle_center')(Game,Renderer,V,state,battle,check,write)
    Renderer.endFrame=oldEnd
    return
  end
  if os.getenv('JP_QA_ACTION_CAMERA')=='1' then
    require('tests.jp27_battle_action_camera_render')(Game,Renderer,V,state,battle,check,write)
    Renderer.endFrame=oldEnd
    return
  end
  for _,size in ipairs({{480,800},{972,1536},{2160,3414},{1536,1160},{800,480}})do
    love.window.setMode(size[1],size[2],{vsync=0})
    require('src.core.ScreenPosition').setMode('center')
    Game.save.options.jpBattleScale=1;Game.save.options.jpDialogScale=1
    Game.save.options.battleLayout='classic'
    Stack.states={state};Game:draw();g.setCanvas()
    if size[1]==480 then
      write('world-before-encounter.png',Viewport.target():newImageData():encode('png'):getString())
    end
    local originalX,originalY=state.player.cellX,state.player.cellY
    local entryEye={V3.eye[1],V3.eye[2],V3.eye[3]}
    Stack.states={state,battle}
    local started=Host.begin(battle,Provider,Cards)
    check(started,'actual MOD provider starts at encounter cell')
    local arena=Host.session.context.arena
    check(arena.map==state.map and arena.origin.cellX==originalX and arena.origin.cellY==originalY,'arena retains original map and encounter origin')
    check(arena.entryPose.eye[1]==entryEye[1] and arena.entryPose.eye[2]==entryEye[2],'entry snapshots rendered world pose')
    if size[1]==480 then
      local expected={unpack(V3.vp)}
      Game:draw();g.setCanvas()
      local equal=true;for i=1,16 do if math.abs(V3.vp[i]-expected[i])>1e-5 then equal=false end end
      check(equal,'entry t=0 retains exact terrain projection at same encounter coordinates')
      write('entry-camera-0.png',Viewport.target():newImageData():encode('png'):getString())
      arena.presentationTime=.275;Game:draw();g.setCanvas()
      write('entry-camera-half.png',Viewport.target():newImageData():encode('png'):getString())
    end
    arena.presentationTime=.55
    Game:draw();g.setCanvas()
    for _,factor in ipairs({.75,1})do
      Game.save.options.jpDialogScale=factor
      Game.save.options.battleLayout=factor==1 and 'wide' or 'classic'
      for _,phase in ipairs({'menu','moveSelect','messages'})do
        battle.phase=phase;battle.moveIndex=1
        battle.current=phase=='messages' and {} or nil
        battle.shown={Font.encode('ピカチュウの こうげき！'),Font.encode('あいての HPが へった！')}
        snapshot('battle-'..size[1]..'x'..size[2]..'-'..factor..'-'..phase)
      end
      check(select(1,battle:uiSize())==160 and battle:moveGridNavigation(),
        Game.save.options.battleLayout..' saved layout retains modern native FX and 2x2 navigation')
    end
    if size[1]==480 then
      battle.phase='moveSelect';battle.moveIndex=1;battle.current=nil
      local first,second=battle.player.curMoves[1],battle.player.curMoves[2]
      local function key(k)
        Game:keypressed(k);Game.input:step();battle:update(1/60)
        Game:keyreleased(k);Game.input:step();battle:update(1/60)
      end
      key('tab');key('right');key('tab')
      check(battle.player.curMoves[1]==second and battle.player.curMoves[2]==first,
        'modern 2x2 SELECT swaps live party move records')
      check(battle.player.mon.moves[1].pp==0 and battle.player.mon.moves[2].pp==20,
        'modern SELECT preserves each remaining PP count')
      check(battle.phase=='moveSelect','modern SELECT consumes no turn')
      key('x');check(battle.phase=='menu','modern move B returns to commands')
      battle.player.curMoves[1],battle.player.curMoves[2]=first,second
      battle.phase='messages';battle.current={};battle.scrollPx=16
      snapshot('battle-message-scroll')
      check(battle.scrollPx==14,'actual Game composition advances message scroll only once')
      battle.scrollPx=nil
      for _,mode in ipairs({'classic','og_inv'})do
        local Palette=require('src.render.PaletteFX')
        Game.save.options.colors=mode;Palette.applyOptions(Game.save.options)
        local _,m,pixels=snapshot('battle-palette-'..mode)
        local rr,gg,bb=pixels:getPixel(math.floor(m.x+(m.playerHUD.x+9)*m.sx),
          math.floor(m.y+(m.playerHUD.y+24)*m.sy))
        check(gg>rr+.2 and gg>bb+.1,mode..' preserves resolved green HP bar through final renderer')
      end
      Game.save.options.colors='gbc';require('src.render.PaletteFX').applyOptions(Game.save.options)
      for _,variant in ipairs({'safari','intro','sendout','cleared'})do
        battle.phase=variant=='safari' and 'menu' or 'messages'
        battle.safari=variant=='safari' and {balls=12} or nil
        battle.introSlide=variant=='intro' and 36 or 0
        battle.enemySendingOut=variant=='sendout'
        battle.fieldCleared=variant=='cleared'
        snapshot('battle-'..variant)
      end
      battle.safari=nil;battle.introSlide=0;battle.enemySendingOut=false;battle.fieldCleared=false
      battle.phase='messages';battle.current={}
      local TextBox=require('src.render.TextBox')
      local Choice=require('src.ui.ChoiceBox')
      Stack.states={state,battle,TextBox.new(Game,'ポケモンを いれかえますか？',nil,{instant=true}),Choice.new(Game,function()end)}
      snapshot('battle-native-confirm')
      local party=require('src.ui.PartyMenu').new(Game,{battle=battle})
      Stack.states={state,battle,party}
      snapshot('battle-native-party',true)
      local beforePhase=battle.phase
      Game:keypressed('x');Game.input:step();party:update(1/60)
      Game:keyreleased('x');Game.input:step()
      check(Stack:top()==battle and battle.phase==beforePhase,'native party B returns to the same battle phase')
      check(Host.session and Host.session.context.arena==arena,'native party return retains same encounter arena')
      snapshot('battle-after-party')
      -- A medicine follows the real Bag -> Party -> result flow. The bag
      -- begins at y=16, so extracting only y>=48 used to erase its top.
      Game.data.items.POTION={id='POTION',name='キズぐすり',index=20,price=300}
      Game.save.inventory.POTION=2;Game.save.bagOrder={'POTION'}
      local bag=require('src.ui.BagMenu').new(Game,{battle=battle})
      Stack.states={state,battle,bag}
      snapshot('battle-item-bag')
      check(Renderer.jpBattleCommands==0,'item list retains its complete upper rows')
      local foundBag=false
      for _,a in ipairs(Renderer.uiAnchors or {})do
        if a.anchor=='battleOverlay' then foundBag=a.y==0 and a.h==144 end
      end
      check(foundBag,'full native bag composition is extracted without top crop')
      local function topKey(k)
        local top=Stack:top()
        Game:keypressed(k);Game.input:step();top:update(1/60)
        Game:keyreleased(k);Game.input:step()
      end
      topKey('z')
      local picker=Stack:top()
      check(picker.isPartyMenu and picker.itemUse,'battle potion opens actual target party page')
      snapshot('battle-item-target-party',true)
      local beforeHP=math.max(1,Game.save.party[1].stats.hp-8)
      Game.save.party[1].hp=beforeHP;battle.player.hp=beforeHP
      topKey('z')
      for _=1,120 do
        if Stack:top()~=picker then break end
        picker:update(1/60)
      end
      check(Game.save.party[1].hp>beforeHP and Game.save.inventory.POTION==1,
        'actual medicine heals chosen party member and consumes exactly one')
      local result=Stack:top()
      check(result~=picker and result~=battle,'medicine result retains a separate text dialog')
      snapshot('battle-item-use-result',true)
      for _=1,480 do
        if Stack:top()==battle then break end
        local top=Stack:top()
        Game.input:step();if top.update then top:update(1/60)end
        if _%20==0 then topKey('z')end
      end
      check(Stack:top()==battle,'medicine dialog closes back to same battle')
      check(Host.session.context.arena==arena,'item use preserves same encounter arena')
      snapshot('battle-after-item')
      -- Real OAM drawing, including the resting capture ball, shares the
      -- projected actor anchors. The authored sheet contains no ROM pixels.
      local tile=g.newCanvas(8,8,{dpiscale=1});g.setCanvas(tile);g.clear(0,0,0,0)
      g.setColor(0,0,0,1);g.rectangle('fill',1,1,6,6)
      g.setColor(1,1,1,1);g.rectangle('fill',2,2,4,4);g.setCanvas()
      fs.write('fixture/battle-oam.png',tile:newImageData():encode('png'));tile:release()
      battle.animPlayer.data.tilesheets.QA={path='fixture/battle-oam.png',width=8,height=8,tiles=1}
      local sprites={{x=128,y=64,tile=0,ts='QA'}}
      battle.animPlayer.steps={{dur=4,sprites=sprites}};battle.animPlayer.stepIndex=1
      battle.animPlaying=true
      snapshot('battle-native-move-fx')
      battle.animPlaying=false;battle.lockedBall=sprites
      snapshot('battle-native-resting-ball')
      battle.lockedBall=nil
      -- The actual captured enemy card must survive an opaque foreground
      -- object. Draw an authored camera-facing blocker through the real
      -- terrain shader; disabling only its cutaway gives a paired baseline.
      battle.phase='menu';battle.current=nil
      local r=Renderer:frameRects();local M=V.require('Mat4')
      local view=M.lookAt(V3.eye,V3.focus,{0,1,0})
      local cell=arena.enemy;local floor=Host.session.context.groundY or 0
      local eye,focus=V3.eye,V3.focus
      local dx,dy,dz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
      local length=math.sqrt(dx*dx+dy*dy+dz*dz);dx,dy,dz=dx/length,dy/length,dz/length
      local depth=(eye[1]-cell[1])*dx+(eye[2]-floor)*dy+(eye[3]-cell[2])*dz
      local unit=r.Up*2*depth*math.tan(V3.fovY/2)/r.ph
      local bounds=Cards:presentationBounds(P.metrics(r),'enemy')
      local width,height=bounds.width*unit*1.12,bounds.height*unit*1.12
      local vertices={}
      for _,uv in ipairs({{0,0},{1,0},{1,1},{0,0},{1,1},{0,1}})do
        local x=(uv[1]-.5)*width;local y=uv[2]*height
        vertices[#vertices+1]={cell[1]+view[1]*x+view[5]*y+dx*8,
          floor+view[6]*y+dy*8,cell[2]+view[3]*x+view[7]*y+dz*8,
          uv[1],uv[2],1}
      end
      local mesh=g.newMesh({{'VertexPosition','float',3},{'VertexTexCoord','float',2},
        {'VertexShade','float',1}},vertices,'triangles','static')
      local white=love.image.newImageData(1,1);white:setPixel(0,0,.3,.2,.1,1)
      local texture=g.newImage(white)
      local terrain=V.require('VoxelScene').prefetch(state)
      local originalDraw=V3.draw
      V3.draw=function(geometry,...)
        local out=originalDraw(geometry,...)
        if geometry==terrain then originalDraw(mesh,texture,nil)end
        return out
      end
      local originalClear=V3.battleOcclusion
      V3.battleOcclusion=function()end
      local _,beforeM,beforePixels=snapshot('battle-foreground-before')
      V3.battleOcclusion=originalClear
      local _,afterM,afterPixels=snapshot('battle-foreground-after')
      local function greenCount(pixels,m)
        local a=m.actor.enemy;local n=0
        local x0=math.max(0,math.floor(m.x+(a.x-bounds.width/2)*m.sx))
        local x1=math.min(pixels:getWidth()-1,math.ceil(m.x+(a.x+bounds.width/2)*m.sx))
        local y0=math.max(0,math.floor(m.y+(a.y-bounds.height)*m.sy))
        local y1=math.min(pixels:getHeight()-1,math.ceil(m.y+a.y*m.sy))
        for y=y0,y1 do for x=x0,x1 do
          local rr,gg,bb=pixels:getPixel(x,y)
          if gg>rr*1.15 and rr>.4 and bb<.4 then n=n+1 end
        end end
        return n
      end
      local obscured,readable=greenCount(beforePixels,beforeM),greenCount(afterPixels,afterM)
      check(readable>1000 and readable>obscured*3,'actual foreground cutaway restores captured enemy pixels')
      V3.draw=originalDraw;mesh:release();texture:release();white:release()
      -- A one-cell northward gap uses the same native view while shrinking
      -- only the world-space card and camera rig; no player/save movement.
      local priorEnemy,priorMid=arena.enemy,arena.mid
      local fullRadius=Cards:footprint(Host.session.context,'enemy').radius
      arena.enemy={arena.player[1],arena.player[2]-16}
      arena.mid={(arena.player[1]+arena.enemy[1])/2,(arena.player[2]+arena.enemy[2])/2}
      snapshot('battle-nearby-one-cell')
      check(math.abs(Cards:footprint(Host.session.context,'enemy').radius*3-fullRadius)<.001,
        'one-cell card footprint shrinks with actual billboard')
      arena.enemy,arena.mid=priorEnemy,priorMid
    end
    if size[1]==800 then
      local bag=require('src.ui.BagMenu').new(Game,{battle=battle})
      Stack.states={state,battle,bag}
      snapshot('battle-item-bag-landscape')
      check(Renderer.jpBattleCommands==0,'landscape bag preserves its native top rows')
      Game:keypressed('z');Game.input:step();bag:update(1/60)
      Game:keyreleased('z');Game.input:step()
      local picker=Stack:top()
      check(picker.isPartyMenu,'landscape medicine opens actual target party')
      local r=snapshot('battle-item-target-landscape',true)
      check(r.uoy>=r.body.y-.001,'landscape party top stays inside visible playfield')
      Game:keypressed('x');Game.input:step();picker:update(1/60)
      Game:keyreleased('x');Game.input:step()
      check(Stack:top()==bag,'landscape target cancel returns to bag')
      Game:keypressed('x');Game.input:step();bag:update(1/60)
      Game:keyreleased('x');Game.input:step()
      check(Stack:top()==battle,'landscape bag cancel returns to same battle')
    end
    for _,spacing in ipairs({'normal','wide','wider'})do
      Game.save.options.jpBattleSpacing=spacing
      battle.phase='menu';battle.current=nil
      local r,m=snapshot('spacing-'..spacing..'-'..size[1]..'x'..size[2])
      check(m.spacing==spacing,'saved spacing reaches shared battle metrics')
      local p,e=m.actor.player,m.actor.enemy
      local up=V3.camera and V3.camera.up or {0,1,0}
      local eye,focus=V3.eye,V3.focus
      local dx,dy,dz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
      local rig=Cam.rig(arena,Host.session.context.groundY,true)
      check(math.abs(eye[2]-rig.eye[2])<.001,
        'actual '..spacing..' camera retains third-person eye height')
      check(math.abs(math.deg(2*math.atan(math.tan(V3.fovY/2)*144*r.Up/r.ph))-46)<.001,
        'actual '..spacing..' camera uses the wider46-degree battle lens')
      if not m.compact then
        check(p.y-e.y==({normal=56,wide=80,wider=104})[spacing],
          'spacing changes vertical actor separation without resizing font')
      end
    end
    Game.save.options.jpBattleSpacing='wide'
    local final=Blend.copy(arena.lastPose)
    Host.finish('battle.ended')
    check(Blend.active(),'return transition begins from last scene camera')
    local first=Blend.applyReturn(worldPose)
    check(first.eye[1]==final.eye[1] and first.filmY==final.filmY,'return starts without camera or film jump')
    Blend.update(.4);Blend.applyReturn(worldPose)
    check(not Blend.active(),'return transition restores free camera ownership')
    check(state.player.cellX==originalX and state.player.cellY==originalY,'presentation never moves save/player coordinates')
  end
  -- No safe arena never substitutes an authored location or a white stage.
  love.window.setMode(480,800,{vsync=0})
  local VoxelScene=V.require('VoxelScene');local originalGround=VoxelScene.groundAt
  VoxelScene.groundAt=function(_,x,y)return x*100+y end
  Stack.states={state,battle};battle.phase='menu';battle.current=nil
  check(Host.begin(battle,Provider,Cards) and Host.session.context.arena.backgroundOnly,
    'unequal terrain heights retain a 3D background with native actors')
  VoxelScene.groundAt=originalGround
  snapshot('battle-uneven-ground-fallback')
  local minX,maxX,count=160,-1,0
  for y=0,143 do for x=0,159 do
    local rr,gg,bb,aa=nativePixels:getPixel(x,y)
    if aa>.1 and rr>.8 and gg>.4 and bb<.4 then
      minX=math.min(minX,x);maxX=math.max(maxX,x);count=count+1
    end
  end end
  check(count>100 and math.abs((minX+maxX+1)/2-36)<1,
    'native fallback back artwork stays centred on player FX anchor')
  local Finder=V.require('BattleArena');local oldFind=Finder.find
  Finder.find=function()return nil end
  Stack.states={state,battle};battle.phase='menu';battle.current=nil
  check(Host.begin(battle,Provider,Cards) and Host.session.context.arena.backgroundOnly,
    'unsafe encounter declines 3D actor placement while retaining its background')
  snapshot('battle-no-safe-arena')
  check(Host.session.context.arena.backgroundOnly and battle:bgMode()=='world',
    'fallback retains original world and native actors')
  Finder.find=oldFind
  -- Without an explicit pending battle, retain the original fallback effect.
  -- The ready 3D OW.pushBattle handoff is covered by the separate seamless
  -- fixture; these calls intentionally omit opts.battle.
  local Transition=require('src.render.BattleTransition')
  Stack.states={state}
  check(Provider:canTransition(),'same-map voxel arena is ready before the original encounter effect')
  local function transitionImage(label)
    Game:draw();g.setCanvas()
    local pixels=Viewport.target():newImageData()
    write(label..'.png',pixels:encode('png'):getString())
    return pixels
  end
  for _,kind in ipairs({'wild','trainer'})do
    local done,elapsed=0,0
    local wipe=Transition.new(Game,function()
      done=done+1
      Stack.states={state,battle}
      check(Host.begin(battle,Provider,Cards),kind..' effect completes into actual voxel battle')
    end,{trainer=kind=='trainer'})
    Stack.states={state,wipe}
    local function tick()wipe:update(1/60);elapsed=elapsed+1 end
    check((wipe.phase=='flash')==(kind=='wild'),kind..' retains original flash/no-flash style')
    if wipe.phase=='flash' then
      while wipe.t<4 do tick()end
      local black=transitionImage('encounter-'..kind..'-black-flash')
      local r,g,b=black:getPixel(240,400)
      check(Renderer.screenVeil and r<.01 and g<.01 and b<.01,'wild flash visibly reaches black in final composite')
      while wipe.t<16 do tick()end
      local white=transitionImage('encounter-'..kind..'-white-flash')
      local peak=0
      for y=400,403 do for x=240,243 do
        r,g,b=white:getPixel(x,y);peak=math.max(peak,math.min(r,g,b))
      end end
      check(Renderer.screenVeil and peak>.99,'wild flash visibly reaches white in final composite beneath the preserved LCD grid')
      while wipe.phase=='flash' do tick()end
    end
    while wipe.t<math.floor(wipe.wipeLen/2)do tick()end
    local partial=transitionImage('encounter-'..kind..'-half-wipe')
    local black,visible=0,0
    for y=8,792,16 do for x=8,472,16 do
      local r,g,b=partial:getPixel(x,y)
      if math.max(r,g,b)<.02 then black=black+1 end
      if math.max(r,g,b)>.2 then visible=visible+1 end
    end end
    check(Renderer.battleWipe and Renderer.battleWipe.prog>0 and Renderer.battleWipe.prog<1
      and black>0 and visible>0,kind..' original wipe visibly masks part of the same world')
    check(done==0,kind..' partial effect cannot start battle early')
    while wipe.t<wipe.wipeLen do tick()end
    local full=transitionImage('encounter-'..kind..'-full-wipe')
    local dark=true
    for y=8,792,16 do for x=8,472,16 do
      local r,g,b=full:getPixel(x,y);dark=dark and math.max(r,g,b)<.01
    end end
    check(dark,kind..' complete wipe reaches black before battle handoff')
    while done==0 and elapsed<1000 do tick()end
    check(done==1 and elapsed==wipe.wipeLen+60+(kind=='wild' and 72 or 0),
      kind..' retains original effect duration and one completion callback')
    local arena=Host.session.context.arena
    check(arena.map==state.map and arena.origin.cellX==state.player.cellX
      and arena.origin.cellY==state.player.cellY,kind..' effect returns to the same encounter map and position')
    arena.presentationTime=.55;battle.phase='menu';battle.current=nil
    snapshot('battle-after-'..kind..'-encounter')
    Host.finish('qa-encounter-effect');Blend.cancel()
  end
  local before=Provider.canTransition;Provider.canTransition=function()return false end
  local fallback=Transition.new(Game,function()end,{})
  Stack.states={state,fallback};fallback.t=4
  transitionImage('encounter-without-arena')
  check(Renderer.screenVeil~=nil,'unavailable arena retains original visible transition')
  Provider.canTransition=before
  check(#Game.mods.errors==0,'loaded MOD reports no render/runtime error')
  Renderer.endFrame=oldEnd
end
