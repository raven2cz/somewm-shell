// StorageDetailPanel — layer-shell overlay mirroring MemoryDetailPanel.
// Gate driven by Core.DetailController; shown on the pinned screen (from
// wibar click) or the active screen (from dashboard gear).
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

        readonly property string pinned: Core.Panels.pinFor("storage-detail")
        property bool shouldShow: Core.Panels.isOpen("storage-detail") && (
            pinned !== ""
                ? (modelData.name === pinned || String(modelData.index) === pinned)
                : Services.Compositor.isActiveScreen(modelData))

        visible: shouldShow || fadeAnim.running

        color: "transparent"
        focusable: shouldShow

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "somewm-shell:storage-detail"
        WlrLayershell.keyboardFocus: shouldShow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors { top: true; right: true }
        margins.top: 50
        margins.right: 20

        implicitWidth: Math.round(620 * Core.Theme.dpiScale)
        // See MemoryDetailPanel.qml for the 1400 px cap rationale.
        implicitHeight: Math.min(
            Math.round(1400 * Core.Theme.dpiScale),
            modelData && modelData.height ? modelData.height - 120
                                          : Math.round(820 * Core.Theme.dpiScale))

        mask: Region { item: card }

        Components.GlassCard {
            id: card
            anchors.fill: parent
            focus: panel.shouldShow
            Keys.onEscapePressed: Core.Panels.close("storage-detail")

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
                        icon: "\ue1db"       // storage (reuse memory-like glyph; theme accent disambiguates)
                        size: Core.Theme.fontSize.xl
                        color: Core.Theme.widgetDisk
                    }

                    Components.StyledText {
                        Layout.fillWidth: true
                        text: "Storage"
                        font.pixelSize: Core.Theme.fontSize.xl
                        font.weight: Font.DemiBold
                        color: Core.Theme.widgetDisk
                    }

                    // Mounts summary chip: "N mounts" once loaded
                    Rectangle {
                        Layout.preferredHeight: Math.round(26 * Core.Theme.dpiScale)
                        Layout.preferredWidth: chipText.implicitWidth + Core.Theme.spacing.md * 2
                        radius: height / 2
                        color: Qt.rgba(Core.Theme.widgetDisk.r,
                                       Core.Theme.widgetDisk.g,
                                       Core.Theme.widgetDisk.b, 0.15)
                        border.color: Qt.rgba(Core.Theme.widgetDisk.r,
                                              Core.Theme.widgetDisk.g,
                                              Core.Theme.widgetDisk.b, 0.30)
                        border.width: 1
                        visible: Services.StorageDetail.mountsLoaded

                        Components.StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: Services.StorageDetail.mounts.length + " mounts"
                            font.family: Core.Theme.fontMono
                            font.pixelSize: Core.Theme.fontSize.sm
                            color: Core.Theme.widgetDisk
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
                            onClicked: Services.StorageDetail.refresh()
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
                            onClicked: Core.Panels.close("storage-detail")
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

                        MountsSection   { Layout.fillWidth: true }
                        HotspotsSection { Layout.fillWidth: true }
                        TopDirsSection  { Layout.fillWidth: true }
                    }
                }

                FooterActions { Layout.fillWidth: true }
            }
        }
    }
}
