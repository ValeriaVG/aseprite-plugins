-- GUI-context probe: run with Aseprite in GUI mode (NOT -b), e.g.
--   /Applications/Aseprite.app/Contents/MacOS/aseprite -script gui_probe.lua
-- Verifies the exact dialog construction the plugin performs, plus an
-- apply() pass with pure GUI-context defaults (no option overrides).

local out_path = "/Users/valeria/git/aseprite-plugins/isometrify/test/gui_probe.out"
local outf = io.open(out_path, "w")
local function say(s)
  print(s)
  if outf then outf:write(s .. "\n"); outf:flush() end
end

say("isUIAvailable: " .. tostring(app.isUIAvailable))

local M = dofile("/Users/valeria/git/aseprite-plugins/isometrify/isometrify.lua")

-- 1) dialog construction, exactly as run_dialog does it
local dlg = Dialog("Isometrify probe")
say("Dialog created: " .. tostring(dlg ~= nil))
if dlg == nil then
  say("ERROR: no UI, cannot probe further")
  return
end
say("  dlg.combo     exists: " .. tostring(dlg.combo ~= nil))
say("  dlg.combobox  exists: " .. tostring(dlg.combobox ~= nil))
say("  dlg.check     exists: " .. tostring(dlg.check ~= nil))
say("  dlg.button    exists: " .. tostring(dlg.button ~= nil))
say("  dlg.show      exists: " .. tostring(dlg.show ~= nil))

local DR = [[Down-right  \  (left wall)]]
local UR = [[Up-right  /  (right wall)]]
local combo_fn = dlg.combobox or dlg.combo
if combo_fn == nil then
  say("ERROR: neither combobox nor combo method exists -> this is the bug")
else
  local ok, err = pcall(function()
    combo_fn(dlg, { id = "dir", label = "Wall lean:", option = DR, options = { DR, UR } })
    dlg:check{ id = "rev", text = "Reverse (take art back off the wall)", selected = false }
    dlg:button{ id = "ok", text = "Isometrify" }
    dlg:button{ id = "cancel", text = "Cancel" }
  end)
  if ok then
    say("dialog widgets constructed OK (method: " ..
        (dlg.combobox and "combobox" or "combo") .. ")")
  else
    say("ERROR constructing widgets: " .. tostring(err))
  end
end

-- 2) apply() with pure GUI-context defaults (no sprite/layer/frame overrides)
local spr = Sprite(16, 16)
local cel = spr.layers[1]:cel(1)
local img = Image(8, 8, ColorMode.RGBA)
for y = 0, 7 do
  for x = 0, 7 do
    img:putPixel(x, y, app.pixelColor.rgba(255, 0, 0, 255))
  end
end
cel.image = img
cel.position = Point(2, 3)
pcall(function() app.activeSprite = spr end)
say("activeSprite is our sprite: " .. tostring(app.activeSprite == spr))

local ok, msg = M.apply({ direction = "dr" })
say("apply() in GUI context: ok=" .. tostring(ok) .. " msg=" .. tostring(msg))
if ok then
  say("  cel bounds: " .. tostring(cel.bounds))
  say("  sprite size: " .. spr.width .. "x" .. spr.height)
end

say("gui probe done")
