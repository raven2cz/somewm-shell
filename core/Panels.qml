pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Keyed visibility: { "dashboard": false, "sidebar": false, ... }
    property var openPanels: ({})

    // OSD state (separate — auto-hide, not user-toggled)
    property bool osdVisible: false
    property string osdType: ""
    property real osdValue: 0

    // Auto-hide timer for OSD (1.5s after last trigger)
    Timer {
        id: osdTimer
        interval: 1500
        repeat: false
        onTriggered: root.osdVisible = false
    }

    function showOsd(type, value) {
        root.osdType = type
        root.osdValue = parseFloat(value) || 0
        root.osdVisible = true
        osdTimer.restart()
    }

    // Requested tab index for dashboard (set by media/notif shortcuts, consumed by Dashboard.qml)
    property int requestedTab: -1

    // Track whether any overlay panel is open (for compositor scroll-guard).
    // Includes non-mutually-exclusive panels like sidebar-left so mouse-wheel
    // over the panel doesn't leak to desktop tag-switching.
    readonly property bool anyOverlayOpen: {
        var panels = openPanels
        var overlays = ["dashboard", "wallpapers", "weather", "ai-chat",
                        "sidebar-left", "memory-detail", "storage-detail"]
        for (var i = 0; i < overlays.length; i++) {
            if (panels[overlays[i]] === true) return true
        }
        return false
    }

    // Pinned screen for a given panel — set by toggleOnScreen(), cleared on close.
    // Panels that find a pin for their name prefer the pinned screen over the
    // globally-focused screen. Used by the memory/storage detail panels so a
    // wibar click on the Samsung TV opens the panel on the Samsung TV, not on
    // whichever screen happens to hold keyboard focus. Consumers read
    // `pinFor(name)` and fall back to Services.Compositor.isActiveScreen.
    property var panelPin: ({})

    function pinFor(name) {
        var p = panelPin[name]
        return (p === undefined) ? "" : p
    }

    function _setPin(name, screenName) {
        var m = Object.assign({}, panelPin)
        if (!screenName || screenName === "") delete m[name]
        else m[name] = screenName
        panelPin = m
    }

    onAnyOverlayOpenChanged: _pushOverlayState()

    function _pushOverlayState() {
        overlayStateProc.command = ["somewm-client", "eval",
            "awesome._shell_overlay = " + (anyOverlayOpen ? "true" : "false")]
        overlayStateProc.running = true
    }

    Process { id: overlayStateProc }

    function isOpen(name) {
        return openPanels[name] === true
    }

    function toggle(name) {
        // Route media/sidebar/notifications to dashboard tabs
        if (name === "media" || name === "performance" || name === "sidebar" || name === "notifications") {
            var tab = name === "media" ? 1 : (name === "performance" ? 2 : (name === "notifications" ? 3 : 0))
            root.requestedTab = tab
            // If dashboard is already open, just switch tab (don't toggle off)
            if (isOpen("dashboard")) return
            return toggle("dashboard")
        }

        var state = Object.assign({}, openPanels)
        // Mutual exclusion: close overlapping panels
        var exclusive = ["dashboard", "wallpapers", "weather", "ai-chat",
                         "memory-detail", "storage-detail"]
        var pins = Object.assign({}, panelPin)
        if (!state[name] && exclusive.indexOf(name) >= 0) {
            exclusive.forEach(function(p) {
                if (state[p]) delete pins[p]
                state[p] = false
            })
        }
        state[name] = !state[name]
        openPanels = state
        // Clear any pin when the panel closes
        if (!state[name]) delete pins[name]
        panelPin = pins
    }

    // Toggle a panel and pin it to a specific screen (by name or index string).
    // If the panel is being closed, the pin is cleared.
    //
    // Ordering is load-bearing: `_setPin` writes to the live `panelPin` first,
    // then `toggle()` snapshots `panelPin` via `Object.assign({}, panelPin)`
    // so the new pin survives the mutual-exclusion rewrite. Do not swap the
    // two calls or move `panelPin = pins` earlier inside `toggle()` — the new
    // pin would be silently dropped (review round 2, sonnet).
    function toggleOnScreen(name, screenName) {
        var willOpen = !openPanels[name]
        if (willOpen) _setPin(name, screenName)
        toggle(name)
    }

    function close(name) {
        if (openPanels[name]) {
            var state = Object.assign({}, openPanels)
            state[name] = false
            openPanels = state
        }
        _setPin(name, "")
    }

    function closeAll() {
        openPanels = ({})
        panelPin = ({})
    }

    // IPC: external control from rc.lua via qs ipc
    IpcHandler {
        target: "somewm-shell:panels"
        function toggle(name: string): void   { root.toggle(name) }
        function toggleOnScreen(name: string, screenName: string): void {
            root.toggleOnScreen(name, screenName)
        }
        function close(name: string): void    { root.close(name) }
        function closeAll(): void             { root.closeAll() }
        function showOsd(type: string, value: string): void { root.showOsd(type, value) }
    }
}
