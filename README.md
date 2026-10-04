# aseprite-plugins

A home for small [Aseprite](https://aseprite.org) extensions.

| Plugin                             | What it does                                                 |
| ---------------------------------- | ------------------------------------------------------------ |
| [isometrify](isometrify/README.md) | Project a flat selection onto 2:1 isometric walls and floors |

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

## License

Everything in this repository is released under the MIT License — see
[LICENSE](LICENSE). Each plugin folder carries a copy of the license so it
ships inside the built `.aseprite-extension` package.

## AI use

The code in this repository was generated with AI assistance: **GLM 5.3**
([Z.ai](https://z.ai)), run via [Ollama Cloud](https://ollama.com) and
driven by Zed Agent, the coding agent built into the [Zed](https://zed.dev)
editor.
