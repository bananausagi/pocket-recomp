function love.conf(t)
  love.filesystem.setSymlinksEnabled(true)
  t.identity = 'jp19-music-clock-fixture'
  t.version = '11.5'
  t.window.width, t.window.height = 320, 160
  t.window.vsync = 0
  t.modules.physics = false
end
