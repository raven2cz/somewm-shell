// SystemSection — compact label/value grid for kernel, uptime, load,
// CPU model, core count, and GPU (plan §8.1). All values are either
// one-shot reads (kernelRelease, cpuModel, cpuCount, gpuModel) or
// cheap polls (uptime, load). Read-only; no actions.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    function _fmtUptime(sec) {
        if (sec <= 0) return "—"
        var d = Math.floor(sec / 86400)
        var h = Math.floor((sec % 86400) / 3600)
        var m = Math.floor((sec % 3600) / 60)
        if (d > 0) return d + " d " + h + " h"
        if (h > 0) return h + " h " + m + " m"
        return m + " m"
    }

    // Red the 1-min load if it exceeds the core count (classic
    // "saturated box" signal; not a bug, but worth flagging visually).
    function _loadColor(l1, cores) {
        if (cores > 0 && l1 > cores) return "#e06c75"
        return Core.Theme.fgMain
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "System"
            accentColor: Core.Theme.widgetCpu
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Core.Theme.spacing.md
            rowSpacing: Core.Theme.spacing.xs

            component Row: RowLayout {
                property string label: ""
                property string value: ""
                property color valueColor: Core.Theme.fgMain
                Layout.fillWidth: true
                spacing: Core.Theme.spacing.sm
                Components.StyledText {
                    Layout.preferredWidth: Math.round(92 * Core.Theme.dpiScale)
                    text: label
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.xs
                    color: Core.Theme.fgDim
                }
                Components.StyledText {
                    Layout.fillWidth: true
                    text: value
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: valueColor
                    elide: Text.ElideRight
                }
            }

            Row {
                label: "Kernel"
                value: Services.CpuDetail.kernelRelease || "—"
            }
            Row {
                label: "Uptime"
                value: root._fmtUptime(Services.CpuDetail.uptimeSec)
            }
            Row {
                label: "CPU"
                value: Services.CpuDetail.cpuModel || "—"
            }
            Row {
                label: "Cores"
                value: Services.CpuDetail.cpuCount > 0
                    ? String(Services.CpuDetail.cpuCount)
                    : "—"
            }
            Row {
                label: "Load"
                valueColor: root._loadColor(Services.CpuDetail.load1,
                                             Services.CpuDetail.cpuCount)
                value: (Services.CpuDetail.load1 > 0)
                    ? Services.CpuDetail.load1.toFixed(2) + "  " +
                      Services.CpuDetail.load5.toFixed(2) + "  " +
                      Services.CpuDetail.load15.toFixed(2)
                    : "—"
            }
            Row {
                label: "GPU"
                value: Services.CpuDetail.gpuModel || "—"
            }
        }
    }
}
