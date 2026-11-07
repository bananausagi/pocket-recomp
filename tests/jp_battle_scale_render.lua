-- Real battle renderers and compositor; only handwritten fixture creatures,
-- independently rasterized kana and synthetic HP tiles. No cartridge data.
return function(Game, Renderer, check, write)
  local g, fs = love.graphics, love.filesystem
  local Font = require("src.render.Font")
  local Runtime = require("src.mods.Runtime")
  local Viewport = require("src.render.GameViewport")
  local Position = require("src.core.ScreenPosition")
  local Battle = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  local PaletteFX = require("src.render.PaletteFX")
  local Layout=require("src.ui.GameUILayout")
  PaletteFX.setMode("sgb")
  require("src.render.DotMatrix").setLevel(0)
  Runtime.install(require("src.mods.Events").new(), require("src.mods.Hooks").new())
  Runtime.hooks:wrap("render.viewport", function(next, ctx)
    local result = next(ctx); result.capture = true; return result
  end, 0, "battle-size-fixture")

  -- Authored test HP segments: the production HudTiles.drawHPBar selects
  -- full/partial/empty tiles from this sheet, just as with imported graphics.
  local sheet = g.newCanvas(23 * 8, 8, {dpiscale=1})
  g.setCanvas(sheet); g.clear(0,0,0,0)
  for code = 0x62, 0x78 do
    local x = (code - 0x62) * 8
    g.setColor(0,0,0,1)
    if code >= 0x63 and code <= 0x6b then
      g.rectangle("fill",x,2,8,1); g.rectangle("fill",x,6,8,1)
      local filled = code - 0x63
      if filled > 0 then
        g.setColor(0.66,0.66,0.66,1); g.rectangle("fill",x,3,filled,3)
      end
    else
      g.rectangle("fill",x+1,2,6,1); g.rectangle("fill",x+1,2,1,5)
    end
  end
  g.setCanvas()
  fs.write("fixture-battle-hud.png",sheet:newImageData():encode("png"))
  Game.data.font.pages = {font_battle_extra={image="fixture-battle-hud.png",base=0x62}}
  require("src.core.Data").font = Game.data.font
  require("src.render.HudTiles").invalidate()
  Game.save = require("src.core.SaveData").newGame()
  Game.save.party = {Pokemon.new(Game.data,"FIXMON_A",12)}
  local battle = Battle.newWild(Game,"FIXMON_C",10)
  battle.enemy.name, battle.player.name = "テスト", "サンプル"
  battle.enemy.mon.hp = math.floor(battle.enemy.mon.stats.hp * 0.7)
  battle.player.mon.hp = math.floor(battle.player.mon.stats.hp * 0.4)
  battle.enemy.shownHP, battle.player.shownHP = nil,nil
  battle.colorFxReady = false
  battle.phase, battle.menuIndex, battle.frame = "menu",1,0
  battle.isOpaque = true
  Game.stack.states = {battle}

  -- Observe the actual Game:draw wiring before compositing, so a future
  -- battle-only override cannot pass by testing Renderer in isolation.
  local endFrame = Renderer.endFrame
  local drawText, japaneseCommand = Font.draw, false
  Font.draw = function(text,x,y,...)
    if text=="ポケモン" and x==240 and y==112 then japaneseCommand=true end
    return drawText(text,x,y,...)
  end
  local source, hud, rects, anchors
  Renderer.endFrame = function(self,...)
    g.setCanvas()
    source = self.canvas:newImageData()
    hud = self.battleHUDCanvas and self.battleHUDCanvas:newImageData()
    rects, anchors = self:frameRects(), self.uiAnchors
    return endFrame(self,...)
  end
  local function equalPixel(a, ax, ay, b, bx, by)
    local ar,ag,ab,aa = a:getPixel(ax,ay)
    if aa < 0.99 then return true end
    local br,bg,bb = b:getPixel(bx,by)
    return math.abs(ar-br)<0.02 and math.abs(ag-bg)<0.02 and math.abs(ab-bb)<0.02
  end
  local function compareRegion(result, input, x,y,w,h, dx,dy, sx,sy)
    for yy=y,y+h-1 do for xx=x,x+w-1 do
      local px,py = math.floor(dx+(xx-x+0.5)*sx),math.floor(dy+(yy-y+0.5)*sy)
      if not equalPixel(input,xx,yy,result,px,py) then
        return false, (" source %d,%d -> %d,%d"):format(xx,yy,px,py)
      end
    end end
    return true,""
  end
  local reports = {}
  local cases = {
    {972,1536,"center","classic","fixed"},
    {972,1536,"upper","classic","fill"},
    {1536,972,"top","classic","fill"},
    {972,1536,"upper","wide","fixed"},
    {1536,972,"center","wide","fixed"},
    {1536,972,"top","wide","fill"},
    {972,1536,"center","extended","fixed"},
    {972,1536,"upper","extended","fill"},
    {1536,972,"top","extended","fixed"},
    {1536,972,"center","extended","fill"},
    {480,800,"upper","wide","fixed"},
    {800,480,"top","classic","fill"},
  }
  for _, case in ipairs(cases) do
    local w,h,position,layout,fit = unpack(case)
    love.window.setMode(w,h,{vsync=0})
    Position.setMode(position)
    for _, factor in ipairs({0.5,0.75,1}) do
      Game.save.options = {jpDialogScale=factor,uiLayout="centered",
        battleLayout=layout=="classic" and "classic" or "wide",battleFit=fit,
        battleHud=layout=="extended" and "extended" or "fixed",battleBg="white"}
      for _, phase in ipairs({"menu","messages"}) do
        battle.phase = phase
        battle.current = phase=="messages" and {} or nil
        battle.shown = {Font.encode("サンプルの こうげき！"),Font.encode("テストの HPが へった")}
        local label=table.concat({w.."x"..h,position,layout,fit,factor,phase},"-")
        japaneseCommand=false
        Game:draw(); g.setCanvas()
        local result = Viewport.target():newImageData()
        local r = rects
        check(Renderer.dialogScale==factor,label.." Game passes shared window size")
        if layout~="classic" and phase=="menu" then
          check(japaneseCommand,label.." Japanese party command uses kana instead of English ligatures")
        end
        local baseline = math.floor(math.min(w/160,h/144))
        local expected=math.min(Renderer.windowScale(baseline,factor),
          math.max(1,math.floor(math.min((r.body.w-2*r.margin)/r.uiw,
            (r.body.h-2*r.margin)/r.uih))))
        check(r.Up==expected,
          label.." shared window factor fits readable whole pixels in playfield")
        check(math.abs(r.Ux*r.dpiX-r.Uy*r.dpiY)<0.00001,
          label.." HP bars and characters retain square pixels")
        check(r.uox>=0 and r.uoy>=0 and r.uox+r.uvpw<=w and r.uoy+r.uvph<=h,
          label.." whole battle fits the display")
        if layout~="classic" then
          check(anchors and #anchors==3,label.." separate enemy/player/command anchors exist")
          local previousBottom=0
          for i,a in ipairs(anchors or {}) do
            local dx,dy=Layout.place(r,a)
            local same,where=compareRegion(result,hud,a.x,a.y,a.w,a.h,dx,dy,r.Ux,r.Uy)
            check(same,label.." anchored HP/name/command pixels match"..where)
            if i>1 then check(dy>=previousBottom,label.." vertical HUD groups do not overlap") end
            previousBottom=dy+a.h*r.Uy
          end
        else
          local same,where=compareRegion(result,source,0,0,r.uiw,r.uih,r.uox,r.uoy,r.Ux,r.Uy)
          check(same,label.." all battle pixels share the dialogue scale"..where)
        end
        local hp=layout~="classic" and hud or source
        local hpX,hpY=layout=="classic" and 32 or 24,16
        local hr,hg,hb=hp:getPixel(hpX,hpY+3)
        check(hr>0.1 and hr<0.9 and hg==hr and hb==hr,label.." real HP bar draws a filled segment")
        reports[#reports+1]={case=label,uiPixels=r.Up,worldPixels=r.Sp}
        if factor~=1 and phase=="menu" and w>=972 then
          write("battle-"..label..".png",result:encode("png"):getString())
        end
      end
    end
  end
  Renderer.endFrame = endFrame
  Font.draw = drawText
  write("geometry.json",require("src.link.Json").encode({romUsed=false,cases=reports}))
end
