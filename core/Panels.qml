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

    // Central registry of panel names.
    //
    // Two lists, ONE source of truth. Keep them declared here (not
    // inlined inside anyOverlayOpen and toggle()) so adding a new detail
    // panel is a single-line edit in each list instead of a triple edit
    // across the file — the old shape bit us when memory/storage were
    // added (review round 1 + gemini). Lists are intentionally
    // asymmetric — see notes below.
    //
    // overlayPanels: every panel that should count as "an overlay is
    // open" for the compositor scroll-guard IPC push. Includes
    // sidebar-left so mouse-wheel over the sidebar doesn't leak to
    // desktop tag-switching.
    readonly property var overlayPanels: [
        "dashboard", "wallpapers", "weather", "ai-chat",
        "sidebar-left",
        "memory-detail", "storage-detail", "cpu-detail",
    ]
    // exclusivePanels: panels that mutually close each other when one
    // opens. DELIBERATELY excludes sidebar-left — the sidebar is a
    // non-mutually-exclusive overlay (it can coexist with the dashboard
    // or a detail panel). Do NOT merge the two lists; the asymmetry is
    // load-bearing and asserted by test-detail-panels.sh.
    readonly property var exclusivePanels: [
        "dashboard", "wallpapers", "weather", "ai-chat",
        "memory-detail", "storage-detail", "cpu-detail",
    ]

    // Track whether any overlay panel is open (for compositor scroll-guard).
    readonly property bool anyOverlayOpen: {
        var panels = openPanels
        for (var i = 0; i < overlayPanels.length; i++) {
            if (panels[overlayPanels[i]] === true) return true
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
        // Mutual exclusion: close overlapping panels (see exclusivePanels
        // declaration above; sidebar-left is deliberately absent).
        var pins = Object.assign({}, panelPin)
        if (!state[name] && exclusivePanels.indexOf(name) >= 0) {
            exclusivePanels.forEach(function(p) {
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
