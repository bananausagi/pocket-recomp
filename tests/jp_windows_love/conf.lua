function love.conf(t)
  love.filesystem.setSymlinksEnabled(true)
  t.identity = "kanto-jp7-window-fixtures"
  t.version = "11.5"
  t.window.width, t.window.height = 480, 800
  t.window.vsync = 0
  t.window.title = "ROM-free Japanese window composition"
  t.modules.audio, t.modules.physics = false, false
end
