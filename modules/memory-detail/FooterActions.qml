// FooterActions — Force GC, Copy snapshot, Open baseline.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

RowLayout {
    id: root
    spacing: Core.Theme.spacing.sm

    component ActionButton: Rectangle {
        property string label: ""
        property string iconText: ""
        property color accent: Core.Theme.accent
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(40 * Core.Theme.dpiScale)
        radius: Core.Theme.radius.sm
        color: mouse.containsMouse
             ? Qt.rgba(accent.r, accent.g, accent.b, 0.18)
             : Qt.rgba(accent.r, accent.g, accent.b, 0.10)
        border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.30)
        border.width: 1
        Behavior on color { Components.CAnim {} }

        RowLayout {
            anchors.centerIn: parent
            spacing: Core.Theme.spacing.xs
            Components.MaterialIcon {
                icon: iconText
                size: Core.Theme.fontSize.base
                color: accent
            }
            Components.StyledText {
                text: label
                font.family: Core.Theme.fontUI
                font.pixelSize: Core.Theme.fontSize.sm
                color: accent
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    ActionButton {
        iconText: "\ue872"       // delete (broom-ish)
        label: "Force Lua GC"
        accent: "#98c379"
        onClicked: Services.MemoryDetail.forceGc()
    }
    ActionButton {
        iconText: "\ue14d"       // content_copy
        label: "Copy snapshot"
        accent: Core.Theme.widgetMemory
        onClicked: Services.MemoryDetail.copySnapshot()
    }
    ActionButton {
        iconText: "\ue865"       // open_in_new
        label: "Open baseline"
        accent: Core.Theme.accent
        onClicked: Services.MemoryDetail.openBaseline()
    }
}
