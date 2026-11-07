-- Real game pages and the installed Dramaless arena; handwritten assets only.
return function(Game,Renderer,V,state,check,write)
  local g,fs=love.graphics,love.filesystem
  local Font=require("src.render.Font")
  local Layout=require("src.ui.GameUILayout")
  local Viewport=require("src.render.GameViewport")
  local Touch=require("src.core.TouchControls")
  local Save=require("src.core.SaveData")
  local Pokemon=require("src.pokemon.Pokemon")
  local Battle=require("src.battle.BattleState")
  local Position=require("src.core.ScreenPosition")
  local Stack=require("src.core.StateStack");Stack:init();Game.stack=Stack
  require("src.render.DotMatrix").setLevel(0)
  require("src.render.PaletteFX").setMode("gbc")
  local green={{245,249,235},{175,207,135},{48,136,64},{8,32,24}}
  Game.data.palettes={palettes={GREENBAR=green,YELLOWBAR={{245,249,235},{230,210,110},{160,130,30},{8,32,24}},
    REDBAR={{245,249,235},{230,150,110},{180,60,40},{8,32,24}},MEWMON=green,GRAYMON=green,PALLET=green},
    pokemon={FIXMON_A="MEWMON",FIXMON_C="MEWMON"},maps={FIX_TOWN="PALLET"}}
  Touch:init();Touch.active=true;check(Touch:ensureImages(),"real touch art loads")
  local options=Game.save.options
  Game.save=Save.newGame();Game.save.options=options
  options.jpDialogScale=0.75;options.uiLayout="centered"
  options.battleLayout="classic";options.battleHud="fixed";options.battleBg="white"
  Game.save.party={}
  for i=1,6 do
    local p=Pokemon.new(Game.data,"FIXMON_A",i+5)
    p.nickname=i==1 and "ゼニガメ" or "サンプル"
    Game.save.party[i]=p
  end
  -- Synthetic HP art, selected by the real HudTiles renderer.
  local sheet=g.newCanvas(23*8,8,{dpiscale=1})
  g.setCanvas(sheet);g.clear(0,0,0,0)
  for code=0x62,0x78 do
    local x=(code-0x62)*8
    g.setColor(0,0,0,1);g.rectangle("line",x,2,7,4)
    if code>=0x64 and code<=0x6b then
      g.setColor(.66,.66,.66,1);g.rectangle("fill",x,3,code-0x63,3)
    end
  end
  g.setCanvas();fs.write("fixture-layout-hud.png",sheet:newImageData():encode("png"))
  Game.data.font.pages={font_battle_extra={image="fixture-layout-hud.png",base=0x62}}
  require("src.core.Data").font=Game.data.font
  require("src.render.HudTiles").invalidate()

  local records={}
  local oldEnd=Renderer.endFrame
  local source,hud,r,anchors,hadArena
  Renderer.endFrame=function(self,...)
    g.setCanvas()
    source=self.canvas:newImageData()
    hud=self.battleHUDCanvas and self.battleHUDCanvas:newImageData()
    r,anchors,hadArena=self:frameRects(),self.uiAnchors,self.worldOverride~=nil
    return oldEnd(self,...)
  end
  local function render(label)
    Game:draw();g.setCanvas()
    g.setCanvas(Viewport.target());Touch:draw();g.setCanvas()
    local pixels=Viewport.target():newImageData()
    write(label..".png",pixels:encode("png"):getString())
    check(r.Up==math.floor(r.Up) and r.Ux*r.dpiX==r.Uy*r.dpiY,label.." square whole pixels")
    check(r.uoy>=r.body.y and r.uoy+r.uvph<=r.body.y+r.body.h,label.." page stays above controls")
    local boxes={}
    for _,a in ipairs(anchors or {}) do
      local x,y,w,h=Layout.place(r,a)
      check(x>=r.body.x and x+w<=r.body.x+r.body.w and y>=r.body.y and y+h<=r.body.y+r.body.h,
        label.." "..a.anchor.." fits usable playfield")
      boxes[#boxes+1]={anchor=a.anchor,x=x,y=y,w=w,h=h}
    end
    records[#records+1]={name=label,scale=r.Up,body=r.body,boxes=boxes}
    return pixels,boxes
  end

  local Host=V.require("VoxelBattleStandalone")
  local battle=Battle.newWild(Game,"FIXMON_C",10)
  battle.player.name,battle.enemy.name="ゼニガメ","テスト"
  battle.phase,battle.menuIndex,battle.frame="menu",1,0
  battle.introSlide,battle.introBalls,battle.showPlayerBack=0,false,false
  battle.enemyHudPending,battle.enemySendingOut=false,false
  battle.current=nil
  check(battle:colorMode(),"real shader palette pass is active")
  Host.install()
  local originalLoad=Save.load;Save.load=function()return Game.save end
  for _,size in ipairs({{972,1536},{1536,1160},{1536,864},{480,800}}) do
    love.window.setMode(size[1],size[2],{vsync=0})
    Position.setMode("center")
    local suffix=size[1].."x"..size[2]
    Game.overworld=state
    local party=require("src.ui.PartyMenu").new(Game)
    Stack.states={party}
    local pixels=render("party-"..suffix)
    check(select(3,pixels:getPixel(1,1))>.8,"party "..suffix.." paper reaches window edges")
    check(source:getHeight()==152,"party "..suffix.." room for first row voicing")
    -- The authored dakuten fixture has dots at x4/6,y5/6. The first
    -- nickname starts at (24,8), so its ゼ dots must occupy rows 5/6.
    check(select(1,source:getPixel(28,5))<.1,"party "..suffix.." first voiced kana survives")
    Stack.states={party,require("src.render.TextBox").new(Game,"テストの メッセージ",nil,{instant=true})}
    render("party-message-"..suffix)
    check(source:getHeight()==152,"party prompt retains extended canvas")
    Stack.states={require("src.ui.PlayerStartMenu").new(Game)}
    pixels=render("start-"..suffix)
    check(select(3,pixels:getPixel(1,1))>.8,"start "..suffix.." paper reaches window edges")
    check(#Stack.states[1]:sgbPalettes(Game)==1,"start "..suffix.." owns uniform palette")

    local field={isOpaque=true,isOverworld=true}
    function field:draw()
      local old=g.getCanvas()
      self.image=self.image or g.newCanvas(size[1],size[2],{dpiscale=1})
      g.setCanvas(self.image);g.clear(.22,.48,.36,1);g.setCanvas(old)
      Renderer:setWorldOverride(self.image)
    end
    Game.overworld=field
    Stack.states={field,require("src.ui.StartMenu").new(Game)}
    local _,fieldBoxes=render("field-menu-"..suffix)
    check(#fieldBoxes>=1 and fieldBoxes[1].x+fieldBoxes[1].w>r.uox+r.uvpw,
      "field START reaches right edge instead of centre")

    Stack.states={battle};Game.overworld=state
    check(Host.begin(battle,V.require("VoxelBattleArenaProvider"),V.require("VoxelBattleCardProvider")),"real arena session begins")
    -- Let the provider complete first-use native texture capture before
    -- comparing steady-state scene pixels across command phases.
    Game:draw();g.setCanvas()
    local menuScene
    for _,phase in ipairs({"menu","messages","moveSelect"}) do
      battle.phase=phase;battle.moveIndex=1
      battle.current=phase=="messages" and {} or nil
      battle.shown={Font.encode("ゼニガメの こうげき！"),Font.encode("テストの HPが へった")}
      local frame,boxes=render("battle-"..phase.."-"..suffix)
      check(hadArena,"battle "..phase.." "..suffix.." installed voxel arena draws")
      check(#boxes==3,"battle "..phase.." "..suffix.." separate HUD and command layers")
      check(boxes[1].x<=r.uox and boxes[2].x+boxes[2].w>=r.uox+r.uvpw,
        "battle "..phase.." "..suffix.." HUD spreads toward side edges")
      check(boxes[2].y+boxes[2].h<=boxes[3].y,
        "battle "..phase.." "..suffix.." player HUD never overlaps commands")
      -- Resolved HP/name pixels travel with the independent HUD canvas.
      local a=anchors[1];local b=boxes[1]
      local same=true
      for y=0,33 do for x=0,93 do
        local rr,gg,bb,aa=hud:getPixel(x,y)
        if aa>.99 then
          local pr,pg,pb=frame:getPixel(math.floor(b.x+(x+.5)*r.Ux),math.floor(b.y+(y+.5)*r.Uy))
          if math.abs(rr-pr)>.025 or math.abs(gg-pg)>.025 or math.abs(bb-pb)>.025 then same=false end
        end
      end end
      check(same,"battle "..phase.." "..suffix.." resolved enemy HUD pixels preserved")
      if phase=="menu" then menuScene=source end
      if phase=="moveSelect" then
        local intact=true
        for y=32,95 do for x=0,63 do
          local a,b,c,d=source:getPixel(x,y)
          local e,f,h,j=menuScene:getPixel(x,y)
          if a~=e or b~=f or c~=h or d~=j then intact=false end
        end end
        check(intact,"move selection keeps the complete native back sprite in place")
      end
    end
    Host.finish("qa")
    options.battleLayout="wide"
    Stack.states={battle}
    battle.phase="menu"
    check(Host.begin(battle,V.require("VoxelBattleArenaProvider"),V.require("VoxelBattleCardProvider")),"wide arena starts")
    local _,boxes=render("battle-wide-"..suffix)
    check(#boxes==3,"wide HUD panels and commands use responsive positions")
    Host.finish("qa");options.battleLayout="classic"
  end
  Save.load=originalLoad;Renderer.endFrame=oldEnd
  write("layout-geometry.json",require("src.link.Json").encode({romUsed=false,cases=records}))
end
