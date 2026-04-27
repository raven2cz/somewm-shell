// TopGpuProcessesSection — compute + graphics apps from nvidia-smi
// (plan §8.5). Usually 0–3 rows on desktop; no bars needed, just a
// tight list. Hidden on non-NVIDIA systems.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    readonly property var procs: Services.CpuDetail.gpuProcs

    visible: Services.CpuDetail.nvidiaSmiAvailable &&
             Services.CpuDetail.gpuLoaded && procs.length > 0
    implicitHeight: visible ? content.implicitHeight : 0

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "GPU processes"
            accentColor: Core.Theme.widgetCpu
            Layout.fillWidth: true
        }

        Repeater {
            model: root.procs
            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: Core.Theme.spacing.sm
                Components.StyledText {
                    Layout.preferredWidth: Math.round(60 * Core.Theme.dpiScale)
                    text: String(modelData.pid)
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMuted
                    horizontalAlignment: Text.AlignRight
                }
                Components.StyledText {
                    Layout.fillWidth: true
                    text: modelData.name
                    elide: Text.ElideRight
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                }
                Components.StyledText {
                    Layout.preferredWidth: Math.round(50 * Core.Theme.dpiScale)
                    text: (modelData.sm || 0) + "%"
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: (modelData.sm || 0) > 0 ? Core.Theme.widgetCpu
                                                   : Core.Theme.fgMuted
                    horizontalAlignment: Text.AlignRight
                }
                Components.StyledText {
                    Layout.preferredWidth: Math.round(80 * Core.Theme.dpiScale)
                    text: Math.round(modelData.vramMB) + " MiB"
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
