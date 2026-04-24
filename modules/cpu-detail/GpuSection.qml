// GpuSection — NVIDIA-only live telemetry. Gated on
// CpuDetail.nvidiaSmiAvailable; hidden (zero height) on other GPUs
// rather than showing "not supported" noise (plan §8.4).
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    // Collapse to zero height when nvidia-smi isn't available so the
    // enclosing ColumnLayout spacing doesn't leave an orphan gap.
    visible: Services.CpuDetail.nvidiaSmiAvailable
    implicitHeight: visible ? content.implicitHeight : 0

    function _tempColor(c) {
        if (c < 0) return Core.Theme.fgMain
        if (c < 70) return "#98c379"
        if (c < 85) return Core.Theme.widgetCpu
        return "#e06c75"
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "GPU (nvidia-smi)"
            accentColor: Core.Theme.widgetCpu
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: !Services.CpuDetail.gpuLoaded
            text: "Querying nvidia-smi…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            visible: Services.CpuDetail.gpuLoaded
            columns: 4
            rowSpacing: Core.Theme.spacing.sm
            columnSpacing: Core.Theme.spacing.sm

            component StatCard: Rectangle {
                property string title: ""
                property string value: "—"
                property color valueColor: Core.Theme.fgMain
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(58 * Core.Theme.dpiScale)
                radius: Core.Theme.radius.sm
                color: Core.Theme.surfaceContainerHigh
                border.color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    Components.StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: title
                        font.family: Core.Theme.fontUI
                        font.pixelSize: Core.Theme.fontSize.xs
                        color: Core.Theme.fgDim
                    }
                    Components.StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: value
                        font.family: Core.Theme.fontMono
                        font.pixelSize: Core.Theme.fontSize.lg
                        font.weight: Font.Medium
                        color: valueColor
                    }
                }
            }

            StatCard {
                title: "GPU"
                value: Services.CpuDetail.gpuUtilPct >= 0
                    ? Services.CpuDetail.gpuUtilPct + "%" : "—"
                valueColor: Core.Theme.widgetCpu
            }
            StatCard {
                title: "VRAM"
                value: Services.CpuDetail.gpuMemPct >= 0
                    ? Services.CpuDetail.gpuMemPct + "%" : "—"
                valueColor: Core.Theme.widgetCpu
            }
            StatCard {
                title: "VRAM MiB"
                value: Services.CpuDetail.gpuMemTotalMB > 0
                    ? Math.round(Services.CpuDetail.gpuMemUsedMB) + " / " +
                      Math.round(Services.CpuDetail.gpuMemTotalMB)
                    : "—"
            }
            StatCard {
                title: "Temp"
                value: Services.CpuDetail.gpuTempC >= 0
                    ? Services.CpuDetail.gpuTempC + " °C" : "—"
                valueColor: root._tempColor(Services.CpuDetail.gpuTempC)
            }
        }
    }
}
