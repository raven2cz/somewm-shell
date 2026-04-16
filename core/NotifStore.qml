pragma Singleton

// NotifStore — single source of truth for notification history UI.
//
// Owns the IPC surface for fetching/dismissing/clearing notifications from
// the compositor (awesome._notif_history + naughty.active fallback). Both
// sidebar's NotifHistory.qml and dashboard's NotificationsTab.qml bind to
// this singleton — no duplicate IPC code, no duplicate IpcHandler.
//
// IPC: somewm-shell:notifications { refresh } — single owner.
// Reads: awesome._notif_history, require('naughty').active.
// Writes: awesome._notif_history (table.remove on dismiss; clear on clearAll).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // List in display order: newest-first. QML index i == Lua index (count - i).
    property var notifications: []

    // Fetch from compositor. Uses awesome._notif_history if present,
    // falls back to naughty.active for first-boot scenarios.
    function refresh() {
        fetchProc.running = true
    }

    // Clear all: wipes awesome._notif_history AND destroys live naughty
    // notifications so both backing stores are empty.
    function clearAll() {
        clearProc.running = true
    }

    // Dismiss the notification at QML index `idx`. We display newest-first
    // but Lua stores append-order, so Lua index = count - idx.
    function dismissOne(idx) {
        var count = root.notifications.length
        var luaIdx = count - idx
        dismissProc.command = ["somewm-client", "eval",
            "if awesome._notif_history and #awesome._notif_history >= " + luaIdx +
            " then table.remove(awesome._notif_history, " + luaIdx + ") end; return 'ok'"]
        dismissProc.running = true
    }

    // Copy title + message to clipboard via wl-copy.
    function copyToClipboard(title, message) {
        var content = title || ""
        if (message) content += "\n" + message
        // Single-quote escape for shell
        var escaped = content.replace(/'/g, "'\\''")
        copyProc.command = ["sh", "-c", "printf '%s' '" + escaped + "' | wl-copy"]
        copyProc.running = true
    }

    Process {
        id: fetchProc
        command: ["somewm-client", "eval",
            "local n = require('naughty'); " +
            "local function esc(s) return s:gsub('\\\\','\\\\\\\\'):gsub('\"','\\\\\"'):gsub('\\n','\\\\n'):gsub('\\t','\\\\t'):gsub('\\r','') end " +
            "local json='[' local sep='' " +
            "local all = {} " +
            "if awesome._notif_history and #awesome._notif_history > 0 then " +
            "for _,v in ipairs(awesome._notif_history) do all[#all+1]=v end " +
            "else " +
            "for _,v in ipairs(n.active or {}) do all[#all+1]=v end " +
            "end " +
            "for i=#all,1,-1 do local v=all[i] " +
            "json=json..sep..'{\"title\":\"'..esc(v.title or '')..'\",\"message\":\"'..esc(v.message or '')..'\",\"app\":\"'..esc(v.app_name or '')..'\",' " +
            "..'\"urgency\":\"'..esc(tostring(v.urgency or 'normal'))..'\"}'  " +
            "sep=',' end " +
            "return json..']'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var raw = text.trim()
                    var nl = raw.indexOf("\n")
                    var jsonStr = nl >= 0 ? raw.substring(nl + 1) : raw
                    var data = JSON.parse(jsonStr)
                    root.notifications = data || []
                } catch (e) {
                    console.error("NotifStore parse error:", e)
                    root.notifications = []
                }
            }
        }
    }

    Process {
        id: clearProc
        command: ["somewm-client", "eval",
            "awesome._notif_history = {}; " +
            "for _,n in ipairs(require('naughty').active or {}) do n:destroy() end; return 'ok'"]
        onRunningChanged: {
            if (!running) root.notifications = []
        }
    }

    Process {
        id: dismissProc
        onRunningChanged: {
            if (!running) root.refresh()
        }
    }

    Process { id: copyProc }

    // Single owner of the somewm-shell:notifications IPC target.
    // Notifications.lua pushes refresh on every new naughty entry.
    IpcHandler {
        target: "somewm-shell:notifications"
        function refresh(): void { root.refresh() }
    }

    // No Component.onCompleted here — shell.qml drives the initial
    // refresh as part of forcing singleton instantiation at startup.
    // Avoids the double-refresh we had when both sides called it.
}
