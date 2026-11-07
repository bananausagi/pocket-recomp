-- jp.90: Gold/Silver/Crystal maps dressed as the Red map contract the voxel
-- pipeline was written against.
--
-- The pipeline (TileShape, Structures, ChunkMesher, TerrainAtlas, VoxelScene)
-- reads a Red map: tile ids on the 8px grid through map:tileAt, a tileset
-- whose image is one tile per 8px slot, per-tile walkable/water/door sets and
-- the cell predicates.  A gen2 map has all of that information but spelled
-- differently: collision lives in per-block COLL_* quads, Crystal tiles carry
-- flip/bank attributes, and colour comes from eight BG palettes applied by a
-- shader at draw time.  This file builds, once per map id, a read-only facade
-- with the Red field names, so the Red path through every module stays byte
-- for byte what it was.
--
-- Nothing here writes to the gen2 world or to disk.  The grayscale
-- per-tileset sheets live in memory (VirtualAssets) under a virtual
-- dramaless-gen2/ path, which Structures and GlassMask read back as pixels.

local V = ...

local Gen2Facade = {}

-- Gen 2 engine modules refuse to load inside a Gen 1 game, so they resolve
-- on first use (only ever reached when GameVersion.generation() == 2).
local function lazy(name)
  return setmetatable({}, { __index = function(_, k) return require(name)[k] end })
end
local G2Map = lazy("src.world.gen2.Map")
local BorderFill = lazy("src.world.gen2.BorderFill")
local Permissions = lazy("src.world.gen2.Permissions")
local TileAttrs = lazy("src.world.gen2.TileAttrs")
local Palettes = lazy("src.world.gen2.Palettes")
local GbcPalette = require("src.render.GbcPalette")
local PixelCanvas = require("src.render.PixelCanvas")

local PREFIX = "G2_"
local SHEET_DIR = "dramaless-gen2"
local SHEET_VERSION = "v1"
local SHEET_TILES = 256          -- a tile id is one byte; Crystal's sheet is 256 slots
local SHEET_W, SHEET_H = 128, 128

local facades = {}   -- gen2 map id -> facade
local proxies = {}   -- tileset|roof -> proxy tileset
local votesFor = {}  -- gen2 tileset name -> vote result

local function isCrystal(world)
  if world and world.isCrystal then
    local ok, v = pcall(world.isCrystal, world)
    if ok then return v and true or false end
  end
  return false
end

local function roofOf(world, def)
  if not (world and world.roofs and world.roofs.mapGroupRoofs) then return nil end
  if def.tileset ~= "TILESET_JOHTO" and def.tileset ~= "TILESET_JOHTO_MODERN" then
    return nil
  end
  return world.roofs.mapGroupRoofs[def.group]
end

-- ---------------------------------------------------------------- votes
-- A Red tileset names its walkable/water/door tiles; a gen2 tileset names
-- collision per CELL.  Every cell of every map that uses the tileset votes
-- for the four tiles drawn in it, so a tile that is floor nearly everywhere
-- reads as floor.  TileShape.at only falls back to the per-tile class in
-- cells the map itself says are blocked, so a wrong vote can at most make a
-- blocked cell look like floor (never the reverse).
-- jp.91 (par_B): the tree wall.  Red's OVERWORLD profile draws its border
-- tree block ($0F: tiles 64/65/80/81) ROUND -- per-cell `cylinder` with the
-- `tree_support` companion tag, carved by Structures.buildCylinders -- and a
-- gen2 tileset has the same scenery under the block ids BorderFill forces
-- for its TREES fill (its local FILL_BLOCKS table; duplicated here because
-- it is not exported: JOHTO / JOHTO_MODERN / FOREST $05, KANTO $0F).  Every
-- tile those blocks draw is pinned the same way, which also covers the tree
-- rows inside the maps -- the same tiles make up the other tree blocks.
-- The forest's $05 is one 32x32 tree drawing: its top-left cell anchors a
-- `canopy` (the 2x2-cell hull) and the other three cells are its partners.
local TREE_BLOCKS = {
  TILESET_JOHTO = 0x05, TILESET_JOHTO_MODERN = 0x05,
  TILESET_KANTO = 0x0f, TILESET_FOREST = 0x05,
}
local CANOPY_TILESETS = { TILESET_FOREST = true }
-- print the pinned tile lists per tileset (the proposed voxel_heights
-- entries) to the log; os.getenv is not available inside the mod sandbox
local DUMP_TREE_PINS = false

local function treeClasses(name, blocks)
  local id = TREE_BLOCKS[name]
  local tiles = id and blocks and blocks[id + 1]
  if type(tiles) ~= "table" then return nil end
  local seen, cylinder, canopy, support = {}, {}, {}, {}
  for i = 1, 16 do
    local t = tiles[i]
    if type(t) == "number" and not seen[t] then
      seen[t] = true
      local row, col = math.floor((i - 1) / 4), (i - 1) % 4
      if CANOPY_TILESETS[name] and row < 2 and col < 2 then
        canopy[#canopy + 1] = t
      else
        cylinder[#cylinder + 1] = t
      end
      support[#support + 1] = t
    end
  end
  -- jp.91 (par_E): the STACKED tree.  Red's border tree is one 16x16 ball
  -- per cell, but Johto's ($05 in JOHTO and JOHTO_MODERN) is a 16x32
  -- drawing two cells tall -- pointed crown and upper body in the north
  -- cell, lower body, rounded bottom and TRUNK in the south cell -- and
  -- carved cell by cell it is two packed drums, a ribbed hedge with no
  -- trunk and no daylight between neighbours.  The block tells which it
  -- is: a column whose cell-row 0 and cell-row 2 start with different
  -- tiles is two different cells of one tree, and its row-0 tile is the
  -- crown anchor Structures.buildCylinders stacks the cell under it onto
  -- (the `tree_stack` knob).  A ball block repeats its rows (KANTO), and
  -- the forest's 32x32 tree is the canopy's business, so neither stacks.
  local stack, stackSeen = {}, {}
  if not CANOPY_TILESETS[name] then
    for col = 0, 3, 2 do
      local top, lower = tiles[col + 1], tiles[2 * 4 + col + 1]
      if type(top) == "number" and type(lower) == "number" and top ~= lower
         and not stackSeen[top] then
        stackSeen[top] = true
        stack[#stack + 1] = top
      end
    end
  end
  table.sort(cylinder); table.sort(canopy); table.sort(support); table.sort(stack)
  return { cylinder = cylinder, canopy = canopy, support = support, seen = seen,
           stack = stack }
end

local function tally(world, name, gts)
  local res = votesFor[name]
  if res then return res end
  local count = {}
  local function vote(t, kind)
    local c = count[t]
    if not c then
      c = { walk = 0, water = 0, grass = 0, ledge = 0, door = 0, blocked = 0,
            counter = 0, tree = 0 }
      count[t] = c
    end
    c[kind] = c[kind] + 1
  end
  local blocks, coll = gts.blocks, gts.collision
  for _, def in pairs(world.maps or {}) do
    if type(def) == "table" and def.tileset == name and def.blocks
       and def.width and def.height then
      local outdoor = G2Map.isOutdoor(def)
      local border = def.borderBlock or 0
      for by = 0, def.height - 1 do
        for bx = 0, def.width - 1 do
          local raw = def.blocks[by * def.width + bx + 1] or 0
          local id = BorderFill.blockFor(raw, border) or 0
          local block = blocks and blocks[id + 1]
          local quad = coll and coll[id + 1]
          if block and quad and raw ~= 0 then
            for ly = 0, 1 do
              for lx = 0, 1 do
                local c = quad[ly * 2 + lx + 1] or 0xff
                local kind
                if Permissions.isLedge and Permissions.isLedge(c) then kind = "ledge"
                elseif Permissions.isWater(c) then kind = "water"
                elseif Permissions.isGrass and Permissions.isGrass(c) then kind = "grass"
                elseif Permissions.isCounter and Permissions.isCounter(c) then kind = "counter"
                elseif (Permissions.isCutTree and Permissions.isCutTree(c))
                    or (Permissions.isHeadbuttTree and Permissions.isHeadbuttTree(c)) then
                  kind = "tree"
                elseif Permissions.isWalkable(c) then kind = "walk"
                else kind = "blocked" end
                for ry = 0, 1 do
                  for rx = 0, 1 do
                    local t = block[(ly * 2 + ry) * 4 + lx * 2 + rx + 1]
                    if t then
                      vote(t, kind)
                      -- a door is folded from the tile under the frame, which
                      -- Structures reads at the cell's bottom-left
                      if outdoor and rx == 0 and ry == 1
                         and Permissions.isImmediateWarp(c) then
                        vote(t, "door")
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  res = { walkable = {}, waterTiles = {}, doorTiles = {}, authored = {},
          grassTile = nil }
  local bestGrass, authored = 0, { ledge = {}, counter = {}, tree = {} }
  for t, c in pairs(count) do
    local floor = c.walk + c.grass + c.ledge + c.door
    if floor > c.blocked + c.tree + c.counter + c.water then res.walkable[t] = true end
    if c.water > c.walk + c.blocked + c.grass + c.ledge then res.waterTiles[t] = true end
    if c.grass > bestGrass and c.grass > c.walk then bestGrass, res.grassTile = c.grass, t end
    if c.door > 0 and c.door * 2 >= c.walk + c.blocked then res.doorTiles[t] = true end
    local total = c.walk + c.water + c.grass + c.blocked + c.counter + c.tree + c.ledge
    if c.ledge * 2 > total then authored.ledge[#authored.ledge + 1] = t
    elseif c.counter * 2 > total then authored.counter[#authored.counter + 1] = t
    elseif c.tree * 2 > total then authored.tree[#authored.tree + 1] = t end
  end
  -- jp.91 (par_B): the tree-wall tiles outrank the vote (a cut tree's cell
  -- never draws them, but a wrong vote must not box a wall tile)
  local trees = treeClasses(name, blocks)
  if trees then
    for class, list in pairs(authored) do
      local kept = {}
      for _, t in ipairs(list) do
        if not trees.seen[t] then kept[#kept + 1] = t end
      end
      authored[class] = kept
    end
    if #trees.cylinder > 0 then authored.cylinder = trees.cylinder end
    if #trees.canopy > 0 then authored.canopy = trees.canopy end
  end
  for class, list in pairs(authored) do
    table.sort(list)
    if #list > 0 then res.authored[class] = list end
  end
  if trees and #trees.support > 0 then
    res.authored.companion = { tree_support = trees.support }
  end
  if trees and #trees.stack > 0 then
    res.authored.tree_stack = trees.stack
  end
  if DUMP_TREE_PINS then
    local function join(l) return "{" .. table.concat(l or {}, ",") .. "}" end
    print("P91B tiles", name,
      "cylinder=" .. join(res.authored.cylinder),
      "canopy=" .. join(res.authored.canopy),
      "tree=" .. join(res.authored.tree),
      "tree_support=" .. join(trees and trees.support or nil))
  end
  votesFor[name] = res
  return res
end

-- Authored classes go where TileShape looks for hand-written profiles: the
-- voxel_heights data table, which V.data hands out as one cached table.
local function inject(proxyId, authored)
  local ok, spec = pcall(V.data, "voxel_heights")
  if not (ok and type(spec) == "table") then return end
  spec.tilesets = spec.tilesets or {}
  local entry = spec.tilesets[proxyId]
  if type(entry) ~= "table" then
    entry = {}
    for class, list in pairs(authored) do entry[class] = list end
    spec.tilesets[proxyId] = entry
    return
  end
  -- jp.91 (par_E): a hand-authored entry under the proxy id (the data
  -- file's "G2_..." tables) used to switch the votes off entirely, so a
  -- tileset with ANY authored list lost its tree wall.  Now the authored
  -- entry wins per tile and the votes fill in: a vote class the entry does
  -- not name is added, minus every tile the entry pins under some class.
  local pinned = {}
  for _, list in pairs(entry) do
    if type(list) == "table" then
      for _, t in ipairs(list) do
        if type(t) == "number" then pinned[t] = true end
      end
    end
  end
  for class, list in pairs(authored) do
    if entry[class] == nil then
      if class == "tree_stack" or type(list) ~= "table" or #list == 0 then
        -- a knob (tree_stack), a map (companion tags): nothing to pin against
        entry[class] = list
      else
        local keep = {}
        for _, t in ipairs(list) do
          if type(t) ~= "number" or not pinned[t] then keep[#keep + 1] = t end
        end
        if #keep > 0 then entry[class] = keep end
      end
    end
  end
end

-- ---------------------------------------------------------------- sheets
local function sanitize(s)
  return (tostring(s):gsub("[^%w_%-]", "_"))
end

-- Draw tile byte b into sheet slot b exactly as World:bakeMapImage draws it
-- on the map: Crystal resolves the VRAM bank and the flips per tile byte,
-- Gold reads the atlas straight.  `slot` limits the pass to one BG palette.
local function drawSheet(world, atlas, gts, slot)
  local crystal = isCrystal(world)
  local tpr = gts.tilesPerRow or 16
  local quads = {}
  local aw, ah = atlas:getDimensions()
  for b = 0, SHEET_TILES - 1 do
    local dx, dy = (b % 16) * 8, math.floor(b / 16) * 8
    if crystal then
      local attr = TileAttrs.forTile(gts, b)
      if not slot or attr.palette == slot then
        TileAttrs.drawFlippedTile(atlas,
          TileAttrs.quadFor(atlas, b, attr, tpr, quads), dx, dy, attr)
      end
    else
      local tileSlot = gts.tilePalettes and gts.tilePalettes[b + 1] or 1
      local sx, sy = (b % tpr) * 8, math.floor(b / tpr) * 8
      if (not slot or tileSlot == slot) and sx + 8 <= aw and sy + 8 <= ah then
        local q = quads[b]
        if not q then
          q = love.graphics.newQuad(sx, sy, 8, 8, aw, ah)
          quads[b] = q
        end
        love.graphics.draw(atlas, q, dx, dy)
      end
    end
  end
end

local function offscreen(canvas, body)
  local prevShader = love.graphics.getShader and love.graphics.getShader() or nil
  canvas:renderTo(function()
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 0)
    local ok, err = pcall(body)
    love.graphics.pop()
    if not ok then error(err, 0) end
  end)
  if love.graphics.setShader then love.graphics.setShader(prevShader) end
end

-- The raw (grayscale) sheet, baked once per tileset+roof and registered in
-- memory under a virtual path (the mod sandbox cannot write the save dir):
-- Structures, GlassMask and TerrainAtlas read it through VirtualAssets.
local function graySheet(world, def, key)
  local VA = V.require("VirtualAssets")
  local path = SHEET_DIR .. "/" .. SHEET_VERSION .. "_" .. sanitize(key) .. ".png"
  if VA.has(path) then return path end
  local atlas, gts = world:atlasFor(def)
  if not atlas then return nil end
  local canvas = PixelCanvas.new(SHEET_W, SHEET_H, "nearest")
  offscreen(canvas, function() drawSheet(world, atlas, gts, nil) end)
  VA.put(path, canvas:newImageData())
  if canvas.release then canvas:release() end
  return path
end

-- ---------------------------------------------------------------- animation
-- jp.91 (parallel A): the VRAM tiles a gen2 tileset's animation program
-- rewrites, spelled as the Red `animatedTiles` spec that TerrainAtlas,
-- TileShape and Structures already read ("frames": the tile's slot replaced
-- by an 8x8 image per step).  Every row of an engine frame strip
-- (assets/generated/tilesets/water_frames.png etc.) becomes one virtual 8x8
-- grayscale image; TerrainAtlas recolours it off the baked sheet the way it
-- does Red's flower frames.  The step sequence is the cart's 0..7 timer rule
-- (World:animRow) and the step period is the tileset's own program length,
-- so the 3D cadence agrees with the engine's 2D overlay (drawAnimCells), the
-- way Red's 3D follows Red's 2D.  `class` only guards TileShape's
-- frames-means-flower pin: the flower keeps it, water stays what the votes
-- say.  Scroll animations (caves/ice path) and the Ilex tree sway carry no
-- tile in the extracted data, so neither 2D nor this path animates them.
local ANIM_SEQ = {
  water = { 1, 1, 2, 2, 3, 3, 4, 4 },          -- World.waterFrameFor
  whirlpool = { 1, 2, 3, 4, 1, 2, 3, 4 },      -- (timer % 4) + 1
  tower = { 1, 2, 3, 4, 5, 4, 3, 2 },          -- TOWER_ROWS
  lava2 = { 1, 1, 2, 2, 3, 3, 4, 4 },          -- floor(timer / 2) + 1
  lava1 = { 3, 3, 4, 4, 1, 1, 2, 2 },          -- two frames ahead of lava2
}
local ANIM_FUNC_KINDS = {
  AnimateWhirlpoolTile = "whirlpool",
  AnimateTowerPillarTile = "tower",
  AnimateLavaBubbleTile1 = "lava1",
  AnimateLavaBubbleTile2 = "lava2",
}
local ANIM_CLASS = { water = "water", whirlpool = "water", flower = "flower" }

local stripRows = {}   -- strip path -> { virtual 8x8 image paths } or false

-- One engine frame strip (8px wide, one 8x8 frame per row) cut into virtual
-- per-row images under the dramaless-gen2/ path.  nil when unreadable.
local function stripImages(sheetPath)
  local cached = stripRows[sheetPath]
  if cached ~= nil then return cached or nil end
  local VA = V.require("VirtualAssets")
  local ok, strip = pcall(VA.imageData, sheetPath)
  if not (ok and strip and strip.getDimensions and love.image
          and love.image.newImageData) then
    stripRows[sheetPath] = false
    return nil
  end
  local w, h = strip:getDimensions()
  local out = {}
  for row = 1, math.floor(h / 8) do
    local path = SHEET_DIR .. "/" .. SHEET_VERSION .. "_anim_"
      .. sanitize(sheetPath) .. "_" .. row .. ".png"
    if not VA.has(path) then
      local frame = love.image.newImageData(8, 8)
      frame:paste(strip, 0, 0, 0, (row - 1) * 8, math.min(w, 8), 8)
      VA.put(path, frame)
    end
    out[row] = path
  end
  stripRows[sheetPath] = out
  return out
end

-- The proxy tileset's animatedTiles: Red spec records for the gen2 program.
-- Always a table (empty when nothing animates) so TerrainAtlas never falls
-- back to Red's defaultAnimatedTiles on a gen2 proxy.
local function animSpecsFor(world, gts)
  local out = {}
  local anim = gts and gts.anim
  if not (anim and anim.frames and anim.period and anim.period > 0) then
    return out
  end
  local defs = world.tilesets
  local seen = {}
  local function add(tile, kind, sheet, rows)
    if tile == nil or seen[tile] or not sheet then return end
    local images = stripImages(sheet)
    if not images then return end
    local seq = ANIM_SEQ[kind]
    local imgs = {}
    if rows then
      -- the flower: only the CGB rows are ever shown, alternating two ticks
      -- each (World:flowerFrameFor)
      imgs = { images[rows[1]], images[rows[2]] }
      seq = { 1, 1, 2, 2, 1, 1, 2, 2 }
    else
      for i, path in ipairs(images) do imgs[i] = path end
    end
    if not seq then return end
    for _, i in ipairs(seq) do
      if not imgs[i] then return end
    end
    seen[tile] = true
    out[#out + 1] = {
      tile = tile, kind = "frames", period = anim.period,
      images = imgs, sequence = seq, class = ANIM_CLASS[kind] or "plain",
    }
  end
  for _, frame in ipairs(anim.frames) do
    local func = frame.func
    if func == "AnimateWaterTile" then
      add(frame.tile, "water", defs and defs.waterFrames)
    elseif func == "AnimateFlowerTile" then
      -- hardcodes vTiles2 tile $03 (engine/tilesets/tileset_anims.asm:222)
      local rows = defs and defs.flowerCgbFrames
      if not (rows and rows[1] and rows[2]) then rows = { 2, 4 } end
      add(0x03, "flower", defs and defs.flowerFrames, rows)
    elseif ANIM_FUNC_KINDS[func] then
      add(frame.tile, ANIM_FUNC_KINDS[func], frame.sheet)
    end
  end
  return out
end

-- The animation clock.  TerrainAtlas (and Water's ripple phase) read the
-- engine's frame counter through TileRenderer.animFrame when present, else
-- TileRenderer.tick's upvalue -- which nothing advances in a gen2 game, so
-- every animated slot would sit on step 0.  The seam is installed here, only
-- once a gen2 world has asked for a proxy (Red never reaches this file), and
-- turns World:pollTileAnim's 0..7 timer plus its per-pass sub-counter into a
-- monotonic 60Hz count: floor(count / period) % 8 == animTimer exactly, so
-- the atlas step is the engine's step.
local clockWorld = nil
local clockBase, clockValue, clockPeriod = 0, -1, nil

local function installClock(world)
  clockWorld = world
  local TileRenderer = require("src.render.TileRenderer")
  if TileRenderer.animFrame and TileRenderer.animFrameGen2 then return end
  TileRenderer.animFrameGen2 = true
  TileRenderer.animFrame = function()
    local w = clockWorld
    if not w then return 0 end
    local ts = w.map and w.map.def and w.tilesets and w.tilesets[w.map.def.tileset]
    local period = ts and ts.anim and ts.anim.period or 0
    if not (period and period > 0) then period = 20 end
    local rem = (w.animTimer or 0) * period + (w.animClock or 0)
    local v = clockBase + rem
    -- the 0..7 timer wrapped, or a warp changed the program length: pick
    -- the next base that is a whole number of 8-step passes of THIS
    -- period and keeps the count from running backwards
    if period ~= clockPeriod or v < clockValue then
      local span = 8 * period
      local need = clockValue - rem
      if need < 0 then need = 0 end
      clockBase = math.ceil(need / span) * span
      clockPeriod = period
      v = clockBase + rem
    end
    clockValue = v
    return v
  end
end

local function proxyFor(world, def)
  local gts = world.tilesets and world.tilesets[def.tileset]
  if not gts then return nil end
  local roof = roofOf(world, def)
  local key = def.tileset .. "|" .. (roof or "")
  local p = proxies[key]
  if p then return p end
  local path = graySheet(world, def, key)
  if not path then return nil end
  local votes = tally(world, def.tileset, gts)
  local id = PREFIX .. key
  inject(id, votes.authored)
  installClock(world)
  p = {
    id = id,
    name = id,
    image = path,
    imageWidth = SHEET_W,
    imageHeight = SHEET_H,
    tilesPerRow = 16,
    animatedTiles = animSpecsFor(world, gts),
    blocks = gts.blocks,
    grassTile = votes.grassTile,
    gen2 = gts,
    votes = votes,
  }
  proxies[key] = p
  return p
end

-- ---------------------------------------------------------------- colour
-- The pipeline samples renderer.image as an already-coloured atlas
-- (renderer.gbcAtlas, the RED++ route).  Same eight-slot pass as
-- World:bakeMapImage, into the 256-slot sheet instead of the map.  Indoors
-- and DARK keep the engine's own palette.
--
-- jp.91: outdoors bakes the daytime the game's own clock rule picks (MORN
-- 4-10, DAY 10-18, NITE 18-4 -- Palettes.clockDaytime) for the hour
-- DayNight is showing, so night in 3D is Crystal's own night palette, and a
-- dial pin (DAY/NIGHT/DUSK/DAWN) still wins the way it does for the sky.
-- (jp.90 baked DAY outdoors and left the hour to the sky tint alone.)
local function paletteKey(world, facade)
  local daytime = world.daytime or "DAY"
  if facade.def.outdoor and daytime ~= "DARK" then
    local hour = V.require("DayNight").hourOfDay()
    daytime = Palettes.daytimeFor(facade.gdef, hour, world.flashUsed)
  end
  local flicker = daytime == "DARK" and (world.flickerPhase or 1) or 1
  return daytime, flicker, table.concat({ daytime, tostring(GbcPalette.mode),
    tostring(GbcPalette.customRamp), tostring(flicker) }, "|")
end

-- True when no pixel of the baked sheet has any alpha.
local function blankSheet(data)
  local w, h = data:getDimensions()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local _, _, _, a = data:getPixel(x, y)
      if a > 0 then return false end
    end
  end
  return true
end

local function bakeColour(world, facade)
  local daytime, flicker, key = paletteKey(world, facade)
  local r = facade.renderer
  if r.key == key and r.image then return end
  -- after a run of blank bakes (see below), retry every 30th call only
  if r.blanks and r.blanks >= 30 then
    r.blankWait = (r.blankWait or 0) + 1
    if r.blankWait < 30 then return end
    r.blankWait = 0
  end
  local gdef = facade.gdef
  local atlas, gts = world:atlasFor(gdef)
  if not atlas then return end
  local bgSet = world.palettes and Palettes.bgSet(world.palettes, gdef, daytime) or nil
  if bgSet and daytime == "DARK" then bgSet = Palettes.withCaveFlicker(bgSet, flicker) end
  local hasSlots = isCrystal(world) and gts.tileAttrs or gts.tilePalettes
  local colored = bgSet and (hasSlots or gts.tilePalettes) and GbcPalette.available()
  local canvas = PixelCanvas.new(SHEET_W, SHEET_H, "nearest")
  local ok = pcall(offscreen, canvas, function()
    if colored then
      for slot = 1, 8 do
        if bgSet[slot] then
          GbcPalette.with(bgSet[slot], function() drawSheet(world, atlas, gts, slot) end)
        end
      end
    else
      drawSheet(world, atlas, gts, nil)
    end
  end)
  if not ok then return end
  -- jp.91-preview2: keep the sheet as an Image, not the Canvas it was drawn
  -- in. A Canvas is volatile -- a window re-creation (fold/unfold, rotation,
  -- the app coming back from the background, a desktop setMode) leaves its
  -- pixels transparent, and this sheet is cached under a palette key that
  -- never changes indoors, so the whole room's terrain was alpha-discarded
  -- into the void until the app restarted. An Image keeps its data and
  -- survives. If the readback is refused the canvas is kept, as before.
  local sheet = canvas
  local okData, data = pcall(canvas.newImageData, canvas)
  if okData and data then
    -- jp.91: a sheet that came back fully transparent was drawn while the
    -- GPU was not taking draws (the app going to the background mid-bake,
    -- a surface being rebuilt).  Caching it would leave the room void for
    -- good, since nothing re-checks a cached key; drop it and redraw on the
    -- next call instead.  Any real colour sheet has opaque tiles.
    if blankSheet(data) then
      r.blanks = (r.blanks or 0) + 1
      if r.blanks == 1 or r.blanks % 60 == 0 then
        print("[DRAMALESS_SHAPE] gen2 colour sheet came out blank, redrawing (" .. r.blanks .. ")")
      end
      if data.release then pcall(data.release, data) end
      if canvas.release then pcall(canvas.release, canvas) end
      return
    end
    if r.blanks then
      print("[DRAMALESS_SHAPE] gen2 colour sheet redrawn after " .. r.blanks .. " blank bake(s)")
      r.blanks, r.blankWait = nil, nil
    end
    local okImg, img = pcall(love.graphics.newImage, data)
    if okImg and img then
      img:setFilter("nearest", "nearest")
      sheet = img
      if canvas.release then pcall(canvas.release, canvas) end
    end
  end
  local old = r.image
  r.image, r.key = sheet, key
  if old and old ~= sheet and old.release then pcall(old.release, old) end
end

-- ---------------------------------------------------------------- facade
local Facade = {}
Facade.__index = Facade

function Facade:tileAt(tx, ty)
  local w, h = self.width, self.height
  local bx, by = math.floor(tx / 4), math.floor(ty / 4)
  local id
  if bx >= 0 and by >= 0 and bx < w and by < h then
    id = BorderFill.blockFor(self.blocks[by * w + bx + 1], self.gm.borderBlock)
  else
    id = self.ringBlock or self.gm.borderBlock
  end
  local block = self.tileset.blocks and self.tileset.blocks[(id or 0) + 1]
  if not block then return 0 end
  return block[(ty % 4) * 4 + (tx % 4) + 1] or 0
end

-- the tile Red's door/grass logic reads for a cell: its bottom-left 8px tile
function Facade:cellTile(cx, cy) return self:tileAt(cx * 2, cy * 2 + 1) end
function Facade:inBounds(cx, cy) return self.gm:inBounds(cx, cy) end
function Facade:isWalkableCell(cx, cy) return self.gm:isWalkableCell(cx, cy) end
function Facade:isWaterCell(cx, cy) return self.gm:isWaterCell(cx, cy) end
function Facade:isGrassCell(cx, cy) return self.gm:isGrassCell(cx, cy) end
function Facade:warpAtCell(cx, cy) return self.gm:warpAtCell(cx, cy) end
function Facade:isCounterCell(cx, cy) return self.gm:isCounterCell(cx, cy) end
function Facade:cellCollision(cx, cy) return self.gm:cellCollision(cx, cy) end
function Facade:isWarpTileCell(cx, cy) return self.gm:isWarpTileCell(cx, cy) end
function Facade:isDoorTileCell(cx, cy) return self.gm:isDoorTileCell(cx, cy) end

-- live block edits (Cut, Rock Smash) land on the world's own Map instance;
-- read through it when it is the current map so the 2D/3D grids agree
local function liveBlocks(world, gid, gdef)
  local m = world.map
  if m and m.id == gid and m.blocks then return m.blocks end
  return gdef.blocks
end

function Gen2Facade.forMap(world, gid)
  if not (world and world.maps and gid ~= nil) then return nil end
  local gdef = world.maps[gid]
  if type(gdef) ~= "table" then return nil end
  local f = facades[gid]
  if f and f.gdef == gdef then
    f.blocks = liveBlocks(world, gid, gdef)
    bakeColour(world, f)
    return f
  end
  local proxy = proxyFor(world, gdef)
  if not proxy then return nil end
  local gm = G2Map.new(gdef, proxy.gen2)
  local outdoor = G2Map.isOutdoor(gdef) and true or false
  local fill = BorderFill.fillBlock(gdef)
  local def = setmetatable({
    id = PREFIX .. tostring(gid),
    outdoor = outdoor,
    borderBlock = fill,
    tileset = proxy.id,
  }, { __index = gdef })
  f = setmetatable({
    gen2Id = gid,
    gdef = gdef,
    gm = gm,
    def = def,
    id = def.id,
    tileset = proxy,
    width = gdef.width,
    height = gdef.height,
    widthCells = gdef.width * 2,
    heightCells = gdef.height * 2,
    blocks = liveBlocks(world, gid, gdef),
    borderBlock = gm.borderBlock,
    ringBlock = fill or nil,
    walkable = proxy.votes.walkable,
    waterTiles = proxy.votes.waterTiles,
    doorTiles = proxy.votes.doorTiles,
    renderer = { gbcAtlas = true },
  }, Facade)
  facades[gid] = f
  bakeColour(world, f)
  return f
end

function Gen2Facade.reset()
  facades, proxies, votesFor = {}, {}, {}
end

return Gen2Facade
