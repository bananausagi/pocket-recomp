-- External QA wrapper: runs the delivered entrypoint and its real event loop.
local root = assert(os.getenv('JP_MAIN_QA_ROOT'))
local output = assert(os.getenv('JP_MAIN_QA_OUTPUT'))
local configFile = assert(os.getenv('JP_MAIN_QA_CONFIG'))
local Json = require('src.link.Json')
local function read(path)
  local f = assert(io.open(path, 'rb')); local bytes = f:read('*a'); f:close(); return bytes
end
local function write(path, bytes)
  local f = assert(io.open(output .. '/' .. path, 'wb')); f:write(bytes); f:close()
end
local config = assert(Json.decode(read(configFile)))
local report = { events = {}, screenshots = {}, checks = {}, dimensions = {config.width, config.height} }
local function check(value, message)
  assert(value, message)
  report.checks[#report.checks + 1] = message
  print('PASS ' .. message)
end
local importer
assert(loadfile(root .. '/main.lua'))()
local RomImporter = require('src.import.RomImporter')
local originalNew = RomImporter.new
RomImporter.new = function(...)
  importer = originalNew(...)
  return importer
end
local originalLoad, originalUpdate, originalDraw = love.load, love.update, love.draw
local originalError = love.errorhandler or love.errhand
local function hitDescription(hit)
  local result = {}
  for k, v in pairs(hit) do
    if type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean' then result[k] = v end
  end
  local r = hit.rect or hit
  result.rect = {x=r.x,y=r.y,w=r.w,h=r.h}
  return result
end
local function hits()
  local rows = {}
  for _, hit in ipairs(importer._ui.hits or {}) do rows[#rows + 1] = hitDescription(hit) end
  return rows
end
local function click(selector, touch)
  for _, hit in ipairs(importer._ui.hits or {}) do
    local match = true
    for key, wanted in pairs(selector) do
      if key == 'contains' then
        local text = tostring(hit.label or hit.text or hit.key or hit.id or '')
        if not text:find(wanted, 1, true) then match=false end
      elseif hit[key] ~= wanted then match=false end
    end
    if match then
      local r = hit.rect or hit
      local x, y = assert(r.x)+assert(r.w)/2, assert(r.y)+assert(r.h)/2
      if touch then
        love.touchpressed('qa-touch',x,y,0,0,1)
        love.touchreleased('qa-touch',x,y,0,0,0)
      else
        if love.mousemoved then love.mousemoved(x,y,0,0,false) end
        love.mousepressed(x,y,1,false,1)
        if love.mousereleased then love.mousereleased(x,y,1,false,1) end
      end
      return
    end
  end
  error('No hit matches '..Json.encode(selector)..'; available='..Json.encode(hits()))
end
local function act(action)
  if action.lua then assert(loadstring('return function(imp) '..action.lua..' end'))()(importer)
  elseif action.click then click(action.click, action.touch)
  elseif action.key then
    love.keypressed(action.key, action.key, false)
    if love.keyreleased then love.keyreleased(action.key, action.key) end
  elseif action.wheel then love.wheelmoved(0, action.wheel)
  elseif action.drag then
    local ui=importer._ui
    local x=ui.x+ui.w/2
    local y=ui.top+ui.bodyH*0.65
    local dy=action.drag
    love.touchpressed('qa-drag',x,y,0,0,1)
    love.touchmoved('qa-drag',x,y+dy,0,dy,1)
    love.touchreleased('qa-drag',x,y+dy,0,0,0)
  elseif action.gamepad then love.gamepadpressed(nil, action.gamepad)
  else error('Unknown QA action') end
  report.events[#report.events+1] = action
end
function love.load(args)
  originalLoad(args)
  check(importer ~= nil, 'real main.lua created the launcher')
  local save = love.filesystem.getSaveDirectory()
  check(save:sub(1, #assert(os.getenv('XDG_DATA_HOME'))) == os.getenv('XDG_DATA_HOME'), 'save directory is isolated')
  report.saveDirectory = save
  for version, ready in pairs(importer.ready) do check(not ready, version .. ' has no imported ROM') end
  check(love.graphics.getWidth()==config.width and love.graphics.getHeight()==config.height, 'requested real window dimensions')
end
local phaseIndex, phaseFrame, actionIndex, capturePending = 1, 0, 1, false
function love.update(dt)
  originalUpdate(dt)
  phaseFrame = phaseFrame + 1
  local phase = config.phases[phaseIndex]
  if not phase then return end
  if phase.actions and actionIndex <= #phase.actions and phaseFrame % 4 == 0 then
    act(phase.actions[actionIndex]); actionIndex = actionIndex + 1
  end
end
function love.draw()
  originalDraw()
  local phase = config.phases[phaseIndex]
  if not phase or capturePending then return end
  local wait = math.max(phase.frames or 12, 4 * #(phase.actions or {}) + 8)
  if phaseFrame < wait then return end
  if phase.page then check(importer._ui.page == phase.page, phase.name .. ': page is ' .. phase.page) end
  if phase.check then
    local fn = assert(loadstring('return function(imp) ' .. phase.check .. ' end'))()
    check(fn(importer), phase.name .. ': interaction state')
  end
  capturePending = true
  local snapshot = {name=phase.name,page=importer._ui.page,hits=hits(),scroll=importer._ui.scroll}
  love.graphics.captureScreenshot(function(data)
    write(phase.name .. '.png', data:encode('png'):getString())
    report.screenshots[#report.screenshots+1] = snapshot
    print('SCREENSHOT ' .. phase.name)
    phaseIndex, phaseFrame, actionIndex, capturePending = phaseIndex+1, 0, 1, false
    if phaseIndex > #config.phases then
      write('report.json',Json.encode(report));print('PASS real launcher flow complete');love.event.quit(0)
    end
  end)
end
function love.errorhandler(message)
  report.error = tostring(message)
  report.traceback = debug.traceback('',2)
  write('report.json',Json.encode(report))
  io.stderr:write('QA APPLICATION ERROR: '..tostring(message)..'\n'..report.traceback..'\n')
  if originalError then
    local ok, loop = pcall(originalError, message)
    if ok and type(loop)=='function' then pcall(loop) end
  end
  return function() return 1 end
end
love.errhand = love.errorhandler
