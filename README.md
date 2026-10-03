# aseprite-plugins

A home for small [Aseprite](https://aseprite.org) extensions.

| Plugin                    | What it does                                       |
| ------------------------- | -------------------------------------------------- |
| [isometrify](isometrify/) | Project a flat selection onto a 2:1 isometric wall |

## Installing a plugin

Each plugin folder is a standalone Aseprite extension. Either:

- copy the plugin folder (the one containing `package.json`) into Aseprite's
  user `extensions/` folder and restart Aseprite — on macOS that is
  `~/Library/Application Support/aseprite/extensions/`, and the location is
  shown in _Edit > Preferences > Extensions_; or
- build a package with `just package` from the repo root (requires
  [just](https://github.com/casey/just)) and install the resulting
  `dist/isometrify-<version>.aseprite-extension` via
  _Edit > Preferences > Extensions > Add Extension_.

## Developing & testing

Plugins are plain Lua written against the
[Aseprite scripting API](https://aseprite.org/api/). Each plugin ships a
headless test harness that runs without the GUI:

```sh
just test
```

If your Aseprite binary is not at the default macOS path, point the
recipe at it with `just test aseprite=/path/to/aseprite`.
