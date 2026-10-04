-- Development probe: reports which Aseprite scripting APIs this build
-- exposes and their exact semantics, so the plugin can be written
-- against facts instead of memory.
--
-- Run: /Applications/Aseprite.app/Contents/MacOS/aseprite -b -script probe.lua

local function P(desc, f)
  local ok, a, b = pcall(f)
  if ok then
    print("ok   " .. desc .. " -> " .. tostring(a) ..
      (b ~= nil and (" ; " .. tostring(b)) or ""))
  else
    print("ERR  " .. desc .. " -> " .. tostring(a))
  end
  return ok, a
end

local pc = app.pixelColor
local RED = pc.rgba(255, 0, 0, 255)
local BLUE = pc.rgba(0, 0, 255, 255)

print("== version ==")
P("app.version", function() return app.version end)

print("== Image construction ==")
local img
P("Image(4,3,ColorMode.RGBA)",
  function() img = Image(4, 3, ColorMode.RGBA) return img.width .. "x" .. img.height end)

print("== Image methods present ==")
for _, m in ipairs({ "drawPixel", "putPixel", "getPixel", "clone", "resize",
                     "clear", "drawImage", "colorMode", "spec" }) do
  print("  " .. m .. " = " .. tostring(img ~= nil and img[m] ~= nil))
end

print("== pixel write semantics (raw vs alpha blend) ==")
P("drawPixel(0,0,blue128) over red", function()
  local i = Image(4, 3, ColorMode.RGBA)
  i:drawPixel(0, 0, RED)
  i:drawPixel(0, 0, pc.rgba(0, 0, 255, 128))
  local v = i:getPixel(0, 0)
  return pc.rgbaR(v) .. "," .. pc.rgbaG(v) .. "," .. pc.rgbaB(v) .. "," .. pc.rgbaA(v) ..
    "  (raw=0,0,255,128  blend~127,0,127,255)"
end)
P("putPixel(0,0,blue128) over red", function()
  local i = Image(4, 3, ColorMode.RGBA)
  i:putPixel(0, 0, RED)
  i:putPixel(0, 0, pc.rgba(0, 0, 255, 128))
  local v = i:getPixel(0, 0)
  return pc.rgbaR(v) .. "," .. pc.rgbaG(v) .. "," .. pc.rgbaB(v) .. "," .. pc.rgbaA(v)
end)

print("== image helpers ==")
P("clone + resize + clear", function()
  local b = img:clone()
  b:resize(10, 12)
  b:clear()
  return b.width .. "x" .. b.height .. " colorMode=" .. tostring(b.colorMode)
end)
P("clear(Rectangle)", function()
  local i = Image(8, 8, ColorMode.RGBA)
  i:drawPixel(2, 2, RED)
  i:clear(Rectangle(0, 0, 4, 4))
  return "cleared=" .. tostring(i:getPixel(2, 2) == 0) .. " kept=" .. tostring(i:getPixel(5, 5))
end)

print("== Sprite ==")
local spr
P("Sprite(16,16)", function() spr = Sprite(16, 16) return spr end)
P("app.activeSprite == new sprite", function() return app.activeSprite == spr end)
P("app.activeLayer.name", function() return app.activeLayer and app.activeLayer.name end)
P("app.activeFrame (type)", function()
  local f = app.activeFrame
  return tostring(f) .. " type=" .. type(f)
end)
P("app.activeFrame.frame", function() return app.activeFrame.frame end)
P("app.activeFrame.frameNumber", function() return app.activeFrame.frameNumber end)
local layer = spr.layers[1]
P("layers[1]:cel(1)", function()
  local c = layer:cel(1)
  return c == nil and "nil" or tostring(c)
end)
P("#spr.cels", function() return #spr.cels end)

print("== cel creation ==")
P("Cel(Image)", function() local c = Cel(Image(8, 8, ColorMode.RGBA)) return tostring(c) end)
P("spr:newCel(layer, 1, img, Point(2,3))", function()
  local cimg = Image(8, 8, ColorMode.RGBA)
  cimg:putPixel(0, 0, RED)
  local c = spr:newCel(layer, 1, cimg, Point(2, 3))
  return "cel=" .. tostring(layer:cel(1) ~= nil) .. " bounds=" .. tostring(layer:cel(1) and layer:cel(1).bounds)
end)
P("cel.image/position assignment", function()
  local c = layer:cel(1)
  if c == nil then error("no cel to test with") end
  local big = Image(10, 14, ColorMode.RGBA)
  big:putPixel(3, 3, BLUE)
  c.image = big
  c.position = Point(1, 2)
  return "bounds=" .. tostring(c.bounds) .. " px(4,5)=" .. tostring(c.image:getPixel(3, 3) == BLUE)
end)

print("== canvas size ==")
P("spr.height = 20", function() spr.height = 20 return spr.height end)
P("spr.width = 22", function() spr.width = 22 return spr.width end)

print("== selection ==")
P("Selection(Rectangle)", function() return Selection(Rectangle(2, 3, 4, 5)) end)
P("spr.selection = Selection(...)", function()
  spr.selection = Selection(Rectangle(2, 3, 4, 5))
  return "isEmpty=" .. tostring(spr.selection.isEmpty) .. " bounds=" .. tostring(spr.selection.bounds)
end)

print("== drawImage arg styles ==")
P("dst:drawImage(src, Point(2,2))", function()
  local dst, src = Image(16, 16, ColorMode.RGBA), Image(4, 3, ColorMode.RGBA)
  src:putPixel(1, 1, RED)
  dst:drawImage(src, Point(2, 2))
  return "landed=" .. tostring(dst:getPixel(3, 3) == RED)
end)
P("dst:drawImage(src, 2, 2)", function()
  local dst, src = Image(16, 16, ColorMode.RGBA), Image(4, 3, ColorMode.RGBA)
  src:putPixel(1, 1, RED)
  dst:drawImage(src, 2, 2)
  return "landed=" .. tostring(dst:getPixel(3, 3) == RED)
end)

print("== transaction / refresh ==")
P("app.transaction(fn)", function() app.transaction(function() end) return "ok" end)
P("app.refresh()", function() app.refresh() return "ok" end)

print("== saveAs ==")
P("spr:saveAs ../docs/probe.png", function()
  spr:saveAs("../docs/probe.png")   -- relative to isometrify/test
  return "saved"
end)

print("probe done")
