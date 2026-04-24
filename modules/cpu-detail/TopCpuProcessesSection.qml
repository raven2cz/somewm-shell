// TopCpuProcessesSection — top 10 processes by CPU time delta over
// the last 1 s wall (plan §8.3). Mirrors the Memory panel's top-procs
// section down to the _ready gate on the fill bar (plan §3).
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    readonly property var procs: Services.CpuDetail.topProcs
    // For scaling: max observed over the last sample, capped at
    // 100% × cores (a fully-parallel job on an 8-core box can be 800%).
    readonly property real maxPct: {
        if (procs.length === 0) return 1
        var m = procs[0].pct
        for (var i = 1; i < procs.length; i++)
            if (procs[i].pct > m) m = procs[i].pct
        return Math.max(1, m)
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "Top processes (by CPU)"
            accentColor: Core.Theme.widgetCpu
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: !Services.CpuDetail.topProcsLoaded
            text: "Sampling /proc/[pid]/stat…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: Services.CpuDetail.topProcsLoaded && root.procs.length === 0
            text: "No readable processes."
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        Repeater {
            model: root.procs

            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: Core.Theme.spacing.sm

                Components.StyledText {
                    Layout.preferredWidth: Math.round(130 * Core.Theme.dpiScale)
                    text: (modelData.name || "?") +
                          "  " + "<span style='color:" + Core.Theme.fgMuted +
                          "'>" + modelData.pid + "</span>"
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(10 * Core.Theme.dpiScale)
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.04)

                    Rectangle {
                        id: fillBar
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: {
                            var m = Math.max(1, root.maxPct)
                            return Math.max(2, parent.width * (modelData.pct / m))
                        }
                        height: parent.height
                        radius: height / 2
                        color: Qt.rgba(Core.Theme.widgetCpu.r,
                                       Core.Theme.widgetCpu.g,
                                       Core.Theme.widgetCpu.b, 0.65)
                        // Same _ready pattern as MemoryDetail top procs
                        // (plan §3) — 3 s refresh swaps the array whole,
                        // without this the bars sweep from zero every
                        // tick.
                        property bool _ready: false
                        Component.onCompleted: _ready = true
                        Behavior on width {
                            enabled: fillBar._ready
                            NumberAnimation {
                                duration: Core.Anims.duration.smooth
                                easing.type: Core.Anims.ease.decel
                            }
                        }
                    }
                }

                Components.StyledText {
                    Layout.preferredWidth: Math.round(70 * Core.Theme.dpiScale)
                    text: modelData.pct.toFixed(1) + "%"
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        Components.StyledText {
            Layout.fillWidth: true
            visible: Services.CpuDetail.topProcsLoaded &&
                     Services.CpuDetail.procsUnreadable > 0
            wrapMode: Text.WordWrap
            text: Services.CpuDetail.procsUnreadable +
                  " processes not readable (hidepid / other UID). " +
                  "% scaled so one pinned core = 100% / core count."
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.xs
            color: Core.Theme.fgMuted
        }
    }
}
