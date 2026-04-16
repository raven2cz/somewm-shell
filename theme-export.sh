#!/bin/bash
# theme-export.sh — atomic write, no cjson dependency, full export
# Exports somewm Lua theme colors to theme.json for somewm-shell consumption.
# Falls back to committed default if compositor is not running.

set -euo pipefail

THEME_JSON="$HOME/.config/somewm/themes/default/theme.json"
THEME_TMP="${THEME_JSON}.tmp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FALLBACK="$SCRIPT_DIR/theme.default.json"

# Ensure target directory exists
mkdir -p "$(dirname "$THEME_JSON")"

# Try live export from running compositor (single-line — IPC requires it)
if somewm-client eval 'local b = require("beautiful"); local p = {}; local function a(k,v) p[#p+1] = string.format("  %q: %q", k, tostring(v or "")) end; a("bg_base", b.bg_normal); a("bg_surface", b.bg_focus); a("bg_overlay", b.bg_minimize); a("fg_main", b.fg_focus); a("fg_dim", b.fg_normal); a("fg_muted", b.fg_minimize); a("accent", b.border_color_active); a("accent_dim", b.border_color_marked); a("urgent", b.bg_urgent); a("green", "#98c379"); a("font_ui", "Geist"); a("font_mono", "Geist Mono"); a("widget_cpu", b.widget_cpu_color); a("widget_gpu", b.widget_gpu_color); a("widget_memory", b.widget_memory_color); a("widget_disk", b.widget_disk_color); a("widget_network", b.widget_network_color); a("widget_volume", b.widget_volume_color); return "{\n" .. table.concat(p, ",\n") .. "\n}"' 2>/dev/null | tail -n +2 > "$THEME_TMP"; then
    # Write directly into target (not mv — mv replaces inode and breaks
    # QML FileView inotify watcher). tail -n +2 strips "OK" status line.
    cat "$THEME_TMP" > "$THEME_JSON"
    rm -f "$THEME_TMP"
    echo "Exported theme to $THEME_JSON"
else
    echo "Compositor not running, using fallback theme"
    # Fallback: copy committed default theme.json
    cp "$FALLBACK" "$THEME_JSON" 2>/dev/null
fi
