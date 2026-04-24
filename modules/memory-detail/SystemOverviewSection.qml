// SystemOverviewSection — the honest /proc/meminfo summary.
//
// Left: 4 chip cards (Total / Used / Free NOW / Cached). Right: a stacked
// tri-band bar (Used / Reclaimable / Free) with a one-line explanation.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    function _fmtGiB(kb) {
        return (kb / 1048576.0).toFixed(1) + " GiB"
    }
    function _fmtPct(x) { return Math.round(x * 100) + "%" }

    readonly property bool loaded: Services.MemoryDetail.memTotalKB > 0

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "System overview"
            accentColor: Core.Theme.widgetMemory
            Layout.fillWidth: true
        }

        // --- loading skeleton ---
        Components.StyledText {
            visible: !root.loaded
            text: "Loading /proc/meminfo…"
            color: Core.Theme.fgMuted
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            Layout.fillWidth: true
        }

        // --- chip row: four numbers ---
        GridLayout {
            Layout.fillWidth: true
            visible: root.loaded
            columns: 4
            rowSpacing: Core.Theme.spacing.sm
            columnSpacing: Core.Theme.spacing.sm

            Repeater {
                model: [
                    { label: "Total",
                      value: root._fmtGiB(Services.MemoryDetail.memTotalKB),
                      color: Core.Theme.fgMain },
                    { label: "Used",
                      value: root._fmtGiB(Services.MemoryDetail.usedKB),
                      color: Core.Theme.widgetMemory },
                    { label: "Free NOW",
                      value: root._fmtGiB(Services.MemoryDetail.memAvailKB),
                      color: "#98c379" },
                    { label: "Cached",
                      value: root._fmtGiB(Services.MemoryDetail.memCachedKB +
                                          Services.MemoryDetail.memBuffKB),
                      color: Core.Theme.fgDim }
                ]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(56 * Core.Theme.dpiScale)
                    radius: Core.Theme.radius.sm
                    color: Core.Theme.surfaceContainerHigh
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0

                        Components.StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Core.Theme.fontSize.xs
                            color: Core.Theme.fgDim
                        }
                        Components.StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.value
                            font.family: Core.Theme.fontMono
                            font.pixelSize: Core.Theme.fontSize.lg
                            font.weight: Font.Medium
                            color: modelData.color
                        }
                    }
                }
            }
        }

        // --- legend (used / reclaimable / free) ---
        //
        // Without this the dark-pink / light-pink bar is a colour puzzle.
        // Lives above the bar so the eye picks up the meaning before it
        // hits the visual.
        RowLayout {
            Layout.fillWidth: true
            visible: root.loaded
            spacing: Core.Theme.spacing.md

            Repeater {
                model: [
                    { label: "used",        alpha: 1.00 },
                    { label: "reclaimable", alpha: 0.30 },
                    { label: "free",        alpha: 0.00 }   // free = track colour
                ]
                delegate: RowLayout {
                    spacing: Core.Theme.spacing.xs
                    Rectangle {
                        implicitWidth: Math.round(10 * Core.Theme.dpiScale)
                        implicitHeight: Math.round(10 * Core.Theme.dpiScale)
                        radius: 2
                        color: modelData.alpha > 0
                             ? Qt.rgba(Core.Theme.widgetMemory.r,
                                       Core.Theme.widgetMemory.g,
                                       Core.Theme.widgetMemory.b,
                                       modelData.alpha)
                             : Qt.rgba(1, 1, 1, 0.10)
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1
                    }
                    Components.StyledText {
                        text: modelData.label
                        font.pixelSize: Core.Theme.fontSize.xs
                        color: Core.Theme.fgMuted
                    }
                }
            }
            Item { Layout.fillWidth: true }   // trailing spacer
        }

        // --- stacked bar (used / reclaimable / free) ---
        //
        // Pill shape detail: the TRACK owns the rounded envelope via
        // `radius: height/2` + `clip: true` — clip masks reclaimBar's right
        // edge from bleeding past the cap. usedBar keeps its OWN
        // `radius: height/2` because clip doesn't mask the LEFT side (both
        // usedBar and the track start at x=0, so there's nothing to clip
        // against). reclaimBar is flat (`radius: 0`) so the seam between
        // used/reclaimable is a straight vertical edge, not two rounded
        // caps colliding. All x/width go through Math.round() to avoid
        // fractional-DPI hairline bleed (gemini review round 1 §2).
        Item {
            id: barWrapper
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(22 * Core.Theme.dpiScale)
            visible: root.loaded

            readonly property real totalKB:    Math.max(1, Services.MemoryDetail.memTotalKB)
            readonly property real usedFrac:   Services.MemoryDetail.usedKB / totalKB
            readonly property real reclaimFrac: Services.MemoryDetail.reclaimableKB / totalKB

            Rectangle {
                id: barTrack
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.08)
                clip: true   // masks reclaimBar's right edge past the cap

                // _ready gate for the stacked bars below — shared by
                // usedBar and reclaimBar so they stay in sync.
                //
                // Why: the bars are stable (no Repeater), but the VERY
                // FIRST time /proc/meminfo delivers values memTotalKB
                // flips 0 → N and usedFrac/reclaimFrac flip 0 → real.
                // With an always-on Behavior, that first commit sweeps
                // from 0 → target and looks like a ~200 ms "reveal"
                // every time the user opens the panel (DetailController
                // gates MemoryDetail on detailActive, so memTotalKB
                // IS 0 at panel open until the next refresh tick).
                //
                // Fix: flip _ready true via Qt.callLater AFTER the
                // first data arrival. The first width/x assignment
                // commits with Behavior disabled; subsequent 5 s
                // refreshes animate smoothly.
                property bool _ready: false
                Connections {
                    target: Services.MemoryDetail
                    function onMemTotalKBChanged() {
                        if (Services.MemoryDetail.memTotalKB > 0 && !barTrack._ready)
                            Qt.callLater(function() { barTrack._ready = true })
                    }
                }
                Component.onCompleted: {
                    if (Services.MemoryDetail.memTotalKB > 0)
                        Qt.callLater(function() { barTrack._ready = true })
                }

                Rectangle {
                    id: usedBar
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(2, Math.round(parent.width * barWrapper.usedFrac))
                    radius: height / 2
                    color: Core.Theme.widgetMemory
                    Behavior on width {
                        enabled: barTrack._ready
                        NumberAnimation {
                            duration: Core.Anims.duration.smooth
                            easing.type: Core.Anims.ease.decel
                        }
                    }
                }
                Rectangle {
                    id: reclaimBar
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    x: Math.round(parent.width * barWrapper.usedFrac)
                    width: Math.round(parent.width * barWrapper.reclaimFrac)
                    radius: 0
                    color: Qt.rgba(Core.Theme.widgetMemory.r,
                                   Core.Theme.widgetMemory.g,
                                   Core.Theme.widgetMemory.b, 0.30)
                    Behavior on x {
                        enabled: barTrack._ready
                        NumberAnimation {
                            duration: Core.Anims.duration.smooth
                            easing.type: Core.Anims.ease.decel
                        }
                    }
                    Behavior on width {
                        enabled: barTrack._ready
                        NumberAnimation {
                            duration: Core.Anims.duration.smooth
                            easing.type: Core.Anims.ease.decel
                        }
                    }
                }
            }

            // Centred USED percent, layered above both bars. Outlined for
            // contrast whether the text lands on pink (used) or on the
            // dark track (free) — the label stays in place, the bars slide
            // underneath it.
            Components.StyledText {
                anchors.centerIn: parent
                text: Math.round(100 * barWrapper.usedFrac) + "%"
                font.family: Core.Theme.fontMono
                font.pixelSize: Core.Theme.fontSize.sm
                font.bold: true
                color: "#ffffff"
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.55)
            }

            // Accessibility: hover reveals the exact GiB breakdown so
            // users curious about the colour mapping get the numbers too.
            HoverHandler { id: barHover }
            Components.Tooltip {
                target: barWrapper
                visible: barHover.hovered
                text: {
                    var used  = root._fmtGiB(Services.MemoryDetail.usedKB)
                    var recl  = root._fmtGiB(Services.MemoryDetail.reclaimableKB)
                    var free  = root._fmtGiB(Services.MemoryDetail.memAvailKB)
                    return used + " used · " + recl + " reclaimable · " + free + " free"
                }
            }
        }

        // --- one-line honest summary ---
        Components.StyledText {
            Layout.fillWidth: true
            visible: root.loaded
            wrapMode: Text.WordWrap
            text: {
                var pressurePct = Math.round(100 * (1 - Services.MemoryDetail.availPct))
                return "Real pressure: " + pressurePct + "%. " +
                       "Buff/cache is reclaimable on demand — the kernel will " +
                       "hand it back to apps before calling anything OOM."
            }
            color: Core.Theme.fgMuted
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.sm
        }

        // --- swap row (compact, only if swap exists) ---
        RowLayout {
            Layout.fillWidth: true
            visible: root.loaded && Services.MemoryDetail.swapTotalKB > 0
            spacing: Core.Theme.spacing.sm

            Components.StyledText {
                text: "Swap"
                font.family: Core.Theme.fontUI
                font.pixelSize: Core.Theme.fontSize.sm
                color: Core.Theme.fgDim
                Layout.preferredWidth: Math.round(48 * Core.Theme.dpiScale)
            }
            Components.StyledText {
                Layout.fillWidth: true
                text: {
                    var used = Services.MemoryDetail.swapTotalKB -
                               Services.MemoryDetail.swapFreeKB
                    return root._fmtGiB(used) + " used of " +
                           root._fmtGiB(Services.MemoryDetail.swapTotalKB)
                }
                font.family: Core.Theme.fontMono
                font.pixelSize: Core.Theme.fontSize.sm
                color: Core.Theme.fgMain
            }
        }
    }
}
