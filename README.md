# somewm-shell

> A modern desktop shell for [**somewm**](https://github.com/raven2cz/somewm),
> built on [Quickshell](https://quickshell.outfoxxed.me/) (Qt6/QML).
>
> Part of the *AwesomeWM-on-Wayland, at last* stack.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Quickshell](https://img.shields.io/badge/Quickshell-Qt6-blue.svg)](https://quickshell.outfoxxed.me/)
[![Wayland](https://img.shields.io/badge/Wayland-layer--shell-purple.svg)](https://wayland.app/protocols/wlr-layer-shell-unstable-v1)

<!-- screenshot placeholder -->
<p align="center">
  <em>screenshot: dashboard + dock + control panel · to be added</em>
</p>

## What is this?

`somewm-shell` is an overlay desktop shell for the
[somewm](https://github.com/raven2cz/somewm) Wayland compositor. It is an
*overlay complement* to the wibar and Lua widgets shipped by
[somewm-one](https://github.com/raven2cz/somewm-one) — it does not replace
them.

Everything runs natively inside a single Quickshell process. No server, no
HTTP, no WebSocket. State flows over two well-defined channels:

- `qs ipc call somewm-shell:<module> <method>` — Lua pushing events into QML
- `somewm-client eval "<lua>"` — QML pulling state from the compositor

## Features

- **Tabbed dashboard** (bottom-slide, concave top edge) with four tabs:
  Home · Performance · Media · Notifications. MD3 `BezierSpline` motion.
- **Dock** (bottom-left) with auto-detected running apps via
  `foreign-toplevel-management`, pinning, hover preview cards.
- **Control panel** (bottom-right) — volume, mic input, brightness.
- **Hot screen edges** — hover-activated corners and center strip for
  dock / dashboard / control panel.
- **Wallpaper picker** with isometric skew carousel and per-tag overrides.
- **Weather, collage, OSD** modules.
- **Per-tab lazy polling** — Cava, GPU and temperature sensors only run
  when their tab is visible.
- **Single-owner notification store** — both sidebar and dashboard bind to
  one `NotifStore` singleton that owns the IPC and the 50-entry history.
- **Reactive theme** — `theme.json` is actively watched via Quickshell's `FileView`. Changing the
  wallpaper automatically re-exports colors from Lua, instantly re-rendering the entire UI without a restart.

## Requirements

- [Quickshell](https://quickshell.outfoxxed.me/) (main or latest release)
- [`somewm`](https://github.com/raven2cz/somewm) compositor
- [`somewm-one`](https://github.com/raven2cz/somewm-one) (recommended —
  provides the `somewm-client eval` globals and push-IPC integration)
- Qt6, `wl-clipboard`, `wpctl` (PipeWire), `brightnessctl`
- Optional: `cava` (Media-tab visualizer), `nmcli`, `nvidia-smi`

## Quick start

```bash
git clone https://github.com/raven2cz/somewm-shell.git
cd somewm-shell

# Deploy to Quickshell's config directory
./deploy.sh

# Launch (from a running somewm session)
qs -c somewm
```

`somewm-one` auto-spawns `qs -c somewm -n -d` from `rc.lua`, so once both
are installed the shell comes up with the session.

## Troubleshooting

- **Shell fails to launch**: Run `qs -c somewm` manually in a terminal to check for QML syntax errors or missing Qt6 modules.
- **Dock is empty**: Ensure your apps support the `foreign-toplevel-management` Wayland protocol. XWayland clients may have limited support.
- **Volume/Brightness controls don't work**: Verify that `wpctl` (for audio) and `brightnessctl` (for backlight) are installed and functioning on your system.
- **Theme changes don't apply**: Ensure `Core.Theme` is properly watching the generated `theme.json` file. Run `theme-export.sh` manually from `somewm-one` to force an update.

## Documentation

| Document | What's in it |
|----------|--------------|
| [**GUIDE.md**](GUIDE.md) | Architecture, services, modules, design principles, animation system, theme system, adding new modules |
| [**IPC.md**](IPC.md) | Authoritative Lua ↔ Shell IPC catalogue — every handler and every `awesome._*` global |
| [**STYLE.md**](STYLE.md) | QML header templates, singleton patterns, DPI scaling, theme-token rules |
| [somewm-one GUIDE](https://github.com/raven2cz/somewm-one/blob/main/GUIDE.md) | The Lua side — rc.lua orchestration, fishlive framework, `.setup()` convention |

## Repository layout

```
somewm-shell/
├── shell.qml             # Entry point (ShellRoot + ModuleLoaders)
├── deploy.sh             # Sync → ~/.config/quickshell/somewm/
├── config.default.json   # Module enable/disable + animation scale
├── theme.default.json    # Fallback theme colors
│
├── core/                 # Framework singletons
│   ├── Theme.qml         # Colors / fonts / spacing / dpiScale
│   ├── Anims.qml         # Durations + MD3 BezierSpline curves
│   ├── Config.qml        # Module enable/disable (watches config.json)
│   ├── Panels.qml        # Panel visibility + exclusivity + tab routing
│   ├── NotifStore.qml    # Single-owner notification IPC + history
│   └── Constants.qml     # Dashboard dimensions, gauge sizes, …
│
├── components/           # 25 reusable UI primitives
├── services/             # 11 data-source singletons
├── modules/              # dashboard, dock, controlpanel, hotedges,
│                         # weather, wallpapers, collage, osd, …
└── tests/                # Structural + syntax + import lint
```

## Architecture overview

```
somewm (C compositor + Lua API)
    │
    ├─ Lua signals → awful.spawn("qs ipc call somewm-shell:… ") [PUSH]
    ├─ somewm-client eval "<lua>"                          [QUERY]
    └─ wlr-layer-shell protocol                            [SURFACES]
                                                 │
                                                 ▼
somewm-shell (Quickshell / QML)
    ├─ Services       — IPC, D-Bus, procfs, Wayland protocols
    ├─ Core           — Theme, Anims, Panels, Config, NotifStore
    └─ Modules        — dashboard / dock / controlpanel / hotedges / …
```

See [GUIDE.md](GUIDE.md) for the full architecture.

## Contributing

1. Edit QML under `plans/project/somewm-shell/` (or your fork).
2. Add a header (see [STYLE.md](STYLE.md)).
3. Extend `IPC.md` if you add or change an IPC surface.
4. Run tests and the header lint:
   ```bash
   bash tests/test-all.sh
   bash ../../scripts/check-headers.sh
   ```
5. Commit with a conventional message (`feat:`, `fix:`, `refactor:`,
   `docs:`).

## Credits

Built by studying and adapting excellent prior work — all attributions
below link to the original repositories:

- **[Quickshell](https://quickshell.outfoxxed.me/)** by
  [@outfoxxed](https://git.outfoxxed.me/outfoxxed) — the Qt/QML desktop
  shell toolkit this project is built on.
  Source: [git.outfoxxed.me/quickshell/quickshell](https://git.outfoxxed.me/quickshell/quickshell)
  (GitHub mirror: [quickshell-mirror/quickshell](https://github.com/quickshell-mirror/quickshell)).
- **[Caelestia shell](https://github.com/caelestia-dots/shell)** by
  [@caelestia-dots](https://github.com/caelestia-dots) — the most
  significant design and code inspiration. The dashboard (Home /
  Performance / Media tabs), notification swipe-to-dismiss pattern,
  progress-ring media player, resource bars, concave-edge panel shape
  and MD3 animation taxonomy all trace back to Caelestia. Source files
  across `modules/dashboard/`, `modules/border/` and
  `core/Constants.qml` carry `Caelestia-inspired` attributions inline.
- **[end_4 / dots-hyprland](https://github.com/end-4/dots-hyprland)** —
  the Quickshell configuration that inspired Caelestia and, transitively,
  this project. Worth studying if you want to see how far Quickshell can
  be pushed.
- **[ilyamiro / imperative-dots](https://github.com/ilyamiro/imperative-dots)**
  ([profile](https://github.com/ilyamiro)) — the isometric-skew
  wallpaper carousel in `components/WallpaperCarousel.qml` is a faithful
  adaptation of ilyamiro's original concept.
- **[Material Design 3](https://m3.material.io/)** — motion language
  (`BezierSpline` curves, `emphasized` / `expressive` / `standard`
  tokens) used throughout the animation system.

## License

**MIT**
