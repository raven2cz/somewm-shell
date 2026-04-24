// MemoryDetailPanel — layer-shell overlay with a scrollable column of
// sections. Mirrors the WeatherPanel.qml shape (Variants + PanelWindow +
// GlassCard). Gate is driven by Core.DetailController.
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

        readonly property string pinned: Core.Panels.pinFor("memory-detail")
        property bool shouldShow: Core.Panels.isOpen("memory-detail") && (
            pinned !== ""
                ? (modelData.name === pinned || String(modelData.index) === pinned)
                : Services.Compositor.isActiveScreen(modelData))

        visible: shouldShow || fadeAnim.running

        color: "transparent"
        focusable: shouldShow

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "somewm-shell:memory-detail"
        WlrLayershell.keyboardFocus: shouldShow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors { top: true; right: true }
        margins.top: 50
        margins.right: 20

        implicitWidth: Math.round(580 * Core.Theme.dpiScale)
        // Grow vertically on 4K/portrait screens: (modelData.height - 120)
        // gives a screen-edge safety margin, capped at 1400 px so a 3840 px
        // portrait HP display doesn't turn the panel into a column the user
        // has to crane their neck to read. On 1080p/1440p the
        // (height - 120) term rules; on 4K the 760 ceiling is lifted.
        implicitHeight: Math.min(
            Math.round(1400 * Core.Theme.dpiScale),
            modelData && modelData.height ? modelData.height - 120
                                          : Math.round(760 * Core.Theme.dpiScale))

        mask: Region { item: card }

        Components.GlassCard {
            id: card
            anchors.fill: parent
            focus: panel.shouldShow
            Keys.onEscapePressed: Core.Panels.close("memory-detail")

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
                        icon: "\ue1db"       // memory_alt
                        size: Core.Theme.fontSize.xl
                        color: Core.Theme.widgetMemory
                    }

                    Components.StyledText {
                        Layout.fillWidth: true
                        text: "Memory"
                        font.pixelSize: Core.Theme.fontSize.xl
                        font.weight: Font.DemiBold
                        color: Core.Theme.widgetMemory
                    }

                    // Honest "Free NOW" chip
                    Rectangle {
                        Layout.preferredHeight: Math.round(26 * Core.Theme.dpiScale)
                        Layout.preferredWidth: chipText.implicitWidth + Core.Theme.spacing.md * 2
                        radius: height / 2
                        color: Qt.rgba(Core.Theme.widgetMemory.r,
                                       Core.Theme.widgetMemory.g,
                                       Core.Theme.widgetMemory.b, 0.15)
                        border.color: Qt.rgba(Core.Theme.widgetMemory.r,
                                              Core.Theme.widgetMemory.g,
                                              Core.Theme.widgetMemory.b, 0.30)
                        border.width: 1
                        visible: Services.MemoryDetail.memTotalKB > 0

                        Components.StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: {
                                var avail = Services.MemoryDetail.memAvailKB / 1048576
                                return "Free now: " + avail.toFixed(1) + " GiB"
                            }
                            font.family: Core.Theme.fontMono
                            font.pixelSize: Core.Theme.fontSize.sm
                            color: Core.Theme.widgetMemory
                        }
                    }

                    Components.MaterialIcon {
                        icon: "\ue5d5"       // refresh
                        size: Core.Theme.fontSize.lg
                        color: refreshMouse.containsMouse ? Core.Theme.fgMain : Core.Theme.fgDim
                        Behavior on color { Components.CAnim {} }
                        MouseArea {
                            id: refreshMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.MemoryDetail.refresh()
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
                            onClicked: Core.Panels.close("memory-detail")
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

                        SystemOverviewSection  { Layout.fillWidth: true }
                        SomewmInternalsSection { Layout.fillWidth: true }
                        TopProcessesSection    { Layout.fillWidth: true }
                        TrendSection           { Layout.fillWidth: true }
                    }
                }

                FooterActions { Layout.fillWidth: true }
            }
        }
    }
}
