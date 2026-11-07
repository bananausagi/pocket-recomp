function love.conf(t)
  love.filesystem.setSymlinksEnabled(true)
  t.identity = "gen1recomp-jp3-fixture-qa"
  t.version = "11.5"
  t.window.width, t.window.height = 800, 600
  t.window.vsync = 0
  t.window.title = "JP display fixture QA (no ROM)"
  t.modules.audio = os.getenv('JP_QA_BATTLE_SEAMLESS') == '1'
  t.modules.physics = false
end
