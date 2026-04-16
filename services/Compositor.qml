pragma Singleton

// Compositor — bridge to somewm: clients, tags, focused screen, active tag.
//
// Debounced refresh via `somewm-client eval`; compositor pushes invalidate /
// setScreen / setTag signals from rc.lua. Typed focus/spawn — no raw eval.
// IPC: somewm-shell:compositor { invalidate, setScreen, setTag, focus, spawn }

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var clients: []
    property var tags: []
    property string focusedClient: ""
    // Set by screenProc on startup, then updated by rc.lua screen::focus signal.
    property string focusedScreenName: ""
    // Active tag name on the focused screen (legacy global — kept for
    // single-monitor consumers and as fallback when per-screen data is missing).
    property string activeTag: ""
    // Per-screen active tag: { screenName: tagName }. Populated via
    // setTagScr() IPC so consumers on multi-monitor setups can show the
    // correct tag on each physical screen instead of mirroring activeTag.
    property var activeTagByScreen: ({})

    // Lookup helper — returns per-screen active tag, or activeTag as fallback.
    function activeTagFor(screenName: string): string {
        var t = activeTagByScreen[screenName]
        return (t !== undefined && t !== "") ? t : activeTag
    }

    // Update per-screen active tag. Exposed on root (not just via IPC)
    // so in-process QML consumers can call it directly (e.g. Collage panels
    // seeding their own screen's tag at startup or during slide animations).
    function setTagScr(screenName: string, tagName: string): void {
        var m = activeTagByScreen
        m[screenName] = tagName
        // Reassign to trigger QML binding re-evaluation.
        activeTagByScreen = Object.assign({}, m)
        if (screenName === focusedScreenName)
            activeTag = tagName
    }

    // Check if a given screen is the focused one.
    // Used by all panel modules to target the correct monitor.
    function isActiveScreen(screenData): bool {
        return screenData.name === focusedScreenName ||
               String(screenData.index) === focusedScreenName
    }

    // Debounce: coalesce rapid push events into a single refresh
    property bool _dirty: false
    Timer {
        id: debounceTimer
        interval: 50  // 50ms coalesce window
        onTriggered: root._doRefresh()
    }

    function _doRefresh() {
        if (stateProc.running) {
            // stateProc busy — set dirty flag, will re-run on finish
            root._dirty = true
        } else {
            root._dirty = false
            stateProc.running = true
        }
    }

    // somewm-client eval returns "OK\n<value>" — strip prefix
    function _ipcValue(raw) {
        var s = raw.trim()
        var nl = s.indexOf("\n")
        return nl >= 0 ? s.substring(nl + 1) : s
    }

    // === Typed commands (no raw eval exposed!) ===
    function _luaEscape(str) {
        // Escape backslashes first, then single quotes (order matters!)
        return str.replace(/\\/g, "\\\\").replace(/'/g, "\\'").replace(/\n/g, "\\n")
    }

    function focusClient(windowId) {
        var wid = parseInt(windowId)
        if (isNaN(wid) || wid === 0) return
        _run("for _,c in ipairs(client.get()) do " +
             "if c.window==" + wid + " then " +
             "if c.first_tag then c.first_tag:view_only() end; " +
             "c:activate{raise=true} return end end")
    }

    // Legacy: focus by class (first match)
    function focusClientByClass(className) {
        var safe = _luaEscape(className)
        _run("for _,c in ipairs(client.get()) do " +
             "if c.class=='" + safe + "' then c:activate{raise=true} return end end")
    }

    function viewTag(idx) {
        _run("require('awful').tag.viewidx(" + parseInt(idx) + ")")
    }

    function spawn(cmd) {
        var safe = _luaEscape(cmd)
        _run("require('awful').spawn('" + safe + "')")
    }

    // Private: fire-and-forget somewm-client call with command queue
    property var _cmdQueue: []
    function _run(lua) {
        _cmdQueue.push(lua)
        _drainQueue()
    }
    function _drainQueue() {
        if (runProc.running || _cmdQueue.length === 0) return
        var lua = _cmdQueue.shift()
        runProc.command = ["somewm-client", "eval", lua]
        runProc.running = true
    }
    Process {
        id: runProc
        onRunningChanged: if (!running) root._drainQueue()
    }

    // === State refresh (triggered by push IPC, debounced) ===
    function _refreshState() {
        // Coalesce: restart debounce timer on each push
        debounceTimer.restart()
    }

    Process {
        id: stateProc
        command: ["somewm-client", "eval",
            "local function esc(s) return s:gsub('\\\\','\\\\\\\\'):gsub('\"','\\\\\"'):gsub('\\n','\\\\n'):gsub('\\t','\\\\t'):gsub('\\r','') end " +
            "local json='{\"clients\":[' local sep='' " +
            "for _,c in ipairs(client.get()) do " +
            "json=json..sep..'{\"name\":\"'..esc(c.name or '')..'\",\"class\":\"'..esc(c.class or '')" +
            "..'\",\"tag\":\"'..esc(c.first_tag and c.first_tag.name or '')..'\",\"wid\":'..tostring(c.window or 0)..'}' " +
            "sep=',' end " +
            "local fs = require('awful').screen.focused() " +
            "json=json..'],\"focusedScreen\":\"'..esc(fs and (fs.name or tostring(fs.index)) or '')..'\"}' " +
            "return json"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(root._ipcValue(text))
                    root.clients = data.clients || []
                    if (data.focusedScreen)
                        root.focusedScreenName = data.focusedScreen
                } catch (e) {
                    console.error("Client state parse error:", e)
                    root.clients = []
                }
            }
        }
        // Re-run if dirty (invalidation arrived during refresh)
        onRunningChanged: {
            if (!running && root._dirty) root._doRefresh()
        }
    }

    // IPC: compositor pushes invalidate, shell refreshes
    IpcHandler {
        target: "somewm-shell:compositor"
        function invalidate(): void { root._refreshState() }
        // Focused screen tracking (pushed from rc.lua screen::focus signal)
        function setScreen(name: string): void { root.focusedScreenName = name }
        // Active tag tracking (pushed from rc.lua tag::selected signal).
        // Legacy single-arg form — updates only the global activeTag.
        function setTag(name: string): void { root.activeTag = name }
        // Screen-aware form — delegates to root.setTagScr so the same
        // logic is callable both via IPC (from rc.lua) and directly from
        // in-process QML (e.g. Collage panels).
        function setTagScr(screenName: string, tagName: string): void {
            root.setTagScr(screenName, tagName)
        }
        // No eval() exposed! Only typed commands.
        function focus(cls: string): void { root.focusClientByClass(cls) }
        function spawn(cmd: string): void { root.spawn(cmd) }
    }

    // Initial state fetch — stateProc returns clients + focusedScreen in one call
    Component.onCompleted: _refreshState()
}
