# Isometrify

An [Aseprite](https://aseprite.org) extension that projects flat pixel art
onto a **2:1 isometric wall** — the thing you would otherwise do by hand:
select the rightmost two-pixel strip and nudge it down one, then the
rightmost four and nudge down one, then six, eight, and so on. The plugin
runs every pass in one click.

| flat                           | after _Isometrify_             |
| ------------------------------ | ------------------------------ |
| ![flat](docs/example_flat.png) | ![wall](docs/example_wall.png) |

(The horizontal stripe turns into the classic 2:1 staircase, the vertical
stripe stays perfectly vertical, the block just slides along.)

## Usage

No dialog, no settings. Select a portion of your drawing — or select
nothing to transform the whole active cel — and run _Edit > Isometrify_
(it sits right after the Shift submenu, among the transform commands).
The art is immediately sheared down-right onto the wall:

- verticals stay vertical, horizontals become 2:1 staircases
- the canvas grows if the result needs room
- the result stays selected, so you can nudge it into place
- the whole step is a single undo

**Hotkey:** _Edit > Keyboard Shortcuts_ → search for **Isometrify** → press
your key combination. Every Aseprite command can be bound; that is all a
plugin can do to support hotkeys.

## How it works

An isometric wall is a pure _vertical shear_ of flat art, so no rotation
or scaling is involved:

- vertical lines stay vertical;
- horizontal lines become the classic 2:1 staircase (two across, one down);
- pixel column `x` slides down by `floor(x/2)`, so pairs of columns share
  each step;
- the result's bounding box grows taller by about half the width.

Every source pixel lands on exactly one destination pixel — nothing is
scaled, duplicated or dropped — which makes the transform lossless in all
color modes (RGBA, Grayscale, Indexed) and exactly reversible. That is
also why the hand technique works: each "select more, nudge down" pass
pushes every earlier strip one row further down, so strip pair `i` ends
exactly `i` rows lower.

## Notes & limits

- The transform is **drawn over** existing pixels: opaque pixels of the
  result replace what is under them, but transparent parts do not erase
  art outside the source region (the source region itself is always
  cleared first).
- The selection is used as its **bounding rectangle** (a mask-shaped
  selection is treated as its bounding box).
- It operates on the **active layer and frame** only.
- Linked cels share their image; treat the plugin like any edit if you
  use linked cels across frames.

## Developing

```sh
cd test
/path/to/aseprite -b -script test_isometrify.lua   # 20-check test suite
/path/to/aseprite -b -script probe.lua             # API capability probe
```

`isometrify.lua` doubles as a library: loading it only defines
`ISOMETRIFY.transform` / `ISOMETRIFY.apply` plus the `init(plugin)` hook
that registers the menu command — nothing runs at load time. The command
exposes the down-right wall; the library also keeps the mirrored wall
(`"ur"`) and `reverse` (un-shear) for the tests and future modes.

## Ideas for later

- Floor mode: project top-down art onto the top face of a cube.
- "True projection" 2× wide mode, matching scenes drawn at full
  axonometric scale (one unit = two pixels).
- Multi-layer mode; mask-accurate (non-rectangular) regions.
