pragma Singleton

// StorageDetail — lazy, gated storage-info service for the Storage detail
// panel. Gated on `detailActive`; mounts poll every 30 s while open, all
// other probes are one-shot on panel open (du / find are too expensive to
// poll).
//
// Uses findmnt -J for robust mount parsing (handles spaces / weird fstypes
// that tripped df --output). Guards every external call with `timeout` so
// a hung NFS/SSHFS mount cannot wedge the service.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- gate ---
    property bool detailActive: false

    // --- mounts ---
    // [{source, target, fstype, size, used, avail, pct}]  (bytes)
    property var mounts: []
    property bool mountsLoaded: false
    property var lastMounts: null

    // --- Arch hotspots ---
    property var hotspots: []   // [{key, label, path, bytes, hint, available}]
    property bool hotspotsLoaded: false
    property var lastHotspots: null

    // --- top dirs under $HOME (depth-1) ---
    property var topDirs: []   // [{path, bytes}]
    property bool topDirsLoaded: false
    property bool topDirsRunning: false

    // True $HOME size in bytes (from an independent `du --max-depth=0` run
    // — see homeTotalProc). Used as the denominator for the "% of $HOME"
    // column in TopDirsSection. Without this denominator, showing a
    // percentage against the sum of the top 10 dirs is misleading (plan §5
    // / gemini review round 1). 0 means "not yet loaded" — UI renders `—`.
    property double homeTotalBytes: 0
    property bool homeTotalLoaded: false

    // --- paccache state ---
    property bool paccacheAvailable: false
    property bool pkexecAvailable: false
    property bool paccacheBusy: false
    property string paccachePreview: ""
    property int paccachePreviewCount: 0
    property int paccachePreviewBytes: 0
    property string paccacheStatus: ""     // "", "dryrun", "cleaned", "cancelled", "error"
    property int paccacheCleanedCount: 0
    property int paccacheCleanedBytes: 0

    // Tool availability
    property bool flatpakAvailable: false
    property bool baobabAvailable: false
    property bool filelightAvailable: false

    // =============================================================
    // Timers / initial probes
    // =============================================================

    Timer {
        id: mountsTimer
        running: root.detailActive
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!mountsProc.running) mountsProc.running = true
    }

    // Lifecycle: when detailActive flips true we kick off one-shots; when it
    // flips false we force-stop every Process and clear per-session state so
    // the panel can't keep burning CPU/IO after the user closed it.
    //
    // Safe to set `running = false` on an idle Process (no-op). For a live
    // one, Quickshell sends SIGTERM to the child. Every command below is
    // wrapped in `timeout N …` whose argv[0] IS the child — POSIX timeout
    // propagates SIGTERM to its child (du/findmnt/journalctl/paccache), so
    // there are no zombies left behind. See plans/qs-detail-panels-polish-plus-cpu.md §7.
    onDetailActiveChanged: {
        if (detailActive) {
            if (!toolsProc.running) toolsProc.running = true
            if (!hotspotsProc.running) hotspotsProc.running = true
            _runTopDirs()
            return
        }
        if (mountsProc.running)      mountsProc.running = false
        if (toolsProc.running)       toolsProc.running = false
        if (hotspotsProc.running)    hotspotsProc.running = false
        if (topDirsProc.running)     topDirsProc.running = false
        if (homeTotalProc.running)   homeTotalProc.running = false
        if (paccacheDryProc.running) paccacheDryProc.running = false
        // paccacheRunProc is left alone: it's user-initiated via pkexec and
        // killing it mid-flight would leave the pacman cache half-pruned.
        root.topDirsRunning = false
        root.paccacheBusy = false
    }

    function refresh() {
        if (!detailActive) return
        if (!mountsProc.running) mountsProc.running = true
        if (!hotspotsProc.running) hotspotsProc.running = true
        _runTopDirs()
    }

    function _runTopDirs() {
        if (topDirsRunning) return
        topDirsRunning = true
        topDirsProc.running = true
        // Kick off the $HOME total in parallel — independent probe, same
        // interval, used as the denominator for the "% of $HOME" column.
        if (!homeTotalProc.running) homeTotalProc.running = true
    }

    // =============================================================
    // Processes
    // =============================================================

    // Tool availability (one-shot). `command -v` is essentially free but
    // `timeout 2` still guards against a wedged PATH lookup on exotic
    // filesystems (autofs, stale NFS) that has bitten me before.
    Process {
        id: toolsProc
        command: ["timeout", "2", "bash", "-c",
            "printf 'paccache='; command -v paccache >/dev/null && echo 1 || echo 0; " +
            "printf 'pkexec=';   command -v pkexec   >/dev/null && echo 1 || echo 0; " +
            "printf 'flatpak=';  command -v flatpak  >/dev/null && echo 1 || echo 0; " +
            "printf 'baobab=';   command -v baobab   >/dev/null && echo 1 || echo 0; " +
            "printf 'filelight=';command -v filelight>/dev/null && echo 1 || echo 0"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = (text || "").split("\n")
                var m = {}
                for (var i = 0; i < lines.length; i++) {
                    var kv = lines[i].split("=")
                    if (kv.length === 2) m[kv[0]] = kv[1].trim() === "1"
                }
                root.paccacheAvailable  = !!m.paccache
                root.pkexecAvailable    = !!m.pkexec
                root.flatpakAvailable   = !!m.flatpak
                root.baobabAvailable    = !!m.baobab
                root.filelightAvailable = !!m.filelight
            }
        }
    }

    // Mounts — findmnt JSON
    Process {
        id: mountsProc
        command: ["timeout", "3", "findmnt", "-J", "-b", "--real",
                  "-o", "SOURCE,TARGET,FSTYPE,SIZE,USED,AVAIL,USE%"]
        stdout: StdioCollector {
            onStreamFinished: root._parseMounts(text)
        }
    }

    // Arch hotspots — sizes in bytes for a known set of paths
    Process {
        id: hotspotsProc
        command: ["timeout", "8", "bash", "-c",
            "getsize() { " +
                "if [ -d \"$1\" ] || [ -f \"$1\" ]; then " +
                    "du -sb \"$1\" 2>/dev/null | awk '{print $1}'; " +
                "else echo NA; fi; " +
            "}; " +
            "printf 'pacman_cache=%s\\n'    \"$(getsize /var/cache/pacman/pkg)\"; " +
            "printf 'pacman_log=%s\\n'      \"$(getsize /var/log/pacman.log)\"; " +
            "if command -v journalctl >/dev/null; then " +
                // LC_ALL=C forces the 'Archived and active journals take up N'
                // phrasing; otherwise a non-en locale would break the awk match.
                "ju=$(LC_ALL=C journalctl --disk-usage 2>/dev/null | " +
                "awk '/take up/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9.]+[KMGTP]?$/) print $i}' | head -1); " +
                "printf 'journald=%s\\n' \"${ju:-NA}\"; " +
            "else printf 'journald=NA\\n'; fi; " +
            "printf 'coredump=%s\\n'       \"$(getsize /var/lib/systemd/coredump)\"; " +
            "printf 'paru_cache=%s\\n'     \"$(getsize \"$HOME/.cache/paru\")\"; " +
            "printf 'yay_cache=%s\\n'      \"$(getsize \"$HOME/.cache/yay\")\"; " +
            "printf 'home_cache=%s\\n'     \"$(getsize \"$HOME/.cache\")\"; " +
            "printf 'trash=%s\\n'          \"$(getsize \"$HOME/.local/share/Trash\")\""
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseHotspots(text)
        }
    }

    // Top-level $HOME dirs by size (depth-1), top 10.
    //
    // `du --max-depth=1` avoids the shell glob `* .[!.]*` which on huge
    // flat $HOMEs (many dotfiles or thousands of top-level dirs) could hit
    // ARG_MAX → E2BIG and silently return nothing (review round 2, sonnet).
    //
    // `head -n -1` strips du's $HOME rollup row (emitted last) BEFORE sort,
    // so the drop is symlink-safe — matching on path equality in the parser
    // fails if $HOME resolves differently than du's reported path (review
    // round 3, sonnet). The parser still strips the $HOME prefix so the UI
    // shows relative names (Documents, .cache, …).
    Process {
        id: topDirsProc
        command: ["timeout", "20", "bash", "-c",
            "du -xb --max-depth=1 \"$HOME\" 2>/dev/null | head -n -1 | sort -n -r | head -10"
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseTopDirs(text)
        }
    }

    // True $HOME total (rollup, depth 0) — denominator for the "% of
    // $HOME" column in TopDirsSection. Runs in parallel with topDirsProc
    // at the same 30 s interval; on SSD this is 0.5–5 s. Until it lands,
    // the UI renders `—` rather than a misleading "% of top-10 sum".
    //
    // Output: a single line, e.g. "123456789\t/home/box". awk prints
    // $1 only (bytes field) so the stdin to QML is just the number.
    Process {
        id: homeTotalProc
        command: ["timeout", "20", "bash", "-c",
            "du -xb --max-depth=0 \"$HOME\" 2>/dev/null | awk '{print $1}'"
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseHomeTotal(text)
        }
    }

    // paccache dry-run preview: how many pkgs, how many bytes would be removed.
    //
    // `command` is intentionally empty — paccacheDryRun() always rebuilds it
    // so `keep` is clamped and `LC_ALL=C` is forced. Declaring a static
    // command here would be a latent trap if something ever flipped `running`
    // before the function ran (review round 2, sonnet).
    Process {
        id: paccacheDryProc
        property int keep: 2
        command: []
        stdout: StdioCollector {
            onStreamFinished: root._parsePaccacheDry(text)
        }
    }

    // paccache real run (via pkexec).
    //
    // Read exitCode on `onExited` rather than inside `StdioCollector.
    // onStreamFinished` — stdout may close (EOF) a scheduler tick before the
    // process is fully reaped, so the collector handler can see an
    // undefined/stale exit code (review round 2, gemini).
    Process {
        id: paccacheRunProc
        property int keep: 2
        property string _stdout: ""
        stdout: StdioCollector {
            onStreamFinished: paccacheRunProc._stdout = text
        }
        stderr: StdioCollector { }
        onExited: function(code, status) {
            root._parsePaccacheRun(paccacheRunProc._stdout, code)
            paccacheRunProc._stdout = ""
        }
    }

    // =============================================================
    // Parsers
    // =============================================================

    function _parseMounts(text) {
        try {
            var body = (text || "").trim()
            if (!body) { root.mounts = []; root.mountsLoaded = true; return }
            var j = JSON.parse(body)
            var out = []
            function walk(nodes) {
                if (!nodes) return
                for (var i = 0; i < nodes.length; i++) {
                    var n = nodes[i]
                    var size  = parseInt(n.size)  || 0
                    var used  = parseInt(n.used)  || 0
                    var avail = parseInt(n.avail) || 0
                    var pct = 0
                    if (typeof n["use%"] === "string") {
                        pct = parseInt(n["use%"].replace("%","")) || 0
                    } else if (size > 0) {
                        pct = Math.round(100 * used / size)
                    }
                    out.push({
                        source: n.source  || "",
                        target: n.target  || "",
                        fstype: n.fstype  || "",
                        size: size, used: used, avail: avail, pct: pct
                    })
                    if (n.children) walk(n.children)
                }
            }
            walk(j.filesystems)
            // Primary mount (/) first, then by size desc
            out.sort(function(a, b) {
                if (a.target === "/") return -1
                if (b.target === "/") return 1
                return b.size - a.size
            })
            root.mounts = out
            root.mountsLoaded = true
            root.lastMounts = new Date()
        } catch (e) {
            console.error("StorageDetail._parseMounts:", e, text)
            root.mounts = []
            root.mountsLoaded = true
        }
    }

    function _parseHotspots(text) {
        try {
            var lines = (text || "").split("\n")
            var m = {}
            for (var i = 0; i < lines.length; i++) {
                var kv = lines[i].split("=")
                if (kv.length === 2) m[kv[0]] = kv[1].trim()
            }
            function bytes(key) {
                var v = m[key]
                if (v === undefined || v === "NA" || v === "") return -1
                return parseInt(v) || 0
            }
            function parseSuffix(s) {
                // Journalctl output like "842.3M" or "1.2G" — return bytes.
                if (!s || s === "NA") return -1
                var unit = { K: 1024, M: 1048576, G: 1073741824, T: 1099511627776 }
                var m2 = s.match(/^([0-9.]+)([KMGTP]?)$/)
                if (!m2) return -1
                var v = parseFloat(m2[1]) || 0
                return Math.round(v * (unit[m2[2]] || 1))
            }
            var hs = []
            hs.push({ key: "pacman_cache",
                      label: "Pacman cache",
                      path: "/var/cache/pacman/pkg",
                      bytes: bytes("pacman_cache"),
                      hint: "paccache can keep latest N per package",
                      available: true })
            hs.push({ key: "pacman_log",
                      label: "Pacman log",
                      path: "/var/log/pacman.log",
                      bytes: bytes("pacman_log"),
                      hint: "Rotate manually if needed",
                      available: true })
            hs.push({ key: "journald",
                      label: "Journal (systemd)",
                      path: "/var/log/journal",
                      bytes: parseSuffix(m["journald"]),
                      hint: "Cap via SystemMaxUse= in journald.conf",
                      available: true })
            hs.push({ key: "coredump",
                      label: "Coredumps",
                      path: "/var/lib/systemd/coredump",
                      bytes: bytes("coredump"),
                      hint: "coredumpctl list / rm",
                      available: true })
            hs.push({ key: "paru_cache",
                      label: "AUR helper cache (paru)",
                      path: "~/.cache/paru",
                      bytes: bytes("paru_cache"),
                      hint: "paru --clean",
                      available: true })
            hs.push({ key: "yay_cache",
                      label: "AUR helper cache (yay)",
                      path: "~/.cache/yay",
                      bytes: bytes("yay_cache"),
                      hint: "yay -Sc",
                      available: true })
            hs.push({ key: "home_cache",
                      label: "Total ~/.cache",
                      path: "~/.cache",
                      bytes: bytes("home_cache"),
                      hint: "App-level caches (safe to clear when apps closed)",
                      available: true })
            hs.push({ key: "trash",
                      label: "Trash",
                      path: "~/.local/share/Trash",
                      bytes: bytes("trash"),
                      hint: "Empty via file manager",
                      available: true })
            if (root.flatpakAvailable) {
                hs.push({ key: "flatpak_unused",
                          label: "Flatpak unused runtimes",
                          path: "", bytes: -1,
                          hint: "flatpak uninstall --unused",
                          available: true })
            }
            root.hotspots = hs
            root.hotspotsLoaded = true
            root.lastHotspots = new Date()
        } catch (e) {
            console.error("StorageDetail._parseHotspots:", e)
        }
    }

    function _parseTopDirs(text) {
        try {
            var home = Quickshell.env("HOME") || ""
            var homePrefix = home ? (home + "/") : ""
            var lines = (text || "").split("\n")
            var out = []
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (!line) continue
                var parts = line.split(/\s+/)
                if (parts.length < 2) continue
                var bytes = parseInt(parts[0]) || 0
                var name = parts.slice(1).join(" ")
                if (bytes <= 0) continue
                // The rollup row is already stripped by `head -n -1` in the
                // Process command. Belt-and-braces: drop anything equal to
                // $HOME in case a different du version changes ordering.
                if (home && (name === home || name === home + "/")) continue
                if (homePrefix && name.indexOf(homePrefix) === 0)
                    name = name.slice(homePrefix.length)
                out.push({ path: name, bytes: bytes })
            }
            out.sort(function(a, b) { return b.bytes - a.bytes })
            root.topDirs = out.slice(0, 10)
            root.topDirsLoaded = true
        } catch (e) {
            console.error("StorageDetail._parseTopDirs:", e)
        } finally {
            root.topDirsRunning = false
        }
    }

    function _parseHomeTotal(text) {
        try {
            var n = parseInt((text || "").trim())
            if (n > 0) {
                root.homeTotalBytes = n
                root.homeTotalLoaded = true
            }
        } catch (e) {
            console.error("StorageDetail._parseHomeTotal:", e)
        }
    }

    function _parsePaccacheDry(text) {
        try {
            var body = text || ""
            // paccache -d prints "finished: N candidates (disk space saved: M)"
            var m = body.match(/(\d+)\s+candidate/)
            var count = m ? parseInt(m[1]) : 0
            var b = body.match(/disk space saved:\s*([0-9.]+)\s*(KiB|MiB|GiB|TiB|B)/i)
            var bytes = 0
            if (b) {
                // Normalise "gib" etc to CamelCase before dictionary lookup;
                // the /i flag would otherwise let "Gib" or "GIB" fall through
                // to the `|| 1` fallback and under-report by ~9 orders of
                // magnitude (review round 2, gemini).
                var unit = { B: 1, KiB: 1024, MiB: 1048576, GiB: 1073741824, TiB: 1099511627776 }
                var u = (b[2] || "").toUpperCase()
                var canonical = { B: "B", KIB: "KiB", MIB: "MiB",
                                  GIB: "GiB", TIB: "TiB" }
                bytes = Math.round((parseFloat(b[1]) || 0) * (unit[canonical[u]] || 1))
            }
            root.paccachePreview = body.trim()
            root.paccachePreviewCount = count
            root.paccachePreviewBytes = bytes
            root.paccacheStatus = count > 0 ? "dryrun" : "empty"
        } catch (e) {
            console.error("StorageDetail._parsePaccacheDry:", e)
        } finally {
            root.paccacheBusy = false
        }
    }

    function _parsePaccacheRun(text, exitCode) {
        try {
            if (exitCode === 126 || exitCode === 127) {
                root.paccacheStatus = "cancelled"
            } else if (exitCode !== 0) {
                root.paccacheStatus = "error"
            } else {
                root.paccacheStatus = "cleaned"
                // Refresh hotspots so the pacman cache size updates
                if (!hotspotsProc.running) hotspotsProc.running = true
            }
        } catch (e) {
            console.error("StorageDetail._parsePaccacheRun:", e)
        } finally {
            root.paccacheBusy = false
        }
    }

    // =============================================================
    // Actions
    // =============================================================

    // Clamp `keep` to a small positive int — paccache -dkN expects a bare
    // integer and we pass this directly on the command line. Any JS caller
    // could hand us a float / string, so normalise aggressively.
    function _clampKeep(keep) {
        var n = parseInt(keep) || 2
        if (n < 0) n = 0
        if (n > 999) n = 999
        return n
    }

    function paccacheDryRun(keep) {
        if (!paccacheAvailable || paccacheBusy) return
        var k = _clampKeep(keep)
        paccacheBusy = true
        paccacheDryProc.keep = k
        // LC_ALL=C: the dry-run parser greps for English "candidate" and
        // "disk space saved:" — non-en locale would silently report 0 pkgs.
        paccacheDryProc.command = ["timeout", "30", "env", "LC_ALL=C",
            "bash", "-c",
            "paccache -dk" + k + " --nocolor 2>&1"]
        paccacheDryProc.running = true
    }

    function paccacheClean(keep) {
        if (!paccacheAvailable || !pkexecAvailable || paccacheBusy) return
        if (paccacheStatus !== "dryrun" || paccachePreviewCount <= 0) return
        var k = _clampKeep(keep)
        paccacheBusy = true
        paccacheRunProc.keep = k
        // No outer timeout on the pkexec path — the user may sit at the
        // polkit prompt for a while, and paccache itself already finishes
        // quickly once it starts. The dry-run timeout above is enough to
        // catch a wedged paccache upstream.
        paccacheRunProc.command = ["/usr/bin/pkexec", "/usr/bin/paccache",
                                   "-rk" + k, "--nocolor"]
        paccacheRunProc.running = true
    }

    function openBaobab() {
        if (!baobabAvailable) return
        Quickshell.execDetached(["baobab", "/"])
    }

    function openFilelight() {
        if (!filelightAvailable) return
        var home = Quickshell.env("HOME") || "."
        Quickshell.execDetached(["filelight", home])
    }

    function openHome() {
        var home = Quickshell.env("HOME") || "."
        Quickshell.execDetached(["xdg-open", home])
    }
}
