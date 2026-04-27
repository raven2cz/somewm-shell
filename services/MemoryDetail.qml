pragma Singleton

// MemoryDetail — lazy, gated memory-info service for the Memory detail panel.
//
// Nothing polls until `detailActive` is true (set by Core.DetailController
// when the panel opens). Three independent poll loops:
//
//   * /proc/meminfo                                       — 2 s
//   * somewm-client eval somewm.memory.stats(true)         — 3 s
//   * PSS scan of /proc/<pid>/smaps_rollup (top 15)        — 5 s, timeout-guarded
//
// Plus a derived somewm RSS/PSS from /proc/<somewm_pid>/smaps_rollup
// (values are not exposed by the Lua API; we get them here the same way
// plans/scripts/somewm-memory-snapshot.sh does).
//
// Trend ring: three parallel 60-sample arrays (5 min × 5 s), plain QML
// arrays handed to components/Graph.qml via addPoint(). In-memory only.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- gate ---
    property bool detailActive: false

    // --- /proc/meminfo (all values in KB) ---
    property int memTotalKB: 0
    property int memAvailKB: 0
    property int memFreeKB: 0
    property int memBuffKB: 0
    property int memCachedKB: 0
    property int memShmemKB: 0
    property int memSlabKB: 0
    property int memAnonKB: 0
    property int swapTotalKB: 0
    property int swapFreeKB: 0
    readonly property int usedKB: Math.max(0, memTotalKB - memAvailKB)
    readonly property int reclaimableKB: Math.max(0, memBuffKB + memCachedKB + memSlabKB - memShmemKB)
    readonly property real usedPct: memTotalKB > 0 ? usedKB / memTotalKB : 0
    readonly property real reclaimPct: memTotalKB > 0 ? reclaimableKB / memTotalKB : 0
    readonly property real availPct: memTotalKB > 0 ? memAvailKB / memTotalKB : 0

    // --- somewm process memory (from /proc/<pid>/smaps_rollup) ---
    property int somewmPid: 0
    property int somewmRssKB: 0
    property int somewmPssKB: 0
    property int somewmPrivDirtyKB: 0

    // --- somewm.memory.stats() + nested tables ---
    property int luaBytes: 0
    property int clientsCount: 0
    property int drawableShmCount: 0
    property int drawableShmBytes: 0
    property int wiboxCount: 0
    property int wiboxSurfaceBytes: 0
    property int wallpaperEntries: 0
    property int wallpaperEstBytes: 0
    property int wallpaperCairoBytes: 0
    property int wallpaperShmBytes: 0
    property int drawableSurfaceBytes: 0
    property int mallocUsedBytes: 0
    property int mallocFreeBytes: 0
    property int mallocReleasableBytes: 0
    property bool somewmLoaded: false   // false until first successful eval
    property string somewmError: ""

    // --- top processes (by PSS). [{pid, name, pssKB, rssKB}] ---
    property var topProcesses: []
    property bool procsLoaded: false
    property int procsUnreadable: 0      // pids where smaps_rollup wasn't readable

    // --- last-updated timestamps (for "Updated Ns ago" hints) ---
    property var lastMemInfo: null
    property var lastSomewm: null
    property var lastProcs: null

    // --- trend ring (values are 0..1 normalised for the sparkline) ---
    property var trendRss: []
    property var trendLua: []
    property var trendWallpaper: []
    property int trendMaxPoints: 60

    // --- absolute-scale trend stats ---
    //
    // The sparkline ring is 0..1 normalised; by itself it can't answer
    // "what's the peak?" or "how much did this grow since I opened the
    // panel?". These companion scalars carry the raw bytes/KB so
    // TrendSection can render proper labels + delta since open without
    // re-normalising. Reset to 0 in onDetailActiveChanged on close; the
    // first _pushTrend call after re-open seeds init = current, so deltas
    // are always anchored to "since this panel open" (plan §4 Fix A/C).
    property int trendRssPeakKB: 0
    property int trendRssInitKB: 0
    property double trendLuaMaxBytes: 0
    property double trendLuaMinBytes: 0
    property double trendLuaInitBytes: 0
    property double trendWpMaxBytes: 0
    property double trendWpMinBytes: 0
    property double trendWpInitBytes: 0

    // --- parser helper: strip "OK\n" prefix from somewm-client eval output ---
    function _ipcValue(raw) {
        var s = (raw || "").replace(/\s+$/, "")
        var nl = s.indexOf("\n")
        return nl >= 0 ? s.substring(nl + 1) : s
    }

    // =============================================================
    // Timers — only run while detailActive
    // =============================================================

    // /proc/meminfo — cheap
    Timer {
        id: memInfoTimer
        running: root.detailActive
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!memInfoProc.running) memInfoProc.running = true
    }

    // somewm-client eval — medium
    Timer {
        id: somewmTimer
        running: root.detailActive
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!somewmProc.running) somewmProc.running = true
    }

    // PSS scan — expensive
    Timer {
        id: procsTimer
        running: root.detailActive
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!procsProc.running) procsProc.running = true
    }

    // Trend ring update — 5 s after first values land
    Timer {
        id: trendTimer
        running: root.detailActive
        interval: 5000
        repeat: true
        onTriggered: root._pushTrend()
    }

    // Lifecycle: force-stop in-flight Process instances on close so a slow
    // probe (e.g. PSS scan over hundreds of /proc entries) doesn't keep
    // running for seconds after the panel is gone.
    //
    // Contract: EVERY Process in this file wraps its command in `timeout N`
    // at argv[0]. Setting `Process.running = false` terminates the immediate
    // child (the `timeout` wrapper); POSIX `timeout` then propagates SIGTERM
    // to its child (gawk/bash/etc.). This is the only reason the stop is
    // safe — per sonnet review round 2 plan, a raw bash/cmd without timeout
    // wrapper could leave orphans. Enforced by test-detail-panels.sh.
    //
    // Also: reset `*Loaded` flags so the next open starts clean rather than
    // flashing stale numbers from minutes ago.
    onDetailActiveChanged: {
        if (detailActive) {
            pidProc.running = true
            return
        }
        if (pidProc.running)         pidProc.running = false
        if (pidFallbackProc.running) pidFallbackProc.running = false
        if (memInfoProc.running)     memInfoProc.running = false
        if (somewmProc.running)      somewmProc.running = false
        if (somewmRssProc.running)   somewmRssProc.running = false
        if (procsProc.running)       procsProc.running = false
        root.trendRss = []
        root.trendLua = []
        root.trendWallpaper = []
        root.trendRssPeakKB = 0
        root.trendRssInitKB = 0
        root.trendLuaMaxBytes = 0
        root.trendLuaMinBytes = 0
        root.trendLuaInitBytes = 0
        root.trendWpMaxBytes = 0
        root.trendWpMinBytes = 0
        root.trendWpInitBytes = 0
        root.somewmLoaded = false
        root.procsLoaded = false
        // Sections key off `memTotalKB > 0` to gate the loading skeleton —
        // resetting it forces "Loading /proc/meminfo…" on next open, instead
        // of flashing stale numbers from an earlier session.
        root.memTotalKB = 0
    }

    // =============================================================
    // Processes
    // =============================================================

    // Resolve somewm pid by asking the IPC-connected compositor itself —
    // pidof -s somewm is wrong in the nested-sandbox case (it returns the
    // outer compositor pid). Reading /proc/self/status from inside the
    // compositor's Lua state guarantees we measure the process behind the
    // socket we're actually talking to. `pidof -s` is only used as a final
    // fallback if /proc/self isn't readable from inside the eval.
    Process {
        id: pidProc
        command: ["timeout", "2", "somewm-client", "eval",
                  "local f=io.open('/proc/self/status','r'); " +
                  "if not f then return '0' end; " +
                  "local body=f:read('*a'); f:close(); " +
                  "return tostring(body:match('Pid:%s+(%d+)') or 0)"]
        stdout: StdioCollector {
            onStreamFinished: {
                var body = root._ipcValue(text).trim()
                var pid = parseInt(body) || 0
                if (pid > 0) {
                    root.somewmPid = pid
                    if (!somewmRssProc.running) somewmRssProc.running = true
                } else {
                    if (!pidFallbackProc.running) pidFallbackProc.running = true
                }
            }
        }
    }

    // Fallback pid resolver used only when the in-process /proc read fails.
    Process {
        id: pidFallbackProc
        command: ["timeout", "2", "bash", "-c", "pidof -s somewm 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                var pid = parseInt((text || "").trim()) || 0
                if (pid > 0) {
                    root.somewmPid = pid
                    if (!somewmRssProc.running) somewmRssProc.running = true
                }
            }
        }
    }

    // somewm RSS/PSS from /proc/<pid>/smaps_rollup
    Process {
        id: somewmRssProc
        command: ["timeout", "2", "bash", "-c",
            "pid=" + root.somewmPid + "; " +
            "[ -r /proc/$pid/smaps_rollup ] || { echo NOFILE; exit 0; }; " +
            "awk '" +
                "/^Rss:/{rss+=$2} " +
                "/^Pss:/{pss+=$2} " +
                "/^Private_Dirty:/{pd+=$2} " +
                "END{print \"rss=\"rss+0\" pss=\"pss+0\" pd=\"pd+0}" +
            "' /proc/$pid/smaps_rollup"
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseSomewmRss(text)
        }
    }

    // /proc/meminfo
    //
    // /proc/meminfo is a kernel-backed virtual file and can't block in
    // practice, but we still wrap in `timeout 2` so the lifecycle invariant
    // holds uniformly across every Process in this file: argv[0] == timeout,
    // so `running = false` on panel close reliably propagates SIGTERM to
    // the child (see onDetailActiveChanged contract block above).
    Process {
        id: memInfoProc
        command: ["timeout", "2", "cat", "/proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: root._parseMemInfo(text)
        }
    }

    // somewm.memory.stats(true) flat k=v via somewm-client eval
    Process {
        id: somewmProc
        command: ["timeout", "3", "somewm-client", "eval",
            "local ok,m=pcall(function() return somewm.memory.stats(true) end); " +
            "if not ok then return 'error=memory_stats_failed' end; " +
            "return string.format(" +
            "'lua_bytes=%d clients=%d drawable_shm_count=%d drawable_shm_bytes=%d " +
            "wibox_count=%d wibox_surface_bytes=%d " +
            "wallpaper_entries=%d wallpaper_estimated_bytes=%d " +
            "wallpaper_cairo_bytes=%d wallpaper_shm_bytes=%d " +
            "drawable_surface_bytes=%d " +
            "malloc_used_bytes=%d malloc_free_bytes=%d malloc_releasable_bytes=%d'," +
            "m.lua_bytes or 0, m.clients or 0," +
            "m.drawable_shm_count or 0, m.drawable_shm_bytes or 0," +
            "m.wibox_count or 0, m.wibox_surface_bytes or 0," +
            "m.wallpaper and m.wallpaper.entries or 0," +
            "m.wallpaper and m.wallpaper.estimated_bytes or 0," +
            "m.wallpaper and m.wallpaper.cairo_bytes or 0," +
            "m.wallpaper and m.wallpaper.shm_bytes or 0," +
            "m.drawables and m.drawables.surface_bytes or 0," +
            "m.malloc_used_bytes or 0, m.malloc_free_bytes or 0," +
            "m.malloc_releasable_bytes or 0)"
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseSomewm(text)
        }
    }

    // PSS scan — one gawk pass over all /proc/*/smaps_rollup instead of a
    // fork-per-pid loop (review round 2, gemini: the prior loop cost ~1000
    // fork+execs every 5 s on a 1k-process desktop).
    //
    // Uses `gawk` explicitly — BEGINFILE/ENDFILE/ERRNO are gawk-only; a
    // minimal install where `awk` resolves to mawk/bwk would silently fail
    // (review round 3, sonnet).
    //
    // `BEGINFILE{ if (ERRNO) { unread++; nextfile } }` silently skips files
    // that vanish mid-scan (race: pid dies between glob expansion and open)
    // AND counts the unreadable ones in the same pass — the prior shell
    // `for d in /proc/[0-9]*` fallback counted a different pid set than
    // gawk saw (review round 3, sonnet). `timeout 6` still bounds any
    // single stuck read.
    Process {
        id: procsProc
        command: ["timeout", "6", "bash", "-c",
            // gawk emits PSS rows on stdout and UNREAD= on stderr; we route
            // stderr to a per-PID temp in $XDG_RUNTIME_DIR so concurrent
            // panels don't clobber each other's counter.
            "err=\"${XDG_RUNTIME_DIR:-/tmp}/somewm-procs-unread.$$\"; " +
            "gawk '" +
                "BEGINFILE{if (ERRNO) { unread++; nextfile } " +
                "pid=FILENAME; sub(/^\\/proc\\//, \"\", pid); sub(/\\/smaps_rollup$/, \"\", pid); p=0; r=0} " +
                "/^Pss:/{p+=$2} " +
                "/^Rss:/{r+=$2} " +
                "ENDFILE{if (r > 0) printf \"%d\\t%d\\t%s\\n\", p+0, r+0, pid} " +
                "END{printf \"UNREAD=%d\\n\", unread+0 > \"/dev/stderr\"}" +
            "' /proc/[0-9]*/smaps_rollup 2>\"$err\" " +
            "| sort -k1,1 -nr | head -15 " +
            "| while read pss rss pid; do " +
                "name=$(tr -d '\\0' <\"/proc/$pid/comm\" 2>/dev/null); " +
                "[ -z \"$name\" ] && name=\"?\"; " +
                "printf \"%s\\t%s\\t%s\\t%s\\n\" \"$pss\" \"$rss\" \"$pid\" \"$name\"; " +
            "done; " +
            "cat \"$err\" 2>/dev/null || echo UNREAD=0; " +
            "rm -f \"$err\""
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseProcs(text)
        }
    }

    // =============================================================
    // Parsers
    // =============================================================

    function _parseMemInfo(text) {
        try {
            var lines = (text || "").split("\n")
            function _kb(field) {
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf(field + ":") === 0) {
                        return parseInt(lines[i].split(/\s+/)[1]) || 0
                    }
                }
                return 0
            }
            root.memTotalKB   = _kb("MemTotal")
            root.memAvailKB   = _kb("MemAvailable")
            root.memFreeKB    = _kb("MemFree")
            root.memBuffKB    = _kb("Buffers")
            root.memCachedKB  = _kb("Cached")
            root.memShmemKB   = _kb("Shmem")
            root.memSlabKB    = _kb("Slab")
            root.memAnonKB    = _kb("AnonPages")
            root.swapTotalKB  = _kb("SwapTotal")
            root.swapFreeKB   = _kb("SwapFree")
            root.lastMemInfo  = new Date()
        } catch (e) {
            console.error("MemoryDetail._parseMemInfo:", e)
        }
    }

    function _parseSomewmRss(text) {
        try {
            var body = (text || "").trim()
            if (body === "NOFILE" || body === "") return
            // Format: "rss=NNN pss=NNN pd=NNN"
            var out = body.match(/rss=(\d+)\s+pss=(\d+)\s+pd=(\d+)/)
            if (!out) return
            root.somewmRssKB       = parseInt(out[1]) || 0
            root.somewmPssKB       = parseInt(out[2]) || 0
            root.somewmPrivDirtyKB = parseInt(out[3]) || 0
        } catch (e) {
            console.error("MemoryDetail._parseSomewmRss:", e)
        }
    }

    // Expected keys for memory_stats eval — must match the format string in
    // somewmProc.command. Missing keys after a successful eval signal a C API
    // drift, so we log once per drift event to catch silent renames in CI.
    readonly property var _expectedStatKeys: [
        "lua_bytes", "clients", "drawable_shm_count", "drawable_shm_bytes",
        "wibox_count", "wibox_surface_bytes",
        "wallpaper_entries", "wallpaper_estimated_bytes",
        "wallpaper_cairo_bytes", "wallpaper_shm_bytes",
        "drawable_surface_bytes",
        "malloc_used_bytes", "malloc_free_bytes", "malloc_releasable_bytes"
    ]
    property string _lastSchemaWarning: ""

    function _parseSomewm(text) {
        try {
            var body = root._ipcValue(text).trim()
            if (body.indexOf("error=") === 0) {
                root.somewmError = body.substring(6)
                return
            }
            var tokens = body.split(/\s+/)
            var m = {}
            for (var i = 0; i < tokens.length; i++) {
                var kv = tokens[i].split("=")
                if (kv.length === 2) m[kv[0]] = parseInt(kv[1]) || 0
            }
            // Schema-drift detector — warn once when the eval output stops
            // carrying a field we expect. Catches C-API field renames without
            // requiring a live test.
            //
            // Bail out if parsing produced zero tokens: that means the IPC
            // call timed out / returned empty, NOT that the schema drifted.
            // Without this guard we'd spam the log once per compositor hiccup
            // (review round 2, sonnet).
            var gotAnyKey = false
            for (var mk in m) { gotAnyKey = true; break }
            if (gotAnyKey) {
                var missing = []
                for (var k = 0; k < _expectedStatKeys.length; k++) {
                    if (!(_expectedStatKeys[k] in m)) missing.push(_expectedStatKeys[k])
                }
                var sig = missing.join(",")
                if (sig !== _lastSchemaWarning) {
                    if (missing.length > 0) {
                        console.warn("MemoryDetail: schema drift — missing keys: " + sig)
                    }
                    root._lastSchemaWarning = sig
                }
            }
            root.luaBytes              = m.lua_bytes || 0
            root.clientsCount          = m.clients || 0
            root.drawableShmCount      = m.drawable_shm_count || 0
            root.drawableShmBytes      = m.drawable_shm_bytes || 0
            root.wiboxCount            = m.wibox_count || 0
            root.wiboxSurfaceBytes     = m.wibox_surface_bytes || 0
            root.wallpaperEntries      = m.wallpaper_entries || 0
            root.wallpaperEstBytes     = m.wallpaper_estimated_bytes || 0
            root.wallpaperCairoBytes   = m.wallpaper_cairo_bytes || 0
            root.wallpaperShmBytes     = m.wallpaper_shm_bytes || 0
            root.drawableSurfaceBytes  = m.drawable_surface_bytes || 0
            root.mallocUsedBytes       = m.malloc_used_bytes || 0
            root.mallocFreeBytes       = m.malloc_free_bytes || 0
            root.mallocReleasableBytes = m.malloc_releasable_bytes || 0
            root.somewmLoaded          = true
            root.somewmError           = ""
            root.lastSomewm            = new Date()
            // Also refresh somewm RSS/PSS in lockstep.
            if (root.somewmPid > 0 && !somewmRssProc.running)
                somewmRssProc.running = true
        } catch (e) {
            console.error("MemoryDetail._parseSomewm:", e)
            root.somewmError = String(e)
        }
    }

    function _parseProcs(text) {
        try {
            var lines = (text || "").split("\n")
            var out = []
            var unread = 0
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i]
                if (line.indexOf("UNREAD=") === 0) {
                    unread = parseInt(line.substring(7)) || 0
                    continue
                }
                var parts = line.split("\t")
                if (parts.length < 4) continue
                var pss = parseInt(parts[0]) || 0
                if (pss <= 0) continue
                out.push({
                    pssKB: pss,
                    rssKB: parseInt(parts[1]) || 0,
                    pid:   parseInt(parts[2]) || 0,
                    name:  parts[3]
                })
            }
            root.topProcesses    = out
            root.procsUnreadable = unread
            root.procsLoaded     = true
            root.lastProcs       = new Date()
        } catch (e) {
            console.error("MemoryDetail._parseProcs:", e)
        }
    }

    // =============================================================
    // Trend ring — normalised 0..1
    // =============================================================

    function _pushTrend() {
        if (root.memTotalKB <= 0) return
        var totalB = root.memTotalKB * 1024
        var pts

        // RSS of somewm as fraction of total memory
        pts = trendRss.slice()
        pts.push(Math.min(1, (root.somewmRssKB * 1024) / totalB))
        if (pts.length > trendMaxPoints) pts.shift()
        trendRss = pts

        // Lua as fraction of somewm RSS (capped) — scaled up so the spark
        // is visible (lua is usually <1 % of RSS).
        pts = trendLua.slice()
        var luaFrac = (root.somewmRssKB > 0)
            ? Math.min(1, root.luaBytes / (root.somewmRssKB * 1024) * 10)
            : 0
        pts.push(luaFrac)
        if (pts.length > trendMaxPoints) pts.shift()
        trendLua = pts

        // Wallpaper est as fraction of somewm RSS
        pts = trendWallpaper.slice()
        var wpFrac = (root.somewmRssKB > 0)
            ? Math.min(1, root.wallpaperEstBytes / (root.somewmRssKB * 1024))
            : 0
        pts.push(wpFrac)
        if (pts.length > trendMaxPoints) pts.shift()
        trendWallpaper = pts

        // Absolute-scale stats for TrendSection (plan §4). First sample
        // after open seeds init; subsequent samples extend peak/min so
        // "delta since open" and "peak (last 5 min)" are always anchored
        // to this panel session.
        if (root.trendRssInitKB === 0 && root.somewmRssKB > 0)
            root.trendRssInitKB = root.somewmRssKB
        if (root.somewmRssKB > root.trendRssPeakKB)
            root.trendRssPeakKB = root.somewmRssKB

        if (root.luaBytes > 0) {
            if (root.trendLuaInitBytes === 0) root.trendLuaInitBytes = root.luaBytes
            if (root.trendLuaMinBytes === 0 || root.luaBytes < root.trendLuaMinBytes)
                root.trendLuaMinBytes = root.luaBytes
            if (root.luaBytes > root.trendLuaMaxBytes)
                root.trendLuaMaxBytes = root.luaBytes
        }
        if (root.wallpaperEstBytes > 0) {
            if (root.trendWpInitBytes === 0) root.trendWpInitBytes = root.wallpaperEstBytes
            if (root.trendWpMinBytes === 0 || root.wallpaperEstBytes < root.trendWpMinBytes)
                root.trendWpMinBytes = root.wallpaperEstBytes
            if (root.wallpaperEstBytes > root.trendWpMaxBytes)
                root.trendWpMaxBytes = root.wallpaperEstBytes
        }
    }

    // =============================================================
    // Actions (footer buttons)
    // =============================================================

    function forceGc() {
        Quickshell.execDetached(["somewm-client", "eval",
            "collectgarbage(); collectgarbage(); return 'ok'"])
    }

    function copySnapshot() {
        var home = Quickshell.env("HOME") || ""
        if (home === "") { console.error("MemoryDetail.copySnapshot: HOME unset"); return }
        // sh -c with positional args — the script path is passed as "$1" out
        // of the shell's parse path, so there is no interpolation / injection
        // risk even if HOME ever contained metacharacters.
        var script = home + "/git/github/somewm/plans/scripts/somewm-memory-snapshot.sh"
        Quickshell.execDetached(["sh", "-c",
            "timeout 10 \"$1\" --tsv 2>/dev/null | wl-copy",
            "copySnapshot", script])
    }

    function openBaseline() {
        Quickshell.execDetached(["xdg-open",
            Quickshell.env("HOME") +
            "/git/github/somewm/plans/docs/memory-baseline.md"])
    }

    function refresh() {
        if (!detailActive) return
        if (!memInfoProc.running) memInfoProc.running = true
        if (!somewmProc.running) somewmProc.running = true
        if (!procsProc.running) procsProc.running = true
    }
}
