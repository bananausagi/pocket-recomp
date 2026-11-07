function love.conf(t)
  t.version='11.5'
  t.identity='jp33-gles-qa'
  t.window.width,t.window.height=64,64
  t.window.vsync=0
  t.modules.audio,t.modules.physics=false,false
end
