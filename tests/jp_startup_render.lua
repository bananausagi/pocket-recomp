-- Shared Japanese fixture atlas is initialized by jp_windows_love/main.lua.
return function(Game, Renderer, check, write)
  local g=love.graphics
  local Font=require("src.render.Font")
  local Save=require("src.core.SaveData")
  local Runtime=require("src.mods.Runtime")
  Runtime.install(require("src.mods.Events").new(),require("src.mods.Hooks").new())
  Runtime.hooks:wrap("render.viewport",function(next,ctx)
    local r=next(ctx);r.capture=true;return r
  end,0,"startup-fixture")
  local Viewport=require("src.render.GameViewport")
  local originalLoad, originalDraw=Save.load, Font.draw
  local saved
  Save.load=function()return saved end
  local drawCount,overflow=0,false
  Font.draw=function(text,x,y,...)
    drawCount=drawCount+1
    if x<0 or x+Font.width(text)>160 or y<0 or y+8>144 then overflow=true end
    return originalDraw(text,x,y,...)
  end
  for _,size in ipairs({{480,800},{800,480},{972,1536}})do
    love.window.setMode(size[1],size[2],{vsync=0})
    for _,kind in ipairs({"new","continue","confirm-new","failed-continue"})do
      saved=kind~="new" and {player={name="レッド"},options={}} or nil
      Game.stack:clear()
      local title=Game:makeTitleState()
      Game.stack:push(title)
      -- The real title now precedes these commands. This older render fixture
      -- still covers command layout; title_boot_love exercises title input/art.
      title:openMenu()
      title=Game.stack:top()
      if kind=="confirm-new" then title:confirmNew() end
      if kind=="failed-continue" then
        saved=nil;title.menu.items[1].onSelect()
      end
      Viewport.begin(1)
      Renderer.dialogScale=0.75;Renderer.uiCentered=true;Renderer.uiAnchorHold=false
      Renderer:beginFrame(false);title:draw();Renderer:endFrame()
      local canvas=Viewport.target();g.setCanvas()
      local label=kind.."-"..size[1].."x"..size[2]
      write(label..".png",canvas:newImageData():encode("png"):getString())
      check(not overflow,label.." title/menu/warning/footer fit 160x144")
      check(title.isPlayerStartMenu,label.." uses safe JP commands after the title")
    end
  end
  check(drawCount>50,"real font draws all startup variants")
  Font.draw,Save.load=originalDraw,originalLoad
end
