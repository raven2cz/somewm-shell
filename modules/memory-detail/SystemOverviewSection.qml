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

        // --- stacked bar ---
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(18 * Core.Theme.dpiScale)
            visible: root.loaded

            readonly property real totalKB:  Math.max(1, Services.MemoryDetail.memTotalKB)
            readonly property real usedFrac: Services.MemoryDetail.usedKB / totalKB
            readonly property real reclaimFrac: Services.MemoryDetail.reclaimableKB / totalKB

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.04)
            }

            // Used (opaque accent)
            Rectangle {
                height: parent.height
                width: Math.max(2, parent.width * parent.usedFrac)
                radius: height / 2
                color: Core.Theme.widgetMemory
                Behavior on width {
                    NumberAnimation {
                        duration: Core.Anims.duration.smooth
                        easing.type: Core.Anims.ease.decel
                    }
                }
            }
            // Reclaimable (semi-transparent accent)
            Rectangle {
                x: parent.width * parent.usedFrac
                height: parent.height
                width: parent.width * parent.reclaimFrac
                radius: 0
                color: Qt.rgba(Core.Theme.widgetMemory.r,
                               Core.Theme.widgetMemory.g,
                               Core.Theme.widgetMemory.b, 0.30)
                Behavior on width {
                    NumberAnimation {
                        duration: Core.Anims.duration.smooth
                        easing.type: Core.Anims.ease.decel
                    }
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
