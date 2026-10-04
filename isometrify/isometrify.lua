-- Isometrify: project a flat pixel-art selection onto the planes of a
-- 2:1 isometric scene.
--
-- Walls -- the math: an isometric wall is a pure vertical shear of
-- flat art.
--   * Vertical lines stay vertical.
--   * Horizontal lines become the classic 2:1 staircase (two across,
--     one down), because pixel column x slides down by floor(x/2)
--     (front wall) or floor((w-1-x)/2) (left wall).
--   * Every pixel lands on exactly one pixel: nothing is scaled,
--     duplicated or dropped, and the transform is exactly reversible.
--
-- This is what an artist does by hand: select the rightmost 2-pixel
-- strip and nudge it down 1; then the rightmost 4, down 1; then 6, 8...
-- Every pass pushes all earlier strips one row further down, so strip
-- pair i (counted from the left edge) ends up exactly i rows lower --
-- i.e. column x is down floor(x/2). The plugin runs every pass in one
-- click.
--
-- The commands are one-click by design: *Edit > Isometrify*,
-- *Edit > Isometrify Left Wall* and *Edit > Isometrify Floor*
-- transform the current selection (or the whole active cel)
-- immediately, no dialog, no settings. Only the pixels inside take
-- part: the region is trimmed to them first, so the staircase is
-- counted from the drawing's own edges and empty margin around it
-- (inside a bigger selection) is left alone. Bind the commands to
-- keyboard shortcuts via Edit > Keyboard Shortcuts (search
-- "Isometrify").
--
-- Three commands cover every plane a 2:1 isometric scene has:
--   * "dr"    the front wall: horizontals become "\" staircases;
--   * "ur"    the left wall: the same shear mirrored, so horizontals
--             become "/" staircases. The other two walls of a room
--             are these same two orientations (a mirrored wall is just
--             a flipped drawing);
--   * "floor" the floor (a ceiling is the same plane). The projection
--             (u, v) -> (u - v, (u + v)/2) moves every texture pixel to
--             exactly one output pixel. The diamond is rasterized with
--             full coverage -- solid outline, 2-pixel-wide tips -- and
--             spans w + h pixels, exactly the width of the two walls
--             side by side, so an isometrified square assembles into
--             a cube with matching proportions. The solid outline
--             costs one repeated pixel per row edge (a 16x16 floor is
--             256 moved pixels + 32 outline copies). Texture pixels
--             with odd u + v fall between rows and are dealt out to
--             balance the diamond (at most one pixel of adjustment
--             each). The diamond does not remember the original
--             aspect, so there is no reverse.
--
-- Aseprite loads this file as a plugin (package.json points at it via
-- "contributes.scripts"): init(plugin) at the bottom registers the
-- commands. The transform functions also work as a plain library (the
-- test harness loads the file that way); reverse (un-shear) is kept
-- in the library for completeness and for the tests, but is not
-- exposed in the UI.

local ISOMETRIFY = {}

-- ------------------------------------------------------------------ images --

-- Empty image with the same color spec as `like`, sized w x h.
local function new_image(like, w, h)
  local ok, img = pcall(function()
    local i = like:clone()
    if i.width ~= w or i.height ~= h then i:resize(w, h) end
    i:clear()
    return i
  end)
  if ok then return img end
  -- fallback for color modes where resize is unavailable
  return Image(w, h, like.colorMode)
end

ISOMETRIFY.new_image = new_image

-- ------------------------------------------------------------------- shear --

-- How many pixels column x (0-based, in a w-wide region) slides DOWN.
local function column_shift(x, w, direction)
  if direction == "dr" then        -- "\" wall: horizontals run down-right
    return math.floor(x / 2)
  elseif direction == "ur" then    -- "/" wall: horizontals run up-right
    return math.floor((w - 1 - x) / 2)
  end
  error("isometrify: unknown direction '" .. tostring(direction) .. "'")
end

-- -------------------------------------------------------------------- floor --

-- Project onto the top face at the walls' own scale, so that an
-- isometrified square assembles into a cube with matching proportions:
-- the floor's edges are the same 2:1 staircases the walls produce,
-- and the diamond spans exactly the width the two walls have side by
-- side, with 2-pixel-wide tips to match the walls' front-edge flats.
--
-- The continuous projection is (u, v) -> (u - v, (u + v) / 2): the
-- drawing's x runs down-right, its y runs down-left, and a w x h
-- region lands on a diamond w + h wide and (w + h) / 2 tall. Every
-- texture pixel is MOVED to exactly one output pixel -- nothing is
-- scaled, duplicated or dropped -- except the outline: the diamond
-- is rasterized with full coverage (a solid outline), and each
-- row's outermost pixel is repeated once at each flank to keep that
-- outline solid. A 16x16 square becomes 32x16: 256 moved pixels
-- plus 32 outline copies.
--
-- The lattice detail: a texture pixel with even u + v falls exactly
-- on a pixel row; one with odd u + v falls between two rows. The odd
-- diagonals are therefore dealt out from the top: each row takes the
-- pixels it is still missing, preferring the left side, and the rest
-- falls one row further down, until every row holds exactly as many
-- pixels as it has slots. Within a row the pixels are sorted by
-- u - v and laid from the left, which spreads the half-row adjustment
-- evenly (at most one pixel each). The diamond does not remember the
-- original aspect (only w + h), so there is no reverse.
local function floor_forward(src)
  local w, h = src.width, src.height

  -- rows of the diamond, rasterized with full coverage:
  --   f_min..f_max  the whole row
  --   c_min..c_max  the slots the texture pixels themselves fill;
  --                 the fringe slots repeat the nearest placed pixel
  local rows = {}
  local r = 0
  while true do
    local lo, hi
    if r + 1 <= h / 2 then lo = -2*r - 2
    elseif r >= h / 2 then lo = 2*r - 2*h
    else lo = -h end
    if r + 1 <= w / 2 then hi = 2*r + 2
    elseif r >= w / 2 then hi = 2*w - 2*r
    else hi = w end
    if lo > hi - 1 then break end
    rows[#rows + 1] = {
      f_min = lo, f_max = hi - 1,
      c_min = math.max(-2*r - 1, 2*r + 1 - 2*h),
      c_max = math.min(2*r, 2*w - 2*r - 2),
      list = {}, placed = {},
    }
    r = r + 1
  end

  -- even diagonals go to their exact row; odd ones are dealt out
  local odd = {}
  for v = 0, h - 1 do
    for u = 0, w - 1 do
      local s = u + v
      local t = { u = u, v = v }
      if s % 2 == 0 then
        rows[s / 2 + 1].list[#rows[s / 2 + 1].list + 1] = t
      else
        local diag = odd[s] or {}
        diag[#diag + 1] = t
        odd[s] = diag
      end
    end
  end
  for _, diag in pairs(odd) do
    table.sort(diag, function(a, b) return a.u < b.u end)   -- = by u - v
  end

  -- deal the odd diagonals out, row by row from the top
  local pending = {}
  for i, row in ipairs(rows) do
    for _, t in ipairs(pending) do row.list[#row.list + 1] = t end
    pending = {}
    local slots = math.max(0, row.c_max - row.c_min + 1)
    while #row.list > slots do          -- safety; rows balance exactly
      pending[#pending + 1] = table.remove(row.list)
    end
    local need = slots - #row.list
    local diag = odd[2*i - 1]           -- the odd diagonal above row i
    if diag ~= nil and need > 0 then
      local take = math.min(need, #diag)
      for k = 1, take do row.list[#row.list + 1] = diag[k] end
      for k = take + 1, #diag do pending[#pending + 1] = diag[k] end
    end
  end
  for _, t in ipairs(pending) do        -- never happens; stay lossless
    for i = #rows, 1, -1 do
      if rows[i].c_min <= rows[i].c_max then
        rows[i].list[#rows[i].list + 1] = t
        break
      end
    end
  end

  -- lay each row's texture pixels: sorted by u - v, from c_min
  local x_lo, x_hi = math.huge, -math.huge
  for i, row in ipairs(rows) do
    local list = row.list
    table.sort(list, function(a, b)
      if a.u - a.v ~= b.u - b.v then return a.u - a.v < b.u - b.v end
      return a.u < b.u
    end)
    if row.c_min <= row.c_max then
      for k, t in ipairs(list) do
        t.x = row.c_min + k - 1
        t.y = i - 1
        row.placed[t.x] = t
      end
    end
    if row.f_min < x_lo then x_lo = row.f_min end
    if row.f_max > x_hi then x_hi = row.f_max end
  end

  -- the nearest placed pixel, for an outline slot (same row first)
  local function nearest(i, x)
    local best, bd, br, bx = nil, math.huge, math.huge, math.huge
    for dr = -1, 1 do
      local row = rows[i + dr]
      if row ~= nil then
        for px, t in pairs(row.placed) do
          local d = math.abs(px - x) + math.abs(dr)
          if d < bd or (d == bd and (math.abs(dr) < br
                    or (math.abs(dr) == br and px - x < bx))) then
            best, bd, br, bx = t, d, math.abs(dr), px - x
          end
        end
      end
    end
    return best
  end

  local out = new_image(src, x_hi - x_lo + 1, #rows)
  for i, row in ipairs(rows) do
    for x = row.f_min, row.f_max do
      local t = row.placed[x] or nearest(i, x)
      if t ~= nil then
        out:putPixel(x - x_lo, i - 1, src:getPixel(t.u, t.v))
      end
    end
  end
  return out
end

-- Shear a standalone region image (walls) or project it onto the top
-- face ("floor"). Returns a new image.
--   forward: pixel (x, y)    -> (x, y + shift(x))   result w x (h + d)
--   reverse: pixel (x, y+s)  -> (x, y)              result w x (h - d)
--   where d = floor((w-1)/2). Reverse expects `src` to be wall-shaped
--   (e.g. the output of a forward pass); it undoes the shear. The
--   floor has no reverse (see floor_forward).
function ISOMETRIFY.transform(src, direction, reverse)
  if direction == "floor" then
    if reverse then
      error("isometrify: the floor cannot be un-projected")
    end
    return floor_forward(src)
  end
  local w, h = src.width, src.height
  local d = math.floor((w - 1) / 2)
  local out
  if reverse then
    local oh = math.max(1, h - d)
    out = new_image(src, w, oh)
    for x = 0, w - 1 do
      local s = column_shift(x, w, direction)
      for y = 0, oh - 1 do
        local sy = y + s
        if sy < h then out:putPixel(x, y, src:getPixel(x, sy)) end
      end
    end
  else
    out = new_image(src, w, h + d)
    for x = 0, w - 1 do
      local s = column_shift(x, w, direction)
      for y = 0, h - 1 do
        out:putPixel(x, y + s, src:getPixel(x, y))
      end
    end
  end
  return out
end

-- ------------------------------------------------------------- rectangles --

local function isect(a, b)
  local x0, y0 = math.max(a.x, b.x), math.max(a.y, b.y)
  local x1 = math.min(a.x + a.width,  b.x + b.width)
  local y1 = math.min(a.y + a.height, b.y + b.height)
  if x0 >= x1 or y0 >= y1 then return nil end
  return Rectangle(x0, y0, x1 - x0, y1 - y0)
end

local function hull(a, b)
  local x0, y0 = math.min(a.x, b.x), math.min(a.y, b.y)
  local x1 = math.max(a.x + a.width,  b.x + b.width)
  local y1 = math.max(a.y + a.height, b.y + b.height)
  return Rectangle(x0, y0, x1 - x0, y1 - y0)
end

local function selection_bounds(sprite)
  local ok, sel = pcall(function() return sprite.selection end)
  if not ok or sel == nil then return nil end
  local ok2, empty = pcall(function() return sel.isEmpty end)
  if ok2 and empty then return nil end
  local ok3, b = pcall(function() return sel.bounds end)
  if not ok3 or b == nil or b.width <= 0 or b.height <= 0 then return nil end
  return b
end

-- Bounding rectangle of the non-empty pixels inside region `r` (in
-- sprite coordinates) of the cel image `img` placed at `cb`. A pixel
-- counts as empty when it reads 0 -- transparent in every color
-- mode. Returns nil when the region holds no pixels at all.
--
-- This is what keeps the shear honest: it is counted from the
-- drawing's own edge, so selecting empty margin around a shape
-- neither shifts that margin nor grows the result or the canvas.
local function content_bounds(img, cb, r)
  local x0, y0, x1, y1
  for y = r.y, r.y + r.height - 1 do
    local ly = y - cb.y
    for x = r.x, r.x + r.width - 1 do
      if img:getPixel(x - cb.x, ly) ~= 0 then
        if x0 == nil or x < x0 then x0 = x end
        if x1 == nil or x > x1 then x1 = x end
        if y0 == nil or y < y0 then y0 = y end
        y1 = y
      end
    end
  end
  if x0 == nil then return nil end
  return Rectangle(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
end

local function active_frame_number()
  local f = app.activeFrame
  if type(f) == "number" then return f end
  if f ~= nil then return f.frameNumber end
  return nil
end

-- ------------------------------------------------------------------ apply --

-- Project the selection (or the whole active cel) onto an isometric
-- plane. The working region is first trimmed to the pixels that are
-- really there, so the staircase is counted from the drawing's own
-- edge and empty margin around it is left alone.
-- opts.direction: "dr" (front wall, default), "ur" (left wall) or
-- "floor"; opts.reverse: boolean, walls only;
-- opts.sprite/layer/frame/cel/region: optional overrides (used by tests).
-- Returns true on success, false + reason otherwise.
function ISOMETRIFY.apply(opts)
  opts = opts or {}
  local direction = opts.direction or "dr"
  local reverse = opts.reverse and true or false
  if direction == "floor" and reverse then
    return false, "the floor cannot be un-projected (the diamond does not remember the original aspect)"
  end

  local sprite = opts.sprite or app.activeSprite
  if sprite == nil then return false, "no active sprite" end
  local layer = opts.layer or app.activeLayer
  if layer == nil and sprite.layers ~= nil and sprite.layers[1] ~= nil then
    layer = sprite.layers[1]
  end
  if layer == nil then return false, "no layer to work on" end

  local frame = opts.frame or active_frame_number()
  local cel = opts.cel
  if cel == nil then
    local ok, c = pcall(function() return layer:cel(frame) end)
    if ok then cel = c end
  end
  if cel == nil then
    return false, "the active layer has no pixels in the current frame"
  end
  local img = cel.image
  if img == nil then return false, "the active cel has no image" end
  local cb = cel.bounds

  -- source region, in sprite coordinates
  local r = opts.region or selection_bounds(sprite) or
            Rectangle(cb.x, cb.y, cb.width, cb.height)
  r = isect(r, Rectangle(0, 0, sprite.width, sprite.height))
  if r ~= nil then r = isect(r, cb) end
  if r == nil or r.width < 1 or r.height < 1 then
    return false, "the selection does not overlap the active layer"
  end

  -- Trim the region down to the pixels that are really there: empty
  -- margin inside the selection is not shifted, not cleared, and does
  -- not grow the result or the canvas.
  r = content_bounds(img, cb, r)
  if r == nil then
    return false, "the selection holds no pixels to transform"
  end

  -- pull the region out into a standalone image
  local src = new_image(img, r.width, r.height)
  local lx, ly = r.x - cb.x, r.y - cb.y
  for y = 0, r.height - 1 do
    for x = 0, r.width - 1 do
      src:putPixel(x, y, img:getPixel(lx + x, ly + y))
    end
  end

  local sheared = ISOMETRIFY.transform(src, direction, reverse)
  local out = Rectangle(r.x, r.y, sheared.width, sheared.height)

  -- compose: current cel image, minus the old region, plus the sheared copy
  local u = hull(cb, out)
  local nimg = new_image(img, u.width, u.height)
  local function blit(simg, sx, sy)
    local ok = pcall(function() nimg:drawImage(simg, Point(sx, sy)) end)
    if not ok then nimg:drawImage(simg, sx, sy) end
  end
  blit(img, cb.x - u.x, cb.y - u.y)
  nimg:clear(Rectangle(r.x - u.x, r.y - u.y, r.width, r.height))
  blit(sheared, out.x - u.x, out.y - u.y)

  local ok, err = pcall(function()
    cel.image = nimg
    cel.position = Point(u.x, u.y)

    -- grow the canvas if the result sticks out past the bottom/right edge
    if u.y + u.height > sprite.height then sprite.height = u.y + u.height end
    if u.x + u.width > sprite.width then sprite.width = u.x + u.width end

    -- keep the result selected so it can be nudged into place
    sprite.selection = Selection(out)
  end)
  if not ok then return false, tostring(err) end

  app.refresh()
  return true
end

-- ----------------------------------------------------------------- plugin --

-- Called by Aseprite when the extension loads (plugin API v1.2.18+).
function init(plugin)
  plugin:newCommand{
    id = "Isometrify",
    title = "Isometrify",
    group = "edit_transform",   -- Edit menu, right after the Shift submenu
    onclick = function()
      app.transaction(function()
        local done, msg = ISOMETRIFY.apply({ direction = "dr" })
        if not done then app.alert("Isometrify: " .. (msg or "failed")) end
      end)
    end,
    onenabled = function() return app.activeSprite ~= nil end,
  }
  plugin:newCommand{
    id = "IsometrifyLeftWall",
    title = "Isometrify Left Wall",
    group = "edit_transform",   -- flat, right after Isometrify
    onclick = function()
      app.transaction(function()
        local done, msg = ISOMETRIFY.apply({ direction = "ur" })
        if not done then app.alert("Isometrify Left Wall: " .. (msg or "failed")) end
      end)
    end,
    onenabled = function() return app.activeSprite ~= nil end,
  }
  plugin:newCommand{
    id = "IsometrifyFloor",
    title = "Isometrify Floor",
    group = "edit_transform",   -- flat, right after Isometrify Left Wall
    onclick = function()
      app.transaction(function()
        local done, msg = ISOMETRIFY.apply({ direction = "floor" })
        if not done then app.alert("Isometrify Floor: " .. (msg or "failed")) end
      end)
    end,
    onenabled = function() return app.activeSprite ~= nil end,
  }
end

return ISOMETRIFY
