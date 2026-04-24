pragma Singleton

// CpuDetail — lazy, gated CPU/GPU-info service for the CPU detail
// panel. Mirrors the MemoryDetail / StorageDetail pattern:
//
//   * Nothing polls until `detailActive` flips true
//     (Core.DetailController drives it when the panel opens).
//   * `onDetailActiveChanged(false)` force-stops every Process and
//     resets the session state (prev /proc/stat snapshot, tops init).
//   * Every Process wraps its command in `timeout N …` as argv[0] —
//     `running = false` then sends SIGTERM that POSIX-timeout
//     propagates to the real child, same invariant as MemoryDetail
//     (enforced by plans/tests/test-detail-panels.sh).
//
// Data layout:
//   /proc/stat            — per-core utilisation (cpuN lines),
//                           single-shot snapshot, delta computed in QML
//                           against `_prevStat` (plan §8.2 — chosen
//                           over in-bash sleep to eliminate overlap).
//   /proc/loadavg         — 1/5/15 min load averages.
//   /proc/uptime          — seconds since boot.
//   /proc/cpuinfo         — model name + core count (one-shot on open).
//   /proc/sys/kernel/osrelease — kernel release (one-shot).
//   /sys/class/drm/card*  — GPU PCI vendor:device (one-shot, instant —
//                           avoids nvidia-smi 150–300 ms cold start).
//   nvidia-smi            — GPU utilisation + VRAM (every 2 s, gated
//                           on nvidia-smi availability).
//   /proc/[0-9]*/stat     — top CPU processes. gawk two-snapshot
//                           single-subprocess pattern (plan §8.3).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // --- gate ---
    property bool detailActive: false

    // --- system overview (one-shot on open) ---
    property string kernelRelease: ""
    property string cpuModel: ""
    property int cpuCount: 0
    property string gpuVendor: ""    // "NVIDIA", "AMD", "Intel", or "" if unknown
    property string gpuModel: ""     // resolved name or "0x2c02" fallback
    property bool nvidiaSmiAvailable: false

    // --- live uptime / load ---
    property double uptimeSec: 0
    property double load1: 0
    property double load5: 0
    property double load15: 0

    // --- per-core utilisation ---
    // perCoreUsage: [{ core: "CPU0"|"All", pct: 0..100 }]. "All" is the
    // aggregate (index 0 in /proc/stat); kept as first entry so the UI
    // can show it as the headline pill.
    property var perCoreUsage: []
    property bool statsLoaded: false
    property var _prevStat: null     // { cpuN: { total, idle } }

    // --- top processes by CPU ---
    // [{ pid, name, pct }] — pct is the share of 100 % × cpuCount cores
    // scaled to wall time (so one pinned core on an 8-core box shows
    // ~12 %). Loaded every 3 s (too heavy for 1 s).
    property var topProcs: []
    property bool topProcsLoaded: false
    property int procsUnreadable: 0

    // --- GPU live (nvidia only) ---
    property int  gpuUtilPct: -1
    property int  gpuMemPct: -1
    property double gpuMemUsedMB: 0
    property double gpuMemTotalMB: 0
    property int  gpuTempC: -1
    property var  gpuProcs: []       // [{ pid, name, vramMB }]
    property bool gpuLoaded: false

    // --- fastfetch-style static footer (load-once) ---
    property string osName: ""
    property string arch: ""
    property string shellName: ""
    property string totalRamHuman: ""
    property string resolutions: ""
    property bool footerLoaded: false

    // =============================================================
    // Timers — only run while detailActive
    // =============================================================

    // /proc/stat — 2 s (plan §8.2 bumped from 1.5 s for headroom)
    Timer {
        id: statTimer
        running: root.detailActive
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!statProc.running) statProc.running = true
    }

    // /proc/loadavg + /proc/uptime — 2 s (both cheap)
    Timer {
        id: liveTimer
        running: root.detailActive
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!loadProc.running)   loadProc.running = true
            if (!uptimeProc.running) uptimeProc.running = true
        }
    }

    // /proc/[0-9]*/stat two-snapshot scan — 3 s
    Timer {
        id: topTimer
        running: root.detailActive
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!topProcsProc.running) topProcsProc.running = true
    }

    // nvidia-smi poll — 2 s, only if nvidia-smi exists
    Timer {
        id: nvidiaTimer
        running: root.detailActive && root.nvidiaSmiAvailable
        interval: 2000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!nvidiaProc.running)     nvidiaProc.running = true
            if (!nvidiaProcsProc.running) nvidiaProcsProc.running = true
        }
    }

    // Lifecycle: force-stop every Process and reset the session state
    // on close. /proc/stat delta only makes sense within one session —
    // clearing `_prevStat` so the first tick after re-open seeds fresh.
    onDetailActiveChanged: {
        if (detailActive) {
            // One-shot probes that don't belong to a Timer
            if (!staticInfoProc.running) staticInfoProc.running = true
            if (!gpuDetectProc.running)  gpuDetectProc.running = true
            if (!footerProc.running)     footerProc.running = true
            return
        }
        if (statProc.running)         statProc.running = false
        if (loadProc.running)         loadProc.running = false
        if (uptimeProc.running)       uptimeProc.running = false
        if (topProcsProc.running)     topProcsProc.running = false
        if (nvidiaProc.running)       nvidiaProc.running = false
        if (nvidiaProcsProc.running)  nvidiaProcsProc.running = false
        if (staticInfoProc.running)   staticInfoProc.running = false
        if (gpuDetectProc.running)    gpuDetectProc.running = false
        if (footerProc.running)       footerProc.running = false
        root._prevStat = null
        root.statsLoaded = false
        root.topProcsLoaded = false
        root.gpuLoaded = false
    }

    // =============================================================
    // Processes
    // =============================================================

    // One-shot: kernel, cpu model, cpu count. Reads /proc virtual files;
    // timeout kept for lifecycle-invariant uniformity.
    Process {
        id: staticInfoProc
        command: ["timeout", "2", "bash", "-c",
            "printf 'kernel=%s\\n' \"$(cat /proc/sys/kernel/osrelease 2>/dev/null)\"; " +
            "printf 'model=%s\\n'  \"$(awk -F: '/^model name/{print $2; exit}' /proc/cpuinfo | sed 's/^ *//')\"; " +
            "printf 'cores=%s\\n'  \"$(grep -c '^processor' /proc/cpuinfo)\"; " +
            "printf 'nvsmi=%s\\n'  \"$(command -v nvidia-smi >/dev/null && echo 1 || echo 0)\""
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseStaticInfo(text)
        }
    }

    // GPU vendor/model via sysfs — instant, no nvidia-smi cold start.
    // /sys/class/drm/card*/device/{vendor,device} returns hex PCI IDs;
    // we map a small table of common ones, fall through to raw hex.
    // Only the first GPU (card0) is surfaced — multi-GPU laptops would
    // need a richer UI; punt until asked.
    Process {
        id: gpuDetectProc
        command: ["timeout", "2", "bash", "-c",
            "for c in /sys/class/drm/card[0-9]*/device; do " +
            "  [ -d \"$c\" ] || continue; " +
            "  v=$(cat \"$c/vendor\" 2>/dev/null); " +
            "  d=$(cat \"$c/device\" 2>/dev/null); " +
            "  [ -n \"$v\" ] && [ -n \"$d\" ] && { printf '%s %s\\n' \"$v\" \"$d\"; break; }; " +
            "done"
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseGpuDetect(text)
        }
    }

    // /proc/stat — single snapshot, delta computed in JS against _prevStat.
    Process {
        id: statProc
        command: ["timeout", "2", "cat", "/proc/stat"]
        stdout: StdioCollector {
            onStreamFinished: root._parseStat(text)
        }
    }

    Process {
        id: loadProc
        command: ["timeout", "2", "cat", "/proc/loadavg"]
        stdout: StdioCollector {
            onStreamFinished: root._parseLoad(text)
        }
    }

    Process {
        id: uptimeProc
        command: ["timeout", "2", "cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: root._parseUptime(text)
        }
    }

    // Top CPU processes: two-snapshot gawk over /proc/[0-9]*/stat with a
    // 1 s sleep INSIDE gawk so there is exactly one subprocess per
    // refresh (plan §8.3). Reading from /proc/<pid>/stat field 14 + 15
    // (utime + stime, in clock ticks) gives us the CPU-time delta; we
    // scale against the sampling window (here 1 s) to get percent.
    //
    // Race note: pids may appear/disappear between snapshots. We only
    // emit processes seen in BOTH snapshots. procsUnreadable counts
    // the hidepid/other-UID misses in the first pass (same idiom as
    // MemoryDetail.procsProc, round-3 fix).
    //
    // XDG_RUNTIME_DIR + $$ for the unreadable stderr tmp file — same
    // per-PID isolation as MemoryDetail (round-3 sonnet fix).
    //
    // IMPORTANT: every gawk line is joined with an explicit "\n". Earlier
    // revision used `+ " "` concatenation, which collapsed the program to
    // one physical line — any `#` comment then swallowed the rest of the
    // program (awk comments run to end-of-line), killing the whole top
    // processes section silently. Keep the `\n` terminators even when
    // you delete the inline comments.
    //
    // The `$TMP` path is passed in via `-v TMP="$TMP"` so gawk gets the
    // resolved filename as an awk variable; do NOT inline "$TMP" inside
    // the gawk single-quoted program (bash won't expand it there and
    // gawk would write to a literal file called "$TMP").
    Process {
        id: topProcsProc
        command: ["timeout", "4", "bash", "-c",
            "RUNDIR=\"${XDG_RUNTIME_DIR:-/tmp}\"; " +
            "TMP=\"$RUNDIR/somewm-cpu-unread.$$\"; " +
            "gawk -v TMP=\"$TMP\" '\n" +
            "BEGIN {\n" +
            "    cmd=\"getconf CLK_TCK\"; cmd | getline tck; close(cmd);\n" +
            "    if (tck+0 == 0) tck=100;\n" +
            "    unread=0;\n" +
            "    while ((\"ls -1 /proc/ 2>/dev/null\" | getline pid) > 0) {\n" +
            "        if (pid !~ /^[0-9]+$/) continue;\n" +
            "        f=\"/proc/\" pid \"/stat\";\n" +
            "        if ((getline line < f) <= 0) { unread++; close(f); continue; }\n" +
            "        close(f);\n" +
            "        pos=index(line, \") \"); if (pos==0) continue;\n" +
            "        rest=substr(line, pos+2); n=split(rest, fields, \" \");\n" +
            "        if (n < 13) continue;\n" +
            "        t0[pid] = fields[12] + fields[13];\n" +
            "        a=index(line, \"(\");\n" +
            "        name[pid] = substr(line, a+1, pos-a-1);\n" +
            "    }\n" +
            "    close(\"ls -1 /proc/ 2>/dev/null\");\n" +
            "    system(\"sleep 1\");\n" +
            "    while ((\"ls -1 /proc/ 2>/dev/null\" | getline pid) > 0) {\n" +
            "        if (pid !~ /^[0-9]+$/) continue;\n" +
            "        if (!(pid in t0)) continue;\n" +
            "        f=\"/proc/\" pid \"/stat\";\n" +
            "        if ((getline line < f) <= 0) { close(f); continue; }\n" +
            "        close(f);\n" +
            "        pos=index(line, \") \"); if (pos==0) continue;\n" +
            "        rest=substr(line, pos+2); n=split(rest, fields, \" \");\n" +
            "        if (n < 13) continue;\n" +
            "        t1 = fields[12] + fields[13];\n" +
            "        dt = t1 - t0[pid]; if (dt <= 0) continue;\n" +
            "        pct = (dt * 100.0) / tck;\n" +
            "        printf \"%s\\t%s\\t%.1f\\n\", pid, name[pid], pct;\n" +
            "    }\n" +
            "    close(\"ls -1 /proc/ 2>/dev/null\");\n" +
            "    print unread > TMP;\n" +
            "}' | sort -k3 -n -r | head -15; " +
            "cat \"$TMP\" 2>/dev/null | head -1 | awk '{print \"__unread__=\"$1}'; " +
            "rm -f \"$TMP\" 2>/dev/null"
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseTopProcs(text)
        }
    }

    // nvidia-smi: 5-value query. comma-separated, no header, no units.
    Process {
        id: nvidiaProc
        command: ["timeout", "3", "bash", "-c",
            "nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu " +
            "--format=csv,noheader,nounits 2>/dev/null | head -1"
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseNvidia(text)
        }
    }

    // nvidia-smi compute/graphics apps
    Process {
        id: nvidiaProcsProc
        command: ["timeout", "3", "bash", "-c",
            "{ nvidia-smi --query-compute-apps=pid,process_name,used_memory " +
            "  --format=csv,noheader,nounits 2>/dev/null; " +
            "  nvidia-smi --query-graphics-apps=pid,process_name,used_memory " +
            "  --format=csv,noheader,nounits 2>/dev/null; } | sort -u"
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseGpuProcs(text)
        }
    }

    // Static footer — arch, os, shell, total RAM, resolutions. Load once.
    Process {
        id: footerProc
        command: ["timeout", "3", "bash", "-c",
            "printf 'arch=%s\\n'  \"$(uname -m)\"; " +
            "printf 'os=%s\\n'    \"$(. /etc/os-release 2>/dev/null; echo \"${PRETTY_NAME:-}\")\"; " +
            "printf 'shell=%s\\n' \"$(basename \"${SHELL:-sh}\")\"; " +
            "printf 'ram=%s\\n'   \"$(awk '/^MemTotal/{printf \"%.1f GiB\", $2/1048576; exit}' /proc/meminfo)\"; " +
            "printf 'res=%s\\n'   \"$(command -v swaymsg >/dev/null && swaymsg -t get_outputs 2>/dev/null | " +
            "  awk -F'\"' '/current_mode/{gsub(/[^0-9x@ .]/, \"\", $0); print}' | paste -sd' ' || echo '')\""
        ]
        stdout: StdioCollector {
            onStreamFinished: root._parseFooter(text)
        }
    }

    // =============================================================
    // Parsers
    // =============================================================

    function _parseStaticInfo(text) {
        try {
            var lines = (text || "").split("\n")
            var m = {}
            for (var i = 0; i < lines.length; i++) {
                var kv = lines[i].split("=")
                if (kv.length >= 2) m[kv[0]] = kv.slice(1).join("=").trim()
            }
            root.kernelRelease = m["kernel"] || ""
            root.cpuModel = m["model"] || ""
            root.cpuCount = parseInt(m["cores"]) || 0
            root.nvidiaSmiAvailable = m["nvsmi"] === "1"
        } catch (e) {
            console.error("CpuDetail._parseStaticInfo:", e)
        }
    }

    // PCI ID lookup — tiny table for common desktop GPUs, with a hex
    // fallback. Spec-level IDs change every generation, so we keep the
    // table small (vendor name + a few notable families) and let the
    // fallback carry the rest.
    readonly property var _pciVendors: ({
        "0x10de": "NVIDIA",
        "0x1002": "AMD",
        "0x8086": "Intel"
    })
    function _parseGpuDetect(text) {
        try {
            var t = (text || "").trim()
            if (!t) return
            var parts = t.split(/\s+/)
            if (parts.length < 2) return
            var vendor = _pciVendors[parts[0].toLowerCase()] || parts[0]
            root.gpuVendor = vendor
            root.gpuModel = vendor + " (device " + parts[1] + ")"
        } catch (e) {
            console.error("CpuDetail._parseGpuDetect:", e)
        }
    }

    function _parseStat(text) {
        try {
            var lines = (text || "").split("\n")
            var now = {}
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i]
                if (!/^cpu\d*\s/.test(line)) continue
                var f = line.split(/\s+/)
                // f[0] = "cpu"|"cpuN", f[1..] = user, nice, system, idle,
                // iowait, irq, softirq, steal, guest, guest_nice
                var key = f[0]
                var idle = (parseInt(f[4]) || 0) + (parseInt(f[5]) || 0)
                var total = 0
                for (var j = 1; j < f.length; j++) total += parseInt(f[j]) || 0
                now[key] = { total: total, idle: idle }
            }
            if (root._prevStat) {
                var out = []
                // Keep "cpu" (aggregate) first, then cpu0..cpuN sorted.
                var keys = Object.keys(now).sort(function(a, b) {
                    if (a === "cpu") return -1
                    if (b === "cpu") return 1
                    return parseInt(a.slice(3)) - parseInt(b.slice(3))
                })
                for (var k = 0; k < keys.length; k++) {
                    var key2 = keys[k]
                    if (!root._prevStat[key2]) continue
                    var dTot = now[key2].total - root._prevStat[key2].total
                    var dIdle = now[key2].idle - root._prevStat[key2].idle
                    if (dTot <= 0) continue
                    var pct = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTot)))
                    out.push({
                        core: key2 === "cpu" ? "All" : "C" + key2.slice(3),
                        pct: pct
                    })
                }
                root.perCoreUsage = out
                root.statsLoaded = true
            }
            root._prevStat = now
        } catch (e) {
            console.error("CpuDetail._parseStat:", e)
        }
    }

    function _parseLoad(text) {
        try {
            var t = (text || "").trim().split(/\s+/)
            if (t.length < 3) return
            root.load1 = parseFloat(t[0]) || 0
            root.load5 = parseFloat(t[1]) || 0
            root.load15 = parseFloat(t[2]) || 0
        } catch (e) {
            console.error("CpuDetail._parseLoad:", e)
        }
    }

    function _parseUptime(text) {
        try {
            var t = (text || "").trim().split(/\s+/)
            root.uptimeSec = parseFloat(t[0]) || 0
        } catch (e) {
            console.error("CpuDetail._parseUptime:", e)
        }
    }

    function _parseTopProcs(text) {
        try {
            var body = (text || "")
            var lines = body.split("\n")
            var out = []
            var unread = 0
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i]
                if (!line) continue
                if (line.indexOf("__unread__=") === 0) {
                    unread = parseInt(line.substring(11)) || 0
                    continue
                }
                var parts = line.split("\t")
                if (parts.length < 3) continue
                var pid = parseInt(parts[0]) || 0
                var name = parts[1] || "?"
                var pct = parseFloat(parts[2]) || 0
                if (pid <= 0) continue
                out.push({ pid: pid, name: name, pct: pct })
            }
            out.sort(function(a, b) { return b.pct - a.pct })
            root.topProcs = out.slice(0, 10)
            root.procsUnreadable = unread
            root.topProcsLoaded = true
        } catch (e) {
            console.error("CpuDetail._parseTopProcs:", e)
        }
    }

    function _parseNvidia(text) {
        try {
            var t = (text || "").trim()
            if (!t) return
            var parts = t.split(",").map(function(x) { return x.trim() })
            if (parts.length < 5) return
            root.gpuUtilPct     = parseInt(parts[0])
            root.gpuMemPct      = parseInt(parts[1])
            root.gpuMemUsedMB   = parseFloat(parts[2]) || 0
            root.gpuMemTotalMB  = parseFloat(parts[3]) || 0
            root.gpuTempC       = parseInt(parts[4])
            root.gpuLoaded = true
        } catch (e) {
            console.error("CpuDetail._parseNvidia:", e)
        }
    }

    function _parseGpuProcs(text) {
        try {
            var lines = (text || "").split("\n")
            var out = []
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim()
                if (!line) continue
                var p = line.split(",").map(function(x) { return x.trim() })
                if (p.length < 3) continue
                out.push({
                    pid: parseInt(p[0]) || 0,
                    name: p[1] || "?",
                    vramMB: parseFloat(p[2]) || 0
                })
            }
            root.gpuProcs = out
        } catch (e) {
            console.error("CpuDetail._parseGpuProcs:", e)
        }
    }

    function _parseFooter(text) {
        try {
            var lines = (text || "").split("\n")
            var m = {}
            for (var i = 0; i < lines.length; i++) {
                var kv = lines[i].split("=")
                if (kv.length >= 2) m[kv[0]] = kv.slice(1).join("=").trim()
            }
            root.arch          = m["arch"]  || ""
            root.osName        = m["os"]    || ""
            root.shellName     = m["shell"] || ""
            root.totalRamHuman = m["ram"]   || ""
            root.resolutions   = m["res"]   || ""
            root.footerLoaded = true
        } catch (e) {
            console.error("CpuDetail._parseFooter:", e)
        }
    }

    // =============================================================
    // Actions (footer buttons)
    // =============================================================

    function openHtop() {
        spawnProc.command = ["timeout", "2", "somewm-client", "exec",
            "awful.spawn({\"alacritty\", \"-e\", \"htop\"})"]
        spawnProc.running = true
    }
    function openBtop() {
        spawnProc.command = ["timeout", "2", "somewm-client", "exec",
            "awful.spawn({\"alacritty\", \"-e\", \"btop\"})"]
        spawnProc.running = true
    }
    function openNvidiaSmi() {
        spawnProc.command = ["timeout", "2", "somewm-client", "exec",
            "awful.spawn({\"alacritty\", \"-e\", \"watch\", \"-n\", \"1\", \"nvidia-smi\"})"]
        spawnProc.running = true
    }

    Process { id: spawnProc }
}
