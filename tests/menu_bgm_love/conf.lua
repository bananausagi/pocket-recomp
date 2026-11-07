function love.conf(t)
  love.filesystem.setSymlinksEnabled(true)
  t.identity = 'jp20-menu-bgm-fixture'
  t.version = '11.5'
  t.window.width, t.window.height = 360, 160
  t.window.vsync = 0
  t.modules.physics = false
end
