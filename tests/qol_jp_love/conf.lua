function love.conf(t)
  love.filesystem.setSymlinksEnabled(true)
  t.identity = "gen1recomp-qol-jp-fixture-qa"
  t.version = "11.5"
  t.window.width, t.window.height = 800, 600
  t.window.vsync = 0
  t.window.title = "QoL Japanese fixture QA (no ROM)"
  t.modules.audio = false
  t.modules.physics = false
end
