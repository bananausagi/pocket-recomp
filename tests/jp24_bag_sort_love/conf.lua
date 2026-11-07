function love.conf(t)
  love.filesystem.setSymlinksEnabled(true)
  t.identity='jp24-bag-sort-fixture'
  t.window.width=480;t.window.height=800;t.window.vsync=0
  t.modules.audio=false;t.modules.physics=false;t.modules.joystick=false
end
