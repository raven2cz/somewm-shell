#!/bin/bash
# Deploy somewm-shell to ~/.config/quickshell/somewm/
# Usage: ./deploy.sh [--dry-run]
#
# Copies the somewm-shell project from the repo to the Quickshell config dir.
# *.default.json files are excluded from rsync and seeded only if the target
# file doesn't exist (preserves user edits made in-app).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.config/quickshell/somewm"

if [[ "${1:-}" == "--dry-run" ]]; then
    echo "Dry run — would sync:"
    rsync -av --exclude 'deploy.sh' --exclude '*.default.json' --dry-run "$SCRIPT_DIR/" "$TARGET/"
    exit 0
fi

# Create target directory
mkdir -p "$TARGET"

# Sync (exclude deploy.sh and *.default.json — those are seeded below)
rsync -av --exclude 'deploy.sh' --exclude '*.default.json' "$SCRIPT_DIR/" "$TARGET/"

# Seed *.default.json → *.json only if target doesn't exist (preserve user edits).
# Applies to config.json, collage-layouts.json, and any future seedable defaults.
for default_file in "$SCRIPT_DIR"/*.default.json; do
    [[ -e "$default_file" ]] || continue
    target_name="$(basename "$default_file" .default.json).json"
    target_path="$TARGET/$target_name"
    if [[ ! -f "$target_path" ]]; then
        cp "$default_file" "$target_path"
        echo "Seeded $target_name from defaults"
    fi
done

# Seed theme.json if not exists (ensures QS Theme singleton loads real colors)
THEME_JSON="$HOME/.config/somewm/themes/default/theme.json"
if [[ ! -f "$THEME_JSON" ]]; then
    mkdir -p "$(dirname "$THEME_JSON")"
    bash "$TARGET/theme-export.sh" 2>/dev/null || \
        cp "$TARGET/theme.default.json" "$THEME_JSON" 2>/dev/null || true
    echo "Seeded theme.json"
fi

echo ""
echo "Deployed somewm-shell to $TARGET"
echo "Launch: qs -c somewm"
