-- jp.75: the experimental 3D field for Gold / Silver / Crystal.
--
-- Off by default (OPTION > 3D).  Self-contained: World:draw asks for a frame
-- with Field3D.draw and falls back to the normal 2D path whenever this
-- returns nil, so a device without depth canvases or custom vertex shaders
-- simply keeps playing in 2D.  Nothing here changes game logic: the map, the
-- collision, the people and the scripts are the cart's; this only looks at
-- them from another angle.
--
--   terrain  the ground the 2D path would draw (World:drawGround at scale 1)
--            becomes the texture of a height field built from the collision
--            bytes (walls, trees, counters, ledges, water).
--   people   every sprite World:drawPeople would draw goes into a slot of one
--            atlas canvas and stands up as a camera-facing board.
--   camera   above (default), third person or first person; Q/E or a drag on
--            the field rotates it in 90 degree steps.
--   atmos    sky colour and fog by time of day, rain / snow by date.
--   battle   an orbiting view of the field around the player behind the
--            battle panel.

local Permissions = require("src.world.gen2.Permissions")
local MapAttrGrid = require("src.world.gen2.MapAttrGrid")

local Field3D = {}

local CELL = 16
-- jp.81: the region grew (16,14 -> 18,18) so the wider portrait framing never
-- shows its far edge inside the picture; the fog ends just short of it
local RX, RY = 18, 18                 -- cells either side of the player
local GW, GH = 2 * RX + 1, 2 * RY + 1 -- region size in cells
-- jp.83: the jp.82 tree models are gone (trees are flat cards of their own
-- art again), so the ground mesh is back to the jp.81 size
-- (jp.83 HD-2D fold: side faces are cut into 8px bands, so a little more)
local MAX_GROUND_VERTS = 96000
-- jp.83: the HD-2D fold of the whole field, after the Gen 1 3D field
-- (DRAMALESS_SHAPE ChunkMesher.lua runGeometry, Structures.lua, Voxel3D
-- FACE_SHADE).  A run of upright cells down one column finds its Gen 1
-- unit (the repeat period of its 8px tile rows, else its length, at most
-- maxRows rows), which picks the rows its faces and top show; its faces
-- wear its own tile rows 8px band by 8px band, cropped, never stretched:
-- the front shows the bottom rows, the top the rows above them.  It keeps
-- the jp.82 standing height (HD-2D wins over Gen 1 here: the Gen 1 height
-- raised ledges and fences over the sprites behind them).
Field3D.FOLD = {
  maxRows = 6,       -- Gen 1 MAX_ROWS (outdoors)
  roomRows = 4,      -- furniture indoors stays shorter than the shell view
  top = 0.85,        -- Gen 1 VOLUME_TOP_SHADE
  front = 1.0,       -- the south face of a run (Gen 1: full light)
  S = 0.90, E = 0.84, W = 0.72, N = 0.68, -- Gen 1 Voxel3D.FACE_SHADE
}
-- jp.84: the big buildings with no gable (the Goldenrod Dept Store, the
-- Radio Tower, the Olivine lighthouse...) stand up.  The folded wall cells
-- joined to the cell over a door (not a cave door, not a roofed house) are
-- a building; each of its columns stands as tall as its own run of rows,
-- so its whole picture is upright on the front, band by band, the way the
-- cart draws it (a tower's narrow top rises over its base).  w/h bound the
-- search around the door, cells caps a column's height in cells.
Field3D.TOWER = { w = 9, h = 14, cells = 10, minRows = 24 }
-- jp.83: trees, after the Gen 1 3D field (DRAMALESS_SHAPE SpriteBillboards /
-- TileShape "upright") and the HD-2D look: the tree's own 16x32 picture
-- (crown cell + trunk cell) stands up as a card, leaned back like the people
-- boards, crisp pixels, the grass around the tree cut away (only grass
-- pixels joined to the card's edge, so the crown keeps its own light pixels).
-- Nothing is drawn that the cart does not draw.  The cell under the card
-- keeps its picture flat, darkened: the tree's shadow.
Field3D.TREECARD = {
  shadow = 0.55,  -- shade of the flat picture under a card
  minBlack = 8,   -- a cell past the map edge is a tree only with this many
                  -- outline pixels (tree palette colour 3) and no colour
                  -- from another palette
}
local MAX_TREE_CARDS = GW * GH
local SLOT_W, SLOT_H = 32, 64
local SLOT_FOOT_X, SLOT_FOOT_Y = 16, 60
local ATLAS_COLS, ATLAS_ROWS = 16, 8
local MAX_SPRITES = ATLAS_COLS * ATLAS_ROWS
local MAX_DROPS = 700                 -- jp.76 3D weather particles

local DIRS = { "up", "right", "down", "left" }
local DIR_INDEX = { up = 0, right = 1, down = 2, left = 3 }

-- ---------------------------------------------------------------------------
-- options

local function optionsOf(world)
  local game = world and world.game
  return game and game.options or nil
end

local function isOn(v) return v == true or v == 1 end

function Field3D.enabled(world)
  local o = optionsOf(world)
  if not (o ~= nil and isOn(o.jp3D)) then return false end
  -- jp.87: rooms and caves stay flat (the cart's own 2D renderer); only
  -- towns and routes go 3D.  The jp.79 room shells read as a tilted box in
  -- a black void on the tester's phone.
  local def = world and world.map and world.map.def
  local kind = def and Field3D.envKind and Field3D.envKind(def)
  if kind == "room" or kind == "cave" then return false end
  return true
end

function Field3D.cameraMode(world)
  local o = optionsOf(world)
  local m = o and o.jp3DCamera
  if m == "third" or m == "first" then return m end
  return "above"
end

local function moveRelative(world)
  local o = optionsOf(world)
  return o ~= nil and isOn(o.jp3DMove)
end

-- jp.81 view controls, after the Gen 1 3D field: an angle ladder for the view
-- from above (tilt from straight overhead, as Gen 1 counts it), a zoom step
-- and free up/down look in the chase and first-person views.
Field3D.ANGLES = { "diorama", "15", "35", "50", "75" }
Field3D.TILT = { diorama = 35, ["15"] = 15, ["35"] = 35, ["50"] = 50, ["75"] = 75 }
Field3D.ANGLE_LABEL = { diorama = "ジオラマ", ["15"] = "15ど", ["35"] = "35ど", ["50"] = "50ど", ["75"] = "75ど" }
-- the one ladder V / the view button / the right stick click walk through
Field3D.LADDER = { "diorama", "15", "35", "50", "75", "third", "first" }
Field3D.ZOOMS = { 0.7, 0.85, 1.0, 1.2, 1.45 }
Field3D.ZOOM_DEFAULT = 3

function Field3D.angleOf(world)
  local o = optionsOf(world)
  local a = o and o.jp3DAngle
  a = a ~= nil and tostring(a) or "35"
  if Field3D.TILT[a] == nil then a = "35" end
  return a, Field3D.TILT[a]
end

function Field3D.zoomIndex(world)
  local o = optionsOf(world)
  local z = math.floor(tonumber(o and o.jp3DZoom) or Field3D.ZOOM_DEFAULT)
  return math.max(1, math.min(#Field3D.ZOOMS, z))
end

local function zoomFactor(world)
  return Field3D.ZOOMS[Field3D.zoomIndex(world)]
end

local function invertLook(world)
  local o = optionsOf(world)
  return o ~= nil and isOn(o.jp3DInvert)
end

-- the rung of the ladder the current options sit on
function Field3D.ladderIndex(world)
  local mode = Field3D.cameraMode(world)
  local key = mode == "above" and (Field3D.angleOf(world)) or mode
  for i, k in ipairs(Field3D.LADDER) do
    if k == key then return i end
  end
  return 3
end

function Field3D.viewLabel(world)
  local mode = Field3D.cameraMode(world)
  if mode == "third" then return "うしろから" end
  if mode == "first" then return "いちにんしょう" end
  return "うえから " .. Field3D.ANGLE_LABEL[(Field3D.angleOf(world))]
end

local function atmosOn(world)
  local o = optionsOf(world)
  return o ~= nil and isOn(o.jp3DAtmos)
end

-- jp.87: battles always use the cart's 2D battle screen (upstream BattleHud
-- layout), 3D field or not.  The 3D battle backdrop left the bottom of the
-- tester's 1216x2688 screen white and put the command box over the mon, so
-- it is off until it is verified clean at that size (jp3DBattle is kept in
-- the save but no longer read).
--
-- jp.91: back on, but only through the DRAMALESS_SHAPE mod's own voxel arena
-- (the gen2BattleBackdrop export) -- the same renderer and rigs Red's 3D
-- battles use -- with the 3D field option on and the voxel pipeline live.
-- Rooms and caves are not excluded here: the mod stages those like Red does.
-- Crystal's own jp.75-86 arena (arenaOpts) is not used any more.
local function battleBackdropExport(game)
  local mods = game and game.mods
  local exports = mods and mods.exports and mods.exports.DRAMALESS_SHAPE
  local fn = type(exports) == "table" and exports.gen2BattleBackdrop
  return type(fn) == "function" and fn or nil
end

function Field3D.battleOn(game)
  local o = game and game.options
  if not (o ~= nil and isOn(o.jp3D)) then return false end
  if not battleBackdropExport(game) then return false end
  local ok, Pipelines = pcall(require, "src.render.Pipelines")
  if not (ok and type(Pipelines) == "table" and type(Pipelines.level) == "function") then
    return false
  end
  local okL, level = pcall(Pipelines.level, "voxel")
  return okL and tonumber(level) ~= nil and level > 0
end

-- ---------------------------------------------------------------------------
-- GPU objects, created once and lazily.  Several test harnesses stub
-- love.graphics.newShader to throw, so nothing here may run at require time.

local SHADER = [[
varying float vDist;
#ifdef VERTEX
uniform mat4 viewProj;
uniform float flipY;
uniform vec3 camPos;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vDist = distance(vertex_position.xyz, camPos);
  vec4 p = viewProj * vec4(vertex_position.xyz, 1.0);
  p.y *= flipY;
  return p;
}
#endif
#ifdef PIXEL
uniform vec3 fogColor;
uniform vec2 fogRange;
// jp.87: Gen 1 3D's hidden-figure silhouette (DRAMALESS_SHAPE Voxel3D
// GHOST_COLOR 0.26,0.26,0.28 at GHOST_ALPHA 0.5): a person behind a roof or
// a wall shows as a flat dim shape, not in full colour on top of the roof
uniform float ghost;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc) * color;
  // jp.84: a vertex alpha below 1 fades the board by screen-door dither
  if (color.a < 0.999) {
    if (c.a < color.a * 0.5) discard;
    if (color.a < fract(52.9829189 * fract(dot(sc, vec2(0.06711056, 0.00583715))))) discard;
    c.a = 1.0;
  }
  if (c.a < 0.5) discard;
  if (ghost > 0.5) return vec4(0.26, 0.26, 0.28, 0.5);
  float f = clamp((vDist - fogRange.x) / max(fogRange.y - fogRange.x, 1.0), 0.0, 1.0);
  return vec4(mix(c.rgb, fogColor, f), 1.0);
}
#endif
]]

-- jp.83: the tree cards' shader, the same plus a cut-out mask laid out like
-- the ground canvas (alpha 0 = the grass around the tree)
local TREE_SHADER = SHADER:gsub("vec4 effect%(", "uniform Image treeMask;\nvec4 effect(", 1)
  :gsub("vec4 c = Texel%(tex, tc%) %* color;",
    "if (Texel(treeMask, tc).a < 0.5) discard;\n  vec4 c = Texel(tex, tc) * color;", 1)

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "byte", 4 },
}

local gpu = { tried = false, ok = false, reason = "not tried" }

local function note(msg)
  print("[Field3D] " .. tostring(msg))
end

local function blankVerts(n)
  local t = {}
  for i = 1, n do t[i] = { 0, 0, 0, 0, 0, 1, 1, 1, 1 } end
  return t
end

function Field3D.available()
  if gpu.tried then return gpu.ok, gpu.reason end
  gpu.tried = true
  local G = love and love.graphics
  if not G then gpu.reason = "no love.graphics"; return false, gpu.reason end
  for _, fn in ipairs({ "newShader", "newMesh", "setDepthMode", "newCanvas",
      "setMeshCullMode" }) do
    if type(G[fn]) ~= "function" then
      gpu.reason = "missing love.graphics." .. fn
      note(gpu.reason)
      return false, gpu.reason
    end
  end
  local ok, err = pcall(function()
    gpu.shader = G.newShader(SHADER)
    gpu.ground = G.newMesh(FORMAT, blankVerts(MAX_GROUND_VERTS), "triangles", "dynamic")
    gpu.boards = G.newMesh(FORMAT, blankVerts(MAX_SPRITES * 6), "triangles", "dynamic")
    gpu.weather = G.newMesh(FORMAT, blankVerts(MAX_DROPS * 6), "triangles", "dynamic")
    gpu.cards = G.newMesh(FORMAT, blankVerts(12), "triangles", "dynamic")
    gpu.trees = G.newMesh(FORMAT, blankVerts(MAX_TREE_CARDS * 6), "triangles", "dynamic")
    -- jp.83: a driver that refuses the mask shader still draws the cards,
    -- only without the cut-out
    local okT, sh = pcall(G.newShader, TREE_SHADER)
    if okT then gpu.treeShader = sh else note("tree mask off: " .. tostring(sh)) end
    local white = love.image.newImageData(1, 1)
    white:setPixel(0, 0, 1, 1, 1, 1)
    gpu.white = G.newImage(white)
    gpu.sky = G.newMesh({
      { 0, 0, 0, 0, 1, 1, 1, 1 }, { 1, 0, 0, 0, 1, 1, 1, 1 },
      { 1, 1, 0, 0, 1, 1, 1, 1 }, { 0, 1, 0, 0, 1, 1, 1, 1 },
    }, "fan", "dynamic")
  end)
  if not ok then
    gpu.reason = "init failed: " .. tostring(err)
    note(gpu.reason)
    return false, gpu.reason
  end
  gpu.ok, gpu.reason = true, "ok"
  return true, gpu.reason
end

local function sendUniform(shader, name, ...)
  if shader.hasUniform and not shader:hasUniform(name) then return end
  shader:send(name, ...)
end

-- jp.81 tilt-shift for the diorama rung: sharp in a band around focusY (a
-- 0..1 screen fraction), a separable 9-tap gaussian (one horizontal pass,
-- one vertical) whose reach eases up to `radius` pixels past the band.
-- Built on first use; a driver that refuses it just skips the blur.
-- jp.86: rebuilt after the Gen 1 (初代 JP) tilt-shift the tester holds up as
-- the reference.  jp.85 blurred each pixel with its own reach (a sparse
-- 9-tap whose step grew with the distance from the band), which on a phone
-- read as a hard step between the sharp band and a blocky smear.  Now the
-- whole frame is blurred once at a fixed, small sigma through a downsample
-- pyramid (Gen 1's sigma = h * preset.sigma, halved until it fits 2.5 px),
-- and the sharp and blurred frames are mixed with Gen 1's quadratic mask
-- amount = clamp((|y - focusY| - band) / range, 0, 1)^2, so the edge of the
-- band fades in over a third of the screen instead of stepping.  Levels 1-5
-- are Gen 1's five presets; 0 = なし skips the pass.  Default 2 = Gen 1's
-- DEFAULT_DISTANCE_BLUR.
Field3D.BLUR_PRESETS = {
  { sigma = 0.0018, band = 0.14, range = 0.32, saturation = 1.10 },
  { sigma = 0.0030, band = 0.10, range = 0.30, saturation = 1.18 },
  { sigma = 0.0045, band = 0.07, range = 0.28, saturation = 1.28 },
  { sigma = 0.0065, band = 0.06, range = 0.27, saturation = 1.28 },
  { sigma = 0.0090, band = 0.05, range = 0.26, saturation = 1.28 },
}
-- jp.86: default 1 (Gen 1's DEFAULT_DISTANCE_BLUR is 2, but on the tester's
-- Red JP field capture the far rows are all but sharp, and Gen 2's maps put
-- more tall blocks near the top of the view; 1 keeps the depth without the
-- smear).  0 = なし.
Field3D.BLUR_DEFAULT = 1

-- the とおくの ぼかし level 0..5 from an options table (nil / junk = default)
function Field3D.blurLevel(o)
  local v = o and tonumber(o.jp3DBlur)
  if v == nil or v ~= v then v = Field3D.BLUR_DEFAULT end
  return math.max(0, math.min(5, math.floor(v)))
end

Field3D.BLUR_LABELS = { [0] = "なし", "1", "2", "3", "4", "5" }

local BLUR_SHADER = [[
extern vec2 dir;
extern number sigma;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  float k = -0.5 / (sigma * sigma);
  vec4 sum = Texel(tex, uv);
  float wsum = 1.0;
  for (int i = 1; i <= 6; i++) {
    float fi = float(i);
    float w = exp(k * fi * fi);
    sum += (Texel(tex, uv + dir * fi) + Texel(tex, uv - dir * fi)) * w;
    wsum += 2.0 * w;
  }
  return (sum / wsum) * color;
}
]]

local MIX_SHADER = [[
extern Image blurTex;
extern number focusY;
extern number band;
extern number range;
extern number saturation;
extern number farOnly;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 sharp = Texel(tex, uv);
  float d = uv.y - focusY;
  if (farOnly > 0.5 && d > 0.0) d = 0.0;
  float a = clamp((abs(d) - band) / range, 0.0, 1.0);
  a = a * a;
  if (a <= 0.0) return sharp * color;
  vec4 blur = Texel(blurTex, uv);
  float g = dot(blur.rgb, vec3(0.299, 0.587, 0.114));
  blur.rgb = mix(vec3(g), blur.rgb, 1.0 + (saturation - 1.0) * a);
  return mix(sharp, blur, a) * color;
}
]]

local ensureCanvas

-- src: the finished frame (w x h canvas).  focusY: the sharp band's centre
-- as a 0..1 screen fraction.  level: 0..5 (nil = default).  farOnly: blur
-- only above the focus (the battle: the near ground under the panel stays
-- sharp, as in 初代's battle backdrop).  Returns the composited canvas, left
-- bound as the current canvas, or nil to keep the sharp frame.
function Field3D.tiltShift(src, w, h, focusY, level, farOnly)
  local G = love.graphics
  if gpu.tiltFailed then return nil end
  level = level or Field3D.BLUR_DEFAULT
  local preset = Field3D.BLUR_PRESETS[level]
  if not preset then return nil end
  if not gpu.tiltShader then
    local ok, sh = pcall(G.newShader, BLUR_SHADER)
    if not ok then gpu.tiltFailed = true; note("tilt-shift off: " .. tostring(sh)); return nil end
    local ok2, sh2 = pcall(G.newShader, MIX_SHADER)
    if not ok2 then gpu.tiltFailed = true; note("tilt-shift off: " .. tostring(sh2)); return nil end
    gpu.tiltShader, gpu.tiltMixShader = sh, sh2
  end
  -- Gen 1: sigma in frame pixels, then halve the frame until it fits
  local sigma = math.max(1.25, h * preset.sigma)
  local div = 1
  while sigma / div > 2.5 and div < 16 do div = div * 2 end
  sigma = sigma / div
  local sw, sh_ = math.max(1, math.floor(w / div + 0.5)), math.max(1, math.floor(h / div + 0.5))
  local small = ensureCanvas("tiltSmallA", sw, sh_)
  local small2 = ensureCanvas("tiltSmallB", sw, sh_)
  local dst = ensureCanvas("tiltCanvas", w, h)
  local blur, mixer = gpu.tiltShader, gpu.tiltMixShader
  G.origin()
  G.setScissor()
  G.setColor(1, 1, 1, 1)
  -- 1. downsample (linear) into the small canvas
  G.setShader()
  G.setCanvas(small)
  G.clear(0, 0, 0, 1)
  local f1, f2 = src:getFilter()
  src:setFilter("linear", "linear")
  G.draw(src, 0, 0, 0, sw / w, sh_ / h)
  src:setFilter(f1, f2)
  -- 2. separable gaussian on the small canvas
  blur:send("sigma", sigma)
  G.setShader(blur)
  local function pass(from, to, dx, dy)
    blur:send("dir", { dx / sw, dy / sh_ })
    G.setCanvas(to)
    G.clear(0, 0, 0, 1)
    from:setFilter("linear", "linear")
    G.draw(from, 0, 0)
  end
  pass(small, small2, 1, 0)
  pass(small2, small, 0, 1)
  -- 3. mix sharp and blurred by the band mask
  small:setFilter("linear", "linear")
  mixer:send("blurTex", small)
  mixer:send("focusY", focusY)
  mixer:send("band", preset.band)
  mixer:send("range", preset.range)
  mixer:send("saturation", preset.saturation)
  mixer:send("farOnly", farOnly and 1 or 0)
  G.setShader(mixer)
  G.setCanvas(dst)
  G.clear(0, 0, 0, 1)
  src:setFilter("nearest", "nearest")
  G.draw(src, 0, 0)
  src:setFilter(f1, f2)
  G.setShader()
  G.setCanvas(dst)
  return dst
end

function ensureCanvas(slot, w, h)
  local c = gpu[slot]
  if c and c:getWidth() == w and c:getHeight() == h then return c end
  if c and c.release then c:release() end
  -- jp.87: framebuffer pixels, as upstream's src/render/PixelCanvas.lua does
  -- for every scene target (#208): w, h are the scene canvas's pixels, and a
  -- default canvas on a dpi 2.75 phone would be 2.75 times that
  c = love.graphics.newCanvas(w, h, { dpiscale = 1 })
  c:setFilter("nearest", "nearest")
  gpu[slot] = c
  return c
end

-- ---------------------------------------------------------------------------
-- matrices (row-major, sent with the "row" layout)

local function mul(a, b)
  local r = {}
  for i = 1, 4 do
    r[i] = {}
    for j = 1, 4 do
      r[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j]
        + a[i][3] * b[3][j] + a[i][4] * b[4][j]
    end
  end
  return r
end

local function perspective(fovy, aspect, near, far)
  local f = 1 / math.tan(fovy / 2)
  return {
    { f / aspect, 0, 0, 0 },
    { 0, f, 0, 0 },
    { 0, 0, (far + near) / (near - far), 2 * far * near / (near - far) },
    { 0, 0, -1, 0 },
  }
end

-- jp.81: the same projection from a vertical focal length (1 / tan(fovy/2))
local function perspectiveF(fy, aspect, near, far)
  return {
    { fy / aspect, 0, 0, 0 },
    { 0, fy, 0, 0 },
    { 0, 0, (far + near) / (near - far), 2 * far * near / (near - far) },
    { 0, 0, -1, 0 },
  }
end

local function normalize(x, y, z)
  local l = math.sqrt(x * x + y * y + z * z)
  if l < 1e-9 then return 0, 0, 0 end
  return x / l, y / l, z / l
end

local function cross(ax, ay, az, bx, by, bz)
  return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

local function lookAt(ex, ey, ez, tx, ty, tz)
  local fx, fy, fz = normalize(tx - ex, ty - ey, tz - ez)
  local sx, sy, sz = normalize(cross(fx, fy, fz, 0, 1, 0))
  local ux, uy, uz = cross(sx, sy, sz, fx, fy, fz)
  return {
    { sx, sy, sz, -(sx * ex + sy * ey + sz * ez) },
    { ux, uy, uz, -(ux * ex + uy * ey + uz * ez) },
    { -fx, -fy, -fz, fx * ex + fy * ey + fz * ez },
    { 0, 0, 0, 1 },
  }
end

local function flat(m)
  return {
    m[1][1], m[1][2], m[1][3], m[1][4],
    m[2][1], m[2][2], m[2][3], m[2][4],
    m[3][1], m[3][2], m[3][3], m[3][4],
    m[4][1], m[4][2], m[4][3], m[4][4],
  }
end

-- ---------------------------------------------------------------------------
-- shape profiles: how tall each kind of collision stands, per tileset with
-- the map environment as the fallback.  Every Johto / Kanto tileset the cart
-- ships is named so no map falls through to a guess.

local ENV_PROFILE = {
  TOWN = { wall = 16, tree = 20 },
  ROUTE = { wall = 16, tree = 20 },
  INDOOR = { wall = 12, tree = 14 },
  GATE = { wall = 12, tree = 14 },
  CAVE = { wall = 22, tree = 22 },
  DUNGEON = { wall = 22, tree = 22 },
  ENVIRONMENT_5 = { wall = 14, tree = 16 },
}

local TILESET_PROFILE = {
  TILESET_JOHTO = { wall = 16, tree = 20 },
  TILESET_JOHTO_MODERN = { wall = 16, tree = 20 },
  TILESET_KANTO = { wall = 16, tree = 20 },
  TILESET_PARK = { wall = 14, tree = 20 },
  TILESET_FOREST = { wall = 20, tree = 22 },
  TILESET_CAVE = { wall = 22, tree = 22 },
  TILESET_ICE_PATH = { wall = 22, tree = 22 },
  TILESET_RUINS_OF_ALPH = { wall = 20, tree = 20 },
  TILESET_ALPH_WORD_ROOM = { wall = 20, tree = 20 },
  TILESET_TOWER = { wall = 20, tree = 20 },
  TILESET_LIGHTHOUSE = { wall = 18, tree = 18 },
  TILESET_BATTLE_TOWER_OUTSIDE = { wall = 16, tree = 20 },
  TILESET_BATTLE_TOWER_INSIDE = { wall = 14, tree = 14 },
  TILESET_POKECENTER = { wall = 12, tree = 12, counter = 8 },
  TILESET_POKECOM_CENTER = { wall = 12, tree = 12, counter = 8 },
  TILESET_MART = { wall = 12, tree = 12, counter = 8 },
  TILESET_HOUSE = { wall = 12, tree = 12 },
  TILESET_PLAYERS_HOUSE = { wall = 12, tree = 12 },
  TILESET_PLAYERS_ROOM = { wall = 12, tree = 12 },
  TILESET_TRADITIONAL_HOUSE = { wall = 12, tree = 12 },
  TILESET_GATE = { wall = 12, tree = 12 },
  TILESET_PORT = { wall = 14, tree = 16 },
  TILESET_LAB = { wall = 12, tree = 12 },
  TILESET_FACILITY = { wall = 14, tree = 14 },
  TILESET_GAME_CORNER = { wall = 12, tree = 12, counter = 8 },
  TILESET_MANSION = { wall = 12, tree = 12 },
  TILESET_RADIO_TOWER = { wall = 14, tree = 14 },
  TILESET_CHAMPIONS_ROOM = { wall = 16, tree = 16 },
  TILESET_ELITE_FOUR_ROOM = { wall = 16, tree = 16 },
  TILESET_UNDERGROUND = { wall = 14, tree = 14 },
}

local DEFAULT_PROFILE = { wall = 16, tree = 20 }

function Field3D.profileFor(def)
  local p = def and (TILESET_PROFILE[def.tileset] or ENV_PROFILE[def.environment])
  p = p or DEFAULT_PROFILE
  return {
    wall = p.wall, tree = p.tree or p.wall, counter = p.counter or 8,
    water = -3, ledge = 3, void = p.wall,
    -- jp.76 shape profiles: tall outdoor blocks taper inward on every side
    -- that drops to a lower neighbour (a canopy / rock silhouette instead of
    -- a box); indoor furniture and walls stay square
    wallTaper = (p.wall >= 16) and 3 or 0,
    treeTaper = 5,
  }
end

-- The inset of a cell's top face on its open sides (0 = a plain box).
function Field3D.taperOf(coll, prof)
  if coll == nil then return 0 end
  local c = coll % 256
  if c == 0xff then return 0 end
  if Permissions.isCutTree(c) or Permissions.isHeadbuttTree(c) then return prof.treeTaper or 0 end
  if Permissions.isCounter(c) then return 0 end
  if Permissions.of(c) == Permissions.WALL then return prof.wallTaper or 0 end
  return 0
end

function Field3D.heightOf(coll, prof)
  if coll == nil then return prof.void end
  local c = coll % 256
  if c == 0xff then return prof.void end
  if Permissions.isCounter(c) then return prof.counter end
  if Permissions.isCutTree(c) or Permissions.isHeadbuttTree(c) then return prof.tree end
  local perm = Permissions.of(c)
  if perm == Permissions.WATER then return prof.water end
  if perm == Permissions.WALL then return prof.wall end
  if Permissions.isLedge(c) then return prof.ledge end
  return 0
end

-- ---------------------------------------------------------------------------
-- per-world state

local function stateFor(world)
  local st = world.field3d
  if not st then
    st = { yaw = 0, yawTarget = 0, camH = 0, frame = 0 }
    world.field3d = st
  end
  return st
end

local function quadrant(yaw)
  return math.floor(yaw / 90 + 0.5) % 4
end

-- The 2D frame a person should show when the camera looks along `yaw`
-- (0 = north): someone facing the way the camera looks shows their back.
function Field3D.viewFacing(facing, yaw)
  local i = DIR_INDEX[facing]
  if not i then return facing end
  return DIRS[(i - quadrant(yaw or 0)) % 4 + 1]
end

-- ---------------------------------------------------------------------------
-- terrain

-- jp.78: roofs.  A building is the rectangle of full-height wall cells over
-- a door: its front row is the row the door opens in when walls flank the
-- door (Gold's houses), else the row just above it; the shorter of the
-- wall runs through the door column on the front row and the row above
-- gives the width (either can run on into fences), and rows above it count
-- while the whole width is wall.  Too wide, too tall or no row above the
-- front means a cliff or a tree line, not a house: skipped.  The rows above
-- the front row get a gable along east-west.  isWall(i, j) says whether a
-- cell is a full-height wall; doors is a list of { i, j }.  Returns
-- roofs[key] = { top = first row, eave = front row } for each roofed cell,
-- and solid[key] = true for every cell of an accepted building (drawn
-- square, no taper).  Pure (no love), key = i .. "," .. j.
Field3D.ROOF_LIMIT = { cells = 72, w = 12, h = 8 }
function Field3D.roofPlan(isWall, doors, limit, report)
  limit = limit or Field3D.ROOF_LIMIT
  local roofs, solid = {}, {}
  for _, d in ipairs(doors or {}) do
    local di, dj = d[1], d[2]
    local front = (isWall(di - 1, dj) or isWall(di + 1, dj)) and dj or dj - 1
    local row = front - 1
    local function run(j)
      local l, r = di, di
      while r - l < limit.w and isWall(l - 1, j) do l = l - 1 end
      while r - l < limit.w and isWall(r + 1, j) do r = r + 1 end
      return l, r
    end
    local L, R = run(front)
    local La, Ra = run(row)
    if Ra - La < R - L then L, R = La, Ra end
    local function fullRow(j)
      for i = L, R do
        if not isWall(i, j) then return false end
      end
      return true
    end
    local top = front
    while front - top + 1 < limit.h and fullRow(top - 1) do top = top - 1 end
    local w, h = R - L + 1, front - top + 1
    local capped = h >= limit.h and fullRow(top - 1)
    local ok = w <= limit.w and w >= 2 and not capped and front - top >= 1 and w * h <= limit.cells
      and isWall(di, row)
    if report then
      report[#report + 1] = string.format("%d,%d:%s%dx%d", di, dj, ok and "" or "no", w, h)
    end
    if ok then
      for j = top, front do
        for i = L, R do
          if isWall(i, j) then
            local k = i .. "," .. j
            solid[k] = true
            if j < front then roofs[k] = { top = top, eave = front, w = w } end
          end
        end
      end
    end
  end
  return roofs, solid
end

-- jp.82: the drawn roofs.  Each roof of roofPlan runs one row further, over
-- its front row (eave + 1), so the gable comes down at the front edge and
-- the front row's own tiles (windows, door) are the upright south face.
-- The front-row cells (solid, under a roofed cell) join with the roof
-- texture row of the cell above (vrow, else that row).  A door in the front
-- row (walls beside it, Gold's houses) joins too, marked flush, and rH (when
-- given) draws it wallH tall.  Returns a new table; roofs is not changed.
-- Pure.
function Field3D.facadePlan(roofs, solid, doors, wallH, rH)
  local out = {}
  local function key(i, j) return i .. "," .. j end
  for k, r in pairs(roofs) do
    out[k] = { top = r.top, eave = r.eave + 1, w = r.w, vrow = r.vrow, tall = r.tall }
  end
  for k, r in pairs(roofs) do
    local ci, cj = k:match("^(-?%d+),(-?%d+)$")
    ci, cj = tonumber(ci), tonumber(cj)
    if ci and cj == r.eave - 1 then
      local fk = key(ci, r.eave)
      if solid[fk] and not out[fk] then
        out[fk] = { top = r.top, eave = r.eave + 1, w = r.w, vrow = r.vrow or cj, facade = true, tall = r.tall }
      end
    end
  end
  for _, d in ipairs(doors or {}) do
    local di, dj = d[1], d[2]
    local dk = key(di, dj)
    local above = roofs[key(di, dj - 1)]
    if not out[dk] and above and above.eave == dj
      and (out[key(di - 1, dj)] or out[key(di + 1, dj)]) then
      out[dk] = { top = above.top, eave = dj + 1, w = above.w, vrow = above.vrow or (dj - 1),
        facade = true, door = true, tall = above.tall }
      d.flush = true
      if rH then rH[dk] = wallH end
    end
  end
  return out
end

-- jp.79: whether a cell's four 8x8 tiles all use the tree palette (BG
-- palette slot 3 = GREEN, 1-based as TileAttrs gives it).  paletteAt(dx, dy)
-- returns the slot of the tile at pixel offset (dx, dy) in the cell, or nil
-- when unknown (then the cell is not called a tree).  Pure.
Field3D.TREE_PALETTE = 3
function Field3D.isTreePalette(paletteAt)
  for _, o in ipairs({ { 0, 0 }, { 8, 0 }, { 0, 8 }, { 8, 8 } }) do
    if paletteAt(o[1], o[2]) ~= Field3D.TREE_PALETTE then return false end
  end
  return true
end

-- jp.83: a cell's picture as the ground canvas shows it, one character per
-- pixel (16 rows of 16): "0".."3" = colour 0..3 of the tree palette, "x" =
-- any other colour.  looksLikeTree(art) is the test for a wall cell the
-- palette grid cannot answer (past the map edge): tree colours only, and a
-- dark outline (colour 3), which the grass and the flower beds drawn in the
-- tree palette do not have.  Pure.
function Field3D.looksLikeTree(art)
  if type(art) ~= "string" or #art ~= CELL * CELL then return false end
  if art:find("x", 1, true) then return false end
  local _, black = art:gsub("3", "")
  return black >= Field3D.TREECARD.minBlack
end

-- jp.83: the cut-out of a tree card, `art` = the card's rows top to bottom
-- (16 wide, any height) in looksLikeTree's characters.  The grass colours
-- (0 and 1) joined to the card's edge, side by side or above and below, are
-- cut away ("0" in the result); everything else stays ("1"), so the light
-- pixels inside the crown, fenced in by the outline, are kept.  Pure.
function Field3D.cardMask(art)
  local w = CELL
  local n = #art
  local h = math.floor(n / w)
  local out, stack = {}, {}
  for p = 1, n do out[p] = "1" end
  local function grass(p)
    local ch = art:byte(p)
    return ch == 48 or ch == 49 -- "0", "1"
  end
  local function push(p)
    if out[p] == "1" and grass(p) then
      out[p] = "0"
      stack[#stack + 1] = p
    end
  end
  for x = 1, w do push(x); push((h - 1) * w + x) end
  for y = 0, h - 1 do push(y * w + 1); push(y * w + w) end
  while #stack > 0 do
    local p = table.remove(stack)
    local x = (p - 1) % w
    if x > 0 then push(p - 1) end
    if x < w - 1 then push(p + 1) end
    if p > w then push(p - w) end
    if p + w <= n then push(p + w) end
  end
  return table.concat(out)
end

-- jp.83: which tree cells make one card.  trees[key "i,j"] = 1 (a tree)
-- or 2 (a cut tree); gy0 = the map row of region row 0.  A GBC tree is 16
-- wide and 32 tall, the crown on an even map row (blocks are 32 tall and
-- start on even rows) and the trunk on the row below: those two make one
-- card two cells tall.  Every other tree cell (the small trees, the cut
-- trees, a crown or trunk whose partner is not a tree) is a card one cell
-- tall.  Returns a list of { i, j, cells }.  Pure.
function Field3D.treeCardPlan(trees, gy0, gw, gh)
  local list, used = {}, {}
  for j = 0, gh - 1 do
    for i = 0, gw - 1 do
      local k = i .. "," .. j
      local t = trees[k]
      if t and not used[k] then
        local below = i .. "," .. (j + 1)
        if t == 1 and (gy0 + j) % 2 == 0 and trees[below] == 1 and j + 1 < gh then
          used[below] = true
          list[#list + 1] = { i, j, 2 }
        else
          list[#list + 1] = { i, j, 1 }
        end
      end
    end
  end
  return list
end

-- jp.79: rooms and caves.  envKind says which shape set a map gets:
-- "out" (towns, routes: roofs and doors), "cave" (cave and ice tilesets:
-- rugged rock), "room" (indoor and gate maps: a tall cut-away shell and low
-- furniture) or "box" (the rest keep the jp.77 boxes; jp.80: dungeon
-- floors such as towers and ruins are rooms now).
local CAVE_TILESETS = { TILESET_CAVE = true, TILESET_ICE_PATH = true }
function Field3D.envKind(def)
  local env = def and def.environment
  if env == "TOWN" or env == "ROUTE" then return "out" end
  if def and CAVE_TILESETS[def.tileset] then return "cave" end
  if env == "CAVE" and not (def and def.tileset and TILESET_PROFILE[def.tileset]) then return "cave" end
  if env == "INDOOR" or env == "GATE" then return "room" end
  -- jp.80: towers, the lighthouse, the Ruins of Alph, the Goldenrod
  -- underground and the Rocket base are indoor floors too
  if env == "DUNGEON" then return "room" end
  return "box"
end

-- Room shapes: the shell (walls joined to the edge of the region or to the
-- void, through walls and void) stands ROOM.shell tall with a dark cut top,
-- so the room reads as a doll's house; walls standing free inside the room
-- (shelves, machines, tables) are furniture, ROOM.furniture tall.
Field3D.ROOM = { shell = 18, furniture = 10, cap = 0.42 }
-- shellOf(isBlock, i0, j0, i1, j1): the set of block cells (key "i,j")
-- reachable from the border of the box through block cells.  Pure.
function Field3D.shellOf(isBlock, i0, j0, i1, j1)
  local shell, stack = {}, {}
  local function push(i, j)
    local k = i .. "," .. j
    if not shell[k] and isBlock(i, j) then
      shell[k] = true
      stack[#stack + 1] = { i, j }
    end
  end
  for i = i0, i1 do push(i, j0); push(i, j1) end
  for j = j0, j1 do push(i0, j); push(i1, j) end
  while #stack > 0 do
    local c = table.remove(stack)
    local i, j = c[1], c[2]
    if i > i0 then push(i - 1, j) end
    if i < i1 then push(i + 1, j) end
    if j > j0 then push(i, j - 1) end
    if j < j1 then push(i, j + 1) end
  end
  return shell
end

-- Cave rock: a grid corner inside the rock (all four cells around it are
-- rock) rises by 0..CAVE.jag, fixed per corner, so the top is rugged while
-- every edge that meets the floor stays at the wall height.  Rock side faces
-- take CAVE.side of their usual shade.  Pure.
Field3D.CAVE = { jag = 9, side = 0.7, fog = { 70, 200 } }
function Field3D.caveJag(gx, gy)
  local hsh = (gx * 92837111 + gy * 689287499 + 12345) % 9973
  return Field3D.CAVE.jag * (hsh / 9972)
end

-- jp.80: the ridge may rise higher on a wide building (Elm's lab, 6 wide,
-- read as a flat lid): 10 up to 4 wide (the houses, as before), +4 a cell
-- past that, up to 18 at 6 wide and over.  Pure.
function Field3D.roofRiseCap(w)
  local extra = math.max(0, math.min(2, (w or 4) - 4))
  return 10 + 4 * extra
end

-- jp.80: which texture row a roof cell shows.  The rows under the ridge
-- line of a GBC house can be the wall's top (the lab's windows, the
-- Pokemon Center's sign) drawn in the wall palette; those take the nearest
-- row of the same column in the roof palette (above first, then below,
-- within the roof).  A column with no roof-palette row (towers drawn in
-- the wall palette all the way up) keeps its own rows.  palAt(i, j) gives
-- a cell's palette slot when all four of its tiles share it, else nil.
-- Pure.
Field3D.ROOF_PALETTE = 7
function Field3D.roofTexRow(palAt, i, j, roof)
  local R = Field3D.ROOF_PALETTE
  if not palAt or palAt(i, j) == R then return j end
  for r = j - 1, roof.top, -1 do
    if palAt(i, r) == R then return r end
  end
  for r = j + 1, roof.eave - 1 do
    if palAt(i, r) == R then return r end
  end
  return j
end

-- jp.84: two-row fronts.  On a building with a real roof (some row of it in
-- the roof palette) whose last roofed row (eave - 1, just above the front
-- row) is not all roof palette, that row is wall art (the Violet Gym's GYM
-- plate and windows, the Pokemon Center's and the Mart's upper brick): it
-- stood under the gable and showed roof tiles.  Such a building is marked
-- tall (every roof cell of it gets tall = true), and the drawing then
-- stands that row upright over the front row, the walls one cell taller.
-- At least one roof row must stay above it.  palAt(i, j) as for
-- roofTexRow; inMap(i, j) says whether a cell's palette is known.  Changes
-- roofs in place; returns the number of tall buildings.  Pure.
function Field3D.tallFronts(roofs, palAt, inMap)
  local R = Field3D.ROOF_PALETTE
  local groups = {}
  for k, r in pairs(roofs) do
    local i, j = k:match("^(-?%d+),(-?%d+)$")
    i, j = tonumber(i), tonumber(j)
    if i and j == r.eave - 1 and r.eave - 1 - r.top >= 1 then
      local l = i
      while true do
        local o = roofs[(l - 1) .. "," .. j]
        if not (o and o.top == r.top and o.eave == r.eave) then break end
        l = l - 1
      end
      local gk = l .. "," .. j
      local g = groups[gk]
      if not g then
        g = { j = j, top = r.top, eave = r.eave, cols = {} }
        groups[gk] = g
      end
      g.cols[#g.cols + 1] = i
    end
  end
  local n = 0
  for _, g in pairs(groups) do
    local wallRow, roofRow, known = false, false, true
    for _, i in ipairs(g.cols) do
      if inMap and not inMap(i, g.j) then known = false end
      if palAt(i, g.j) ~= R then wallRow = true end
      for jj = g.top, g.j - 1 do
        if palAt(i, jj) == R then roofRow = true end
      end
    end
    if known and wallRow and roofRow then
      n = n + 1
      -- more wall rows over it (the Dept Store's two rows of windows) stand
      -- up too, while most of the row is wall art and a roof row stays
      -- above
      local rows = 1
      for jj = g.j - 1, g.top + 1, -1 do
        local wallN, above = 0, false
        for _, i in ipairs(g.cols) do
          if inMap and not inMap(i, jj) then wallN = -math.huge end
          if palAt(i, jj) ~= R then wallN = wallN + 1 end
          for ja = g.top, jj - 1 do
            if palAt(i, ja) == R then above = true end
          end
        end
        if not (above and wallN * 2 > #g.cols) then break end
        rows = rows + 1
      end
      for _, i in ipairs(g.cols) do
        for jj = g.top, g.j do
          local r = roofs[i .. "," .. jj]
          if r and r.top == g.top and r.eave == g.eave then r.tall = rows end
        end
      end
    end
  end
  return n
end

-- The gable's height over a roofed cell at world z (rows top..eave-1 of
-- CELL each, oy = the region's first row): h at both eaves, h + rise on the
-- ridge.  rise grows with the roof's depth, up to roofRiseCap(width).
function Field3D.gableY(roof, oy, h, z)
  local zTop, zEave = (oy + roof.top) * CELL, (oy + roof.eave) * CELL
  local half = (zEave - zTop) / 2
  if half <= 0 then return h end
  local rise = math.min(Field3D.roofRiseCap(roof.w), half * 0.9)
  local zr = zTop + half
  return h + rise * math.max(0, 1 - math.abs(z - zr) / half)
end

-- jp.78: a ground corner's shade.  A small fixed speckle (0.9..1) so the
-- tilemap reads as ground rather than a flat print, and a soft darkening
-- where the corner meets taller cells (walls, trees, counters): up to four.
function Field3D.groundShade(gx, gy, taller)
  -- jp.85: no speckle.  The per-corner shade made every ground tile a
  -- visibly different block on the phone; the 初代 (Gen 1) ground is one
  -- flat print with only the darkening at taller cells.
  return 1 - 0.09 * math.min(4, taller or 0)
end

-- jp.83: the pictures of the cells in `want` (a list of { i, j }) read back
-- from the ground canvas, already drawn for this region, in looksLikeTree's
-- characters.  Tree art never animates, so a cell is read once per map and
-- time of day (cached under World:mapCacheKey, by map cell) and a step reads
-- back only the strip of new cells.  Returns art[key "i,j"], or nil when the
-- palette or the read-back is not there (then nothing is cut out).
local function cellArt(world, st, canvas, ox, oy, want)
  if not canvas or not canvas.newImageData or #want == 0 then return nil end
  -- (a warp's fade shifts the palette one shade at a time: art read then
  -- had no outline colour and stayed cached as "not a tree")
  if world.fade ~= nil then return nil end
  local map = world.map
  local okK, key = pcall(world.mapCacheKey, world, map and map.id)
  local bg = okK and world.bgSets and world.bgSets[key]
  local pal = bg and bg[Field3D.TREE_PALETTE]
  if not pal then return nil end
  local cache = st.artCache
  if not cache or cache.key ~= key then
    local okP, GbcPalette = pcall(require, "src.render.GbcPalette")
    if not okP then return nil end
    local lut = {}
    for c = 4, 1, -1 do
      local col = GbcPalette.color(pal, c)
      if not col then return nil end
      lut[col[1] * 65536 + col[2] * 256 + col[3]] = string.char(47 + c)
    end
    cache = { key = key, lut = lut, cells = {} }
    st.artCache = cache
  end
  local cells, lut = cache.cells, cache.lut
  local x0, y0, x1, y1
  for _, w in ipairs(want) do
    if not cells[(ox + w[1]) .. "," .. (oy + w[2])] then
      local i, j = w[1], w[2]
      x0, y0 = math.min(x0 or i, i), math.min(y0 or j, j)
      x1, y1 = math.max(x1 or i, i), math.max(y1 or j, j)
    end
  end
  if x0 then
    local rw, rh = (x1 - x0 + 1) * CELL, (y1 - y0 + 1) * CELL
    local okD, data = pcall(canvas.newImageData, canvas, 1, 1, x0 * CELL, y0 * CELL, rw, rh)
    if not okD or not data then return nil end
    local okS, raw = pcall(data.getString, data)
    if okS and (data.getFormat and data:getFormat() ~= "rgba8") then okS = false end
    if data.release then data:release() end
    if not okS or type(raw) ~= "string" or #raw < rw * rh * 4 then return nil end
    local byte, chars = string.byte, {}
    for _, w in ipairs(want) do
      local i, j = w[1], w[2]
      local gk = (ox + i) .. "," .. (oy + j)
      if not cells[gk] then
        local px, py = (i - x0) * CELL, (j - y0) * CELL
        for y = 0, CELL - 1 do
          local s = ((py + y) * rw + px) * 4
          local row = { byte(raw, s + 1, s + CELL * 4) }
          for x = 0, CELL - 1 do
            local q = x * 4
            chars[y * CELL + x + 1] = lut[row[q + 1] * 65536 + row[q + 2] * 256 + row[q + 3]] or "x"
          end
        end
        cells[gk] = table.concat(chars)
      end
    end
  end
  local art = {}
  for _, w in ipairs(want) do
    art[w[1] .. "," .. w[2]] = cells[(ox + w[1]) .. "," .. (oy + w[2])]
  end
  return art
end

-- jp.83: one cut-out Image per distinct mask (a wood repeats a handful)
local function maskImage(mask)
  gpu.maskImages = gpu.maskImages or {}
  local img = gpu.maskImages[mask]
  if img then return img end
  local h = math.floor(#mask / CELL)
  local bytes = {}
  for p = 1, #mask do
    bytes[p] = mask:byte(p) == 49 and "\255\255\255\255" or "\0\0\0\0"
  end
  local data = love.image.newImageData(CELL, h, "rgba8", table.concat(bytes))
  img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  gpu.maskImages[mask] = img
  return img
end

local function buildTerrain(world, st, ox, oy, canvas)
  local t0 = os.clock()
  local map = world.map
  local prof = Field3D.profileFor(map and map.def)
  local SW = GW + 2
  local heights, tapers, colls = {}, {}, {}
  for j = -1, GH do
    for i = -1, GW do
      local okc, coll = pcall(world.cellCollisionAcross, world, map, ox + i, oy + j)
      local k = (j + 1) * SW + (i + 1) + 1
      heights[k] = Field3D.heightOf(okc and coll or nil, prof)
      tapers[k] = Field3D.taperOf(okc and coll or nil, prof)
      colls[k] = okc and coll or nil
    end
  end
  -- jp.82: the mesh is a pure function of the map, the region and these
  -- collision values, so the half-second refresh skips the rebuild when
  -- none of them changed (trees made the mesh about ten times bigger)
  do
    -- (jp.83: and the palettes, which the tree cards' cut-out reads)
    local okK, pkey = pcall(world.mapCacheKey, world, map and map.id)
    local parts = { tostring(map), tostring(map and map.id), ox, oy, tostring(world.attrGrid),
      tostring(gpu.ground), okK and tostring(pkey) or "?", world.fade ~= nil and "fade" or "" }
    for k = 1, SW * (GH + 2) do parts[#parts + 1] = colls[k] or "x" end
    local sig = table.concat(parts, ",")
    if st.terrainSig == sig and (st.groundCount or 0) > 0 then
      st.buildMs = (os.clock() - t0) * 1000
      st.buildSkipped = (st.buildSkipped or 0) + 1
      return
    end
    st.terrainSig = sig
  end
  local function hAt(i, j) return heights[(j + 1) * SW + (i + 1) + 1] end
  local function collAt(i, j) return colls[(j + 1) * SW + (i + 1) + 1] end
  -- jp.78: doors and roofs, outdoors only (the house doors of towns and
  -- routes)
  local kind = Field3D.envKind(map and map.def)
  local outside = kind == "out"
  st.envKind3D = kind
  -- jp.79: a room's shell and furniture, a cave's rugged rock
  local capped, rock = {}, {}
  if kind == "room" or kind == "cave" then
    local function blockAt(i, j)
      local c = collAt(i, j)
      if c == nil or c % 256 == 0xff then return true end
      return Permissions.of(c % 256) == Permissions.WALL and not Permissions.isCounter(c % 256)
        and hAt(i, j) >= prof.wall
    end
    if kind == "room" then
      local shell = Field3D.shellOf(blockAt, -1, -1, GW, GH)
      local R = Field3D.ROOM
      for j = -1, GH do
        for i = -1, GW do
          if blockAt(i, j) then
            local k = (j + 1) * SW + (i + 1) + 1
            if shell[i .. "," .. j] then
              heights[k] = math.max(heights[k], R.shell)
              capped[i .. "," .. j] = true
            else
              heights[k] = R.furniture
            end
          end
        end
      end
    else
      for j = -1, GH do
        for i = -1, GW do
          if blockAt(i, j) then rock[i .. "," .. j] = true end
        end
      end
    end
  end
  -- the rise of grid corner (gi, gj) over the rock (0 off the rock)
  local function jagAt(gi, gj)
    if not (rock[(gi - 1) .. "," .. (gj - 1)] and rock[gi .. "," .. (gj - 1)]
      and rock[(gi - 1) .. "," .. gj] and rock[gi .. "," .. gj]) then return 0 end
    return Field3D.caveJag(ox + gi, oy + gj)
  end
  local doors, roofs, solid = {}, {}, {}
  -- jp.82: trees[key] = 1 (a tree) / 2 (a small cut tree), drawn flat
  -- (jp.83: under a standing card of their own art) instead of a box;
  -- rH[key] overrides the DRAWN height of a cell (logic heights,
  -- st.heightAt, stay as they were)
  local trees, rH = {}, {}
  st.roofReport3D = {}
  if outside then
    for j = 0, GH - 1 do
      for i = 0, GW - 1 do
        local c = collAt(i, j)
        c = c and c % 256
        if (c == 0x71 or c == 0x7b) and hAt(i, j) == 0 and (hAt(i, j - 1) or 0) >= prof.wall then
          doors[#doors + 1] = { i, j, cave = c == 0x7b }
        end
      end
    end
    local houseDoors = {}
    for _, d in ipairs(doors) do
      if not d.cave then houseDoors[#houseDoors + 1] = d end
    end
    -- jp.79: a wall cell drawn wholly in the tree palette is a tree line,
    -- not part of a house (Gold's house and Elm's lab back onto the tree
    -- border, so their wall runs used to reach the size cap)
    -- A door inside this map has its house inside it too, so past the map
    -- edge (the border trees) is not house either.  Doors in a neighbour's
    -- strip keep the jp.78 rule (no palette there).
    -- (World:setMap rebuilds attrGrid with the map, before any draw)
    -- jp.80: Gold and Silver keep no attrGrid (World nils it there on
    -- purpose for the 2D view), so the 3D view builds its own palette grid
    -- from the tileset, once per map, and keeps it here
    local grid = world.attrGrid
    if grid == nil and map ~= nil and map.def ~= nil then
      if st.palGridMap ~= map then
        st.palGridMap, st.palGrid = map, nil
        local ts = world.tilesets and world.tilesets[map.def.tileset]
        if ts then
          local okG, g = pcall(MapAttrGrid.build, map, ts)
          if okG and type(g) == "table" and next(g) ~= nil then st.palGrid = g end
        end
      end
      grid = st.palGrid
    end
    st.palGrid3D = grid
    local paletteKnown = grid ~= nil and map ~= nil and map.inBounds ~= nil
    local function treeCell(i, j)
      if not map:inBounds(ox + i, oy + j) then return true end
      return Field3D.isTreePalette(function(dx, dy)
        local cell = MapAttrGrid.lookup(grid, (ox + i) * 16 + dx, (oy + j) * 16 + dy)
        return cell and cell.attr and cell.attr.palette
      end)
    end
    local function wallAt(i, j)
      if i < 0 or j < 0 or i >= GW or j >= GH then return false end
      local c = collAt(i, j)
      return c ~= nil and c % 256 ~= 0xff and Permissions.of(c % 256) == Permissions.WALL
        and hAt(i, j) >= prof.wall
    end
    local inner, outer = {}, {}
    for _, d in ipairs(houseDoors) do
      local list = (paletteKnown and map:inBounds(ox + d[1], oy + d[2])) and inner or outer
      list[#list + 1] = d
    end
    roofs, solid = Field3D.roofPlan(function(i, j)
      return wallAt(i, j) and not treeCell(i, j)
    end, inner, nil, st.roofReport3D)
    local roofs2, solid2 = Field3D.roofPlan(wallAt, outer, nil, st.roofReport3D)
    for k, r in pairs(roofs2) do roofs[k] = roofs[k] or r end
    for k in pairs(solid2) do solid[k] = true end
    -- jp.80: the roof shows roof tiles, not the wall top under the ridge
    if grid ~= nil then
      local function palAt(i, j)
        local p0
        for _, o in ipairs({ { 0, 0 }, { 8, 0 }, { 0, 8 }, { 8, 8 } }) do
          local cell = MapAttrGrid.lookup(grid, (ox + i) * 16 + o[1], (oy + j) * 16 + o[2])
          local p = cell and cell.attr and cell.attr.palette
          if p == nil or (p0 ~= nil and p ~= p0) then return nil end
          p0 = p
        end
        return p0
      end
      for k, r in pairs(roofs) do
        local ci, cj = k:match("^(-?%d+),(-?%d+)$")
        ci, cj = tonumber(ci), tonumber(cj)
        if ci and map.inBounds and map:inBounds(ox + ci, oy + cj) then
          r.vrow = Field3D.roofTexRow(palAt, ci, cj, r)
        end
      end
      -- jp.84: a wall row under the gable (the GYM plate) stands upright
      local okT, nT = pcall(Field3D.tallFronts, roofs, palAt, function(i, j)
        return map.inBounds ~= nil and map:inBounds(ox + i, oy + j)
      end)
      st.tallFronts3D = okT and nT or ("err " .. tostring(nT))
      local tl = {}
      for k, r in pairs(roofs) do
        local ti, tj = k:match("^(-?%d+),(-?%d+)$")
        if r.tall and tonumber(tj) == r.eave - 1 then
          tl[#tl + 1] = string.format("%d,%d:%d-%d:%s", ox + tonumber(ti), oy + tonumber(tj),
            oy + r.top, oy + r.eave, tostring(r.tall))
        end
      end
      table.sort(tl)
      st.tallList3D = tl
    end
    -- jp.82: facades.  The front row (the wall with the windows and the
    -- door) used to lie flat on top of a box under the gable; now the roof
    -- runs on over it to its south edge, so that row's art stands upright
    -- as the house front, and a door flanked by walls sits flush in it
    -- instead of a cell-deep notch.  roofPlan's own answer is untouched.
    roofs = Field3D.facadePlan(roofs, solid, houseDoors, prof.wall, rH)
    -- jp.84: a tall building's walls (and its flush door) stand one cell
    -- taller, so the gable sits over the upright second row
    for k, r in pairs(roofs) do
      if r.tall then
        local ci, cj = k:match("^(-?%d+),(-?%d+)$")
        ci, cj = tonumber(ci), tonumber(cj)
        if ci then rH[k] = (rH[k] or hAt(ci, cj) or prof.wall) + CELL * (tonumber(r.tall) or 1) end
      end
    end
    -- jp.82: trees.  A tree-palette wall that is not part of a house, and
    -- every cut / headbutt tree, is a tree.  jp.83: past the map edge (no
    -- palette grid there; jp.82 called every such wall a tree, which put
    -- fences, flower beds and roofs on tree cards) the cell's own picture
    -- decides (Field3D.looksLikeTree).
    local cand, want = {}, {}
    for j = 0, GH - 1 do
      for i = 0, GW - 1 do
        local k = i .. "," .. j
        local c = collAt(i, j)
        c = c and c % 256
        if c and c ~= 0xff and not solid[k] and not roofs[k] then
          local kind
          if Permissions.isCutTree(c) then
            kind = "cut"
          elseif Permissions.isHeadbuttTree(c) then
            kind = "tree"
          elseif paletteKnown and wallAt(i, j) then
            if map:inBounds(ox + i, oy + j) then
              if treeCell(i, j) then kind = "tree" end
            else
              kind = "edge"
            end
          end
          if kind then
            cand[k] = kind
            want[#want + 1] = { i, j }
          end
        end
      end
    end
    local okA, art = pcall(cellArt, world, st, canvas, ox, oy, want)
    if not okA then note("tree art: " .. tostring(art)); art = nil end
    st.treeArt3D = art
    local er = { edge = 0, tree = 0, noArt = 0, other = 0, sample = nil }
    st.edgeReport3D = er
    for _, w in ipairs(want) do
      local k = w[1] .. "," .. w[2]
      local kind = cand[k]
      if kind == "edge" then
        er.edge = er.edge + 1
        if art and Field3D.looksLikeTree(art[k]) then
          trees[k] = 1
          er.tree = er.tree + 1
        elseif not (art and art[k]) then
          er.noArt = er.noArt + 1
        else
          er.other = er.other + 1
          er.sample = er.sample or (k .. " " .. art[k])
        end
      else
        trees[k] = kind == "cut" and 2 or 1
      end
      if trees[k] then rH[k] = 0 end
    end
  end
  local treeCount = 0
  for _ in pairs(trees) do treeCount = treeCount + 1 end
  st.trees3D, st.treeCells3D = treeCount, trees
  -- jp.83: a room's void (no collision, or 0xff) is the black outside of
  -- the room.  It used to stand as a black block as tall as the shell and
  -- hid the room's front rows; now it is not drawn at all (the indoor sky
  -- is black anyway) and stands at 0.
  local void = {}
  if kind == "room" then
    for j = -1, GH do
      for i = -1, GW do
        local c = collAt(i, j)
        if c == nil or c % 256 == 0xff then
          void[i .. "," .. j] = true
          heights[(j + 1) * SW + (i + 1) + 1] = 0
        end
      end
    end
  end
  -- jp.83: the fold (see Field3D.FOLD).  Local 8px rows: cell j holds rows
  -- 2j and 2j+1.
  local FOLD = Field3D.FOLD
  local foldAt, fH = {}, {}
  local foldRuns = 0
  do
    local doorKey = {}
    for _, d in ipairs(doors) do doorKey[d[1] .. "," .. d[2]] = true end
    local function foldClass(i, j)
      if i < 0 or j < 0 or i >= GW or j >= GH then return nil end
      local key = i .. "," .. j
      local c = collAt(i, j)
      if c == nil or void[key] then return nil end
      if Permissions.isCounter(c % 256) then return nil end
      if (hAt(i, j) or 0) < 8 then return nil end
      if kind == "room" then
        return capped[key] and "shell" or "furn"
      elseif outside then
        if trees[key] or roofs[key] or solid[key] or rH[key] ~= nil or doorKey[key] then return nil end
        return "out"
      end
      return nil
    end
    -- the 8px tile pair of column i at local row r ("" when unknown: no
    -- repeat is read from it)
    local sigCache = {}
    local function sig(i, r)
      local k = i * 4096 + r
      local s = sigCache[k]
      if s ~= nil then return s end
      s = ""
      if map ~= nil and map.tileAt then
        local tx, ty = 2 * (ox + i), 2 * oy + r
        local ok1, a = pcall(map.tileAt, map, tx, ty)
        local ok2, b = pcall(map.tileAt, map, tx + 1, ty)
        if ok1 and ok2 and a ~= nil and b ~= nil then s = a .. "," .. b end
      end
      sigCache[k] = s
      return s
    end
    local function same(i, a, b)
      local sa = sig(i, a)
      return sa ~= "" and sa == sig(i, b)
    end
    local runs = {}
    for i = 0, GW - 1 do
      local j = 0
      while j < GH do
        local cls = foldClass(i, j)
        if cls then
          local j1 = j
          while j1 + 1 < GH and foldClass(i, j1 + 1) == cls do j1 = j1 + 1 end
          local N, F = 2 * j, 2 * j1 + 1
          local extent = F - N + 1
          local maxR = cls == "out" and FOLD.maxRows or FOLD.roomRows
          -- Gen 1 ChunkMesher: the unit is the run's length, or the period
          -- of a tile row repeating up from the front, or 2 rows when the
          -- two rows over the front match (a trim)
          local unit, rep = math.min(extent, maxR), false
          for k = 1, extent - 1 do
            if same(i, F - k, F) then
              unit, rep = math.min(math.max(k, 2), maxR), true
              break
            end
          end
          if not rep and extent > 2 and same(i, F - 1, F - 2) then unit = 2 end
          local r = { i = i, j0 = j, j1 = j1, N = N, F = F, cls = cls, rep = rep, H = unit * 8 }
          runs[#runs + 1] = r
          for jj = j, j1 do foldAt[i .. "," .. jj] = r end
          j = j1 + 1
        else
          j = j + 1
        end
      end
    end
    -- Gen 1 region consensus: the runs joined side by side outdoors share
    -- the most common height (ties to the taller); a repeating run takes it
    -- when that is taller than its own
    local compOf, comps = {}, {}
    for _, r in ipairs(runs) do
      if r.cls == "out" and not compOf[r] then
        local list, stack = {}, { r }
        compOf[r] = list
        while #stack > 0 do
          local q = table.remove(stack)
          list[#list + 1] = q
          for jj = q.j0, q.j1 do
            for _, di in ipairs({ -1, 1 }) do
              local o = foldAt[(q.i + di) .. "," .. jj]
              if o and o.cls == "out" and not compOf[o] then
                compOf[o] = list
                stack[#stack + 1] = o
              end
            end
          end
        end
        comps[#comps + 1] = list
      end
    end
    for _, list in ipairs(comps) do
      local count, modeH, best = {}, nil, 0
      for _, q in ipairs(list) do count[q.H] = (count[q.H] or 0) + 1 end
      for hh, c in pairs(count) do
        if c > best or (c == best and hh > modeH) then modeH, best = hh, c end
      end
      for _, q in ipairs(list) do
        if q.rep and modeH and modeH > q.H then q.H = modeH end
      end
    end
    for _, r in ipairs(runs) do
      -- the top: Gen 1 flatTopRow outdoors, the furniture rule indoors
      local topUniform = same(r.i, r.N, r.N + 1)
      local m = math.min(2, r.F - r.N + 1)
      if r.cls == "out" then
        r.top = function(row)
          local d = row - r.N
          if topUniform then return r.N + math.min(d, m - 1) end
          return r.N + (d % m)
        end
      else
        r.top = function(row)
          local t = math.min(row, r.F - math.floor(r.unitH / 8))
          if t < r.N then t = r.N end
          return t
        end
      end
      -- jp.83: the unit only picks the rows the faces and tops show; the
      -- standing height stays the jp.82 one (a Gen 1 height raised ledges
      -- and fences over the sprites behind them and left gaps)
      r.unitH, r.H = r.H, nil
      for jj = r.j0, r.j1 do fH[r.i .. "," .. jj] = hAt(r.i, jj) end
    end
    -- jp.84: the big buildings stand up (Field3D.TOWER)
    local towerCells = 0
    local towerList = {}
    if outside then
      local TW = Field3D.TOWER
      local seen = {}
      for _, d in ipairs(doors) do
        local si, sj = d[1], d[2] - 1
        local sk = si .. "," .. sj
        local r0 = foldAt[sk]
        if not d.cave and not d.flush and r0 and r0.cls == "out" and not seen[sk] then
          seen[sk] = true
          local function wallOut(i)
            local q = foldAt[i .. "," .. sj]
            return q and q.cls == "out" and (hAt(i, sj) or 0) >= prof.wall and not rH[i .. "," .. sj]
          end
          local fl, fr = si, si
          while fl > si - TW.w and wallOut(fl - 1) do fl = fl - 1 end
          while fr < si + TW.w and wallOut(fr + 1) do fr = fr + 1 end
          local stack, blob = { { si, sj } }, {}
          while #stack > 0 do
            local c = table.remove(stack)
            blob[#blob + 1] = c
            for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
              local ni, nj = c[1] + o[1], c[2] + o[2]
              local nk = ni .. "," .. nj
              local q = foldAt[nk]
              -- only the door's own building: inside the columns its front
              -- wall spans on the door row, never a roofed cell (a neighbour
              -- stays as it was)
              if q and q.cls == "out" and not seen[nk] and ni >= fl and ni <= fr
                and not rH[nk]
                and nj <= sj + 1 and sj - nj <= TW.h and (hAt(ni, nj) or 0) >= prof.wall
                and (o[2] == -1 or (o[2] == 0 and c[2] == sj)) then
                seen[nk] = true
                stack[#stack + 1] = { ni, nj }
              end
            end
          end
          local maxRows, minJ = 0, sj
          for _, c in ipairs(blob) do
            local q = foldAt[c[1] .. "," .. c[2]]
            maxRows = math.max(maxRows, q.F - q.N + 1)
            minJ = math.min(minJ, c[2])
          end
          towerList[#towerList + 1] = string.format("%d,%d:%d-%d:%dc:%dr", si, sj, fl, fr, #blob, maxRows)
          -- a low flat-roofed building (10 rows) keeps its fold; only a
          -- real tower (the lighthouse, 30 rows) stands up.  The Radio
          -- Tower (20) stays as jp.83: its top stood apart from its base
          if maxRows < TW.minRows then blob = {} end
          for _, c in ipairs(blob) do
            local k = c[1] .. "," .. c[2]
            local q = foldAt[k]
            local H = math.min(q.F - q.N + 1, 2 * TW.cells) * 8
            if H > (fH[k] or 0) then
              fH[k] = H
              towerCells = towerCells + 1
            end
          end
        end
      end
    end
    st.towerCells3D = towerCells
    st.note3D = table.concat(towerList, " ")
    foldRuns = #runs
  end
  st.foldRuns3D = foldRuns
  local function hR(i, j)
    local key = i .. "," .. j
    local o = rH[key]
    if o ~= nil then return o end
    o = fH[key]
    if o ~= nil then return o end
    return hAt(i, j)
  end
  st.doors3D, st.roofCells3D = #doors, 0
  for _ in pairs(roofs) do st.roofCells3D = st.roofCells3D + 1 end
  local doorAt = {}
  for _, d in ipairs(doors) do doorAt[d[1] .. "," .. d[2]] = d end
  st.heightAt = function(cx, cy)
    local i, j = cx - ox, cy - oy
    if i < -1 or j < -1 or i > GW or j > GH then return 0 end
    return hAt(i, j) or 0
  end

  -- jp.82: the vertex tables are kept and refilled between builds (a tree
  -- mesh is ~100k vertices; making fresh tables each step fed the GC)
  gpu.groundPool = gpu.groundPool or {}
  local verts, n = gpu.groundPool, 0
  local cw, ch = GW * CELL, GH * CELL
  local function v(x, y, z, u, vv, shade)
    n = n + 1
    local t = verts[n]
    if t then
      t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8] = x, y, z, u, vv, shade, shade, shade
    else
      verts[n] = { x, y, z, u, vv, shade, shade, shade, 1 }
    end
  end
  local function quad(ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, u0, v0, u1, v1, shade, sb, sc, sd)
    -- a=top-left, b=top-right, c=bottom-right, d=bottom-left in texture space
    -- (jp.78: sb, sc, sd give the other corners their own shade)
    local sa = shade
    sb, sc, sd = sb or sa, sc or sa, sd or sa
    v(ax, ay, az, u0, v0, sa); v(bx, by, bz, u1, v0, sb); v(cx, cy, cz, u1, v1, sc)
    v(ax, ay, az, u0, v0, sa); v(cx, cy, cz, u1, v1, sc); v(dx, dy, dz, u0, v1, sd)
  end
  -- jp.83: a side face from height lo up to hi, cut at every 8px band
  -- (band k = heights 8k..8k+8 above the ground).  Band k wears local tile
  -- row rowOf(k), and a part band shows only the part of that row it
  -- covers: the art is cropped, never stretched (Gen 1 ChunkMesher side
  -- bands).  (tax, taz)-(tbx, tbz) is the top edge left to right, (bax,
  -- baz)-(bbx, bbz) the bottom edge; a tapered face leans between them.
  local maxRow = 2 * GH - 1
  local function wall(tax, taz, tbx, tbz, bax, baz, bbx, bbz, hi, lo, ua, ub, rowOf, shade)
    if hi <= lo then return end
    local span = hi - lo
    local k = math.floor(lo / 8)
    while k * 8 < hi do
      local y0, y1 = math.max(lo, k * 8), math.min(hi, k * 8 + 8)
      if y1 > y0 then
        local row = rowOf(math.max(k, 0))
        if row < 0 then row = 0 elseif row > maxRow then row = maxRow end
        local vt = (row * 8 + (k * 8 + 8 - y1)) / ch
        local vb = (row * 8 + (k * 8 + 8 - y0)) / ch
        local f1, f0 = (y1 - lo) / span, (y0 - lo) / span
        quad(bax + (tax - bax) * f1, y1, baz + (taz - baz) * f1,
          bbx + (tbx - bbx) * f1, y1, bbz + (tbz - bbz) * f1,
          bbx + (tbx - bbx) * f0, y0, bbz + (tbz - bbz) * f0,
          bax + (tax - bax) * f0, y0, baz + (taz - baz) * f0,
          ua, vt, ub, vb, shade)
      end
      k = k + 1
    end
  end
  -- jp.78: how many of the four cells around grid corner (gi, gj) stand
  -- taller than the ground there
  local function tallerAround(gi, gj)
    local c = 0
    for _, o in ipairs({ { -1, -1 }, { 0, -1 }, { -1, 0 }, { 0, 0 } }) do
      local hh = hAt(gi + o[1], gj + o[2])
      if hh and hh > 4 then c = c + 1 end
    end
    return c
  end
  -- jp.83: the trees are not modelled.  Each tree stands as a card of its
  -- own GBC picture (the 16x32 tree, crown and trunk, or a 16x16 small
  -- tree), upright at the south edge of its cells like the people (HD-2D;
  -- after the Gen1 3D's SpriteBillboards / TileShape "upright": the art
  -- stands up, nothing is invented).  The grass around the tree in its own
  -- tiles is cut away by a mask (Field3D.cardMask) drawn here into
  -- gpu.treeMask, laid out like the ground canvas; a card whose picture
  -- could not be read stays whole.  The cards themselves are built each
  -- frame in Field3D.draw, as they turn and lean with the camera.  Under
  -- each card the ground keeps the cell's own picture, darker
  -- (Field3D.TREECARD.shadow), as its shadow.
  local cards = Field3D.treeCardPlan(trees, oy, GW, GH)
  st.cards3D = cards
  local art = st.treeArt3D
  local okM, errM = pcall(function()
    local mask = ensureCanvas("treeMask", cw, ch)
    love.graphics.push("all")
    love.graphics.setCanvas(mask)
    love.graphics.clear(1, 1, 1, 1)
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("replace")
    if art then
      for _, c in ipairs(cards) do
        local i, j, cells = c[1], c[2], c[3]
        local top = art[i .. "," .. j]
        local bot = cells == 2 and art[i .. "," .. (j + 1)] or ""
        if top and bot and #top == CELL * CELL and #bot == (cells - 1) * CELL * CELL then
          love.graphics.draw(maskImage(Field3D.cardMask(top .. bot)), i * CELL, j * CELL)
        end
      end
    end
    love.graphics.pop()
  end)
  if not okM then
    note("tree mask: " .. tostring(errM))
    if gpu.treeMask then
      love.graphics.push("all")
      love.graphics.setCanvas(gpu.treeMask)
      love.graphics.clear(1, 1, 1, 1)
      love.graphics.pop()
    end
  end
  for j = 0, GH - 1 do
    for i = 0, GW - 1 do
      if n > MAX_GROUND_VERTS - 600 then break end
      local h = hR(i, j)
      local key = i .. "," .. j
      local fr = foldAt[key]
      if void[key] then goto nextCell end
      local x0, z0 = (ox + i) * CELL, (oy + j) * CELL
      local x1, z1 = x0 + CELL, z0 + CELL
      local u0, u1 = i * CELL / cw, (i + 1) * CELL / cw
      local v0, v1 = j * CELL / ch, (j + 1) * CELL / ch
      local hs, hn, he, hw = hR(i, j + 1), hR(i, j - 1), hR(i + 1, j), hR(i - 1, j)
      -- jp.76 shape profile: the top face is inset on each open side, so
      -- the side faces slope in (tapered canopy / rock) instead of a box
      -- (jp.78: a building with a door is drawn square)
      -- (jp.83: a folded run stands square, as in Gen 1)
      local t = (h > 0 and not solid[key] and not fr) and (tapers[(j + 1) * SW + (i + 1) + 1] or 0) or 0
      local iS = (t > 0 and hs < h) and t or 0
      local iN = (t > 0 and hn < h) and t or 0
      local iE = (t > 0 and he < h) and t or 0
      local iW = (t > 0 and hw < h) and t or 0
      local tx0, tx1, tz0, tz1 = x0 + iW, x1 - iE, z0 + iN, z1 - iS
      local roof = roofs[key]
      local door = doorAt[key]
      if trees[key] then
        -- jp.83: flat, the cell's own picture darker: the card's shadow
        local s = Field3D.TREECARD.shadow
        quad(x0, 0, z0, x1, 0, z0, x1, 0, z1, x0, 0, z1, u0, v0, u1, v1, s)
      elseif roof then
        -- jp.78: the gable, in two halves so the ridge (always on a half
        -- cell line) is a real crease
        local zm, vm = (z0 + z1) / 2, (v0 + v1) / 2
        local y0, ym, y1 = Field3D.gableY(roof, oy, h, z0), Field3D.gableY(roof, oy, h, zm),
          Field3D.gableY(roof, oy, h, z1)
        local north = ym >= y0 -- the half facing north rises to the ridge
        -- (jp.80: the slopes take the texture of roof.vrow when set)
        local r0, r1, rm = v0, v1, vm
        if roof.vrow and roof.vrow ~= j then
          r0, r1 = roof.vrow * CELL / ch, (roof.vrow + 1) * CELL / ch
          rm = (r0 + r1) / 2
        end
        quad(x0, y0, z0, x1, y0, z0, x1, ym, zm, x0, ym, zm, u0, r0, u1, rm, north and 0.86 or 1)
        quad(x0, ym, zm, x1, ym, zm, x1, y1, z1, x0, y1, z1, u0, rm, u1, r1, (y1 >= ym) and 0.86 or 1)
        -- the side walls run up to the gable on any side not roofed alike
        local s = 0.82
        if not roofs[(i + 1) .. "," .. j] then
          local b = math.min(he, h)
          quad(x1, y1, z1, x1, ym, zm, x1, b, zm, x1, b, z1, u0, vm, u1, v1, s)
          quad(x1, ym, zm, x1, y0, z0, x1, b, z0, x1, b, zm, u0, v0, u1, vm, s)
        end
        if not roofs[(i - 1) .. "," .. j] then
          local b = math.min(hw, h)
          quad(x0, y0, z0, x0, ym, zm, x0, b, zm, x0, b, z0, u0, v0, u1, vm, s)
          quad(x0, ym, zm, x0, y1, z1, x0, b, z1, x0, b, zm, u0, vm, u1, v1, s)
        end
        if hs < y1 and not roofs[i .. "," .. (j + 1)] and hs < h then
          -- (jp.82: a house front faces the viewer, so a touch lighter)
          -- (jp.84: a tall front shows the row above too, two cells of art
          -- over the two cells of wall)
          local tn = roof.facade and roof.tall and math.min(tonumber(roof.tall) or 1, j) or 0
          local fv0 = tn > 0 and (j - tn) * CELL / ch or v0
          quad(x0, y1, z1, x1, y1, z1, x1, hs, z1, x0, hs, z1, u0, fv0, u1, v1, roof.facade and 0.84 or 0.72)
        end
        if hn < y0 and not roofs[i .. "," .. (j - 1)] and hn < h then
          quad(x1, y0, z0, x0, y0, z0, x0, hn, z0, x1, hn, z0, u0, v0, u1, v1, 0.9)
        end
      else
        if h == 0 then
          -- jp.78: the ground's corners get a speckle and soft contact shade
          local gx, gy = ox + i, oy + j
          local sa = Field3D.groundShade(gx, gy, tallerAround(i, j))
          local sb = Field3D.groundShade(gx + 1, gy, tallerAround(i + 1, j))
          local sc = Field3D.groundShade(gx + 1, gy + 1, tallerAround(i + 1, j + 1))
          local sd = Field3D.groundShade(gx, gy + 1, tallerAround(i, j + 1))
          if door then
            -- the door's own tile stands up below; the floor in front of it
            -- takes the cell south of it (the path the door opens onto)
            local w0, w1 = v1, math.min(1, v1 + CELL / ch)
            quad(tx0, h, tz0, tx1, h, tz0, tx1, h, tz1, tx0, h, tz1, u0, w0, u1, w1, sa, sb, sc, sd)
          else
            quad(tx0, h, tz0, tx1, h, tz0, tx1, h, tz1, tx0, h, tz1, u0, v0, u1, v1, sa, sb, sc, sd)
          end
        elseif rock[key] then
          -- jp.79: rugged cave rock (inner corners rise, edges stay put)
          local ya, yb = h + jagAt(i, j), h + jagAt(i + 1, j)
          local yc, yd = h + jagAt(i + 1, j + 1), h + jagAt(i, j + 1)
          local sa = 1 - (ya - h) / (3 * Field3D.CAVE.jag)
          local sb = 1 - (yb - h) / (3 * Field3D.CAVE.jag)
          local sc = 1 - (yc - h) / (3 * Field3D.CAVE.jag)
          local sd = 1 - (yd - h) / (3 * Field3D.CAVE.jag)
          quad(tx0, ya, tz0, tx1, yb, tz0, tx1, yc, tz1, tx0, yd, tz1, u0, v0, u1, v1, sa, sb, sc, sd)
        elseif fr and not capped[key] then
          -- jp.83: the run's top, row by 8px row (Gen 1 flatTopRow /
          -- furniture top)
          for s = 0, 1 do
            local row = fr.top(2 * j + s)
            if row < 0 then row = 0 elseif row > maxRow then row = maxRow end
            local za, zb = z0 + 8 * s, z0 + 8 * s + 8
            quad(x0, h, za, x1, h, za, x1, h, zb, x0, h, zb, u0, row * 8 / ch, u1, (row + 1) * 8 / ch, FOLD.top)
          end
        else
          -- (jp.79: a room's shell gets a dark cut top)
          quad(tx0, h, tz0, tx1, h, tz0, tx1, h, tz1, tx0, h, tz1, u0, v0, u1, v1,
            capped[key] and Field3D.ROOM.cap or 1)
        end
        -- the faces that drop to a lower neighbour (jp.79: darker on cave
        -- rock).  jp.83: in 8px bands of the run's own rows (Gen 1): the
        -- south, east and west faces count up from the run's front row, the
        -- north face down from its first row; a cell outside a run is a run
        -- of its own two rows.
        local m = rock[key] and Field3D.CAVE.side or 1
        local N, F = 2 * j, 2 * j + 1
        if fr then N, F = fr.N, fr.F end
        local function up(k) local r = F - k; if r < N then r = N end; return r end
        local function down(k) local r = N + k; if r > F then r = F end; return r end
        if hs < h then
          wall(tx0, tz1, tx1, tz1, x0, z1, x1, z1, h, hs, u0, u1, up, (fr and FOLD.front or FOLD.S) * m)
        end
        if hn < h then wall(tx1, tz0, tx0, tz0, x1, z0, x0, z0, h, hn, u0, u1, down, FOLD.N * m) end
        if he < h then wall(tx1, tz1, tx1, tz0, x1, z1, x1, z0, h, he, u0, u1, up, FOLD.E * m) end
        if hw < h then wall(tx0, tz0, tx0, tz1, x0, z0, x0, z1, h, hw, u0, u1, up, FOLD.W * m) end
      end
      if door and not door.flush then
        -- jp.78: the door stands up against the wall face, a hair in front
        -- of it, with a small awning over a house door
        local dh = math.min(hn or CELL, CELL)
        local dz = z0 + 0.6
        quad(x0 + 1, dh, dz, x1 - 1, dh, dz, x1 - 1, 0, dz, x0 + 1, 0, dz, u0, v0, u1, v1, 0.78)
        if not door.cave then
          local wv0, wv1 = math.max(0, v0 - CELL / ch), v0
          local ay, az = dh + 0.5, z0 + 3.5
          quad(x0, ay, z0, x1, ay, z0, x1, ay, az, x0, ay, az, u0, wv0, u1, wv1, 0.8)
          quad(x0, ay, az, x1, ay, az, x1, ay - 1.5, az, x0, ay - 1.5, az, u0, wv0, u1, wv1, 0.62)
        end
      end
      ::nextCell::
    end
  end
  for k = #verts, n + 1, -1 do verts[k] = nil end
  if n > 0 then
    gpu.ground:setVertices(verts, 1)
    gpu.ground:setDrawRange(1, n)
  end
  st.groundCount = n
  st.buildMs = (os.clock() - t0) * 1000
end

-- ---------------------------------------------------------------------------
-- sky, fog and weather

local SKY = {
  MORN = { top = { 0.55, 0.72, 0.98 }, fog = { 0.98, 0.86, 0.74 } },
  DAY = { top = { 0.36, 0.62, 0.98 }, fog = { 0.78, 0.88, 1.0 } },
  NITE = { top = { 0.03, 0.04, 0.14 }, fog = { 0.10, 0.12, 0.26 } },
  DARK = { top = { 0, 0, 0 }, fog = { 0, 0, 0 } },
}

local function daytimeOf(world)
  if world.daytime then return world.daytime end
  local ok, Palettes = pcall(require, "src.world.gen2.Palettes")
  if ok and Palettes.daytimeFor then
    local okh, hour = pcall(world.hour, world)
    local okd, dt = pcall(Palettes.daytimeFor, world.map and world.map.def,
      okh and hour or 12, world.flashUsed)
    if okd and dt then return dt end
  end
  return "DAY"
end

local function outdoors(def)
  local env = def and def.environment
  return env == "TOWN" or env == "ROUTE"
end

-- Same answer all day for everyone: rain on one day in four, snow around
-- Mt. Silver.  st.weatherOverride lets the shot harness force one.
function Field3D.weatherFor(world)
  local st = world.field3d
  if st and st.weatherOverride ~= nil then return st.weatherOverride or nil end
  local def = world.map and world.map.def
  if not outdoors(def) then return nil end
  local id = tostring(world.map and world.map.id or "")
  if id:find("SILVER_CAVE_OUTSIDE", 1, true) or id:find("ROUTE_28", 1, true) then
    return "snow"
  end
  local t = os.date("*t")
  if ((t.yday or 0) + (t.year or 0)) % 4 == 1 then return "rain" end
  return nil
end

local drops
local function weatherOverlay(kind, w, h)
  local G = love.graphics
  if not drops then
    drops = {}
    local seed = 12345
    for i = 1, 140 do
      seed = (seed * 1103515245 + 12345) % 2147483648
      local a = seed / 2147483648
      seed = (seed * 1103515245 + 12345) % 2147483648
      local b = seed / 2147483648
      drops[i] = { a, b }
    end
  end
  local t = love.timer and love.timer.getTime() or 0
  local unit = math.max(1, math.floor(math.min(w, h) / 144))
  if kind == "rain" then
    G.setColor(0.75, 0.82, 1.0, 0.55)
    G.setLineWidth(unit)
    for _, d in ipairs(drops) do
      local x = (d[1] * w + t * 60 * unit) % w
      local y = (d[2] * h + t * 420 * unit) % h
      G.line(x, y, x - 3 * unit, y - 10 * unit)
    end
  elseif kind == "snow" then
    G.setColor(1, 1, 1, 0.85)
    for i, d in ipairs(drops) do
      local x = (d[1] * w + math.sin(t * 1.3 + i) * 6 * unit) % w
      local y = (d[2] * h + t * 40 * unit) % h
      G.rectangle("fill", x, y, unit * 2, unit * 2)
    end
  end
  G.setColor(1, 1, 1, 1)
end

-- jp.76: rain and snow as particles in the 3D scene (depth tested and fogged
-- like everything else, so they fall behind houses and fade with distance).
-- The particles live in world space inside a box that follows the camera
-- target and wraps, so walking does not drag them along.  Love-free: answers
-- the vertices (FORMAT rows) and how many were written.
local WEATHER = {
  rain = { count = 600, w = 1.0, len = 9, vy = 260, vx = 30, color = { 0.78, 0.84, 1.0, 1 } },
  snow = { count = 520, w = 2.2, len = 2.2, vy = 26, vx = 8, color = { 1, 1, 1, 1 } },
}
local BOX_W, BOX_D, BOX_H = 240, 240, 90
local seeds
function Field3D.weatherParticles(kind, t, cx, cz, rx, rz, out, dim)
  local spec = WEATHER[kind]
  if not spec then return 0 end
  if not seeds then
    seeds = {}
    local s = 98765
    for i = 1, MAX_DROPS * 3 do
      s = (s * 1103515245 + 12345) % 2147483648
      seeds[i] = s / 2147483648
    end
  end
  out = out or {}
  local n = 0
  local bx, bz = cx - BOX_W / 2, cz - BOX_D / 2
  local col = spec.color
  if dim and dim ~= 1 then col = { col[1] * dim, col[2] * dim, col[3] * dim, 1 } end
  local count = math.min(spec.count, MAX_DROPS)
  for i = 1, count do
    local a, b, c = seeds[i * 3 - 2], seeds[i * 3 - 1], seeds[i * 3]
    local sway = kind == "snow" and math.sin(t * 1.3 + i) * 6 or 0
    local x = bx + (a * BOX_W + spec.vx * t + sway - bx) % BOX_W
    local z = bz + (b * BOX_D - bz) % BOX_D
    local y = BOX_H - (c * BOX_H + spec.vy * t) % BOX_H
    -- a camera-facing strip: across along the camera's right, along y
    local hw = spec.w / 2
    local slant = kind == "rain" and spec.vx / spec.vy * spec.len or 0
    local x0, z0 = x - rx * hw, z - rz * hw
    local x1, z1 = x + rx * hw, z + rz * hw
    local top = y + spec.len
    local function put(px, py, pz)
      n = n + 1
      local v = out[n]
      if not v then v = {}; out[n] = v end
      v[1], v[2], v[3], v[4], v[5] = px, py, pz, 0, 0
      v[6], v[7], v[8], v[9] = col[1], col[2], col[3], col[4]
    end
    put(x0 - slant, top, z0); put(x1 - slant, top, z1); put(x1, y, z1)
    put(x0 - slant, top, z0); put(x1, y, z1); put(x0, y, z0)
  end
  return n, out
end

-- Time of day: the sky and fog ease from one daytime to the next instead of
-- jumping, and rain greys them.  Only colours change here; the ground is the
-- cart's own palette (World:applyPalettes), rebaked by the 2D path when the
-- hour crosses a daytime boundary, never per frame.
local function lerp3(a, b, k)
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end
function Field3D.skyFor(st, daytime, weather, k)
  local target = SKY[daytime] or SKY.DAY
  local top, fog = target.top, target.fog
  local night = daytime == "NITE" or daytime == "DARK"
  if weather == "rain" and night then
    top = lerp3(top, { 0.06, 0.07, 0.09 }, 0.6)
    fog = lerp3(fog, { 0.09, 0.10, 0.13 }, 0.6)
  elseif weather == "rain" then
    top = lerp3(top, { 0.42, 0.45, 0.52 }, 0.65)
    fog = lerp3(fog, { 0.55, 0.58, 0.64 }, 0.65)
  elseif weather == "snow" and night then
    fog = lerp3(fog, { 0.22, 0.24, 0.32 }, 0.5)
  elseif weather == "snow" then
    top = lerp3(top, { 0.80, 0.84, 0.90 }, 0.5)
    fog = lerp3(fog, { 0.90, 0.92, 0.96 }, 0.6)
  end
  if not st.skyTop then
    st.skyTop, st.skyFog = top, fog
  else
    k = k or 0.04
    st.skyTop, st.skyFog = lerp3(st.skyTop, top, k), lerp3(st.skyFog, fog, k)
  end
  return st.skyTop, st.skyFog
end

-- jp.76 3D battle: the arena and the camera rig.  Love-free.
-- The arena is the player's cell plus the cell three ahead along the way the
-- player faced when the battle began (pair distance 48, so Gen 1's encounter
-- rig applies at scale 1).  The rig: from behind the player and off to the
-- right, looking at the pair's middle (BattleCam "encounter": side 18.57,
-- back 40.72, height 25.34, lookY 6.67, frameH 43.56), with Gen 1's idle
-- pan (2 degrees over 26 s).  arena.focus 0..1 blends in from a close-up on
-- the foe (BattleIntroFocus: hold .12 s, pull .9 s, smoothstep).
local DIR_VEC = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
-- jp.86: the foe's cell is CHOSEN on the map, the way the 初代 (Gen 1, Red JP)
-- build's BattleArena.findEncounter does it, instead of always three cells
-- along the facing: jp.85 put Route 29's tree lines (20 units tall) straight
-- behind the foe and beside the camera, which is the checkered wall and the
-- striped blocks the tester saw.  The search is on Crystal's own collision
-- data: `probe(cx, cy)` says whether a cell is open floor (Field3D.heightOf
-- 0 = no wall, tree, water, ledge, counter or void), the player keeps the
-- cell the battle began on, and the foe is tried in the four cardinal
-- directions (the rig needs a unit axis) at 3, 2 and 1 cells away.  Score
-- (lower wins): shorter gap +20 each, a turn away from `prefer` (the field
-- camera's forward) +2 per quarter, Gen 1's apron (blocked cells around the
-- pair) +1 each, and -- Gen 2 only, for its long tree lines -- +3 per missing
-- open cell in the four beyond the foe, so the backdrop opens into the far
-- route rather than a wall.  A 1 or 2 cell gap scales the rig (arena.k, as
-- Gen 1's rigFor does with pairDistance / 48).  No probe (or nothing open):
-- the jp.76 arena, three cells ahead.
Field3D.ARENA_BEYOND = 4
function Field3D.battleArena(px, pz, facing, probe, prefer)
  local f = DIR_VEC[facing] or DIR_VEC.down
  local arena = { px = px, pz = pz, ex = px + f[1] * 48, ez = pz + f[2] * 48, ax = f[1], az = f[2],
    focus = 0, t = 0, gap = 3, k = 1 }
  if type(probe) ~= "function" then return arena end
  local pcx, pcy = math.floor(px / 16), math.floor(pz / 16)
  local function open(cx, cy)
    local ok, v = pcall(probe, cx, cy)
    return ok and v == true
  end
  local pf = DIR_VEC[prefer] or f
  local best, bestScore = nil, nil
  for _, name in ipairs({ "up", "right", "down", "left" }) do
    local d = DIR_VEC[name]
    local turn = math.abs(d[1] * pf[1] + d[2] * pf[2]) -- 1 along the axis, 0 across
    turn = (d[1] == pf[1] and d[2] == pf[2]) and 0 or (turn == 1 and 2 or 1)
    local lane = true
    for gap = 1, 3 do
      local ecx, ecy = pcx + d[1] * gap, pcy + d[2] * gap
      lane = lane and open(ecx, ecy)
      if not lane then break end
      local apron = 0
      for j = -1, 1 do
        for i = -1, 1 do
          if not open(pcx + i, pcy + j) then apron = apron + 1 end
          if not open(ecx + i, ecy + j) then apron = apron + 1 end
        end
      end
      local beyond = 0
      for n = 1, Field3D.ARENA_BEYOND do
        if not open(ecx + d[1] * n, ecy + d[2] * n) then break end
        beyond = beyond + 1
      end
      local score = (3 - gap) * 20 + turn * 2 + apron + (Field3D.ARENA_BEYOND - beyond) * 3
      if not bestScore or score < bestScore then
        bestScore = score
        best = { d = d, gap = gap, ecx = ecx, ecy = ecy, score = score, name = name }
      end
    end
  end
  if not best then return arena end
  arena.ax, arena.az = best.d[1], best.d[2]
  arena.ex, arena.ez = best.ecx * 16 + 8, best.ecy * 16 + 8
  arena.gap, arena.k = best.gap, best.gap * 16 / 48
  arena.dir, arena.score = best.name, best.score
  return arena
end

local function smooth(k)
  k = math.max(0, math.min(1, k))
  return k * k * (3 - 2 * k)
end
Field3D.smoothstep = smooth

-- jp.78: Gen 1's BattleActionCamera numbers (DRAMALESS_SHAPE), ported.
-- jp.79: a little livelier (orbit 3.2 -> 5 degrees, period 20 -> 16 s,
-- attention .085 -> .12, push-in .055 -> .08).
-- jp.80: eased back a little so a long battle stays comfortable (orbit 4
-- degrees, period 18 s, attention .10, push-in .065).
Field3D.ACTION = { ORBIT = math.rad(4), PERIOD = 18, ATTENTION = .10, PUSH = .065,
  CHASE = .42, FADE = .75 }
-- One step of the action camera state.  allowed: the close-up is over and
-- nothing holds the camera; kind "attack" with goal +1 (the target is the
-- player) or -1 (the foe), or "idle".  The weight fades in and out over FADE
-- seconds; aim and push chase their goals with CHASE.  Pure (no love).
function Field3D.actionStep(s, dt, allowed, kind, goal)
  local A = Field3D.ACTION
  s = s or { time = 0, w = 0, aim = 0, push = 0 }
  dt = math.max(0, math.min(dt or 0, 0.25))
  s.time = s.time + dt
  if allowed then
    s.w = math.min(1, s.w + dt / A.FADE)
  else
    s.w = math.max(0, s.w - dt / A.FADE)
    kind = "idle"
  end
  local chase = 1 - math.exp(-dt / A.CHASE)
  s.push = s.push + ((kind == "idle" and 0 or 1) - s.push) * chase
  if kind == "idle" then goal = math.sin(s.time * 2 * math.pi / 31) * .18 end
  s.aim = s.aim + ((goal or 0) - s.aim) * chase
  s.kind = kind
  return s
end

function Field3D.battleRig(arena, gh)
  gh = gh or 0
  local ax, az = arena.ax, arena.az
  local sx, sz = -az, ax -- the camera's right
  local mx, mz = (arena.px + arena.ex) / 2, (arena.pz + arena.ez) / 2
  -- jp.86: a closer pair (battleArena gap 1 or 2) scales the whole rig by
  -- arena.k = pair distance / 48, as Gen 1's BattleCam.rigFor does
  local kk = arena.k or 1
  if not (kk > 0) then kk = 1 end
  local eye = { arena.px - ax * 40.72 * kk + sx * 18.57 * kk, gh + 25.34 * kk,
    arena.pz - az * 40.72 * kk + sz * 18.57 * kk }
  local target = { mx, gh + 6.67 * kk, mz }
  -- idle pan around the target
  local sway = math.rad(2) * math.sin((arena.t or 0) * 2 * math.pi / 26)
  local dx, dz = eye[1] - target[1], eye[3] - target[3]
  local cs, sn = math.cos(sway), math.sin(sway)
  eye[1], eye[3] = target[1] + dx * cs - dz * sn, target[3] + dx * sn + dz * cs
  -- the intro close-up on the foe's card
  local k = smooth(arena.focus or 1)
  if k < 1 then
    -- framed so the foe's card fills the panel's upper right (where its 2D
    -- pic sits, x ~116, card y 0..73 of 144) above the text box
    local ceye = { arena.ex - ax * 40 * kk, gh + 8 * kk, arena.ez - az * 40 * kk }
    local ctar = { arena.ex - sx * 8 * kk, gh + 1 * kk, arena.ez - sz * 8 * kk }
    for i = 1, 3 do
      eye[i] = ceye[i] + (eye[i] - ceye[i]) * k
      target[i] = ctar[i] + (target[i] - ctar[i]) * k
    end
  end
  -- jp.78: Gen 1's action camera (BattleActionCamera) once the close-up is
  -- over: a small orbit, the attention pan toward the move's target and a
  -- modest push-in.  No arena.act (or weight 0) = the jp.76/77 rig exactly.
  local act = arena.act
  if act and (act.w or 0) > 0 and k > 0 then
    local A = Field3D.ACTION
    local w = smooth(act.w) * k
    local yaw = math.sin((act.time or 0) * 2 * math.pi / A.PERIOD) * A.ORBIT * w
    local ox, oz = eye[1] - target[1], eye[3] - target[3]
    local cy, sy = math.cos(yaw), math.sin(yaw)
    eye[1], eye[3] = target[1] + ox * cy - oz * sy, target[3] + ox * sy + oz * cy
    local delta = { (arena.px - arena.ex) * (act.aim or 0) * A.ATTENTION * w, 0,
      (arena.pz - arena.ez) * (act.aim or 0) * A.ATTENTION * w }
    local f = { target[1] - eye[1], target[2] - eye[2], target[3] - eye[3] }
    local len = math.sqrt(f[1] ^ 2 + f[2] ^ 2 + f[3] ^ 2)
    if len > 1e-6 then
      for i = 1, 3 do f[i] = f[i] / len end
      local depth = delta[1] * f[1] + delta[2] * f[2] + delta[3] * f[3]
      for i = 1, 3 do
        local pan = delta[i] - f[i] * depth
        eye[i], target[i] = eye[i] + pan, target[i] + pan
      end
      local push = len * A.PUSH * (act.push or 0) * w
      for i = 1, 3 do eye[i] = eye[i] + f[i] * push end
    end
  end
  local dist = math.sqrt((eye[1] - target[1]) ^ 2 + (eye[2] - target[2]) ^ 2 + (eye[3] - target[3]) ^ 2)
  local frameH = (34 + (43.56 - 34) * k) * kk
  local fov = 2 * math.atan(frameH / 2 / math.max(1, dist))
  return eye, target, fov
end

-- Card boards for the two battlers: the battle screen's own pics, captured
-- into a 160x144 canvas, cut out by their pic boxes and stood upright at the
-- arena cells.  16/56 world units per pic pixel (Gen 1's card scale).
local CARD_SCALE = 16 / 56
local CARD_BOXES = {
  enemy = { 96, 0, 56, 56 },  -- 7x7 tiles at tile (12,0)
  player = { 16, 48, 48, 48 }, -- 6x6 tiles at tile (2,6)
}
Field3D.CARD_BOXES = CARD_BOXES

-- jp.77: where the player's card stands.  At rest it is the player's own
-- cell; during the intro close-up (focus < 1) the lens sits ahead of that
-- cell, so the card is carried in front of the lens, to the lower left of the
-- view (where the 2D pic is), and eases back to its cell as the camera pulls
-- back.  It used to be hidden for the whole close-up.
-- ahead: distance from the close-up lens; left: units left of the foe's
-- line; sink: how far the card's foot drops below the ground (the card is
-- drawn depth-always, so this only moves it down the view, onto the 2D pic's
-- rows 48..96 just above the text box).  Third value returned = foot offset.
Field3D.INTRO_CARD = { ahead = 40, left = 17.4, sink = 4.7 }
function Field3D.playerCardPos(arena)
  local k = smooth(arena.focus or 1)
  if k >= 1 then return arena.px, arena.pz, 0 end
  local ax, az = arena.ax, arena.az
  local sx, sz = -az, ax
  local ic = Field3D.INTRO_CARD
  local back = 40 - ic.ahead -- distance in front of the foe
  local cx = arena.ex - ax * back - sx * ic.left
  local cz = arena.ez - az * back - sz * ic.left
  return cx + (arena.px - cx) * k, cz + (arena.pz - cz) * k, -ic.sink * (1 - k)
end

-- jp.84: Gen 1's seamless wild entry (DRAMALESS_SHAPE BattleCameraBlend /
-- WildEncounterMotion), ported as pure functions.  entry = { pose = the last
-- field view (eye, target, proj, horizonY, w, h), t = seconds since the
-- battle came up, dur = 1 }.  Returns nil once it is over (or when the window
-- changed size since the field frame), else
--   move  the eased travel 0..1 (wait 8%, then ease-out cubic),
--   zoom  the short lens cue in the first 28% (fov 5.5% narrower at peak),
--   cast  the player's field sprite opacity (gone by ~46%),
--   cards the battlers' cards' opacity (in over 30%..70%).
Field3D.ENTRY_SECONDS = 1
function Field3D.entryBlend(entry, w, h)
  local fp = entry and entry.pose
  if not (fp and fp.eye and fp.target and fp.proj) then return nil end
  if w and fp.w and (fp.w ~= w or fp.h ~= h) then return nil end
  local dur = math.max(0.001, entry.dur or Field3D.ENTRY_SECONDS)
  local t = math.max(0, entry.t or 0) / dur
  if t >= 1 then return nil end
  local mv = math.max(0, (t - 0.08) / 0.92)
  local move = 1 - (1 - mv) ^ 3
  local pulse = t < 0.28 and math.sin(math.pi * t / 0.28) ^ 2 or 0
  return { t = t, move = move, zoom = 1 / (1 - 0.055 * pulse),
    cast = 1 - smooth((t - 0.12) / 0.34), cards = smooth((t - 0.3) / 0.4) }
end

-- The eye swings around the moving aim point (a slerp of the eye's
-- direction, the distance mixed), the way Gen 1's mix() does.
function Field3D.blendPose(e0, t0, e1, t1, k)
  if k <= 0 then return { e0[1], e0[2], e0[3] }, { t0[1], t0[2], t0[3] } end
  if k >= 1 then return { e1[1], e1[2], e1[3] }, { t1[1], t1[2], t1[3] } end
  local target = {}
  for i = 1, 3 do target[i] = t0[i] + (t1[i] - t0[i]) * k end
  local a = { e0[1] - t0[1], e0[2] - t0[2], e0[3] - t0[3] }
  local b = { e1[1] - t1[1], e1[2] - t1[2], e1[3] - t1[3] }
  local la = math.sqrt(a[1] ^ 2 + a[2] ^ 2 + a[3] ^ 2)
  local lb = math.sqrt(b[1] ^ 2 + b[2] ^ 2 + b[3] ^ 2)
  local dist = la + (lb - la) * k
  local ray
  if la < 1e-6 or lb < 1e-6 then
    ray = { 0, 1, 0 }
  else
    for i = 1, 3 do a[i], b[i] = a[i] / la, b[i] / lb end
    local dot = math.max(-1, math.min(1, a[1] * b[1] + a[2] * b[2] + a[3] * b[3]))
    local theta = math.acos(dot)
    if theta < 1e-5 then
      ray = a
    else
      local tg = { b[1] - a[1] * dot, b[2] - a[2] * dot, b[3] - a[3] * dot }
      local lt = math.sqrt(tg[1] ^ 2 + tg[2] ^ 2 + tg[3] ^ 2)
      if lt < 1e-6 then
        tg = math.abs(a[2]) < 0.9 and { -a[3], 0, a[1] } or { 0, a[3], -a[2] }
        lt = math.sqrt(tg[1] ^ 2 + tg[2] ^ 2 + tg[3] ^ 2)
      end
      local c, s = math.cos(theta * k), math.sin(theta * k)
      ray = {}
      for i = 1, 3 do ray[i] = a[i] * c + tg[i] / lt * s end
    end
  end
  return { target[1] + ray[1] * dist, target[2] + ray[2] * dist, target[3] + ray[3] * dist }, target
end

function Field3D.lerpMat(a, b, k)
  local r = {}
  for i = 1, 4 do
    r[i] = {}
    for j = 1, 4 do r[i][j] = a[i][j] + (b[i][j] - a[i][j]) * k end
  end
  return r
end

function Field3D.cardQuads(arena, gh, rx, rz, out)
  out = out or {}
  local n = 0
  local ppx, ppz, pfoot = Field3D.playerCardPos(arena)
  local gh0 = gh
  for _, side in ipairs({ "enemy", "player" }) do
    local b = CARD_BOXES[side]
    local cx = side == "enemy" and arena.ex or ppx
    local cz = side == "enemy" and arena.ez or ppz
    gh = side == "enemy" and gh0 or gh0 + (pfoot or 0)
    -- jp.78: the pic's sideways slide (intro, lunge, send-out) in pic pixels,
    -- along the card's own +u axis (nil = still, the jp.76/77 card)
    local shift = (side == "enemy" and arena.shiftE or arena.shiftP) or 0
    if shift ~= 0 then
      cx, cz = cx + rx * shift * CARD_SCALE, cz + rz * shift * CARD_SCALE
    end
    local half, tall = b[3] * CARD_SCALE / 2, b[4] * CARD_SCALE
    local u0, u1 = b[1] / 160, (b[1] + b[3]) / 160
    local v0, v1 = b[2] / 144, (b[2] + b[4]) / 144
    local ax0, az0 = cx - rx * half, cz - rz * half
    local ax1, az1 = cx + rx * half, cz + rz * half
    local quad = {
      { ax0, gh + tall, az0, u0, v0 }, { ax1, gh + tall, az1, u1, v0 }, { ax1, gh, az1, u1, v1 },
      { ax0, gh + tall, az0, u0, v0 }, { ax1, gh, az1, u1, v1 }, { ax0, gh, az0, u0, v1 },
    }
    for _, q in ipairs(quad) do
      n = n + 1
      out[n] = { q[1], q[2], q[3], q[4], q[5], 1, 1, 1, 1 }
    end
  end
  return n, out
end

-- ---------------------------------------------------------------------------
-- the scene

local function clampN(v, a, b) return math.max(a, math.min(b, v)) end

-- jp.81: where the view from above aims inside a room.  halfW is the half
-- width the picture shows at the aim point; up / down how far it reaches
-- along the ground ahead of and behind it (world units).  A room narrower
-- than the picture is centred; a wider one is clamped at its walls.
-- Outdoors (and on any map whose size is unknown) the aim stays put.
function Field3D.frameRoom(world, tx, tz, fx, fz, halfW, up, down)
  local map = world and world.map
  if not (map and map.width and map.height) then return tx, tz end
  if Field3D.envKind(map.def) ~= "room" then return tx, tz end
  local W, H = map.width * 32, map.height * 32
  local rx, rz = -fz, fx
  local rmin, rmax, fmin, fmax = math.huge, -math.huge, math.huge, -math.huge
  for _, c in ipairs({ { 0, 0 }, { W, 0 }, { 0, H }, { W, H } }) do
    local r = c[1] * rx + c[2] * rz
    local f = c[1] * fx + c[2] * fz
    rmin, rmax = math.min(rmin, r), math.max(rmax, r)
    fmin, fmax = math.min(fmin, f), math.max(fmax, f)
  end
  local tr, tf = tx * rx + tz * rz, tx * fx + tz * fz
  if rmax - rmin <= 2 * halfW then tr = (rmin + rmax) / 2
  else tr = clampN(tr, rmin + halfW, rmax - halfW) end
  if fmax - fmin <= up + down then tf = (fmin + fmax) / 2 - (up - down) / 2
  else tf = clampN(tf, fmin + down, fmax - up) end
  return tr * rx + tf * fx, tr * rz + tf * fz
end

local function cameraFor(world, st, mode, opts, w, h)
  local p = world.player
  local tx, tz = p.px + 8, p.py + 8
  local cell = st.heightAt and st.heightAt(math.floor(tx / CELL), math.floor(tz / CELL)) or 0
  st.camH = st.camH + (cell - st.camH) * 0.25
  local gh = st.camH
  local yaw = math.rad(st.yaw)
  local fx, fz = math.sin(yaw), -math.cos(yaw)
  local eye, target, fov, pitch
  -- jp.81 framing inputs (unused by the battle and orbit rigs)
  local fyN, focus
  local portrait = h > w * 1.1
  local s = math.max(1, math.min(w / 160, h / 144))
  local k = zoomFactor(world)
  local look = st.lookPitch or 0
  if opts and opts.battle then
    eye, target, fov = Field3D.battleRig(opts.battle, gh)
    local dx, dz = target[1] - eye[1], target[3] - eye[3]
    local hl = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
    fx, fz = dx / hl, dz / hl
    pitch = math.atan2(eye[2] - target[2], hl)
    -- the boards read opts.orbit as the camera heading
    opts.orbit = math.deg(math.atan2(fx, -fz))
  elseif opts and opts.orbit then
    local a = math.rad(opts.orbit)
    local d, pt = 120, math.rad(24)
    eye = { tx - math.sin(a) * d * math.cos(pt), gh + 8 + d * math.sin(pt), tz + math.cos(a) * d * math.cos(pt) }
    target = { tx, gh + 8, tz }
    fov, pitch = math.rad(55), pt
    fx, fz = math.sin(a), -math.cos(a)
  elseif mode == "first" then
    -- jp.81: an upright phone gets a level-but-lower gaze (less sky) and a
    -- picture at least 90 degrees tall instead of a 35-degree-wide slit;
    -- landscape keeps the jp.75 70-degree view.  The zoom step and the free
    -- look (st.lookPitch) apply on top.
    local p0 = 6 + 12 * clampN((h / math.max(1, w) - 1) / 1.2, 0, 1)
    local pt = math.rad(clampN(p0 + look, -30, 70))
    eye = { tx - fx * 4, gh + 13, tz - fz * 4 }
    target = { eye[1] + fx * 100 * math.cos(pt), eye[2] - 100 * math.sin(pt), eye[3] + fz * 100 * math.cos(pt) }
    pitch = pt
    fyN = k * clampN(w / math.max(1, h) / math.tan(math.rad(37)), 1.0, 1 / math.tan(math.rad(35)))
    focus = { tx, gh, tz }
  elseif mode == "third" then
    local d, pt = 88, 24
    local env = world.map and world.map.def and world.map.def.environment
    -- rooms are small: a short, steep chase camera keeps the room in frame
    -- instead of the void past the back wall
    if env ~= "TOWN" and env ~= "ROUTE" then d, pt = 96, 68
    elseif portrait then
      -- jp.81: upright, a steeper chase puts the horizon near the top edge
      -- (jp.80's 24 degrees left a quarter of the picture as sky and fog);
      -- the free look tilts it back up
      pt = 30
    end
    pt = math.rad(clampN(pt + look, 6, 82))
    fyN = 1 / math.tan(math.rad(30))
    -- jp.81: upright, the camera stands far enough back that the player is
    -- drawn about 1.6 times the 2D size (jp.80 drew them five times over and
    -- showed three tiles across); the zoom step moves it in and out
    if portrait then d = math.max(d, fyN * h / (2 * s * 1.6)) end
    d = d / k
    focus = { tx, gh, tz }
    -- pull the camera in when terrain taller than the sight line stands
    -- between it and the player (a room's back wall, a row of trees)
    if st.heightAt then
      local steps = math.floor(d / 4)
      for k = 1, steps do
        local dd = k * 4
        local sx = tx - fx * dd * math.cos(pt)
        local sz = tz - fz * dd * math.cos(pt)
        local rayH = gh + 12 + dd * math.sin(pt)
        local th = st.heightAt(math.floor(sx / CELL), math.floor(sz / CELL))
        if th > rayH - 3 then d = math.max(16, dd - 6); break end
      end
    end
    eye = { tx - fx * d * math.cos(pt), gh + 12 + d * math.sin(pt), tz - fz * d * math.cos(pt) }
    target = { tx, gh + 12, tz }
    pitch = pt
  else
    -- jp.81: the view from above draws a tile at about the 2D size times the
    -- zoom step, whatever the window shape (jp.80 used one 48-degree lens, so
    -- an upright phone showed four and a half tiles across).  Upright, the
    -- camera also stands further back so the lens stays near 58 degrees tall
    -- instead of a fisheye; the tilt comes from the angle ladder.
    local angle, tilt = Field3D.angleOf(world)
    local pt = math.rad(90 - tilt)
    local d = 178
    if portrait then d = math.max(d, h / (2 * s * k * 0.55)) end
    if angle == "diorama" then d = d * 1.6 end
    fyN = 2 * s * k * d / h
    -- a room smaller than the picture sits in the middle of it, and a larger
    -- one stops at its walls, instead of the void past the corner
    local ppu = s * k
    local frac = portrait and 0.5 or 0.5
    tx, tz = Field3D.frameRoom(world, tx, tz, fx, fz, w / (2 * ppu),
      frac * h / ppu / math.sin(pt), (1 - frac) * h / ppu / math.sin(pt))
    eye = { tx - fx * d * math.cos(pt), gh + d * math.sin(pt), tz - fz * d * math.cos(pt) }
    target = { tx, gh, tz }
    pitch = pt
    focus = target
  end
  local proj
  if fyN then
    proj = perspectiveF(fyN, w / math.max(1, h), mode == "first" and 1.5 or 4, 1600)
  else
    proj = perspective(fov, w / math.max(1, h), mode == "first" and 1.5 or 4, 1600)
    fyN = 1 / math.tan(fov / 2)
  end
  local view = lookAt(eye[1], eye[2], eye[3], target[1], target[2], target[3])
  -- where a level sight line lands on screen (pitch measured from the eye)
  local realPitch = math.atan2(eye[2] - target[2],
    math.sqrt((eye[1] - target[1]) ^ 2 + (eye[3] - target[3]) ^ 2))
  -- jp.81: upright, the player's feet are put at a fixed height on the
  -- screen (an off-axis shift, as the battle panel does) so the message box
  -- and the touch pad never sit over them
  local shiftY = 0
  if portrait and focus and (mode == "above" or mode == "third") then
    local m = mul(proj, view)
    local P = focus
    local cw = m[4][1] * P[1] + m[4][2] * P[2] + m[4][3] * P[3] + m[4][4]
    if cw > 1e-6 then
      local ny = (m[2][1] * P[1] + m[2][2] * P[2] + m[2][3] * P[3] + m[2][4]) / cw
      local want = 1 - 2 * (mode == "third" and 0.53 or 0.5)
      shiftY = want - ny
      proj = mul({ { 1, 0, 0, 0 }, { 0, 1, 0, shiftY }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } }, proj)
    end
  end
  local horizonY = h / 2 * (1 - fyN * math.tan(realPitch) - shiftY)
  local fp = focus or target
  local dFocus = math.sqrt((eye[1] - fp[1]) ^ 2 + (eye[2] - fp[2]) ^ 2 + (eye[3] - fp[3]) ^ 2)
  if opts and opts.battle then
    -- jp.76: the battle rig frames the 160x144 panel, wherever it sits in the
    -- window (a phone held upright puts it in a band); the projection is
    -- built for the panel and then extended, off-axis, to the whole window
    local r = opts.panel
    if not r then
      local s = math.max(1, math.min(w / 160, h / 144))
      local x0, y0 = (w - 160 * s) / 2, (h - 144 * s) / 2
      r = { x0, y0, x0 + 160 * s, y0 + 144 * s }
    end
    local pw, ph = math.max(1, r[3] - r[1]), math.max(1, r[4] - r[2])
    proj = perspective(fov, pw / ph, 4, 1600)
    local sx, sy = pw / w, ph / h
    local tx = ((r[1] + r[3]) / 2 - w / 2) / (w / 2)
    local ty = -(((r[2] + r[4]) / 2 - h / 2) / (h / 2))
    proj = mul({ { sx, 0, 0, tx }, { 0, sy, 0, ty }, { 0, 0, 1, 0 }, { 0, 0, 0, 1 } }, proj)
    horizonY = r[2] + ph / 2 * (1 - math.tan(realPitch) / math.tan(fov / 2))
    -- jp.84: Gen 1's seamless wild entry.  For the first second the camera
    -- travels from the field view the player was looking at into this shot
    -- (BattleCameraBlend.encounter), so the battle opens out of the map
    -- instead of over a wipe.
    local entry = opts.battle.entry
    local e = entry and Field3D.entryBlend(entry, w, h)
    if e then
      local fp = entry.pose
      eye, target = Field3D.blendPose(fp.eye, fp.target, eye, target, e.move)
      proj = Field3D.lerpMat(fp.proj, proj, e.move)
      proj[1][1], proj[2][2] = proj[1][1] * e.zoom, proj[2][2] * e.zoom
      view = lookAt(eye[1], eye[2], eye[3], target[1], target[2], target[3])
      horizonY = fp.horizonY + (horizonY - fp.horizonY) * e.move
      local dx, dz = target[1] - eye[1], target[3] - eye[3]
      local hl = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
      fx, fz = dx / hl, dz / hl
      pitch = math.atan2(eye[2] - target[2], hl)
      opts.orbit = math.deg(math.atan2(fx, -fz))
    end
    opts.battle.heading = opts.orbit
    return { viewProj = mul(proj, view), eye = eye, fx = fx, fz = fz, pitch = pitch,
      horizonY = horizonY, dFocus = dFocus, mode = mode, entry = e }
  end
  if not (opts and opts.orbit) then
    -- jp.84: the last field view, where a seamless battle entry starts from
    st.fieldPose = { eye = { eye[1], eye[2], eye[3] }, target = { target[1], target[2], target[3] },
      proj = proj, horizonY = horizonY, w = w, h = h, mode = mode }
  end
  return { viewProj = mul(proj, view), eye = eye, fx = fx, fz = fz, pitch = pitch,
    horizonY = horizonY, dFocus = dFocus, mode = mode }
end

local function drawScene(world, w, h, opts)
  local G = love.graphics
  local st = stateFor(world)
  st.frame = st.frame + 1
  local p = world.player
  local map = world.map
  local mode = (opts and opts.orbit) and "orbit" or Field3D.cameraMode(world)

  -- camera yaw: the rotation keys / drag move yawTarget, this eases toward it
  -- (jp.81: the view from above turns too now; the d-pad then follows the
  -- screen, see Field3D.remapDirection)
  -- jp.81 free look: the right stick held up / down tilts the chase and
  -- first-person views
  if not (opts and opts.orbit) then
    local dt = love.timer and love.timer.getDelta and love.timer.getDelta() or 1 / 60
    dt = math.min(dt, 0.1)
    if st.stickY and math.abs(st.stickY) > 0.25 and mode ~= "above"
        and Field3D.fieldFree and Field3D.fieldFree(world.game) then
      local sgn = invertLook(world) and -1 or 1
      st.lookPitch = clampN((st.lookPitch or 0) + st.stickY * sgn * 70 * dt, -40, 45)
    end
    if st.fieldMode ~= nil and st.fieldMode ~= mode then
      st.lookPitch = 0
      -- coming back to the view from above starts it facing north again
      if mode == "above" and not moveRelative(world) then st.yawTarget, st.yaw = 0, 0 end
    end
    st.fieldMode = mode
  end
  if st.mapId ~= (map and map.id) or (st.lastMode ~= mode and mode == "first") then
    st.mapId = map and map.id
    if mode == "first" then
      local fi = DIR_INDEX[p.facing] or 0
      st.yawTarget = fi * 90
      st.yaw = st.yawTarget
    end
  end
  st.lastMode = mode
  st.yaw = st.yaw + (st.yawTarget - st.yaw) * 0.25
  if math.abs(st.yawTarget - st.yaw) < 0.05 then st.yaw = st.yawTarget end

  local pcx = math.floor((p.px + 8) / CELL)
  local pcy = math.floor((p.py + 8) / CELL)
  local ox, oy = pcx - RX, pcy - RY
  local key = tostring(map and map.id) .. ":" .. ox .. ":" .. oy

  local groundCanvas = ensureCanvas("groundCanvas", GW * CELL, GH * CELL)
  local atlas = ensureCanvas("atlas", SLOT_W * ATLAS_COLS, SLOT_H * ATLAS_ROWS)
  local out = ensureCanvas(opts and opts.slot or "outCanvas", w, h)

  -- 1. the ground texture, live every frame so water and flowers animate
  local cam = world.camera
  local camX, camY = cam.x, cam.y
  cam.x, cam.y = ox * CELL, oy * CELL
  local sprites = {}
  local maskSave = world.playerMasked
  local castAlpha = 1
  -- the 2D view culls neighbour maps and animated tiles to one screen; the
  -- 3D region is wider, so both are widened for this pass only
  local viewWSave, viewHSave, neighborsSave = world.viewW, world.viewH, world.neighbors
  world.viewW, world.viewH = GW * CELL, GH * CELL
  if st.neighborsFor ~= (map and map.id) or st.neighborsSrc ~= neighborsSave then
    st.neighborsFor, st.neighborsSrc = map and map.id, neighborsSave
    st.neighbors = neighborsSave
    local okN, list = pcall(world.computeNeighbors, world.maps, map.id, 2,
      GW * CELL + 2 * CELL, GH * CELL + 2 * CELL)
    if okN and type(list) == "table" then
      local wide = {}
      for _, n in ipairs(list) do
        local okI, img = pcall(world.imageFor, world, n.id)
        if okI and img then wide[#wide + 1] = { id = n.id, ox = n.ox, oy = n.oy, image = img } end
      end
      st.neighbors = wide
    end
  end
  world.neighbors = st.neighbors or neighborsSave
  local ok, err = pcall(function()
    G.setCanvas(groundCanvas)
    G.origin()
    G.setScissor()
    G.setShader()
    G.clear(0, 0, 0, 1)
    G.setColor(1, 1, 1, 1)
    world:drawGround(1)
    if world.bgOverlay then world.bgOverlay(1) end

    -- 2. the people, one atlas slot each
    G.setCanvas(atlas)
    G.origin()
    G.clear(0, 0, 0, 0)
    -- jp.85: nobody in the battle arena.  The field sprites (the player's
    -- own, a passer-by) stood in the sky of the battle backdrop on the
    -- phone; the 初代 (Gen 1) build's arena has only the two battlers.
    if not world.peopleHidden and not (opts and opts.battle) then
      -- jp.84: on a seamless entry the player's own field sprite stays for
      -- the first moments and fades as the camera leaves them (castAlpha)
      local entryNow = opts and opts.battle and Field3D.entryBlend(opts.battle.entry, w, h)
      local cast = entryNow and entryNow.cast or 0
      if entryNow and opts.battle.entry.pose.mode == "first" then cast = 0 end
      if mode == "first" or (opts and opts.battle and cast <= 0.02) then world.playerMasked = true end
      castAlpha = cast
      local maxX, maxY = GW * CELL, GH * CELL
      -- jp.76: the frame follows the camera.  With the view turned q quarter
      -- turns, a person's facing is drawn relative to the camera (someone
      -- facing the way the camera looks shows their back), then restored.
      local viewYaw = (opts and opts.battle and opts.battle.heading) or (opts and opts.orbit) or st.yaw or 0
      local q = quadrant(viewYaw)
      world:drawPeople(1, function(fx, fy, body, entity)
        if q ~= 0 and entity and DIR_INDEX[entity.facing] then
          local inner = body
          body = function()
            local orig = entity.facing
            entity.facing = Field3D.viewFacing(orig, viewYaw)
            local okB, errB = pcall(inner)
            entity.facing = orig
            if not okB then error(errB, 0) end
          end
        end
        local n = #sprites
        if n >= MAX_SPRITES then return end
        if fx < -8 or fy < -8 or fx > maxX + 8 or fy > maxY + 40 then return end
        local sx = (n % ATLAS_COLS) * SLOT_W
        local sy = math.floor(n / ATLAS_COLS) * SLOT_H
        G.push("all")
        G.setScissor(sx, sy, SLOT_W, SLOT_H)
        G.translate(sx + SLOT_FOOT_X - fx, sy + SLOT_FOOT_Y - fy)
        body()
        G.pop()
        sprites[n + 1] = { wx = fx + ox * CELL, wz = fy + oy * CELL, sx = sx, sy = sy,
          alpha = (entity == p and opts and opts.battle) and castAlpha or 1 }
      end)
    end
  end)
  world.playerMasked = maskSave
  world.viewW, world.viewH, world.neighbors = viewWSave, viewHSave, neighborsSave
  cam.x, cam.y = camX, camY
  if not ok then error(err, 0) end

  -- the terrain (jp.83: after the ground canvas, whose tree pictures the
  -- tree cards read back)
  if st.terrainKey ~= key or st.frame - (st.terrainFrame or 0) > 30 then
    buildTerrain(world, st, ox, oy, groundCanvas)
    st.terrainKey, st.terrainFrame = key, st.frame
  end

  -- 3. the 3D pass
  local c = cameraFor(world, st, mode, opts, w, h)
  local def = map and map.def
  local daytime = daytimeOf(world)
  local sky = SKY[daytime] or SKY.DAY
  local skyTop, fog = sky.top, sky.fog
  local fogRange = { 100000, 200000 }
  -- jp.76: with ATMOS on, the sky eases between daytimes and greys in rain
  local weather3d = nil
  if atmosOn(world) and not (opts and opts.orbit) then
    weather3d = Field3D.weatherFor(world)
    if outdoors(def) then skyTop, fog = Field3D.skyFor(st, daytime, weather3d) end
  end
  if not outdoors(def) then
    skyTop, fog = { 0, 0, 0 }, { 0, 0, 0 }
  end
  -- jp.81: the field views measure their fog from the player (c.dFocus is
  -- the eye's distance to them), since the camera now stands at different
  -- distances per window shape and zoom.  The region ends 18 cells (288)
  -- out, so the fog is whole by about 270 past the player and its far edge
  -- never shows as a cut line.
  local base = (not (opts and (opts.orbit or opts.battle))) and (c.dFocus or 0) or nil
  if atmosOn(world) or (opts and opts.orbit) then
    if base and mode == "first" then fogRange = { base + 100, base + 225 }
    elseif base and mode == "third" then fogRange = { base + 40, base + 200 }
    elseif mode == "first" or mode == "third" then fogRange = { 110, 230 }
    elseif mode == "orbit" then fogRange = { 130, 260 }
    elseif base then fogRange = { base + 60, base + 215 }
    else fogRange = { 230, 380 } end
  elseif base then
    if mode == "above" then fogRange = { base + 170, base + 272 }
    else fogRange = { base + 150, base + 265 } end
  elseif mode == "first" or mode == "third" then
    -- the region ends about 14 cells out; a soft edge even with ATMOS off
    fogRange = { 170, 235 }
  end
  -- jp.79: a cave closes in (black fog nearer than anywhere else)
  if not (opts and opts.orbit) and Field3D.envKind(def) == "cave" then
    local f = Field3D.CAVE.fog
    if base and mode == "first" then fogRange = { f[1], f[2] }
    elseif base then fogRange = { base + f[1] - 40, base + f[2] - 40 }
    elseif mode == "first" or mode == "third" then fogRange = { f[1], f[2] }
    else fogRange = { f[1] + 90, f[2] + 130 } end
  end
  -- jp.84: the seamless entry carries the field's fog and sky into the
  -- battle's along with the camera
  if not (opts and opts.orbit) and st.fieldPose then
    st.fieldPose.fog = { fogRange[1], fogRange[2] }
    st.fieldPose.sky = { skyTop, fog }
  elseif c.entry and opts.battle.entry.pose.fog then
    local f0, k = opts.battle.entry.pose.fog, c.entry.move
    fogRange = { f0[1] + (fogRange[1] - f0[1]) * k, f0[2] + (fogRange[2] - f0[2]) * k }
    local s0 = opts.battle.entry.pose.sky
    if s0 then
      local function mixc(a, b)
        return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
      end
      skyTop, fog = mixc(s0[1], skyTop), mixc(s0[2], fog)
    end
  end

  G.setCanvas({ out, depth = true })
  G.origin()
  G.setScissor()
  G.clear(fog[1], fog[2], fog[3], 1)
  -- sky gradient (screen space, no depth)
  G.setDepthMode()
  -- the sky reaches the fog colour a little ABOVE the horizon, so the far
  -- edge of the region (fully fogged) never stands out against blue
  local band = (c.horizonY or h * 0.5) - h * 0.14
  if band > 0 then
    gpu.sky:setVertices({
      { 0, 0, 0, 0, skyTop[1], skyTop[2], skyTop[3], 1 },
      { w, 0, 1, 0, skyTop[1], skyTop[2], skyTop[3], 1 },
      { w, band, 1, 1, fog[1], fog[2], fog[3], 1 },
      { 0, band, 0, 1, fog[1], fog[2], fog[3], 1 },
    })
    G.setColor(1, 1, 1, 1)
    G.draw(gpu.sky)
  end

  G.setDepthMode("lequal", true)
  G.setMeshCullMode("none")
  local shader = gpu.shader
  G.setShader(shader)
  sendUniform(shader, "viewProj", "row", flat(c.viewProj))
  sendUniform(shader, "flipY", -1)
  sendUniform(shader, "camPos", c.eye)
  sendUniform(shader, "fogColor", fog)
  sendUniform(shader, "fogRange", fogRange)
  sendUniform(shader, "ghost", 0)
  G.setColor(1, 1, 1, 1)
  if (st.groundCount or 0) > 0 then
    gpu.ground:setTexture(groundCanvas)
    G.draw(gpu.ground)
  end

  -- jp.83: the tree cards (see buildTerrain): the tree's own picture from
  -- the ground canvas, standing on the edge of its cells nearest the
  -- camera, turned and leaned back exactly like the people boards below,
  -- the grass around it cut away by gpu.treeMask
  local cards = st.cards3D
  -- jp.84: on a seamless battle entry the trees stay standing at first and
  -- settle into their flat battle look as the battlers' cards come in, so
  -- the first battle frame does not pop them flat
  local treeK = 1
  if opts and opts.battle then treeK = c.entry and (1 - c.entry.cards) or 0 end
  if cards and #cards > 0 and gpu.trees and treeK > 0.01 then
    local yaw = math.rad(st.yaw)
    if opts and opts.orbit then yaw = math.rad(opts.orbit) end
    local rx, rz = math.cos(yaw), math.sin(yaw)
    local lean = (c.pitch or 0) * ((c.mode == "above") and 0.6 or 0.3)
    local ux, uy, uz = c.fx * math.sin(lean), math.cos(lean), c.fz * math.sin(lean)
    local afx, afz = math.abs(c.fx), math.abs(c.fz)
    local cw, ch = GW * CELL, GH * CELL
    gpu.treePool = gpu.treePool or {}
    local pool, n = gpu.treePool, 0
    local function put(x, y, z, u, v)
      n = n + 1
      local t = pool[n]
      if t then
        t[1], t[2], t[3], t[4], t[5] = x, y, z, u, v
      else
        pool[n] = { x, y, z, u, v, 1, 1, 1, 1 }
      end
    end
    for k = 1, math.min(#cards, MAX_TREE_CARDS) do
      local cd = cards[k]
      local i, j, cells = cd[1], cd[2], cd[3]
      local mx = (ox + i) * CELL + CELL / 2
      local mz = (oy + j) * CELL + cells * CELL / 2
      local off = afx * CELL / 2 + afz * cells * CELL / 2
      local fx0, fz0 = mx - c.fx * off, mz - c.fz * off
      local hgt = cells * CELL * treeK
      local half = CELL / 2
      local ax, ay, az = fx0 - rx * half + ux * hgt, uy * hgt, fz0 - rz * half + uz * hgt
      local bx, by, bz = fx0 + rx * half + ux * hgt, uy * hgt, fz0 + rz * half + uz * hgt
      local qx, qy, qz = fx0 + rx * half, 0, fz0 + rz * half
      local dx, dy, dz = fx0 - rx * half, 0, fz0 - rz * half
      local u0, u1 = i * CELL / cw, (i + 1) * CELL / cw
      local v0, v1 = j * CELL / ch, (j + cells) * CELL / ch
      put(ax, ay, az, u0, v0); put(bx, by, bz, u1, v0); put(qx, qy, qz, u1, v1)
      put(ax, ay, az, u0, v0); put(qx, qy, qz, u1, v1); put(dx, dy, dz, u0, v1)
    end
    if n > 0 then
      local okT, errT = pcall(function()
        gpu.trees:setVertices(pool, 1, n)
        gpu.trees:setDrawRange(1, n)
        gpu.trees:setTexture(groundCanvas)
        local tsh = (gpu.treeShader and gpu.treeMask) and gpu.treeShader or nil
        if tsh then
          G.setShader(tsh)
          sendUniform(tsh, "viewProj", "row", flat(c.viewProj))
          sendUniform(tsh, "flipY", -1)
          sendUniform(tsh, "camPos", c.eye)
          sendUniform(tsh, "fogColor", fog)
          sendUniform(tsh, "fogRange", fogRange)
          tsh:send("treeMask", gpu.treeMask)
        end
        G.draw(gpu.trees)
      end)
      G.setShader(shader)
      if not okT then note("tree cards: " .. tostring(errT)) end
    end
  end

  -- people boards: camera-facing, leaned back by half the pitch so the
  -- overhead view still reads the sprites the way the cart drew them
  if #sprites > 0 then
    local yaw = math.rad(st.yaw)
    if opts and opts.orbit then yaw = math.rad(opts.orbit) end
    local rx, rz = math.cos(yaw), math.sin(yaw)
    -- jp.81: from above the boards lean back further (0.3 -> 0.6 of the
    -- pitch) so the people are not drawn squat and wide
    local lean = (c.pitch or 0) * ((c.mode == "above") and 0.6 or 0.3)
    local ux, uy, uz = c.fx * math.sin(lean), math.cos(lean), c.fz * math.sin(lean)
    local aw, ah = SLOT_W * ATLAS_COLS, SLOT_H * ATLAS_ROWS
    local verts, n = {}, 0
    for _, s in ipairs(sprites) do
      local fx0, fz0 = s.wx, s.wz - 8
      local hgt = st.heightAt and st.heightAt(math.floor(fx0 / CELL), math.floor(fz0 / CELL)) or 0
      if hgt > 4 then hgt = 0 end -- standing next to, not on, a wall
      -- nudge the board toward the camera so a wall or counter right
      -- behind the person never cuts through the sprite
      local cx, cz = fx0 - c.fx * 7, fz0 - c.fz * 7
      local function corner(dx, dy)
        return cx + rx * dx + ux * dy, hgt + uy * dy, cz + rz * dx + uz * dy
      end
      local u0, u1 = s.sx / aw, (s.sx + SLOT_W) / aw
      local v0, v1 = s.sy / ah, (s.sy + SLOT_H) / ah
      local top, bottom = SLOT_FOOT_Y, SLOT_FOOT_Y - SLOT_H
      local left, right = -SLOT_FOOT_X, SLOT_W - SLOT_FOOT_X
      local ax, ay, az = corner(left, top)
      local bx, by, bz = corner(right, top)
      local qx, qy, qz = corner(right, bottom)
      local dx, dy, dz = corner(left, bottom)
      local al = s.alpha or 1
      verts[n + 1] = { ax, ay, az, u0, v0, 1, 1, 1, al }
      verts[n + 2] = { bx, by, bz, u1, v0, 1, 1, 1, al }
      verts[n + 3] = { qx, qy, qz, u1, v1, 1, 1, 1, al }
      verts[n + 4] = { ax, ay, az, u0, v0, 1, 1, 1, al }
      verts[n + 5] = { qx, qy, qz, u1, v1, 1, 1, 1, al }
      verts[n + 6] = { dx, dy, dz, u0, v1, 1, 1, 1, al }
      n = n + 6
    end
    gpu.boards:setVertices(verts, 1)
    gpu.boards:setDrawRange(1, n)
    gpu.boards:setTexture(atlas)
    -- jp.76/77 occlusion fix: the parts of a person (or item ball) hidden
    -- behind a tree or wall still show, as in the 2D view where sprites are
    -- never covered.  jp.77: this pass now runs BEFORE the boards write any
    -- depth, so it only reveals what terrain hides (one person standing
    -- behind another is no longer painted over them), and it uses the
    -- sprite's own colours, a little dimmed, so the townsfolk behind a
    -- tree row stay readable instead of a dark blue shape.
    -- jp.87: the tester read those full-colour figures as people standing
    -- on the roofs.  Gen 1 3D (DRAMALESS_SHAPE lib/Voxel3D.lua beginGhost)
    -- draws the hidden part as a flat dark silhouette at half alpha instead,
    -- so that is what this pass does now (the shader's ghost switch).
    if not (opts and opts.battle) then
      G.setDepthMode("greater", false)
      G.setColor(1, 1, 1, 1)
      sendUniform(shader, "ghost", 1)
      G.draw(gpu.boards)
      sendUniform(shader, "ghost", 0)
      G.setDepthMode("lequal", true)
    end
    G.draw(gpu.boards)
  end

  -- jp.76 3D battle: the two battlers' cards
  if opts and opts.battle and opts.cards and gpu.cards then
    local yaw = math.rad(opts.orbit or 0)
    local cgh = st.camH or 0
    local n, verts = Field3D.cardQuads(opts.battle, cgh, math.cos(yaw), math.sin(yaw))
    -- jp.84: on a seamless entry the cards come in as the camera arrives
    if c.entry then
      for i = 1, n do verts[i][9] = c.entry.cards end
    end
    gpu.cards:setVertices(verts, 1, n)
    -- while the intro close-up still has the player's card at (or behind)
    -- the lens, draw the foe's card only, so it cannot sweep across the view
    -- (jp.77: during the close-up the card is carried in front of the lens,
    -- Field3D.playerCardPos, so this guard only trips mid pull-back if ever)
    local cpx, cpz = Field3D.playerCardPos(opts.battle)
    local depthP = (cpx - c.eye[1]) * c.fx + (cpz - c.eye[3]) * c.fz
    -- jp.84: while the player's own attack plays, its effect sprites go
    -- between the two cards (opts.underPlayer, drawn below once the feet are
    -- known), so the player's card, nearest the lens, is not covered by the
    -- move it is using
    local splitP = opts.underPlayer and opts.panel and depthP >= 24 and n >= 12
    gpu.cards:setDrawRange(1, (depthP < 24 or splitP) and 6 or n)
    gpu.cards:setTexture(opts.cards)
    -- the battlers are the subject (the 2D panel always shows them): a tree
    -- or wall between the camera and a card must not hide it
    G.setDepthMode("always", false)
    G.draw(gpu.cards)
    G.setDepthMode("lequal", true)
    -- where each card's centre lands (NDC), for the headless checks
    local m, a = c.viewProj, opts.battle
    local function ndc(x, y, z)
      local cw = m[4][1] * x + m[4][2] * y + m[4][3] * z + m[4][4]
      if math.abs(cw) < 1e-6 then return nil end
      return (m[1][1] * x + m[1][2] * y + m[1][3] * z + m[1][4]) / cw,
        (m[2][1] * x + m[2][2] * y + m[2][3] * z + m[2][4]) / cw
    end
    local ex, ey = ndc(a.ex, cgh + 8, a.ez)
    local qx, qz, qf = Field3D.playerCardPos(a)
    local px, py = ndc(qx, cgh + qf + 7, qz)
    local function gb(nx, ny)
      local r = opts.panel
      if not (r and nx) then return -1, -1 end
      local sx, sy = (nx + 1) / 2 * w, (1 - ny) / 2 * h
      return (sx - r[1]) / (r[3] - r[1]) * 160, (sy - r[2]) / (r[4] - r[2]) * 144
    end
    local egx, egy = gb(ex, ey)
    local pgx, pgy = gb(px, py)
    local pr = opts.panel or { 0, 0, 0, 0 }
    local _, etop = gb(ndc(a.ex, cgh + 16, a.ez))
    local _, ebot = gb(ndc(a.ex, cgh, a.ez))
    local _, ptop = gb(ndc(qx, cgh + qf + 48 * CARD_SCALE, qz))
    local _, pbot = gb(ndc(qx, cgh + qf, qz))
    -- jp.78: the two cards' feet (their rest cells, as the 2D effects use
    -- the pics' rest boxes) in panel pixels, for BattleState.feetPlacer
    if opts.panel then
      local efx, efy = gb(ndc(a.ex, cgh, a.ez))
      local pfx, pfy = gb(ndc(qx, cgh + qf, qz))
      a.gbFeet = { efx, efy, pfx, pfy }
    else
      a.gbFeet = nil
    end
    if splitP then
      local r = opts.panel
      G.push("all")
      G.setShader()
      G.setDepthMode("always", false)
      G.origin()
      G.translate(r[1], r[2])
      G.scale((r[3] - r[1]) / 160, (r[4] - r[2]) / 144)
      G.setColor(1, 1, 1, 1)
      local okU, errU = pcall(opts.underPlayer)
      G.pop()
      if not okU then note("under player: " .. tostring(errU)) end
      G.setShader(shader)
      sendUniform(shader, "viewProj", "row", flat(c.viewProj))
      G.setDepthMode("always", false)
      gpu.cards:setDrawRange(7, n - 6)
      G.draw(gpu.cards)
      G.setDepthMode("lequal", true)
    end
    st.cardGb = string.format("gb enemy %d,%d (card y %d..%d) player %d,%d (card y %d..%d) panel %d,%d,%d,%d",
      egx, egy, etop, ebot, pgx, pgy, ptop, pbot, pr[1], pr[2], pr[3], pr[4])
    st.cardNdc = string.format("w%d h%d enemy %.2f,%.2f player %.2f,%.2f", w, h, ex or 9, ey or 9, px or 9, py or 9)
  end

  -- jp.76: rain and snow in the scene, depth tested (no depth write) and
  -- fogged.  Falls back to the flat overlay if the mesh is missing.
  local weatherFlat = weather3d
  if weather3d and gpu.weather and gpu.white then
    local p = world.player
    local yaw = math.rad(st.yaw or 0)
    local tx = (p and p.px or 0) + CELL / 2
    local tz = (p and p.py or 0) + CELL / 2
    local t = love.timer and love.timer.getTime() or 0
    local n
    n, st.weatherVerts = Field3D.weatherParticles(weather3d, t, tx + c.fx * 40, tz + c.fz * 40,
      math.cos(yaw), math.sin(yaw), st.weatherVerts,
      (daytime == "NITE" or daytime == "DARK") and (weather3d == "snow" and 0.85 or 0.6) or 1)
    if n > 0 then
      G.setDepthMode("lequal", false)
      gpu.weather:setVertices(st.weatherVerts, 1, n)
      gpu.weather:setDrawRange(1, n)
      gpu.weather:setTexture(gpu.white)
      G.draw(gpu.weather)
      weatherFlat = nil
    end
  end
  G.setShader()
  G.setDepthMode()

  -- jp.81: the diorama rung blurs the picture above and below the player's
  -- band (a miniature tilt-shift, as Gen 1's diorama look); the overlays
  -- below then land on the blurred copy
  -- jp.85: on every "above" rung, not the diorama one alone -- the 初代
  -- (Gen 1) field has the blur at the default pitch too, and without it the
  -- far rows read as hard blocks
  -- jp.85: the battle arena takes the same blur, focused on the battlers'
  -- band (初代's battle backdrop has the route fall off into depth blur);
  -- note the battle rig sets opts.orbit for the boards, so it is tested first
  -- jp.86: the level comes from OPTION > 3D > とおくの ぼかし (jp3DBlur,
  -- 0 = none); in the battle only the far half (above the battlers) blurs
  local inBattle = opts and opts.battle and true or false
  if inBattle or (mode == "above" and not (opts and opts.orbit)) then
    local level = Field3D.blurLevel(optionsOf(world))
    if level > 0 then
      -- jp.86: in the battle the focus follows the panel (0.45 of its height
      -- below its top, about the player's pic), wherever the panel sits
      local fy
      if inBattle then
        local r = opts.panel
        fy = r and h > 0 and ((r[2] + (r[4] - r[2]) * 0.45) / h) or 0.45
        fy = math.max(0.05, math.min(0.95, fy))
      else
        fy = (c.focusY and c.focusY / h) or 0.5
      end
      local blurred = Field3D.tiltShift(out, w, h, fy, level, inBattle)
      if blurred then out = blurred end
    end
  end

  -- 4. weather and the fade, flat over the top
  if weatherFlat then weatherOverlay(weatherFlat, w, h) end
  if world.fade and not world.fadeHold and not (opts and opts.orbit) then
    local a = math.max(0, math.min(1, world.fadeLevel or 1))
    if world.fade == "white" then G.setColor(1, 1, 1, a) else G.setColor(0, 0, 0, a) end
    G.rectangle("fill", 0, 0, w, h)
    G.setColor(1, 1, 1, 1)
  end

  if not (opts and opts.orbit) then st.live = true end
  st.lastFrame = st.frame
  st.sprites = #sprites
  return out
end

-- The world frame, or nil to keep the 2D path.  An error turns the mode off
-- for the rest of the session (logged once) rather than every frame.
function Field3D.draw(world, w, h, opts)
  if Field3D.failed then return nil end
  if not (world and world.map and world.player and world.camera) then return nil end
  local ok = Field3D.available()
  if not ok then return nil end
  local G = love.graphics
  G.push("all")
  local okDraw, result = pcall(drawScene, world, w, h, opts)
  G.pop()
  if not okDraw then
    Field3D.failed = tostring(result)
    note("disabled: " .. Field3D.failed)
    if world.field3d then world.field3d.live = false end
    return nil
  end
  return result
end

function Field3D.diagnostics()
  local okA, reason = Field3D.available()
  local v = "?"
  if love and love.getVersion then
    local a, b, c = love.getVersion()
    v = tostring(a) .. "." .. tostring(b) .. "." .. tostring(c)
  end
  return string.format("available=%s reason=%s failed=%s love=%s",
    tostring(okA), tostring(reason), tostring(Field3D.failed), v)
end

-- ---------------------------------------------------------------------------
-- battle backdrop: the field around the player, orbiting slowly

-- jp.76: with the battle screen passed in (owner), the view is the arena:
-- the battlers stand in the field as cards and the camera opens on the foe.
-- The battle screen then shows the same frame inside its panel
-- (BattleState:drawPanel3D).  Any error here or there drops that battle back
-- to the jp.75 orbit, and the panel to plain 2D.
local function arenaOpts(world, owner)
  if not (owner and owner.cards3D) or owner.arena3DFailed then return nil end
  local a = owner.arena3D
  if not a then
    local p = world.player
    -- jp.86: the foe's cell is picked on Crystal's collision map (open floor
    -- only, see battleArena); the field camera's forward is the preferred
    -- axis so the seamless entry turns as little as possible
    local map = world.map
    local prof = Field3D.profileFor(map and map.def)
    local function probe(cx, cy)
      local okc, coll = pcall(world.cellCollisionAcross, world, map, cx, cy)
      return okc and Field3D.heightOf(coll, prof) == 0
    end
    local st0 = world.field3d
    local prefer = st0 and st0.yaw and DIRS[quadrant(st0.yaw) + 1] or p.facing
    a = Field3D.battleArena(p.px + 8, p.py + 8, p.facing, map and probe or nil, prefer)
    -- jp.84: a wild battle that skipped the wipe (World:pushBattleTransition)
    -- opens from the field view that was on screen
    local st = world.field3d
    if st and st.entryArmed then
      if st.fieldPose then
        a.entry = { pose = st.fieldPose, t = 0, dur = Field3D.ENTRY_SECONDS }
      end
      st.entryArmed = nil
    end
    owner.arena3D = a
  end
  local dt = love.timer and love.timer.getDelta and love.timer.getDelta() or 1 / 60
  dt = math.min(dt, 0.1)
  a.t = (a.t or 0) + dt
  if a.entry then
    a.entry.t = a.entry.t + dt
    if a.entry.t >= (a.entry.dur or 1) then a.entry = nil end
  end
  local introOver = owner.introDone3D and owner:introDone3D()
  if not introOver then
    a.focus, a.focusClock = 0, nil
  elseif owner.phase == "menu" or owner.phase == "moves" then
    a.focus = 1
  else
    a.focusClock = (a.focusClock or 0) + dt
    a.focus = math.min(1, math.max(a.focus or 0, (a.focusClock - 0.12) / 0.9))
  end
  -- jp.85: no cards in the scene.  The battlers are drawn by the panel
  -- itself (BattleState:drawPanel3D -> drawHud -> drawPics) in the cart's
  -- pic boxes, where they cannot land under the HUD boxes; the arena is the
  -- backdrop only, as the 初代 (Gen 1) build does it.
  local cards = nil
  a.shiftE, a.shiftP = 0, 0
  a.gbFeet = nil
  -- jp.78: the action camera follows a move toward its target
  local anim = owner.anim
  local kind, goal = "idle", 0
  if anim and anim.jpMove then
    kind = "attack"
    goal = anim.hudSide == "player" and -1 or 1
  end
  a.act = Field3D.actionStep(a.act, dt, introOver and (a.focus or 0) >= 1, kind, goal)
  -- jp.84: the player's own damaging move draws its sprites under the
  -- player's card (BattleState:drawUnderPlayer3D)
  -- jp.85: no under-card pass either (the move sprites go over the panel's
  -- pics as on the cart)
  local under = nil
  return { battle = a, cards = cards or nil, orbit = 0, slot = "battleCanvas", panel = owner.panel3D,
    underPlayer = under }
end

function Field3D.drawBattleBackdrop(game, w, h, owner)
  local world = game and game.world
  if not (world and Field3D.battleOn(game)) then return false end
  -- jp.91: the mod's voxel arena.  `owner.panel3D` is the panel's window rect
  -- from the previous frame (nil on the first one; the mod then frames a
  -- centred 160x216 panel and the real rect follows next frame).
  local backdrop = battleBackdropExport(game)
  if backdrop then
    local ok, canvas = pcall(backdrop, owner, w, h, owner and owner.panel3D)
    if not ok then
      print("[Field3D] battle backdrop mod error: " .. tostring(canvas))
      canvas = nil
    end
    if not canvas then return false end
    if owner then owner.bg3dCanvas, owner.bg3dLive = canvas, true end
    local G = love.graphics
    G.push("all")
    G.origin()
    G.setColor(1, 1, 1, 1)
    G.draw(canvas, 0, 0)
    G.pop()
    return true
  end
  local t = love.timer and love.timer.getTime() or 0
  local opts = arenaOpts(world, owner)
  local canvas = Field3D.draw(world, w, h, opts or { orbit = (t * 8) % 360, slot = "battleCanvas" })
  if not canvas and opts and not Field3D.failed then
    canvas = Field3D.draw(world, w, h, { orbit = (t * 8) % 360, slot = "battleCanvas" })
    opts = nil
  end
  if not canvas then return false end
  if owner and opts then
    owner.bg3dCanvas, owner.bg3dLive = canvas, true
  end
  local G = love.graphics
  G.push("all")
  G.origin()
  G.setColor(1, 1, 1, 1)
  G.draw(canvas, 0, 0)
  G.pop()
  return true
end

-- ---------------------------------------------------------------------------
-- input

local function live(world)
  local st = world and world.field3d
  return st and st.live and Field3D.enabled(world) and not Field3D.failed
end

Field3D.live = live

-- jp.84: Gen 1's seamless wild entry.  True (and armed) when the field is on
-- screen in 3D and the battle will be 3D too, so the battle can come straight
-- up and its camera travel out of the current field view; the caller then
-- skips the wipe.  Trainer battles keep the wipe, as in Gen 1.
function Field3D.armSeamlessEntry(world)
  local st = world and world.field3d
  if not (st and live(world) and st.fieldPose and Field3D.battleOn(world.game)) then return false end
  if not (st.lastFrame and st.frame and st.frame - st.lastFrame <= 2) then return false end
  st.entryArmed = true
  return true
end

-- jp.76 free movement: the camera yaw (radians) and whether stick input is
-- read camera-relative.  nil while the 3D field is not live.
function Field3D.moveBasis(world)
  if not live(world) then return nil end
  local st = world.field3d
  local mode = Field3D.cameraMode(world)
  local relative = mode == "first" or moveRelative(world)
    or quadrant(st.yawTarget or 0) ~= 0
  return math.rad(tonumber(st.yaw) or 0), relative, mode
end

-- The held d-pad direction, turned into the map direction it means with the
-- camera where it is.  First person: up/down walk along the view, left/right
-- turn on the spot.  Other views: relative only with MOVE on.
function Field3D.remapDirection(world, dir)
  if not live(world) then return dir end
  local st = world.field3d
  local prev = st.prevRaw
  st.prevRaw = dir
  local q = quadrant(st.yawTarget)
  if Field3D.cameraMode(world) == "first" then
    if dir == "left" or dir == "right" then
      local p = world.player
      local okb, busy = pcall(world.busy, world)
      if prev ~= dir and p and not p.moving and not (okb and busy) then
        st.yawTarget = st.yawTarget + (dir == "left" and -90 or 90)
        p.facing = DIRS[quadrant(st.yawTarget) + 1]
      end
      return nil
    end
    if dir == nil then return nil end
    return DIRS[(DIR_INDEX[dir] + q) % 4 + 1]
  end
  -- jp.81: with the view turned (any view now), the d-pad follows the
  -- screen even with MOVE off, so up always walks up the picture
  if dir == nil or (q == 0 and not moveRelative(world)) then return dir end
  return DIRS[(DIR_INDEX[dir] + q) % 4 + 1]
end

-- the 3D field is live and nothing (a menu, the boot) is over it
local function fieldFree(game)
  local world = game and game.world
  if not live(world) then return false end
  if game.phase == "boot" then return false end
  if game.stack and game.stack.top and game.stack:top() then return false end
  return true
end
Field3D.fieldFree = fieldFree

-- jp.81: every view turns (jp.80 kept the view from above locked north
-- unless MOVE was on, so it had no camera control at all)
local function canRotate(game)
  return fieldFree(game)
end

local function persist(game)
  if game and game.persistOptions then pcall(game.persistOptions, game) end
end

-- jp.81: one step along the view ladder (ジオラマ, 15, 35, 50, 75 from
-- above, then behind, then first person, and round again)
function Field3D.cycleView(game, step)
  local world = game and game.world
  local o = game and game.options
  if not (o and world) then return false end
  local L = Field3D.LADDER
  local i = (Field3D.ladderIndex(world) - 1 + (step or 1)) % #L + 1
  local key = L[i]
  if key == "third" or key == "first" then
    o.jp3DCamera = key
  else
    o.jp3DCamera = "above"
    o.jp3DAngle = key
  end
  local st = stateFor(world)
  st.toast, st.toastClock = Field3D.viewLabel(world), 1.4
  persist(game)
  return true
end

function Field3D.zoomStep(game, step)
  local world = game and game.world
  local o = game and game.options
  if not (o and world) then return false end
  local z = math.max(1, math.min(#Field3D.ZOOMS, Field3D.zoomIndex(world) + step))
  o.jp3DZoom = z
  local st = stateFor(world)
  st.toast, st.toastClock = "ズーム " .. z .. "/" .. #Field3D.ZOOMS, 1.2
  persist(game)
  return true
end

function Field3D.rotate(world, steps)
  local st = stateFor(world)
  st.yawTarget = (math.floor(st.yawTarget / 90 + 0.5) + steps) * 90
  if Field3D.cameraMode(world) == "first" and world.player and not world.player.moving then
    world.player.facing = DIRS[quadrant(st.yawTarget) + 1]
  end
end

-- jp.81 look up / down by a step (keyboard R / F); the chase and first-person
-- views only.  INVERT flips the direction like the stick and the drag.
local function lookStep(game, delta)
  local world = game.world
  if Field3D.cameraMode(world) == "above" then return false end
  local st = stateFor(world)
  if invertLook(world) then delta = -delta end
  st.lookPitch = clampN((st.lookPitch or 0) + delta, -40, 45)
  return true
end

-- Called BEFORE Game2:hotkey: V walks the view ladder, - / = (and the keypad
-- ones) zoom the 3D camera instead of the 2D display while the 3D field is
-- free.  Off 3D (or under a menu) this returns false and the hotkeys keep
-- their jp.80 meaning.
function Field3D.preHotkey(game, key)
  if key ~= "v" and key ~= "-" and key ~= "=" and key ~= "kp-" and key ~= "kp+" then
    return false
  end
  if not fieldFree(game) then return false end
  if key == "v" then return Field3D.cycleView(game, 1) end
  return Field3D.zoomStep(game, (key == "-" or key == "kp-") and -1 or 1)
end

function Field3D.keypressed(game, key)
  if key == "r" or key == "f" then
    if not fieldFree(game) then return false end
    return lookStep(game, key == "r" and -10 or 10)
  end
  if key ~= "q" and key ~= "e" then return false end
  if not canRotate(game) then return false end
  Field3D.rotate(game.world, key == "q" and -1 or 1)
  return true
end

-- mouse wheel: 3D zoom while the field is free
function Field3D.wheel(game, dy)
  if not fieldFree(game) or dy == 0 then return false end
  return Field3D.zoomStep(game, dy > 0 and 1 or -1)
end

local drag
function Field3D.touchpressed(game, id, x, y)
  if not canRotate(game) then return false end
  drag = { id = id, x = x, y = y, moved = 0 }
  return true
end

function Field3D.touchmoved(game, id, x, y)
  if not (drag and drag.id == id) then return false end
  local world = game and game.world
  if not live(world) then drag = nil; return false end
  local st = world.field3d
  local w, h = 800, 600
  if love.graphics.getDimensions then w, h = love.graphics.getDimensions() end
  local dx, dy = x - drag.x, y - drag.y
  drag.x, drag.y = x, y
  drag.moved = drag.moved + math.abs(dx)
  -- a full screen width is half a turn
  st.yawTarget = st.yawTarget + dx / math.max(1, w) * 180
  if Field3D.cameraMode(world) ~= "first" then st.yaw = st.yawTarget end
  -- jp.81: up / down drags tilt the chase and first-person views (a drag up
  -- looks up / further ahead; INVERT flips it)
  if Field3D.cameraMode(world) ~= "above" and math.abs(dy) > 0 then
    local sgn = invertLook(world) and -1 or 1
    st.lookPitch = clampN((st.lookPitch or 0) + dy / math.max(1, h) * 120 * sgn, -40, 45)
  end
  return true
end

-- jp.77 turning without a drag.  On a phone the JP touch mode hands the whole
-- left half of the screen to the floating d-pad, so a drag there never
-- reached the camera.  Two round turn buttons sit at the top left while the
-- 3D field can turn, and a controller turns with L / R or the right stick.
local turnTouch = {}
function Field3D.buttonsShown(game)
  local o = game and game.options
  return not (o and o.jp3DButtons == false)
end

function Field3D.toggleButtons(game)
  local o = game and game.options
  if not o then return false end
  o.jp3DButtons = not Field3D.buttonsShown(game)
  local world = game.world
  if world then
    local st = stateFor(world)
    st.toast, st.toastClock = o.jp3DButtons and "カメラボタン オン" or "カメラボタン オフ", 1.2
  end
  persist(game)
  return true
end

function Field3D.turnButtons(game)
  if not canRotate(game) then return nil end
  local okT, TC = pcall(require, "src.core.TouchControls")
  if not (okT and TC and TC.active and TC.visible) then return nil end
  if TC.preview or not TC:visible() then return nil end
  local ox, oy, ww, wh = 0, 0, 800, 600
  local okS, SafeArea = pcall(require, "src.core.SafeArea")
  if okS and SafeArea and SafeArea.windowRect then
    ox, oy, ww, wh = SafeArea.windowRect()
  elseif love and love.graphics and love.graphics.getDimensions then
    ww, wh = love.graphics.getDimensions()
  end
  local r = math.max(18, math.min(ww, wh) * 0.055)
  local m = r * 0.5
  local cy = oy + m + r
  -- jp.81: the view button and the zoom pair mirror the turn pair at the
  -- top right (Gen 1's V / pinch, for a phone)
  local rx = ox + ww - m - r
  -- the touch overlay's hotbar (the three-dot button) can sit in that same
  -- corner; when it shares the row, the right-hand group steps left of it
  local okH, shown = pcall(function() return not TC:optimized() and TC:hotbarShown() end)
  local okL, L = pcall(function() return TC:layout() end)
  local hb = okH and shown and okL and L and L.hotbar
  if hb and hb.cx and hb.cy and hb.w then
    local hr = hb.w * 0.5 * 1.16
    if math.abs(hb.cy - cy) < hr + r and hb.cx > rx - r * 6 then
      rx = math.min(rx, hb.cx - hr - m - r)
    end
  end
  -- jp.82: a small tab at the top centre hides / shows the row (option
  -- jp3DButtons, absent = shown); hidden, only the tab stays
  -- It sits in the gap between the turn pair and the view button (the
  -- top centre was under the view button when the hotbar shares the row);
  -- if that gap is too narrow, just under the row.
  -- jp.86: the tab is gone (the tester saw only a stray grey chevron at the
  -- top of the field once the row was hidden; 初代 has no widget there).
  -- The row is shown / hidden from OPTION > 3D > 3Dの カメラボタン only.
  if not Field3D.buttonsShown(game) then return nil end
  return {
    { cx = ox + m + r, cy = cy, r = r, steps = -1, kind = "turn" },
    { cx = ox + m + r * 3.4, cy = cy, r = r, steps = 1, kind = "turn" },
    { cx = rx - r * 4.8, cy = cy, r = r, kind = "view" },
    { cx = rx - r * 2.4, cy = cy, r = r, steps = -1, kind = "zoom" },
    { cx = rx, cy = cy, r = r, steps = 1, kind = "zoom" },
  }
end

local toastFonts = {}
local function toastFont(size)
  size = math.max(10, math.floor(size + 0.5))
  if toastFonts[size] == nil then
    local ok, f = pcall(love.graphics.newFont, "assets/fonts/noto/NotoSansJP-Regular.ttf", size)
    if not ok then ok, f = pcall(love.graphics.newFont, size) end
    toastFonts[size] = ok and f or false
  end
  return toastFonts[size] or nil
end

-- the short label a view / zoom change shows at the top of the screen
local function drawToast(game)
  local world = game and game.world
  local st = world and world.field3d
  if not (st and st.toast and (st.toastClock or 0) > 0) then return false end
  if not fieldFree(game) then st.toast = nil; return false end
  local dt = love.timer and love.timer.getDelta and love.timer.getDelta() or 1 / 60
  st.toastClock = st.toastClock - math.min(dt, 0.1)
  local G = love.graphics
  local ww, wh = G.getDimensions()
  local f = toastFont(math.max(14, math.min(ww, wh) * 0.04))
  if not f then return false end
  local a = math.min(1, st.toastClock / 0.3)
  local tw, th = f:getWidth(st.toast), f:getHeight()
  local px, py = th * 0.6, th * 0.3
  local x = (ww - tw) / 2
  local y = wh * 0.16
  G.push("all")
  G.origin()
  G.setShader()
  G.setScissor()
  G.setColor(0, 0, 0, 0.6 * a)
  G.rectangle("fill", x - px, y - py, tw + px * 2, th + py * 2, th * 0.4)
  G.setColor(1, 1, 1, a)
  G.setFont(f)
  G.print(st.toast, x, y)
  G.pop()
  if st.toastClock <= 0 then st.toast = nil end
  return true
end

function Field3D.turnButtonHit(game, x, y)
  local list = Field3D.turnButtons(game)
  if not list then return nil end
  for _, b in ipairs(list) do
    local dx, dy = x - b.cx, y - b.cy
    local k = b.kind == "tab" and 1.6 or 1.25
    if dx * dx + dy * dy <= (b.r * k) ^ 2 then return b end
  end
  return nil
end

-- Called first in Game2:touchpressed (before the touch pad claims it).
function Field3D.turnTouchPressed(game, id, x, y)
  local b = Field3D.turnButtonHit(game, x, y)
  if not b then return false end
  if b.kind == "tab" then
    Field3D.toggleButtons(game)
  elseif b.kind == "view" then
    Field3D.cycleView(game, 1)
  elseif b.kind == "zoom" then
    Field3D.zoomStep(game, b.steps)
  else
    Field3D.rotate(game.world, b.steps)
  end
  turnTouch[id] = true
  return true
end

function Field3D.turnTouchReleased(id)
  if turnTouch[id] then turnTouch[id] = nil; return true end
  return false
end

function Field3D.drawTurnButtons(game)
  local list = Field3D.turnButtons(game)
  if not list then
    drawToast(game)
    return false
  end
  local G = love.graphics
  G.push("all")
  G.origin()
  G.setShader()
  G.setScissor()
  for _, b in ipairs(list) do
    if b.kind == "tab" then
      -- jp.82: a faint pill with a chevron: up = hide the row, down = show it
      local w, hh = b.r * 1.5, b.r * 0.8
      G.setColor(0, 0, 0, 0.45)
      G.rectangle("fill", b.cx - w, b.cy - hh, w * 2, hh * 2, hh)
      G.setColor(1, 1, 1, 0.8)
      G.setLineWidth(math.max(2, b.r * 0.12))
      G.rectangle("line", b.cx - w, b.cy - hh, w * 2, hh * 2, hh)
      G.setLineWidth(math.max(2, b.r * 0.14))
      local a, s = b.r * 0.5, b.shown and -1 or 1
      G.line(b.cx - a, b.cy - a * 0.35 * s, b.cx, b.cy + a * 0.35 * s, b.cx + a, b.cy - a * 0.35 * s)
    else
    G.setColor(0, 0, 0, 0.35)
    G.circle("fill", b.cx, b.cy, b.r)
    G.setColor(1, 1, 1, 0.8)
    G.setLineWidth(math.max(2, b.r * 0.12))
    G.circle("line", b.cx, b.cy, b.r)
    end
    if b.kind == "tab" then
      -- drawn above
    elseif b.kind == "zoom" then
      -- a plus / minus
      local a = b.r * 0.45
      G.line(b.cx - a, b.cy, b.cx + a, b.cy)
      if b.steps > 0 then G.line(b.cx, b.cy - a, b.cx, b.cy + a) end
    elseif b.kind == "view" then
      -- an eye: two arcs and a pupil
      local a = b.r * 0.55
      G.arc("line", "open", b.cx, b.cy + a * 0.55, a * 1.05, math.rad(-150), math.rad(-30), 12)
      G.arc("line", "open", b.cx, b.cy - a * 0.55, a * 1.05, math.rad(30), math.rad(150), 12)
      G.circle("fill", b.cx, b.cy, a * 0.32)
    else
    -- a curved arrow: an arc and a head, mirrored for the right button
    local s = b.steps < 0 and -1 or 1
    local rr = b.r * 0.5
    G.arc("line", "open", b.cx, b.cy, rr, math.rad(-150), math.rad(150), 16)
    local ang = math.rad(s < 0 and -150 or 150)
    local hx, hy = b.cx + math.cos(ang) * rr, b.cy + math.sin(ang) * rr
    local hs = b.r * 0.32
    local tx = s < 0 and 1 or -1
    G.polygon("fill", hx - hs * 0.8, hy + hs * 0.5 * tx * s,
      hx + hs * 0.8, hy + hs * 0.5 * tx * s, hx, hy - hs * 0.7 * tx * s)
    end
  end
  G.pop()
  drawToast(game)
  return true
end

-- Controller: L / R shoulders turn a step; the right stick turns on a push.
-- jp.81: a click of the right stick walks the view ladder (unbound before).
function Field3D.padPressed(game, button)
  if button == "rightstick" then
    if not fieldFree(game) then return false end
    return Field3D.cycleView(game, 1)
  end
  if button ~= "leftshoulder" and button ~= "rightshoulder" then return false end
  if not canRotate(game) then return false end
  Field3D.rotate(game.world, button == "leftshoulder" and -1 or 1)
  return true
end

-- jp.81: right stick up / down -- held, it tilts the chase / first-person
-- views (read every frame in drawScene); in the view from above a push is a
-- zoom step.  Under a menu it is left alone (the menus scroll with it).
local stickArmed, zoomArmed = true, true
function Field3D.padAxis(game, axis, value)
  if axis == "righty" then
    local world = game and game.world
    local st = world and world.field3d
    if math.abs(value) < 0.25 then
      zoomArmed = true
      if st then st.stickY = 0 end
      return false
    end
    if not fieldFree(game) then
      if st then st.stickY = 0 end
      return false
    end
    if Field3D.cameraMode(world) == "above" then
      st.stickY = 0
      if zoomArmed and math.abs(value) > 0.7 then
        zoomArmed = false
        Field3D.zoomStep(game, value < 0 and 1 or -1)
      end
    else
      st.stickY = value
    end
    return true
  end
  if axis ~= "rightx" then return false end
  if math.abs(value) < 0.35 then stickArmed = true; return false end
  if not canRotate(game) then return false end
  if stickArmed and math.abs(value) > 0.7 then
    stickArmed = false
    Field3D.rotate(game.world, value < 0 and -1 or 1)
  end
  return true
end

function Field3D.touchreleased(game, id)
  if Field3D.turnTouchReleased(id) then return true end
  if not (drag and drag.id == id) then return false end
  drag = nil
  local world = game and game.world
  if world and world.field3d then Field3D.rotate(world, 0) end
  return true
end

return Field3D
