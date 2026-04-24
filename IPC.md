# somewm-shell IPC Reference

Single source of truth for the IPC surface between the somewm compositor (Lua)
and the Quickshell-based shell (QML). New IPC additions should follow these
patterns and extend this document.

## Conventions

- **Lua → Shell**: `qs ipc -c somewm call somewm-shell:<module> <method> [args]`.
  Every method is defined in exactly one `IpcHandler { target: "somewm-shell:<module>" }`
  block. No raw `eval` is ever exposed.
- **Shell → Lua**: `somewm-client eval "<single-line lua>"`. All compositor-
  side state accessed by the shell lives under `awesome._<name>` (no bare
  `_G` pollution).

## Lua → Shell handlers

| Target | File | Methods |
|---|---|---|
| `somewm-shell:panels` | `core/Panels.qml` | `toggle(name)`, `toggleOnScreen(name, screenName)`, `close(name)`, `closeAll()`, `showOsd(type, value)` |
| `somewm-shell:compositor` | `services/Compositor.qml` | `invalidate()`, `setScreen(name)`, `setTag(name)`, `focus(cls)`, `spawn(cmd)` |
| `somewm-shell:audio` | `services/Audio.qml` | `volumeUp()`, `volumeDown()`, `toggleMute()` |
| `somewm-shell:brightness` | `services/Brightness.qml` | `up()`, `down()` |
| `somewm-shell:wallpapers` | `services/Wallpapers.qml` | `switchTheme(name)`, `reloadTheme()` |
| `somewm-shell:portraits` | `services/Portraits.qml` | `refresh()` |
| `somewm-shell:notifications` | `core/NotifStore.qml` | `refresh()` |
| `somewm-shell:collage` | `modules/collage/Collage.qml` | `editToggle()` |

`toggleOnScreen(name, screenName)` pins the panel to a specific output (by
`screen.name`, e.g. `HDMI-A-1`). The pin is consulted by each panel's
`shouldShow` and cleared on close. Used by `memory.lua` / `disk.lua` wibar
left-click so a click on the Samsung TV output opens the detail panel on
that output rather than on whichever output currently holds keyboard focus.
Passing an empty `screenName` falls back to the active-screen heuristic.

Notifications use a single-owner pattern: `core/NotifStore.qml` owns the
`IpcHandler` and the IPC surface (fetch, dismiss, clear, copy). The sidebar
widget (`modules/sidebar/NotifHistory.qml`) and dashboard tab
(`modules/dashboard/NotificationsTab.qml`) are display-only — they bind to
`Core.NotifStore.notifications` and call its functions.

Typical call sites in Lua:
- `plans/project/somewm-one/fishlive/config/keybindings.lua` — panel toggles, OSD
- `plans/project/somewm-one/fishlive/config/shell_ipc.lua` — compositor
  invalidate + setScreen on tag/screen signals
- `plans/project/somewm-one/fishlive/components/notifications.lua` —
  notifications.refresh after each new naughty entry

## Shell → Lua: `awesome._*` globals

| Global | Writer (Lua) | Read by (QML) | Written by (QML) | Purpose |
|---|---|---|---|---|
| `awesome._shell_overlay` | `rc.lua` / keybindings.lua (defaults false) | `keybindings.lua` scroll guards | `core/Panels.qml`, `modules/collage/Collage.qml` | Block tag-scroll/other bindings while an overlay is open |
| `awesome._notif_history` | `fishlive/components/notifications.lua` (appended per notification, capped at 50) | `modules/sidebar/NotifHistory.qml`, `modules/dashboard/NotificationsTab.qml` | Same two QML files (`table.remove`, clear) | Persistent notification history shared across shell restarts |

Pattern: QML writes via `["somewm-client", "eval", "awesome._X = ..."]`, reads
via `["somewm-client", "eval", "return awesome._X"]`.

## Adding new IPC

**New Lua → Shell method:**
1. Pick the right target module (or add a new `somewm-shell:<name>` only if the
   scope is genuinely new — don't splinter).
2. Add the method to the existing `IpcHandler` block in the owner file.
3. Call from Lua with `awful.spawn("qs ipc -c somewm call somewm-shell:X y arg1")`.
4. Update this document.

**New shell → Lua global:**
1. Namespace it `awesome._<name>` — never `_G.name`, never `foo` global.
2. Initialize it defensively on the Lua side
   (`awesome._X = awesome._X or <default>`) so a crashed shell that restarts
   doesn't wedge the compositor.
3. Keep the payload JSON-safe (table of strings/numbers/booleans only).
4. Update this document.

## Security

- No raw `eval()` exposed via IPC in either direction. Typed methods only.
- `somewm-client eval` is privileged; never pass untrusted strings to it.
- IPC targets are authenticated by the somewm socket (same user only).
