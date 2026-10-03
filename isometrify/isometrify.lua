-- Isometrify: project a flat pixel-art selection onto a 2:1 isometric wall.
--
-- The math: an isometric wall is a pure vertical shear of flat art.
--   * Vertical lines stay vertical.
--   * Horizontal lines become the classic 2:1 staircase (two across,
--     one down), because pixel column x slides down by floor(x/2).
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
-- The command is one-click by design: *Edit > Isometrify* shears the
-- current selection (or the whole active cel) down-right immediately,
-- no dialog, no settings. Bind it to a keyboard shortcut via
-- Edit > Keyboard Shortcuts (search "Isometrify").
--
-- Aseprite loads this file as a plugin (package.json points at it via
-- "contributes.scripts"): init(plugin) at the bottom registers the
-- command. The transform functions also work as a plain library (the
-- test harness loads the file that way); direction "ur" (mirrored wall)
-- and reverse (un-shear) are kept in the library for completeness and
-- for the tests, but are not exposed in the UI.

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

-- Shear a standalone region image. Returns a new image.
--   forward: pixel (x, y)    -> (x, y + shift(x))   result w x (h + d)
--   reverse: pixel (x, y+s)  -> (x, y)              result w x (h - d)
--   where d = floor((w-1)/2). Reverse expects `src` to be wall-shaped
--   (e.g. the output of a forward pass); it undoes the shear.
function ISOMETRIFY.transform(src, direction, reverse)
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

local function active_frame_number()
  local f = app.activeFrame
  if type(f) == "number" then return f end
  if f ~= nil then return f.frameNumber end
  return nil
end

-- ------------------------------------------------------------------ apply --

-- Shear the selection (or the whole active cel) onto the wall.
-- opts.direction: "dr" (default) or "ur"; opts.reverse: boolean;
-- opts.sprite/layer/frame/cel/region: optional overrides (used by tests).
-- Returns true on success, false + reason otherwise.
function ISOMETRIFY.apply(opts)
  opts = opts or {}
  local direction = opts.direction or "dr"
  local reverse = opts.reverse and true or false

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

    -- grow the canvas if the wall sticks out past the bottom/right edge
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
end

return ISOMETRIFY
