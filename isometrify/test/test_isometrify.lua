-- Headless test harness + example generator for the isometrify plugin.
--
--   cd <repo>/isometrify/test
--   <path-to-aseprite> -b -script test_isometrify.lua
--
-- Loads ../isometrify.lua as a library and checks:
--   * the shear math (staircases, mirroring, no-op widths)
--   * the floor projection (full-coverage diamond: 1:1 pixel moves
--     with a solid copied outline, cube-proportioned)
--   * exact reversibility (round trips)
--   * the sprite plumbing (region extraction, cel replacement,
--     canvas growth, selection update, failure paths, context
--     defaults)
-- Also renders docs/example_flat.png, docs/example_wall.png,
-- docs/example_floor.png and docs/example_cube.png.

local function load_plugin()
  for _, path in ipairs({
    "../isometrify.lua",                 -- run from isometrify/test
    "isometrify.lua",                    -- run from isometrify/
    "../../isometrify/isometrify.lua",   -- run from the repo root
  }) do
    local chunk = loadfile(path)
    if chunk then return chunk(), path end
  end
  error("test: could not load isometrify.lua (run me from isometrify/test)")
end

local M, PLUGIN_PATH = load_plugin()
local DOCS = PLUGIN_PATH:gsub("isometrify%.lua$", "docs")

local pc = app.pixelColor
local A = pc.rgba(255, 0, 0, 255)
local B = pc.rgba(0, 0, 255, 255)
local C = pc.rgba(0, 255, 0, 255)
local D = pc.rgba(255, 255, 0, 255)
local T = 0

local checks, fails = 0, 0
local function report(desc, ok, detail)
  checks = checks + 1
  if ok then
    print("PASS " .. desc)
  else
    fails = fails + 1
    print("FAIL " .. desc .. (detail ~= nil and (" -- " .. detail) or ""))
  end
end

local function solid(w, h, value)
  local img = Image(w, h, ColorMode.RGBA)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      img:putPixel(x, y, value)
    end
  end
  return img
end

-- paint a solid block onto an image
local function block(img, x, y, w, h, value)
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      img:putPixel(xx, yy, value)
    end
  end
end

local MAP = { A = A, B = B, C = C, D = D, ["."] = T }

local function img_from_rows(rows)
  local h, w = #rows, #rows[1]
  local img = Image(w, h, ColorMode.RGBA)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      img:putPixel(x, y, MAP[rows[y + 1]:sub(x + 1, x + 1)] or T)
    end
  end
  return img
end

-- compare an image against ascii rows ('.' or missing rows/chars = transparent)
local function expect(desc, rows, img)
  local bad, first = 0, nil
  for y = 0, img.height - 1 do
    for x = 0, img.width - 1 do
      local row = rows[y + 1]
      local ch = (row ~= nil and row:sub(x + 1, x + 1) or "")
      if ch == "" then ch = "." end
      local want = MAP[ch] or T
      local got = img:getPixel(x, y)
      if got ~= want then
        bad = bad + 1
        if first == nil then
          first = string.format("at (%d,%d) got %d want %d", x, y, got, want)
        end
      end
    end
  end
  report(desc, bad == 0, first)
end

print("testing on Aseprite " .. tostring(app.version))

-- --------------------------------------------------------------- shear math

print("== shear math ==")

expect("forward dr: 8x1 line becomes a 2:1 staircase", {
  "AA......",
  "..AA....",
  "....AA..",
  "......AA",
}, M.transform(img_from_rows({ "AAAAAAAA" }), "dr", false))

local square = img_from_rows({ "AABB", "AABB", "AABB", "AABB" })

expect("forward dr: 4x4 two-tone square", {
  "AA..",
  "AABB",
  "AABB",
  "AABB",
  "..BB",
}, M.transform(square, "dr", false))

expect("forward ur: 4x4 square, mirrored wall", {
  "..BB",
  "AABB",
  "AABB",
  "AABB",
  "AA..",
}, M.transform(square, "ur", false))

expect("reverse dr: round trip is lossless", {
  "AABB", "AABB", "AABB", "AABB",
}, M.transform(M.transform(square, "dr", false), "dr", true))

expect("reverse ur: round trip is lossless", {
  "AABB", "AABB", "AABB", "AABB",
}, M.transform(M.transform(square, "ur", false), "ur", true))

expect("forward dr: 1px-wide region is a no-op", { "A", "A", "A" },
  M.transform(img_from_rows({ "A", "A", "A" }), "dr", false))

-- ---------------------------------------------------------------- floor math

print("== floor math ==")

expect("forward floor: 2x2 square becomes a tiny 4x2 diamond", {
  "CCAA",
  "DDBB",
}, M.transform(img_from_rows({ "AB", "CD" }), "floor", false))

expect("forward floor: 4x4 square becomes an 8x4 cube-scale diamond", {
  "..AAAA..",
  "CCCCAABB",
  "CCDDBBBB",
  "..DDDD..",
}, M.transform(img_from_rows({ "AABB", "AABB", "CCDD", "CCDD" }), "floor", false))

expect("forward floor: a 4x1 strip becomes a staircase of pairs", {
  "ABB..",
  ".CCDD",
  "...DD",
}, M.transform(img_from_rows({ "ABCD" }), "floor", false))

do
  local out = M.transform(solid(16, 16, A), "floor", false)
  local count = 0
  for y = 0, out.height - 1 do
    for x = 0, out.width - 1 do
      if out:getPixel(x, y) ~= T then count = count + 1 end
    end
  end
  report("forward floor: 16x16 becomes a 32x16 diamond (256 moved + 32 outline)",
    out.width == 32 and out.height == 16 and count == 288,
    out.width .. "x" .. out.height .. " with " .. count .. " pixels")
end

do
  local ok, err = pcall(function()
    return M.transform(img_from_rows({ "AB", "CD" }), "floor", true)
  end)
  report("reverse floor is refused (the diamond forgets its aspect)",
    ok == false and tostring(err):find("floor", 1, true) ~= nil)
end

-- --------------------------------------------------------- sprite plumbing

print("== sprite plumbing ==")

-- fresh sprite whose layer-1 cel is `img` placed at (x, y)
local function cel_sprite(img, x, y, canvas_w, canvas_h)
  local spr = Sprite(canvas_w, canvas_h)
  local cel = spr.layers[1]:cel(1)
  cel.image = img
  cel.position = Point(x, y)
  return spr, cel
end

-- 16x16 sprite, 8x8 cel at (2, 3): solid B carrying a 4x4 A block at
-- local (2, 2), with selection (4, 5, 4, 4) over the block
local function two_tone()
  local img = solid(8, 8, B)
  block(img, 2, 2, 4, 4, A)
  local spr, cel = cel_sprite(img, 2, 3, 16, 16)
  spr.selection = Selection(Rectangle(4, 5, 4, 4))
  return spr, cel
end

-- selection-based transform on a cel (two-tone: B background, A region)
-- drawImage composites (alpha blend), so transparent cells of the sheared
-- result keep existing art underneath; opaque cells overwrite.
do
  local spr, cel = two_tone()
  local ok, msg = M.apply({ direction = "dr", sprite = spr, frame = 1 })
  report("apply(dr) on a selection returns true", ok == true, msg)

  expect("apply(dr) selection: cel layout and pixels", {
    "BBBBBBBB",
    "BBBBBBBB",
    "BBAATTBB",   -- top notch (over the cleared hole)
    "BBAAAABB",
    "BBAAAABB",
    "BBAAAABB",
    "BBBBAABB",   -- transparent sheared cells blend: B kept, A landed
    "BBBBBBBB",
  }, cel.image)

  report("apply(dr) selection: cel bounds",
    cel.bounds.x == 2 and cel.bounds.y == 3 and
    cel.bounds.width == 8 and cel.bounds.height == 8)

  local sb = spr.selection.bounds
  report("apply(dr) selection: result left selected",
    sb.x == 4 and sb.y == 5 and sb.width == 4 and sb.height == 5)
  report("apply(dr) selection: canvas untouched",
    spr.width == 16 and spr.height == 16)
end

-- whole-cel transform grows the canvas
do
  local spr, cel = cel_sprite(solid(10, 10, B), 0, 0, 10, 10)
  local ok, msg = M.apply({ direction = "dr", sprite = spr, frame = 1 })
  report("apply(dr) whole cel returns true", ok == true, msg)
  report("apply(dr) whole cel: canvas grew to fit the wall",
    spr.height == 14 and spr.width == 10,
    "sprite is " .. spr.width .. "x" .. spr.height)
  report("apply(dr) whole cel: cel bounds grew",
    cel.bounds.width == 10 and cel.bounds.height == 14)
  report("apply(dr) whole cel: pixel layout",
    cel.image:getPixel(0, 13) == T and
    cel.image:getPixel(9, 13) == B and
    cel.image:getPixel(0, 0) == B)
end

-- mirrored wall through the sprite path (same two-tone cel)
do
  local spr, cel = two_tone()
  local ok = M.apply({ direction = "ur", sprite = spr, frame = 1 })
  report("apply(ur) on a selection returns true", ok == true)
  expect("apply(ur) selection: mirrored cel layout and pixels", {
    "BBBBBBBB",
    "BBBBBBBB",
    "BBTTAABB",   -- mirrored top notch
    "BBAAAABB",
    "BBAAAABB",
    "BBAAAABB",
    "BBAABBBB",   -- mirrored bottom (blend keeps B, A content landed)
    "BBBBBBBB",
  }, cel.image)
end

-- floor through the sprite path: the diamond now fits inside the cel
do
  local spr, cel = two_tone()
  local ok, msg = M.apply({ direction = "floor", sprite = spr, frame = 1 })
  report("apply(floor) on a selection returns true", ok == true, msg)

  expect("apply(floor) selection: cel layout and pixels", {
    "BBBBBBBB..",
    "BBBBBBBB..",
    "BBTTAAAA..",   -- tip of the diamond; the cleared hole shows left of it
    "BBAAAAAAAA",
    "BBAAAAAAAA",
    "BBTTAAAA..",
    "BBBBBBBB..",
    "BBBBBBBB..",   -- cel grew 8 -> 10 wide for the diamond
  }, cel.image)

  report("apply(floor) selection: canvas untouched, cel bounds grew",
    spr.width == 16 and spr.height == 16 and
    cel.bounds.x == 2 and cel.bounds.y == 3 and
    cel.bounds.width == 10 and cel.bounds.height == 8)
  local sb = spr.selection.bounds
  report("apply(floor) selection: diamond left selected",
    sb.x == 4 and sb.y == 5 and sb.width == 8 and sb.height == 4)
end

-- reverse through the sprite path undoes a forward pass
do
  local spr, cel = cel_sprite(solid(8, 8, A), 4, 4, 20, 20)
  spr.selection = Selection(Rectangle(4, 4, 8, 8))
  local ok1 = M.apply({ direction = "dr", sprite = spr, frame = 1 })
  local fwd_h = cel.bounds.height          -- 8 + floor(7/2) = 11
  local ok2 = M.apply({ direction = "dr", reverse = true, sprite = spr, frame = 1 })
  local px = cel.image
  local restored = true
  for y = 0, 7 do
    for x = 0, 7 do
      if px:getPixel(x, y) ~= A then restored = false end
    end
  end
  report("apply(dr) then apply(dr, reverse) restores the region",
    ok1 and ok2 and fwd_h == 11 and restored)
end

-- graceful failure when the selection misses the layer
do
  local spr = cel_sprite(solid(4, 4, A), 0, 0, 12, 12)
  spr.selection = Selection(Rectangle(8, 8, 4, 4))
  local ok, msg = M.apply({ direction = "dr", sprite = spr, frame = 1 })
  report("apply fails cleanly when the selection misses the cel",
    ok == false and msg ~= nil)
end

-- empty margin inside the selection is not shifted: the shear is
-- counted from the drawing's own edge, not from the selection's
--
--   cel 8x8 (transparent), 4x4 block at local (2,2), cel at (4,4)
--   selection = the whole cel -- bigger than the block
do
  local img = Image(8, 8, ColorMode.RGBA)
  block(img, 2, 2, 4, 4, A)
  local spr, cel = cel_sprite(img, 4, 4, 16, 16)
  spr.selection = Selection(Rectangle(4, 4, 8, 8))
  local ok, msg = M.apply({ direction = "dr", sprite = spr, frame = 1 })
  report("apply(dr) with margin: returns true", ok == true, msg)

  expect("apply(dr) with margin: block sheared from its own left edge", {
    "........",
    "........",
    "..AA....",
    "..AAAA..",
    "..AAAA..",
    "..AAAA..",
    "....AA..",
    "........",
  }, cel.image)

  report("apply(dr) with margin: cel bounds unchanged",
    cel.bounds.x == 4 and cel.bounds.y == 4 and
    cel.bounds.width == 8 and cel.bounds.height == 8)
  local sb = spr.selection.bounds
  report("apply(dr) with margin: selection hugs the sheared block",
    sb.x == 6 and sb.y == 6 and sb.width == 4 and sb.height == 5)
  report("apply(dr) with margin: canvas untouched",
    spr.width == 16 and spr.height == 16)
end

-- no selection, but the cel carries transparent margin: same trimming
--
--   cel 8x8 (transparent), 3x3 block at local (4,4), cel at (4,4)
do
  local img = Image(8, 8, ColorMode.RGBA)
  block(img, 4, 4, 3, 3, A)
  local spr, cel = cel_sprite(img, 4, 4, 20, 20)
  local ok, msg = M.apply({ direction = "dr", sprite = spr, frame = 1 })
  report("apply(dr) whole cel with margin: returns true", ok == true, msg)

  expect("apply(dr) whole cel with margin: sheared from the block's edge", {
    "........",
    "........",
    "........",
    "........",
    "....AA..",
    "....AAA.",
    "....AAA.",
    "......A.",
  }, cel.image)

  report("apply(dr) whole cel with margin: cel bounds and canvas unchanged",
    cel.bounds.x == 4 and cel.bounds.y == 4 and
    cel.bounds.width == 8 and cel.bounds.height == 8 and
    spr.width == 20 and spr.height == 20)
  local sb = spr.selection.bounds
  report("apply(dr) whole cel with margin: selection hugs the result",
    sb.x == 8 and sb.y == 8 and sb.width == 3 and sb.height == 4)
end

-- a selection that only covers empty pixels fails cleanly
do
  local img = Image(8, 8, ColorMode.RGBA)
  block(img, 0, 0, 4, 8, A)     -- art only on the left half
  local spr = cel_sprite(img, 4, 4, 16, 16)
  spr.selection = Selection(Rectangle(10, 4, 2, 8))   -- empty half
  local ok, msg = M.apply({ direction = "dr", sprite = spr, frame = 1 })
  report("apply fails cleanly when the selection holds no pixels",
    ok == false and msg ~= nil)
end

-- apply() with pure context defaults: no sprite/layer/frame overrides,
-- the path the one-click commands take
do
  local spr = two_tone()
  local ok, msg = M.apply({ direction = "dr" })
  local sb = spr.selection.bounds
  report("apply(dr) with context defaults works (no overrides)",
    ok == true and sb.width == 4 and sb.height == 5,
    (ok == false and msg or tostring(sb)))
end

-- --------------------------------------------------------------- examples

print("== example render ==")

local function example_art()
  local img = Image(22, 16, ColorMode.RGBA)
  block(img, 0, 4, 22, 2, A)    -- horizontal red stripe
  block(img, 6, 0, 2, 16, B)    -- vertical blue stripe
  block(img, 13, 9, 5, 5, C)    -- green block
  return img
end

do
  local spr = cel_sprite(example_art(), 2, 2, 28, 26)
  spr:saveAs(DOCS .. "/example_flat.png")
  M.apply({ direction = "dr", sprite = spr, frame = 1 })
  spr:saveAs(DOCS .. "/example_wall.png")
  report("example PNGs rendered (flat + wall)",
    spr.height == 28, "sprite height " .. spr.height)
end

do
  local spr = cel_sprite(example_art(), 2, 2, 28, 26)
  M.apply({ direction = "floor", sprite = spr, frame = 1 })
  spr:saveAs(DOCS .. "/example_floor.png")
  report("example PNG rendered (floor)",
    spr.width == 40 and spr.height == 26,
    "sprite is " .. spr.width .. "x" .. spr.height)
end

-- a cube assembled from one square: floor + both walls, seams checked
do
  local S = 16
  local img = Image(S, S, ColorMode.RGBA)
  block(img, 0, 0, S/2, S/2, A)
  block(img, S/2, 0, S/2, S/2, B)
  block(img, 0, S/2, S/2, S/2, C)
  block(img, S/2, S/2, S/2, S/2, D)
  local F = M.transform(img, "floor", false)
  local Wl = M.transform(img, "dr", false)   -- hangs from the front-left edge
  local Wr = M.transform(img, "ur", false)   -- hangs from the front-right edge
  local X, Y = 2, 2
  local cv = Image(36, 36, ColorMode.RGBA)
  local function stamp(src, px, py)
    for y = 0, src.height - 1 do
      for x = 0, src.width - 1 do
        local c = src:getPixel(x, y)
        if c ~= 0 then cv:putPixel(px + x, py + y, c) end
      end
    end
  end
  stamp(F, X, Y)
  stamp(Wl, X, Y + S/2 + 1)          -- side by side, no overlap
  stamp(Wr, X + S, Y + S/2 + 1)
  local count = 0
  for y = 0, 35 do
    for x = 0, 35 do
      if cv:getPixel(x, y) ~= 0 then count = count + 1 end
    end
  end
  report("cube from one square: walls hang from the floor edges, no gaps",
    cv:getPixel(X, Y + S/2 + 1) == A and             -- wall top-left under the W corner
    cv:getPixel(X + 2*S - 2, Y + S/2 + 1) == B and   -- wall top-right under the E corner
    cv:getPixel(X + S - 2, Y + S - 1) ~= T and       -- 4px bottom tip, left...
    cv:getPixel(X + S + 1, Y + S - 1) ~= T and      -- ...and right: caps the 4px wall flat
    count == 288 + 256 + 256,
    count .. " pixels")
  local spr = cel_sprite(cv, 0, 0, 36, 36)
  spr:saveAs(DOCS .. "/example_cube.png")
  report("example PNG rendered (cube)", spr.width == 36 and spr.height == 36)
end

print(string.format("%d checks, %d failures", checks, fails))
if fails > 0 then
  print("SOME TESTS FAILED")
else
  print("ALL TESTS PASSED")
end
