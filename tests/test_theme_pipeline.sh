#!/bin/bash
# Test: theme pipeline — deploy seeds theme.json, export script works
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1 — $2"; }

echo ""
echo "=== Theme Pipeline Tests ==="
echo ""

SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEME_JSON="$HOME/.config/somewm/themes/default/theme.json"

# Test 1: theme-export.sh exists and is executable
if [[ -x "$SHELL_DIR/theme-export.sh" ]]; then
    pass "theme-export.sh exists and is executable"
else
    fail "theme-export.sh" "not found or not executable at $SHELL_DIR/theme-export.sh"
fi

# Test 2: theme.default.json exists (fallback)
if [[ -f "$SHELL_DIR/theme.default.json" ]]; then
    pass "theme.default.json fallback exists"
else
    fail "theme.default.json" "fallback not found"
fi

# Test 3: theme.default.json is valid JSON
if python3 -c "import json; json.load(open('$SHELL_DIR/theme.default.json'))" 2>/dev/null; then
    pass "theme.default.json is valid JSON"
else
    fail "theme.default.json" "invalid JSON"
fi

# Test 4: theme.json exists on disk
if [[ -f "$THEME_JSON" ]]; then
    pass "theme.json exists at $THEME_JSON"
else
    fail "theme.json" "not found at $THEME_JSON"
fi

# Test 5: theme.json is valid JSON with required keys
if python3 -c "
import json, sys
d = json.load(open('$THEME_JSON'))
required = ['bg_base', 'accent', 'fg_main', 'fg_dim']
missing = [k for k in required if k not in d]
if missing:
    print('missing keys:', missing, file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
    pass "theme.json has required color keys"
else
    fail "theme.json" "missing required keys (bg_base, accent, fg_main, fg_dim)"
fi

# Test 6: deploy.sh excludes config.default.json (not *.default.json)
if grep -q "exclude 'config.default.json'" "$SHELL_DIR/deploy.sh"; then
    pass "deploy.sh excludes only config.default.json"
else
    fail "deploy.sh" "still uses *.default.json exclude (blocks theme.default.json)"
fi

# Test 7: deploy.sh has theme.json seeding logic
if grep -q "theme.json" "$SHELL_DIR/deploy.sh" && grep -q "theme-export.sh" "$SHELL_DIR/deploy.sh"; then
    pass "deploy.sh has theme.json seeding logic"
else
    fail "deploy.sh" "missing theme.json seeding"
fi

# Test 8: deployed theme-export.sh exists
DEPLOYED="$HOME/.config/quickshell/somewm/theme-export.sh"
if [[ -x "$DEPLOYED" ]]; then
    pass "theme-export.sh deployed to $DEPLOYED"
else
    fail "theme-export.sh" "not deployed to $DEPLOYED"
fi

# Test 9: deployed theme.default.json exists (fallback for export script)
DEPLOYED_FALLBACK="$HOME/.config/quickshell/somewm/theme.default.json"
if [[ -f "$DEPLOYED_FALLBACK" ]]; then
    pass "theme.default.json deployed as fallback"
else
    fail "theme.default.json" "not deployed to $DEPLOYED_FALLBACK"
fi

# Test 10: Wallpapers.qml calls themeExportProc on startup
if grep -q "themeExportProc.running = true" "$SHELL_DIR/services/Wallpapers.qml"; then
    pass "Wallpapers.qml calls themeExportProc on startup"
else
    fail "Wallpapers.qml" "missing themeExportProc on startup"
fi

echo ""
echo "$PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
