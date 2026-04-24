// FooterActions — escape hatches to richer analysers. All read-only.
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
        property bool active: true
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: Math.round(40 * Core.Theme.dpiScale)
        radius: Core.Theme.radius.sm
        opacity: active ? 1.0 : 0.4
        color: mouseArea.containsMouse && active
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
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (parent.active) parent.clicked()
        }
    }

    ActionButton {
        iconText: "\ue2c7"       // folder_open-ish
        label: "Open baobab"
        accent: Core.Theme.widgetDisk
        active: Services.StorageDetail.baobabAvailable
        onClicked: Services.StorageDetail.openBaobab()
    }
    ActionButton {
        iconText: "\ue2c7"
        label: "Open filelight"
        accent: Core.Theme.widgetDisk
        active: Services.StorageDetail.filelightAvailable
        onClicked: Services.StorageDetail.openFilelight()
    }
    ActionButton {
        iconText: "\ue865"       // open_in_new
        label: "Open $HOME"
        accent: Core.Theme.accent
        onClicked: Services.StorageDetail.openHome()
    }
}
