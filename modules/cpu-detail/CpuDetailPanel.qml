// CpuDetailPanel — layer-shell overlay for CPU + GPU telemetry. Mirrors
// MemoryDetailPanel / StorageDetailPanel (Variants + PanelWindow +
// GlassCard + ScrollArea). Gate comes from Core.DetailController.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: panel

        required property var modelData
        screen: modelData

        readonly property string pinned: Core.Panels.pinFor("cpu-detail")
        property bool shouldShow: Core.Panels.isOpen("cpu-detail") && (
            pinned !== ""
                ? (modelData.name === pinned || String(modelData.index) === pinned)
                : Services.Compositor.isActiveScreen(modelData))

        visible: shouldShow || fadeAnim.running

        color: "transparent"
        focusable: shouldShow

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "somewm-shell:cpu-detail"
        WlrLayershell.keyboardFocus: shouldShow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors { top: true; right: true }
        margins.top: 50
        margins.right: 20

        implicitWidth: Math.round(640 * Core.Theme.dpiScale)
        // Same sizing rule as Memory/Storage detail panels (plan §1): the
        // 1400 px cap keeps portrait-HP usable, (height - 120) drives
        // 4K/landscape growth. The CPU panel carries more sections
        // (System / Cores / Top / GPU / TopGPU / Fastfetch) so it needs
        // the height more than the others.
        implicitHeight: Math.min(
            Math.round(1400 * Core.Theme.dpiScale),
            modelData && modelData.height ? modelData.height - 120
                                          : Math.round(820 * Core.Theme.dpiScale))

        mask: Region { item: card }

        Components.GlassCard {
            id: card
            anchors.fill: parent
            focus: panel.shouldShow
            Keys.onEscapePressed: Core.Panels.close("cpu-detail")

            opacity: panel.shouldShow ? 1.0 : 0.0
            scale: panel.shouldShow ? 1.0 : 0.96

            Behavior on opacity {
                NumberAnimation {
                    id: fadeAnim
                    duration: Core.Anims.duration.normal
                    easing.type: Core.Anims.ease.decel
                }
            }
            Behavior on scale { Components.Anim {} }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Core.Theme.spacing.lg
                spacing: Core.Theme.spacing.md

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Core.Theme.spacing.sm

                    Components.MaterialIcon {
                        icon: "\ue30d"       // memory (chip-like)
                        size: Core.Theme.fontSize.xl
                        color: Core.Theme.widgetCpu
                    }

                    Components.StyledText {
                        Layout.fillWidth: true
                        text: "CPU · GPU"
                        font.pixelSize: Core.Theme.fontSize.xl
                        font.weight: Font.DemiBold
                        color: Core.Theme.widgetCpu
                    }

                    // Headline aggregate pct chip — first entry is "All"
                    Rectangle {
                        Layout.preferredHeight: Math.round(26 * Core.Theme.dpiScale)
                        Layout.preferredWidth: chipText.implicitWidth + Core.Theme.spacing.md * 2
                        radius: height / 2
                        visible: Services.CpuDetail.perCoreUsage.length > 0
                        color: Qt.rgba(Core.Theme.widgetCpu.r,
                                       Core.Theme.widgetCpu.g,
                                       Core.Theme.widgetCpu.b, 0.15)
                        border.color: Qt.rgba(Core.Theme.widgetCpu.r,
                                              Core.Theme.widgetCpu.g,
                                              Core.Theme.widgetCpu.b, 0.30)
                        border.width: 1

                        Components.StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: {
                                var all = Services.CpuDetail.perCoreUsage[0]
                                if (!all) return "—"
                                return "CPU " + Math.round(all.pct) + "%"
                            }
                            font.family: Core.Theme.fontMono
                            font.pixelSize: Core.Theme.fontSize.sm
                            color: Core.Theme.widgetCpu
                        }
                    }

                    Components.MaterialIcon {
                        icon: "\ue5cd"       // close
                        size: Core.Theme.fontSize.lg
                        color: closeMouse.containsMouse ? Core.Theme.fgMain : Core.Theme.fgDim
                        Behavior on color { Components.CAnim {} }
                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Core.Panels.close("cpu-detail")
                        }
                    }
                }

                // Scrollable content
                Components.ScrollArea {
                    id: scroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    contentWidth: width
                    contentHeight: inner.implicitHeight

                    ColumnLayout {
                        id: inner
                        width: scroll.width
                        spacing: Core.Theme.spacing.md

                        SystemSection         { Layout.fillWidth: true }
                        CoresSection          { Layout.fillWidth: true }
                        TopCpuProcessesSection { Layout.fillWidth: true }
                        GpuSection            { Layout.fillWidth: true }
                        TopGpuProcessesSection { Layout.fillWidth: true }
                        FastfetchFooter       { Layout.fillWidth: true }
                    }
                }

                FooterActions { Layout.fillWidth: true }
            }
        }
    }
}
