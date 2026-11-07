-- Production Game/Renderer, real native menus, installed 3D scene and inputs.
return function(Game,Renderer,V,state,check,write)
  local g,fs=love.graphics,love.filesystem
  local Stack=require('src.core.StateStack');Stack:init();Game.stack=Stack
  local Windows=require('src.ui.FloatingGameWindow')
  local Viewport=require('src.render.GameViewport')
  local Touch=require('src.core.TouchControls');Touch:init();Touch.active=true
  local Layout=require('src.ui.GameUILayout')
  local Save=require('src.core.SaveData');local options=Game.save.options
  Game.save=Save.newGame();Game.save.options=options;Game.save.coins=100
  local Pokemon=require('src.pokemon.Pokemon')
  for i=1,6 do
    local p=Pokemon.new(Game.data,'FIXMON_A',i+5);p.nickname=i==1 and 'ゼニガメ' or 'サンプル'
    Game.save.party[i]=p
  end
  Game.save.pokedex={seen={FIXMON_A=true,FIXMON_C=true},owned={FIXMON_A=true}}
  require('src.render.DotMatrix').setLevel(0)
  require('src.render.PaletteFX').setMode('gbc')
  options.jpDialogScale=.75
  -- Hand-authored symbols exercise real reel clipping without retail art.
  local symbols={'7','BAR','CHERRY','MOUSE','FISH','BIRD'}
  local sheet=g.newCanvas(96,16,{dpiscale=1});g.setCanvas(sheet);g.clear(1,1,1,1)
  local art={sheet='window-slot-symbols.png',symbols={}}
  for i,name in ipairs(symbols)do
    local x=(i-1)*16;art.symbols[name]={x=x,y=0,w=16,h=16}
    g.setColor(.08,.08,.08,1);g.rectangle('line',x+2,2,11,11)
    g.setColor(.15+i*.10,.15+i*.10,.15+i*.10,1);g.rectangle('fill',x+4,4,8,8)
  end
  g.setCanvas();g.setColor(1,1,1,1)
  fs.write(art.sheet,sheet:newImageData():encode('png'))
  Game.data.field.slotSymbols=art;Game.data.field.slotWheels={}
  for w=1,3 do
    local wheel={};for i=1,18 do wheel[i]=symbols[(i+w)%6+1]end
    Game.data.field.slotWheels[w]=wheel
  end
  local marker=g.newCanvas(16,96,{dpiscale=1});g.setCanvas(marker);g.clear(.9,.2,.5,1);g.setCanvas()
  fs.write('window-player.png',marker:newImageData():encode('png'))
  local sprite=require('src.render.SpriteRenderer').new({image='window-player.png',frames=6,trueColor=true})
  function sprite:resolveImage()return self.image end
  local player={sprite=sprite,px=128,py=128,cellX=8,cellY=8,facing='up'}
  function player:pose()return self.sprite,self.px,self.py,self.facing,0,false end
  state.player,state.entities,state.camera=player,{player},require('src.render.Camera').new()
  state.isOpaque,state.isOverworld=true,true;Game.overworld=state
  local fieldDraws,fieldUpdates=0,0
  function state:update()fieldUpdates=fieldUpdates+1 end
  function state:draw()
    fieldDraws=fieldDraws+1
    local r=Renderer:frameRects();local vw,vh=Renderer:worldViewSize()
    self.camera:follow(player.px,player.py,vw,vh)
    local scene=require('src.render.Pipelines').drawWorld('voxel',{state=self,cam=self.camera,
      vw=vw,vh=vh,width=r.pw,height=r.ph,scale=require('src.render.Zoom').scale(r.Sp),level=5,
      paletteFor=function()return nil end,drawFx=function()end})
    assert(scene,'real 3D backdrop must render');Renderer:setWorldOverride(scene)
  end
  require('src.render.Pipelines').setLevel('voxel',5);V.require('VoxelState').level=5
  local results={}
  local function shot(label)
    Game:draw();g.setCanvas();local r=Renderer:frameRects()
    local pixels=Viewport.target():newImageData()
    write(label..'.png',pixels:encode('png'):getString())
    check(Renderer.jpFloatingBackdrop~=nil,label..' retains actual field backdrop: '..tostring(Windows.error))
    check(math.abs(r.uox+r.uvpw/2-r.body.x-r.body.w/2)<=1/r.dpiX,label..' horizontally centered')
    check(math.abs(r.uoy+r.uvph/2-r.body.y-r.body.h/2)<=1/r.dpiY,label..' vertically centered above controls')
    check(r.uoy>=r.body.y and r.uoy+r.uvph<=r.body.y+r.body.h,label..' no button overlap')
    check(r.Up==math.floor(r.Up),label..' whole-pixel native font')
    results[#results+1]={name=label,x=r.uox,y=r.uoy,w=r.uvpw,h=r.uvph,body=r.body}
    return r,pixels
  end
  for _,size in ipairs({{480,800},{800,480}})do
    love.window.setMode(size[1],size[2],{vsync=0});Windows.release()
    local suffix=size[1]..'x'..size[2]
    local party=require('src.ui.PartyMenu').new(Game)
    Stack.states={state,party}
    local prior=fieldDraws;local r,pixels=shot('window-party-'..suffix)
    check(fieldDraws==prior+1,'opening captures field once')
    local captures=Windows.stats.captures;local live=Stack.states
    for _=1,3 do Game:draw()end
    check(Windows.stats.captures==captures and fieldDraws==prior+1,'held menu reuses background without 3D work')
    check(Game.stack==Stack and Stack.states==live and Stack:top()==party,'live stack identity and input owner unchanged')
    check(fieldUpdates==0,'capture never updates field simulation')
    local before=party.index
    local oldInput=Game.input;Game.input={wasPressed=function(_,key)return key=='down'end,isDown=function()return false end}
    Stack:update(1/60);Game.input=oldInput
    check(party.index~=before,'native party cursor still accepts pad input')
    local summary=require('src.ui.SummaryMenu').new(Game,Game.save.party[party.index]);summary.whiteHold=0
    Stack:push(summary);shot('window-summary-'..suffix)
    check(Windows.stats.captures==captures,'nested stats reuses same field snapshot')
    Stack:pop();shot('window-party-return-'..suffix)
    check(Stack:top()==party and party.index~=before,'return preserves selected Pokemon')
    Stack:push(require('src.render.TextBox').new(Game,'テストの メッセージ',nil,{instant=true}))
    shot('window-party-message-'..suffix);Stack:pop()
    for _,id in ipairs({'SlotMachine','PokedexMenu','BoxMenu','TrainerCard'})do
      local page=require('src.ui.'..id).new(Game)
      Stack.states={state,page};shot('window-'..id..'-'..suffix)
      check(Windows.context(Game).page==page,id..' selects the actual native page')
    end
    Stack.states={state};Game:draw();check(Renderer.jpFloatingBackdrop==nil,'closing releases floating backdrop')
  end
  -- Every redraw of a spinning machine retains its frozen surroundings.
  local slot=require('src.ui.SlotMachine').new(Game);Stack.states={state,slot}
  shot('window-slot-resize-before');local captures=Windows.stats.captures
  local backdrop=Renderer.jpFloatingBackdrop:newImageData():getString()
  local oldInput=Game.input;Game.input={wasPressed=function()return false end,isDown=function()return false end}
  local oldOffset=slot.offset[1];local oldCoins=Game.save.coins
  slot.stage='spin';Stack:update(1/60);Stack:update(1/60);Game.input=oldInput
  shot('window-slot-spinning')
  check(slot.offset[1]~=oldOffset,'actual slot reels continue updating within the window')
  check(Game.save.coins==oldCoins,'rendering and free spinning do not alter coin balance')
  check(Renderer.jpFloatingBackdrop:newImageData():getString()==backdrop,'reel motion leaves backdrop pixel-identical')
  check(Windows.stats.captures==captures,'reels do not recapture the world')
  love.window.setMode(972,1536,{vsync=0});shot('window-slot-resize-after')
  check(Windows.stats.captures==captures+1,'rotation rebuilds exactly one backdrop')
  local old=Game.data.constants.language;Game.data.constants.language='en'
  check(Windows.context(Game)==nil,'English layout remains native');Game.data.constants.language=old
  check(#Game.mods.errors==0,'all installed MODs remain free of runtime errors')
  write('windows.json',require('src.link.Json').encode({romUsed=false,androidDeviceUsed=false,
    captures=Windows.stats.captures,cases=results}))
  Stack.states={state};Windows.release()
end
