local root = assert(os.getenv("JP_TEST_ROOT"))
local U = dofile(root .. "/tests/drivers/util.lua")
local baseSmoke = dofile(root .. "/tests/drivers/japanese_red_smoke.lua")

return function(game)
  for _, id in ipairs({ "DRAMALESS_SHAPE", "running_shoes", "erilab_bottomless_bag" }) do
    local mod = game.mods.mods[id]
    assert(mod and mod.state == "loaded", id .. ": " .. tostring(mod and mod.failure))
    print("JP MOD PASS: loaded " .. id)
  end
  assert(#game.mods.errors == 0, table.concat(game.mods.errors, "\n"))
  assert(require("src.inventory.Bag").capacity(game.data) == 255, "bag capacity")
  local Pipelines = require("src.render.Pipelines")
  local voxel = assert(Pipelines.get("voxel"), "voxel pipeline missing")
  local draw = voxel.drawWorld
  local frames3d = 0
  voxel.drawWorld = function(ctx)
    local canvas = draw(ctx)
    if canvas then frames3d = frames3d + 1 end
    return canvas
  end
  baseSmoke(game)
  local player = game.overworld.player
  game.input.state.b = false
  local walk = player:stepLength("left")
  game.input.state.b = true
  local run = player:stepLength("left")
  game.input.state.b = false
  assert(run == math.floor(walk / 2 + 0.5), "B dash speed")
  print("JP MOD PASS: walk/run frames " .. walk .. "/" .. run)
  local Bag = require("src.inventory.Bag")
  local inventory = { inventory = {}, bagOrder = {} }
  local count = 0
  for id in pairs(game.data.items) do
    if not id:find("BADGE", 1, true) then
      assert(Bag.add(inventory, id, 1, game.data), "bag blocked at " .. count)
      count = count + 1
      if count == 25 then break end
    end
  end
  assert(count == 25, "25 item types available")
  print("JP MOD PASS: bag accepts 25 distinct items")
  assert(frames3d > 10, "no rendered voxel frames: " .. frames3d)
  assert(Pipelines.worldPipeline() == "voxel", "voxel pipeline retired")
  assert(#game.mods.errors == 0, table.concat(game.mods.errors, "\n"))
  local level = Pipelines.level("voxel")
  Pipelines.setLevel("voxel", 0)
  assert(Pipelines.worldPipeline() == nil, "2D fallback switch")
  Pipelines.setLevel("voxel", level)
  print("JP MOD PASS: voxel frames " .. frames3d)
  print("JAPANESE MODPACK SMOKE PASSED")
end
