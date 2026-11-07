function love.conf(t)
  love.filesystem.setSymlinksEnabled(true)
  t.identity="kanto-jp9-frustum-qa"
  t.version="11.5"
  t.window.width,t.window.height=384,288
  t.window.vsync=0
  t.modules.audio,t.modules.physics=false,false
end
