pragma Singleton

// DetailController — single authority for the Memory/Storage detail service
// gate properties.
//
// Problem: each detail panel is rendered via `Variants { model: screens }`,
// one instance per screen. If every instance writes to
// `Services.MemoryDetail.detailActive` directly, they all fight the
// singleton and the last writer wins. In practice this works, but the
// per-screen `Component.onDestruction: setter = false` can wipe state
// during normal screen reconfiguration.
//
// This controller subscribes once to `Core.Panels.openPanelsChanged` and
// drives the service gates from a single place — the per-screen panels
// stay read-only.

import QtQuick
import Quickshell
import "." as Core
import "../services" as Services

Singleton {
    id: root

    function _refresh() {
        Services.MemoryDetail.detailActive  = Core.Panels.isOpen("memory-detail")
        Services.StorageDetail.detailActive = Core.Panels.isOpen("storage-detail")
        Services.CpuDetail.detailActive     = Core.Panels.isOpen("cpu-detail")
    }

    Connections {
        target: Core.Panels
        function onOpenPanelsChanged() { root._refresh() }
    }

    Component.onCompleted: _refresh()
}
