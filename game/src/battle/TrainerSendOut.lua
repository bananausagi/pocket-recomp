-- Presentation of an opposing trainer's Poke Ball opening on the native
-- enemy picture card. The real battle queue still owns text, cries and HUD.
-- No capture animation, catch sound, or screen-space throw is reused here.
local SendOut = {}
SendOut.OPEN = .18
SendOut.REVEAL = .27
SendOut.DURATION = .62
SendOut.TIMEOUT = 2

local function smooth(v)
  v = math.max(0, math.min(1, v))
  return v * v * (3 - 2 * v)
end

function SendOut.enabled(battle, battler)
  local o = battle.game and battle.game.save and battle.game.save.options or {}
  return battle.jpEnemySendOut3D and battler == battle.enemy
    and battle.kind == 'trainer' and not battle.demo and not battle.safari
    and o.jpBattleIntro ~= 'original' and o.animations ~= false
    and not o.reduceMotion and not o.jpReduceMotion
end

function SendOut.new(now)
  return { time = 0, started = now, lastTime = now }
end

function SendOut.advance(state, now)
  local dt = math.max(0, now - state.lastTime)
  state.lastTime = now
  -- A menu/background pause does not skip straight across the opening.
  if dt <= .25 then
    state.time = math.min(SendOut.DURATION, state.time + dt)
  else
    state.started = state.started + dt
  end
  if now - state.started >= SendOut.TIMEOUT then state.expired = true end
end

function SendOut.scale(state)
  local t = (state.time - SendOut.REVEAL) / (SendOut.DURATION - SendOut.REVEAL)
  return t <= 0 and 0 or .10 + .90 * smooth(t)
end

function SendOut.done(state)
  return state.expired or state.time >= SendOut.DURATION and state.finalDrawn
end

local sheet, top, bottom
local FLECKS = {{-1,-1},{1,-1},{-1,.3},{1,.3}}
local function ballSheet()
  if sheet == nil then
    local ok, image = pcall(love.graphics.newImage, 'assets/generated/battle/balls.png')
    sheet = ok and image or false
    if sheet then
      top = love.graphics.newQuad(0, 0, 8, 4, sheet:getDimensions())
      bottom = love.graphics.newQuad(0, 4, 8, 4, sheet:getDimensions())
    end
  end
  return sheet
end

function SendOut.draw(state, image, x, y, scale)
  local g = love.graphics
  local w, h = image:getDimensions()
  local cx, foot = x + w * scale / 2, y + h * scale
  local t = state.time
  local grow = SendOut.scale(state)
  local open = smooth((t - SendOut.OPEN) / .12)
  local dissolve = 1 - smooth((t - SendOut.REVEAL) / .14)
  local flight = 1 - smooth(t / SendOut.OPEN)
  local bx, by = cx + 20 * flight * scale, foot - (8 + 14 * flight) * scale
  if t >= SendOut.OPEN and t < SendOut.DURATION then
    local light = 1 - smooth((t - SendOut.REVEAL) / .28)
    g.setColor(1, 1, 1, light * .8)
    g.circle('fill', cx, foot - 10 * scale, (3 + 16 * open) * scale, 24)
    -- Four small light flecks, kept within the same card as the ball.
    for _,p in ipairs(FLECKS) do
      g.rectangle('fill', cx + p[1] * (6 + 15 * open) * scale,
        foot - 10 * scale + p[2] * (6 + 15 * open) * scale, 2 * scale, 2 * scale)
    end
  end
  if grow > 0 then
    g.setColor(1, 1, 1, 1)
    g.draw(image, cx - w * scale * grow / 2, foot - h * scale * grow,
      0, scale * grow, scale * grow)
  end
  if dissolve > 0 then
    local ball = ballSheet()
    g.setColor(1, 1, 1, dissolve)
    if ball then
      g.draw(ball, top, bx - 8 * scale, by - (8 + 6 * open) * scale, 0, 2 * scale, 2 * scale)
      g.draw(ball, bottom, bx - 8 * scale, by + 3 * open * scale, 0, 2 * scale, 2 * scale)
    else
      -- A missing optional ball sheet must not make the whole card vanish.
      g.setColor(0, 0, 0, dissolve)
      g.circle('fill', bx, by, 7 * scale, 16)
      g.setColor(1, 1, 1, dissolve)
      g.circle('fill', bx, by, 5 * scale, 16)
      g.setColor(0, 0, 0, dissolve)
      g.rectangle('fill', bx - 6 * scale, by - scale, 12 * scale, 2 * scale)
    end
  end
  g.setColor(1, 1, 1, 1)
  if t >= SendOut.DURATION then state.finalDrawn = true end
end

return SendOut
