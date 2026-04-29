# somewm-shell — Claude Code Project Guide

## What this repo is

Quickshell/QML desktop shell for the [somewm](https://github.com/raven2cz/somewm)
Wayland compositor: dashboard, dock, controlpanel, OSD, weather, wallpapers,
collage editor, hotedges, and the IPC/Wayland services that back them.

This is the **release copy** — edit here, deploy to `~/.config/quickshell/somewm/`.

## User & environment

- **User:** Antonín Fischer (raven2cz)
- **OS:** Arch Linux
- **Shell runtime:** Quickshell (QML, Qt6)
- **Compositor:** somewm (raven2cz fork of `trip-zip/somewm`)
- **Config:** [somewm-one](https://github.com/raven2cz/somewm-one) (rc.lua + themes)
- **Sibling fork checkout:** `~/git/github/somewm` (override with `SOMEWM_FORK_PATH`)

## Edit / deploy / restart cycle

```bash
# 1. Edit QML / services / modules in this repo
vim modules/dashboard/Dashboard.qml

# 2. Deploy to active config
./deploy.sh

# 3. Restart Quickshell
kill $(pgrep -f 'qs -c somewm'); qs -c somewm -n -d &
```

**Rule:** Never hand-edit `~/.config/quickshell/somewm/` directly — `deploy.sh`
rsyncs source → config and overwrites direct edits. Clear QML cache after
structural changes:

```bash
rm -rf ~/.cache/quickshell/qmlcache /run/user/$(id -u)/quickshell/by-{id,pid,path}/*
```

## Tests

```bash
bash tests/test-all.sh
# header lint lives in the somewm fork:
bash "${SOMEWM_FORK_PATH:-$HOME/git/github/somewm}/plans/scripts/check-headers.sh"
```

The test suite is standalone-robust: sections that depend on a `somewm-one`
checkout are guarded by `[[ -d "$ONE_DIR" ]]` and skipped if absent. Override
with `SOMEWM_ONE_PATH=/path/to/somewm-one`.

## Path coupling

Runtime references to sibling repos use env-var overrides:

- `SOMEWM_FORK_PATH` — defaults to `$HOME/git/github/somewm` (used by
  `MemoryDetail.qml` for `memory-baseline.md`, `somewm-memory-snapshot.sh`)
- `SOMEWM_ONE_PATH` — defaults to `$HOME/git/github/somewm-one` (used by
  `tests/test-all.sh` sections 16 and 32)

`MemoryDetail.qml` falls back gracefully (stderr message + no-op) if the fork
doc is absent.

## Commit style

Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`. Co-author
trailer for AI-assisted commits:

```
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

## Communication

Komunikuj s uživatelem česky. Commity, kód, komentáře a docs zůstávají anglicky.
