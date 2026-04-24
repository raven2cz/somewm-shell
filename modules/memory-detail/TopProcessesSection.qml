// TopProcessesSection — top 10 processes by PSS.
//
// PSS = Proportional Set Size: shared pages divided across owners.
// Honest per-process attribution without root. Only counts processes the
// caller can read /proc/<pid>/smaps_rollup for; hidden pids are surfaced
// as a footnote.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    function _fmtMiB(kb) { return (kb / 1024.0).toFixed(0) + " MiB" }

    readonly property var procs: Services.MemoryDetail.topProcesses
    readonly property int maxPss: procs.length > 0 ? procs[0].pssKB : 1

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "Top processes (by PSS)"
            accentColor: Core.Theme.widgetMemory
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: !Services.MemoryDetail.procsLoaded
            text: "Scanning /proc…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: Services.MemoryDetail.procsLoaded && root.procs.length === 0
            text: "No readable processes."
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        Repeater {
            model: root.procs.slice(0, 10)

            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: Core.Theme.spacing.sm

                // name
                Components.StyledText {
                    Layout.preferredWidth: Math.round(130 * Core.Theme.dpiScale)
                    text: (modelData.name || "?") +
                          "  " + "<span style='color:" + Core.Theme.fgMuted +
                          "'>" + modelData.pid + "</span>"
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: modelData.name === "somewm" ? Core.Theme.widgetMemory
                                                       : Core.Theme.fgMain
                }

                // bar
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
                            var m = Math.max(1, root.maxPss)
                            return Math.max(2, parent.width * (modelData.pssKB / m))
                        }
                        height: parent.height
                        radius: height / 2
                        color: modelData.name === "somewm"
                             ? Core.Theme.widgetMemory
                             : Qt.rgba(Core.Theme.widgetMemory.r,
                                       Core.Theme.widgetMemory.g,
                                       Core.Theme.widgetMemory.b, 0.55)

                        // NO Behavior on width here. The Repeater model is
                        // a JS array that the service replaces whole on
                        // each 5 s refresh; QML destroys every delegate
                        // and re-creates it fresh. Any `Behavior on width`
                        // — even with an `_ready` gate flipped in
                        // Component.onCompleted — animates from 0 → target
                        // on EVERY recreation (the first real width
                        // assignment lands AFTER the first layout pass,
                        // and the gate has already opened by then). The
                        // user reads that as "all processes just freed
                        // memory" every 5 seconds.
                        //
                        // Smooth per-tick animation would require a stable
                        // delegate identity (ListModel + setProperty diff)
                        // which is a larger refactor. Snapping to target
                        // is honest and not misleading.
                    }
                }

                // value
                Components.StyledText {
                    Layout.preferredWidth: Math.round(80 * Core.Theme.dpiScale)
                    text: root._fmtMiB(modelData.pssKB)
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        // unreadable footer hint
        Components.StyledText {
            Layout.fillWidth: true
            visible: Services.MemoryDetail.procsLoaded &&
                     Services.MemoryDetail.procsUnreadable > 0
            wrapMode: Text.WordWrap
            text: Services.MemoryDetail.procsUnreadable +
                  " processes not readable (hidepid / other UID / ptrace). " +
                  "Ground truth for readable processes only."
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.xs
            color: Core.Theme.fgMuted
        }
    }
}
