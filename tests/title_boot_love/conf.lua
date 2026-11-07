function love.conf(t)
  t.identity = "kanto-jp11-title-fixture"
  t.version = "11.5"
  t.window.width, t.window.height = 480, 800
  t.window.vsync = 0
  t.window.title = "ROM-free title boot verification"
  t.modules.audio, t.modules.physics = false, false
end
