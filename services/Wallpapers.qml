pragma Singleton

// Wallpapers — wallpaper browsing, per-tag overrides, and theme switching.
//
// Scans folders, caches thumbnails, tracks current wallpaper and per-tag
// overrides pushed from the compositor, and applies themes via swww + pywal.
// IPC: somewm-shell:wallpapers { switchTheme, reloadTheme }

import QtQuick
import Quickshell
import Quickshell.Io
import "../core" as Core

Singleton {
    id: root

    // Current wallpaper path (from compositor)
    property string currentWallpaper: ""

    // List of { path, name } objects — wallpapers from activeFolder
    property var wallpapers: []

    property bool loading: false

    // Thumbnail cache directory
    readonly property string thumbDir: Quickshell.env("HOME") + "/.cache/somewm-shell/wallpaper_thumbs"
    readonly property string thumbDirUrl: Core.FileUtil.fileUrl(thumbDir)

    // Apply theme toggle — persisted in config.json
    property bool applyTheme: {
        var cfg = Core.Config._data
        return cfg && cfg.wallpapers && cfg.wallpapers.applyTheme !== undefined
            ? cfg.wallpapers.applyTheme : true
    }

    // Per-tag override map from compositor { "1": "/path/...", ... }
    property var overrides: ({})

    // === Folder browsing ===

    // Browse folders for filmstrip: [{name, path, isTheme}]
    property var browseFolders: []
    // Currently selected folder in filmstrip
    property string activeFolder: ""
    // Theme wallpapers directory (from compositor)
    property string themeWallpapersDir: ""
    // Raw browse_dirs from compositor config
    property var browseDirs: []
    // Ready flags for async folder building (both must be true)
    property bool _themeWpDirReady: false
    property bool _subdirsReady: false

    // Whether we're showing the virtual tag-state view (resolved wallpapers per tag)
    property bool isThemeView: false


    // === Tag selector ===

    // Tag names from compositor: ["1","2",...,"9"]
    property var tagList: []
    // Currently selected tag for wallpaper assignment
    property string selectedTag: ""

    // === Scan folder for wallpapers ===

    function scanFolder(folderPath) {
        root.isThemeView = false
        root.activeFolder = folderPath
        root.loading = true
        scanProc.command = ["find", "-L", folderPath,
            "-maxdepth", "1", "-type", "f",
            "(", "-name", "*.jpg", "-o", "-name", "*.jpeg",
            "-o", "-name", "*.png", "-o", "-name", "*.webp", ")"]
        scanProc.running = true
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n")
                var result = []
                lines.forEach(function(line) {
                    if (!line) return
                    var name = line.split("/").pop()
                    result.push({ path: line, name: name })
                })
                result.sort(function(a, b) { return a.name.localeCompare(b.name) })
                root.wallpapers = result
                root.loading = false
                // Generate thumbnails for this folder
                root._generateThumbnails(root.activeFolder)
            }
        }
    }

    // === Resolved wallpapers (virtual tag-state view) ===

    property bool _pendingResolvedRefresh: false

    function refreshResolvedWallpapers() {
        root.isThemeView = true
        root.loading = true
        if (resolvedProc.running) {
            // Process already in flight — schedule re-run after it completes
            root._pendingResolvedRefresh = true
            return
        }
        resolvedProc.running = true
    }

    Process {
        id: resolvedProc
        command: ["somewm-client", "eval",
            "return require('fishlive.services.wallpaper').get_resolved_json()"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Guard: user may have switched to a real folder while IPC was in flight
                if (!root.isThemeView) return
                var raw = text.trim()
                var nl = raw.indexOf("\n")
                var json = nl >= 0 ? raw.substring(nl + 1) : raw
                try {
                    var items = JSON.parse(json)
                    var result = items.filter(function(item) {
                        return item.path && item.path !== ""
                    }).map(function(item) {
                        return {
                            path: item.path,
                            name: item.path.split("/").pop(),
                            tag: item.tag,
                            isUserOverride: item.isUserOverride
                        }
                    })
                    root.wallpapers = result
                } catch (e) {
                    console.error("Resolved wallpapers parse error:", e)
                    root.wallpapers = []
                }
                root.loading = false
            }
        }
        onRunningChanged: {
            // Re-run if a refresh was requested while we were busy
            if (!running && root._pendingResolvedRefresh) {
                root._pendingResolvedRefresh = false
                root.refreshResolvedWallpapers()
            }
        }
    }

    // === Clear user-wallpaper (delete from disk, revert to default) ===

    function clearUserWallpaper(tagName) {
        var safe = _luaEscape(tagName)
        clearUserWpProc.command = ["somewm-client", "eval",
            "require('fishlive.services.wallpaper').clear_user_wallpaper('" + safe + "')"]
        clearUserWpProc.running = true
    }

    Process {
        id: clearUserWpProc
        onRunningChanged: {
            if (!running) {
                root.refreshCurrent()
                root.refreshOverrides()
                if (root.isThemeView) root.refreshResolvedWallpapers()
            }
        }
    }

    // Full refresh: fetch dirs from compositor, build folder list, scan first folder
    function refresh() {
        root._themeWpDirReady = false
        root._subdirsReady = false
        refreshThemeWpDir()
        refreshBrowseDirs()
        refreshTagList()
        refreshSelectedTag()
        refreshCurrent()
        refreshOverrides()
        refreshThemes()
    }

    // === Thumbnail generation ===

    function _generateThumbnails(folderPath) {
        if (!folderPath) return
        var thumbDirPath = root.thumbDir
        // Pass paths as positional args to avoid shell injection and quoting issues
        thumbGenProc.command = ["bash", "-c",
            "src_dir=\"$1\"; thumb_dir=\"$2\"\n" +
            "mkdir -p \"$thumb_dir\"\n" +
            "CMD=magick; command -v magick &>/dev/null || CMD=convert\n" +
            "for f in \"$src_dir\"/*.{jpg,jpeg,png,webp}; do\n" +
            "  [ -f \"$f\" ] || continue\n" +
            "  name=$(basename \"$f\")\n" +
            "  thumb=\"$thumb_dir/$name\"\n" +
            "  [ -f \"$thumb\" ] && continue\n" +
            "  $CMD \"$f\" -resize x420 -quality 70 \"$thumb\" 2>/dev/null &\n" +
            "  [ $(jobs -r | wc -l) -ge 4 ] && wait -n\n" +
            "done\n" +
            "wait",
            "bash", folderPath, thumbDirPath]
        thumbGenProc.running = true
    }

    Process {
        id: thumbGenProc
    }

    // === Compositor IPC: current wallpaper ===

    function refreshCurrent() {
        currentProc.running = true
    }

    Process {
        id: currentProc
        command: ["somewm-client", "eval",
            "return require('fishlive.services.wallpaper').get_current()"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim()
                var nl = raw.indexOf("\n")
                var path = nl >= 0 ? raw.substring(nl + 1) : raw
                if (path && path !== "OK") root.currentWallpaper = path
            }
        }
    }

    // === Compositor IPC: focused tag (sync selectedTag on picker open) ===

    function refreshSelectedTag() {
        focusedTagProc.running = true
    }

    Process {
        id: focusedTagProc
        command: ["somewm-client", "eval",
            "local s = require('awful').screen.focused(); " +
            "local t = s and s.selected_tag; " +
            "return t and t.name or '1'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim()
                var nl = raw.indexOf("\n")
                var tag = nl >= 0 ? raw.substring(nl + 1) : raw
                if (tag && tag !== "OK") root.selectedTag = tag
            }
        }
    }

    // === Refresh filmstrip (rescan browse dirs on picker open) ===

    function refreshBrowseFolders() {
        _subdirsReady = false
        refreshBrowseDirs()
    }

    // === Compositor IPC: overrides ===

    function refreshOverrides() {
        overridesProc.running = true
    }

    Process {
        id: overridesProc
        command: ["somewm-client", "eval",
            "return require('fishlive.services.wallpaper').get_overrides_json()"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim()
                var nl = raw.indexOf("\n")
                var json = nl >= 0 ? raw.substring(nl + 1) : raw
                try {
                    root.overrides = JSON.parse(json)
                } catch (e) {
                    root.overrides = {}
                }
            }
        }
    }

    // === Compositor IPC: theme wallpapers dir ===

    function refreshThemeWpDir() {
        themeWpDirProc.running = true
    }

    Process {
        id: themeWpDirProc
        command: ["somewm-client", "eval",
            "return require('fishlive.services.wallpaper').get_theme_wallpapers_dir()"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim()
                var nl = raw.indexOf("\n")
                var dir = nl >= 0 ? raw.substring(nl + 1) : raw
                if (dir && dir !== "OK") {
                    root.themeWallpapersDir = dir
                }
                root._themeWpDirReady = true
                if (root._subdirsReady) root._buildBrowseFolders()
            }
        }
    }

    // === Compositor IPC: browse directories ===

    function refreshBrowseDirs() {
        browseDirsProc.running = true
    }

    Process {
        id: browseDirsProc
        command: ["somewm-client", "eval",
            "return require('fishlive.services.wallpaper').get_browse_dirs_json()"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim()
                var nl = raw.indexOf("\n")
                var json = nl >= 0 ? raw.substring(nl + 1) : raw
                try {
                    root.browseDirs = JSON.parse(json)
                } catch (e) {
                    root.browseDirs = []
                }
                // Scan for subdirectories
                root._scanSubdirs()
            }
        }
    }

    // Scan one-level-deep subdirectories from browse_dirs
    property var _subdirsRaw: []

    function _scanSubdirs() {
        if (root.browseDirs.length === 0) {
            root._subdirsRaw = []
            root._subdirsReady = true
            if (root._themeWpDirReady) root._buildBrowseFolders()
            return
        }
        // Pass dirs as positional args to avoid shell injection
        // Output: dir\tfirst_image per line
        var cmd = ["bash", "-c",
            "for d in \"$@\"; do\n" +
            "  [ -d \"$d\" ] || continue\n" +
            "  for sub in \"$d\"/*/; do\n" +
            "    [ -d \"$sub\" ] || continue\n" +
            "    first=$(find -L \"$sub\" -maxdepth 1 -type f \\( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.webp' \\) 2>/dev/null | sort | head -1)\n" +
            "    echo \"${sub%/}\t${first}\"\n" +
            "  done\n" +
            "done | sort",
            "bash"]
        for (var i = 0; i < root.browseDirs.length; i++) {
            cmd.push(root.browseDirs[i])
        }
        subdirsProc.command = cmd
        subdirsProc.running = true
    }

    Process {
        id: subdirsProc
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n")
                var dirs = []
                lines.forEach(function(line) {
                    if (!line) return
                    var parts = line.split("\t")
                    dirs.push({ path: parts[0], firstImage: parts[1] || "" })
                })
                root._subdirsRaw = dirs
                root._subdirsReady = true
                if (root._themeWpDirReady) root._buildBrowseFolders()
            }
        }
    }

    // Build the browseFolders model from theme dir + subdirs
    function _buildBrowseFolders() {
        var folders = []

        // 1. Active theme wallpapers dir (always first)
        if (root.themeWallpapersDir) {
            var themeName = root.themeWallpapersDir.split("/").filter(function(s) { return s !== "" })
            var lastDir = themeName.length > 1 ? themeName[themeName.length - 2] : "Theme"
            // Theme dir uses "1.jpg" as preview (theme wallpapers are numbered)
            folders.push({
                name: lastDir + " (theme)",
                path: root.themeWallpapersDir,
                isTheme: true,
                firstImage: root.themeWallpapersDir + "1.jpg"
            })
        }

        // 2. Subdirectories from browse_dirs (one level deep, with firstImage)
        root._subdirsRaw.forEach(function(entry) {
            if (!entry.firstImage) return
            var dir = entry.path || entry
            var parts = dir.split("/")
            var name = parts[parts.length - 1]
            folders.push({
                name: name,
                path: dir,
                isTheme: false,
                firstImage: entry.firstImage || ""
            })
        })

        root.browseFolders = folders

        // Auto-select first folder if none selected
        if (!root.activeFolder && folders.length > 0) {
            root.activeFolder = folders[0].path
            if (folders[0].isTheme) {
                root.refreshResolvedWallpapers()
            } else {
                root.scanFolder(folders[0].path)
            }
        }
    }

    // === Compositor IPC: tag list ===

    function refreshTagList() {
        tagListProc.running = true
    }

    Process {
        id: tagListProc
        command: ["somewm-client", "eval",
            "return require('fishlive.services.wallpaper').get_tags_json()"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim()
                var nl = raw.indexOf("\n")
                var json = nl >= 0 ? raw.substring(nl + 1) : raw
                try {
                    root.tagList = JSON.parse(json)
                    // Default to first tag if none selected
                    if (!root.selectedTag && root.tagList.length > 0) {
                        root.selectedTag = root.tagList[0]
                    }
                } catch (e) {
                    root.tagList = []
                }
            }
        }
    }

    // === Lua escape for IPC ===

    function _luaEscape(str) {
        return str.replace(/\\/g, "\\\\").replace(/'/g, "\\'")
            .replace(/\n/g, "\\n").replace(/\r/g, "\\r")
            .replace(/[\x00-\x1f]/g, "")
    }

    // === Set wallpaper (save to user-wallpapers for selected tag) ===

    function setWallpaper(path) {
        root.currentWallpaper = path
        var safePath = _luaEscape(path)
        var safeTag = _luaEscape(root.selectedTag || "1")

        setProc.command = ["somewm-client", "eval",
            "require('fishlive.services.wallpaper').save_to_theme('" +
            safeTag + "', '" + safePath + "'); " +
            "return '" + safeTag + "'"]
        setProc.running = true
    }

    Process {
        id: setProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.refreshCurrent()
                root.refreshOverrides()
                if (root.isThemeView) root.refreshResolvedWallpapers()
            }
        }
        onRunningChanged: {
            if (!running && root.applyTheme) {
                themeExportProc.running = true
            }
        }
    }

    // Theme export — regenerates theme.json from current wallpaper colors
    Process {
        id: themeExportProc
        command: [Quickshell.shellDir + "/theme-export.sh"]
        onRunningChanged: {
            // After export finishes, force Theme reload via Process (cat)
            // because FileView inotify may miss the change
            if (!running) themeReloadTimer.restart()
        }
    }

    Timer {
        id: themeReloadTimer
        interval: 200
        onTriggered: Core.Theme.forceReload()
    }

    // Set wallpaper for a specific tag
    function setWallpaperForTag(tagName, path) {
        root.currentWallpaper = path
        var safePath = _luaEscape(path)
        var safeTag = _luaEscape(tagName)
        tagSetProc.command = ["somewm-client", "eval",
            "require('fishlive.services.wallpaper').save_to_theme('" +
            safeTag + "', '" + safePath + "')"]
        tagSetProc.running = true
    }

    Process {
        id: tagSetProc
        onRunningChanged: {
            if (!running) {
                if (root.applyTheme) themeExportProc.running = true
                if (root.isThemeView) root.refreshResolvedWallpapers()
            }
        }
    }

    // Clear override for a tag (revert to resolved wallpaper)
    function clearOverride(tagName) {
        var safe = _luaEscape(tagName)
        clearProc.command = ["somewm-client", "eval",
            "require('fishlive.services.wallpaper').clear_override('" + safe + "')"]
        clearProc.running = true
    }

    Process {
        id: clearProc
        onRunningChanged: {
            if (!running) {
                refreshCurrent()
                refreshOverrides()
            }
        }
    }

    // Toggle apply-theme setting (persisted via Config singleton)
    function setApplyTheme(enabled) {
        root.applyTheme = enabled
        Core.Config.set("wallpapers.applyTheme", enabled)
    }

    // === View tag (switch tag in compositor + update selectedTag) ===

    function viewTag(tagName) {
        root.selectedTag = tagName
        viewTagProc.command = ["somewm-client", "eval",
            "require('fishlive.services.wallpaper').view_tag('" +
            _luaEscape(tagName) + "')"]
        viewTagProc.running = true
    }

    Process {
        id: viewTagProc
        onRunningChanged: {
            if (!running) {
                refreshCurrent()
            }
        }
    }

    // === Theme scanning and switching ===

    property var themes: []
    property string activeTheme: ""

    function refreshThemes() {
        themeScanProc.running = true
    }

    Process {
        id: themeScanProc
        command: ["somewm-client", "eval",
            "return require('fishlive.services.themes').scan_json()"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim()
                var nl = raw.indexOf("\n")
                var json = nl >= 0 ? raw.substring(nl + 1) : raw
                try {
                    var list = JSON.parse(json)
                    root.themes = list
                    for (var i = 0; i < list.length; i++) {
                        if (list[i].active) {
                            root.activeTheme = list[i].name
                            break
                        }
                    }
                } catch (e) {
                    console.error("Theme scan parse error:", e)
                    root.themes = []
                }
            }
        }
    }

    function switchTheme(themeName) {
        var safe = _luaEscape(themeName)
        themeSwitchProc.command = ["somewm-client", "eval",
            "require('fishlive.services.themes').switch('" + safe + "'); " +
            "return '" + safe + "'"]
        themeSwitchProc.running = true
    }

    Process {
        id: themeSwitchProc
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text.trim()
                var nl = raw.indexOf("\n")
                var name = nl >= 0 ? raw.substring(nl + 1) : raw
                if (name && name !== "OK") root.activeTheme = name
                // Re-export theme colors to JSON for shell
                themeExportProc.running = true
                // Refresh everything: theme dir changed, folder list needs rebuild
                root.activeFolder = ""  // force folder rebuild to pick new theme dir
                root.refreshThemeWpDir()
                root.refreshCurrent()
                root.refreshThemes()
            }
        }
    }

    // IPC: external theme switching (e.g. from terminal)
    IpcHandler {
        target: "somewm-shell:wallpapers"
        function switchTheme(name: string): void { root.switchTheme(name) }
        function reloadTheme(): void             { themeExportProc.running = true }
    }

    Component.onCompleted: {
        themeExportProc.running = true  // sync theme.json from compositor
        refresh()
    }
}
