-- Headless test harness + example generator for the isometrify plugin.
--
--   cd <repo>/isometrify/test
--   <path-to-aseprite> -b -script test_isometrify.lua
--
-- Loads ../isometrify.lua as a library (no dialog) and checks:
--   * the shear math (staircases, mirroring, no-op widths)
--   * exact reversibility (round trips)
--   * the sprite plumbing (region extraction, cel replacement,
--     canvas growth, selection update, failure paths)
-- Also renders docs/example_flat.png and docs/example_wall.png.

local function load_plugin()
  for _, path in ipairs({
    "../isometrify.lua",
    "isometrify.lua",
    "/Users/valeria/git/aseprite-plugins/isometrify/isometrify.lua",
  }) do
    local chunk = loadfile(path)
    if chunk then return chunk() end
  end
  error("test: could not load isometrify.lua")
end

local M = load_plugin()

local pc = app.pixelColor
local A = pc.rgba(255, 0, 0, 255)
local B = pc.rgba(0, 0, 255, 255)
local C = pc.rgba(0, 255, 0, 255)
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

local MAP = { A = A, B = B, C = C, ["."] = T }

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

-- --------------------------------------------------------- sprite plumbing

print("== sprite plumbing ==")

-- fresh sprite whose layer-1 cel is a solid block at (celx, cely)
local function make_sprite(w, h, celw, celh, celx, cely, value)
  local spr = Sprite(w, h)
  local cel = spr.layers[1]:cel(1)
  cel.image = solid(celw, celh, value)
  cel.position = Point(celx, cely)
  return spr, cel
end

-- selection-based transform on a cel (two-tone: B background, A region)
-- drawImage composites (alpha blend), so transparent cells of the sheared
-- result keep existing art underneath; opaque cells overwrite.
do
  local spr = Sprite(16, 16)
  local cel = spr.layers[1]:cel(1)
  local img = solid(8, 8, B)
  for y = 2, 5 do
    for x = 2, 5 do
      img:putPixel(x, y, A)
    end
  end
  cel.image = img
  cel.position = Point(2, 3)
  spr.selection = Selection(Rectangle(4, 5, 4, 4))
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
  local spr, cel = make_sprite(10, 10, 10, 10, 0, 0, B)
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
  local spr = Sprite(16, 16)
  local cel = spr.layers[1]:cel(1)
  local img = solid(8, 8, B)
  for y = 2, 5 do
    for x = 2, 5 do
      img:putPixel(x, y, A)
    end
  end
  cel.image = img
  cel.position = Point(2, 3)
  spr.selection = Selection(Rectangle(4, 5, 4, 4))
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

-- reverse through the sprite path undoes a forward pass
do
  local spr, cel = make_sprite(20, 20, 8, 8, 4, 4, A)
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
  local spr = make_sprite(12, 12, 4, 4, 0, 0, A)
  spr.selection = Selection(Rectangle(8, 8, 4, 4))
  local ok, msg = M.apply({ direction = "dr", sprite = spr, frame = 1 })
  report("apply fails cleanly when the selection misses the cel",
    ok == false and msg ~= nil)
end

-- --------------------------------------------------------------- examples

print("== example render ==")

do
  local spr = Sprite(28, 26)
  local cel = spr.layers[1]:cel(1)
  local img = Image(22, 16, ColorMode.RGBA)
  for x = 0, 21 do          -- horizontal red stripe
    img:putPixel(x, 4, A)
    img:putPixel(x, 5, A)
  end
  for y = 0, 15 do          -- vertical blue stripe
    img:putPixel(6, y, B)
    img:putPixel(7, y, B)
  end
  for y = 9, 13 do          -- green block
    for x = 13, 17 do
      img:putPixel(x, y, C)
    end
  end
  cel.image = img
  cel.position = Point(2, 2)
  spr:saveAs("/Users/valeria/git/aseprite-plugins/isometrify/docs/example_flat.png")
  M.apply({ direction = "dr", sprite = spr, frame = 1 })
  spr:saveAs("/Users/valeria/git/aseprite-plugins/isometrify/docs/example_wall.png")
  report("example PNGs rendered (flat + wall)",
    spr.height == 28, "sprite height " .. spr.height)
end

print(string.format("%d checks, %d failures", checks, fails))
if fails > 0 then
  print("SOME TESTS FAILED")
else
  print("ALL TESTS PASSED")
end
