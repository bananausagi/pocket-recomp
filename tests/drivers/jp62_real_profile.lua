-- Driver (jp.62): frame times on the real imported Red JP data -- the first
-- field picture after a cold start on Route 1, then a first and a second wild
-- battle. POKEPORT_NOJIT=1 switches LuaJIT's compiler off like LÖVE on arm64
-- Android. Prints [p62] lines; takes no screenshots unless SHOT_DIR is set.
return function(game)
  if os.getenv("POKEPORT_NOJIT") == "1" and jit and jit.off then jit.off(); jit.flush() end
  local U = dofile("tests/drivers/util.lua")
  local now = love.timer.getTime
  local Pipelines = require("src.render.Pipelines")
  game.save.options.pipelines = { voxel = 2 }
  Pipelines.applyOptions(game.save.options)
  local w, h = tonumber(os.getenv("P62_W")) or 540, tonumber(os.getenv("P62_H")) or 1200
  love.window.setMode(w, h, { vsync = 0 })
  if #game.save.party == 0 then
    game.save.party[1] = require("src.pokemon.Pokemon").new(game.data, "PIKACHU", 8)
  end
  print(("[p62] jit=%s size=%dx%d"):format(tostring(jit and jit.status and jit.status()), w, h))

  local function frames(label, n, stop)
    local worst, sum, count, slow, last = 0, 0, 0, {}, now()
    for i = 1, n do
      U.wait(1)
      local t = now(); local dt = t - last; last = t
      sum, count = sum + dt, count + 1
      if dt > worst then worst = dt end
      if dt > 0.05 then slow[#slow + 1] = ("%d:%.0f"):format(i, dt * 1000) end
      if stop and stop() then break end
    end
    print(("[p62] %-9s frames=%d total=%.0fms worst=%.0fms over50=%s"):format(
      label, count, sum * 1000, worst * 1000, table.concat(slow, " ")))
  end

  -- P62_PROFILE=1: sample where the time goes over the cold start (LuaJIT's
  -- profiler works with the compiler off too).
  local prof, counts
  if os.getenv("P62_PROFILE") == "1" then
    prof = require("jit.profile"); counts = {}
    prof.start("i1", function(thread, samples)
      local stack = prof.dumpstack(thread, "pl;", 12)
      counts[stack] = (counts[stack] or 0) + samples
    end)
  end
  -- P62_WRAP=1: inclusive time of every function of the field/render modules,
  -- per frame; the slowest frames' top entries are printed.
  local bucket, frameBuckets = nil, {}
  if os.getenv("P62_WRAP") == "1" then
    local V = game.mods and game.mods.exports and game.mods.exports.DRAMALESS_SHAPE
      and game.mods.exports.DRAMALESS_SHAPE.lib
    local wrapped = {}
    local function deep(label, M)
      if type(M) ~= "table" or wrapped[M] then return end
      wrapped[M] = true
      local keys = {}
      for k, v in pairs(M) do if type(v) == "function" and type(k) == "string" then keys[#keys + 1] = k end end
      for _, k in ipairs(keys) do
        local f = M[k]
        if not (label == "Voxel3D" and (k == "project" or k == "pushQuad")) then
          M[k] = function(...)
            if not bucket then return f(...) end
            local t = now()
            local out = { n = select("#", ...), f(...) }
            local e = bucket[label .. "." .. k] or { n = 0, t = 0 }
            bucket[label .. "." .. k] = e; e.n = e.n + 1; e.t = e.t + now() - t
            return unpack(out, 1, out.n + 50)
          end
        end
      end
    end
    for _, name in ipairs({ "Voxel3D", "VoxelScene", "Sky", "Water", "ShadowMap", "AntiAlias", "TiltShift", "SceneGlow",
        "SceneEffects", "Atmosphere", "ChunkMesher", "TerrainAtlas", "Structures", "TileShape", "CliffTerrain",
        "GlassMask", "DayNight", "VoxelBattleWarmup", "VoxelBootWarmup", "VoxelPrecache", "TreeInstances",
        "SpriteBillboards", "WeatherParticles", "VoxelBattleScene", "VoxelBattleStandalone", "BattlePics", "VoxelBattleArenaProvider", "VoxelBattleCardProvider", "BattleArena", "BattleCam", "BattleIntroFocus" }) do
      if V then local ok, M = pcall(V.require, name); if ok then deep(name, M) end end
    end
    for _, name in ipairs({ "src.world.MapLoader", "src.render.TileRenderer", "src.render.PaletteFX", "src.render.Renderer", "src.battle.BattleState", "src.pokemon.Sprites", "src.render.Assets", "src.battle.BattlePresentation", "src.battle.JapaneseBattlePanels", "src.render.BattleTransition",
        "src.core.Music", "src.core.ChipAudio", "src.core.Sound" }) do
      local ok, M = pcall(require, name); if ok then deep(name:match("[^.]+$"), M) end
    end
    print("[p62] wrap V=" .. tostring(V ~= nil))
  end
  local function report()
    local rows = {}
    for i, b in ipairs(frameBuckets) do rows[#rows + 1] = { i, b.dt, b.labels } end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    for r = 1, math.min(3, #rows) do
      local list = {}
      for k, e in pairs(rows[r][3]) do list[#list + 1] = { k, e } end
      table.sort(list, function(a, b) return a[2].t > b[2].t end)
      print(("[p62wrap] frame %d %.0fms"):format(rows[r][1], rows[r][2] * 1000))
      for j = 1, math.min(18, #list) do print(("[p62wrap]    %-44s %7.1fms n=%d"):format(list[j][1], list[j][2].t * 1000, list[j][2].n)) end
    end
  end
  local t0 = now()
  if os.getenv("P62_WRAP") == "1" then
    bucket = {}
    U.teleport(game, "ROUTE_1", 9, 20, "up")
    frameBuckets[#frameBuckets + 1] = { dt = now() - t0, labels = bucket }
    local last = now()
    for _ = 1, 40 do
      bucket = {}; U.wait(1)
      local t = now(); frameBuckets[#frameBuckets + 1] = { dt = t - last, labels = bucket }; last = t
    end
    bucket = nil
    report()
    -- then the first wild battle, frame by frame
    frameBuckets = {}
    local battle = require("src.battle.BattleState").newWild(game, "PIDGEY", 3)
    game.overworld:pushBattle(battle)
    last = now()
    for _ = 1, 160 do
      bucket = {}; U.wait(1)
      local t = now(); frameBuckets[#frameBuckets + 1] = { dt = t - last, labels = bucket }; last = t
    end
    bucket = nil
    print("[p62wrap] ---- first battle")
    report()
    return
  end
  U.teleport(game, "ROUTE_1", 9, 20, "up")
  print(("[p62] teleport %.0fms"):format((now() - t0) * 1000))
  frames("field", prof and 12 or 360)
  if prof then
    prof.stop()
    local byFn, rows = {}, {}
    for stack, n in pairs(counts) do
      -- inclusive per function: every frame on the stack gets the samples once
      local seen = {}
      for fn in stack:gmatch("[^;]+") do
        if not seen[fn] then seen[fn] = true; byFn[fn] = (byFn[fn] or 0) + n end
      end
    end
    for fn, n in pairs(byFn) do rows[#rows + 1] = { fn, n } end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(40, #rows) do print(("[p62prof] %6d %s"):format(rows[i][2], rows[i][1])) end
    return
  end
  if os.getenv("SHOT_DIR") then U.shot(game, os.getenv("SHOT_DIR") .. "/p62_field.png") end

  local BattleState = require("src.battle.BattleState")
  for index, species in ipairs({ "PIDGEY", "RATTATA" }) do
    local battle = BattleState.newWild(game, species, 3)
    local tb = now()
    game.overworld:pushBattle(battle)
    print(("[p62] battle%d push %.0fms"):format(index, (now() - tb) * 1000))
    frames("battle" .. index, 420)
    if os.getenv("SHOT_DIR") then U.shot(game, os.getenv("SHOT_DIR") .. "/p62_battle" .. index .. ".png") end
    while game.stack:top() ~= game.overworld do game.stack:pop() end
    frames("after" .. index, 120)
  end
end
