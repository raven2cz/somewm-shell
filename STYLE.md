# Style Guide — somewm-shell

Code conventions for the somewm-shell Quickshell/QML desktop shell. New
files stay consistent by following this document.

## File headers (QML)

QML has no LDoc, so use a compact C++-style block at the top of the file.

### With `pragma Singleton`

Pragma must be on line 1 (Quickshell requirement). Place the header
immediately after:

```qml
pragma Singleton

// <Component> — <one-line purpose>.
//
// <2–3 lines: what it renders / what it exposes / how it is wired>.
// IPC: somewm-shell:<name> { methods } — OR omit if none.
// Reads: awesome._foo  (if the component reads compositor state).

import QtQuick
// ...
```

### Without pragma

Header on line 1, imports after:

```qml
// <Component> — <one-line purpose>.
//
// <2–3 lines: what it renders / what it exposes / how it is wired>.

import QtQuick
// ...
```

### Scope

- **`services/*.qml`** — every service must have a header. Include IPC
  handler target, polling model (timer / event-driven / reactive), and key
  public properties.
- **`components/*.qml`** — every reusable component must have a header +
  short prose doc on public properties (e.g. `hovered`, `elevated`,
  `accentTint`).
- **Module roots** (e.g. `modules/sidebar/Sidebar.qml`) — must have a
  header. The tabs and sub-components under a module root may omit the
  header and inherit context.
- **Tests** and `deploy.sh` already carry their own shebang/preamble — no
  QML header applies.

## Module init conventions

- **Services are QML singletons** — no explicit setup, lazy-loaded via
  `Core.<Name>` or `Services.<Name>`. If a singleton needs to be reachable
  before any consumer imports it, its consumer (typically `shell.qml`) must
  call a method on it from `Component.onCompleted` to force instantiation.
  A property-access alone can be optimised away by the JS engine.
- **Panels / modules** are instantiated by `core/Panels.qml` via `Variants`
  per screen. New modules register through `shell.qml` + `ModuleLoader` +
  `config.default.json`.
- **Single-owner IPC pattern.** Each `somewm-shell:<name>` target belongs
  to exactly one QML file. If multiple consumers share state (e.g. the
  notification list), they bind to a singleton store (`core/NotifStore.qml`)
  and never replicate the IPC surface.

## Sizing & theming

- **DPI scale everything.** Hard-coded pixel sizes go through
  `Math.round(N * Core.Theme.dpiScale)`. This includes widths, heights,
  spacing, radii and font sizes.
- **Theme tokens only.** All colors come from `Core.Theme` (`accent`, `fgMain`,
  `surfaceContainer`, …). No inline hex values — if a color is missing from
  the theme, add it to `theme.json` and `Theme.qml` rather than hard-coding.
  Widget-category colors (`widgetCpu`, `widgetGpu`, …) must match the
  compositor's wibar palette exactly for cross-surface consistency.
- **Animations via `Core.Anims`.** All durations and easing curves come
  from there; honour `Core.Anims.scale` so `scale = 0` gives reduced
  motion. Prefer MD3 `BezierSpline` curves for premium animations
  (dashboard, carousel, gauges).

## Lazy polling

Heavyweight data sources are gated by visibility flags:

```qml
SystemStats.perfTabActive = dashboardTabIndex === 1
CavaService.mediaTabActive = dashboardTabIndex === 2
```

Always-on polling is reserved for data the wibar needs (base CPU/memory).
Everything else is lazy.

## IPC conventions (Shell → Lua)

Every `somewm-client eval` call writes or reads a namespaced global:

```
awesome._<name>
```

Never `_G.<name>`, never an anonymous top-level. The authoritative
catalogue of handlers and globals lives in [`IPC.md`](IPC.md).

Rules:
- Single-line Lua. Multi-line `eval` is unsupported by the IPC transport.
- No dynamic code construction from user input. Escape strings if they
  originate from config or external sources.
- Keep payloads small and JSON-safe (string / number / boolean / plain
  table). Prefer a structured reply parsed by `JSON.parse` over positional
  stdout scraping.

## Verification

```
plans/scripts/check-headers.sh
```

Minimum-viable grep lint for header presence across Lua and QML. Re-run
after adding new files.
