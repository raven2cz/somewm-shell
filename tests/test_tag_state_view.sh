#!/bin/bash
# Test: tag-state view — resolved wallpapers IPC, clear_user_wallpaper safety
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1 — $2"; }

echo ""
echo "=== Tag-State View Tests ==="
echo ""

# Check compositor is running
if ! somewm-client ping &>/dev/null; then
    echo "SKIP: compositor not running"
    exit 0
fi

# Test 1: get_resolved_json returns valid JSON array
RESOLVED=$(somewm-client eval 'return require("fishlive.services.wallpaper").get_resolved_json()' 2>/dev/null | tail -n +2)
if echo "$RESOLVED" | python3 -m json.tool &>/dev/null; then
    pass "get_resolved_json returns valid JSON"
else
    fail "get_resolved_json" "invalid JSON: $RESOLVED"
fi

# Test 2: resolved JSON has tag field
if echo "$RESOLVED" | grep -q '"tag"'; then
    pass "resolved JSON contains tag field"
else
    fail "resolved JSON" "missing tag field"
fi

# Test 3: resolved JSON has path field
if echo "$RESOLVED" | grep -q '"path"'; then
    pass "resolved JSON contains path field"
else
    fail "resolved JSON" "missing path field"
fi

# Test 4: resolved JSON has isUserOverride field
if echo "$RESOLVED" | grep -q '"isUserOverride"'; then
    pass "resolved JSON contains isUserOverride field"
else
    fail "resolved JSON" "missing isUserOverride field"
fi

# Test 5: resolved JSON has entries for all tags
TAG_COUNT=$(echo "$RESOLVED" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
EXPECTED_TAGS=$(somewm-client eval 'return #(require("awful").screen.focused().tags)' 2>/dev/null | tail -n +2)
if [[ "$TAG_COUNT" == "$EXPECTED_TAGS" ]]; then
    pass "resolved JSON has $TAG_COUNT entries (matches tag count)"
else
    fail "tag count" "expected $EXPECTED_TAGS, got $TAG_COUNT"
fi

# Test 6: all resolved paths point to existing files
BAD_PATHS=$(echo "$RESOLVED" | python3 -c "
import sys, json, os
items = json.load(sys.stdin)
bad = [i['path'] for i in items if i['path'] and not os.path.isfile(i['path'])]
print(len(bad))
" 2>/dev/null)
if [[ "$BAD_PATHS" == "0" ]]; then
    pass "all resolved paths point to existing files"
else
    fail "resolved paths" "$BAD_PATHS paths point to missing files"
fi

# Test 7: clear_user_wallpaper rejects path traversal
RESULT=$(somewm-client eval 'return tostring(require("fishlive.services.wallpaper").clear_user_wallpaper("../etc"))' 2>/dev/null | tail -n +2)
if [[ "$RESULT" == "false" ]]; then
    pass "clear_user_wallpaper rejects ../ traversal"
else
    fail "path traversal" "expected false, got $RESULT"
fi

# Test 8: clear_user_wallpaper rejects empty string
RESULT=$(somewm-client eval 'return tostring(require("fishlive.services.wallpaper").clear_user_wallpaper(""))' 2>/dev/null | tail -n +2)
if [[ "$RESULT" == "false" ]]; then
    pass "clear_user_wallpaper rejects empty string"
else
    fail "empty tag" "expected false, got $RESULT"
fi

# Test 9: clear_user_wallpaper rejects special chars
RESULT=$(somewm-client eval "return tostring(require('fishlive.services.wallpaper').clear_user_wallpaper('tag;rm'))" 2>/dev/null | tail -n +2)
if [[ "$RESULT" == "false" ]]; then
    pass "clear_user_wallpaper rejects special chars"
else
    fail "special chars" "expected false, got $RESULT"
fi

# Test 10: isUserOverride matches actual user-wallpapers dir
USER_WP_DIR=$(somewm-client eval 'return require("fishlive.services.wallpaper")._user_wppath or ""' 2>/dev/null | tail -n +2)
if [[ -n "$USER_WP_DIR" ]]; then
    OVERRIDE_COUNT=$(echo "$RESOLVED" | python3 -c "
import sys, json
items = json.load(sys.stdin)
print(sum(1 for i in items if i['isUserOverride']))
" 2>/dev/null)
    FILE_COUNT=$(find "$USER_WP_DIR" -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.webp" -o -name "*.jpeg" \) 2>/dev/null | wc -l)
    if [[ "$OVERRIDE_COUNT" == "$FILE_COUNT" ]]; then
        pass "isUserOverride count ($OVERRIDE_COUNT) matches user-wallpapers files ($FILE_COUNT)"
    else
        fail "override count" "JSON says $OVERRIDE_COUNT, disk has $FILE_COUNT files"
    fi
else
    pass "user-wallpapers dir not set (no overrides expected)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
