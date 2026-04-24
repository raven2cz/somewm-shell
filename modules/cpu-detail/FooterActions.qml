// FooterActions — escape hatches: htop / btop / nvidia-smi (plan §8.7).
// nvidia-smi button greys out when the binary isn't found.
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
        iconText: "\ue8f4"       // monitor_heart-ish
        label: "htop"
        accent: Core.Theme.widgetCpu
        onClicked: Services.CpuDetail.openHtop()
    }
    ActionButton {
        iconText: "\ue1bd"       // equalizer-ish
        label: "btop"
        accent: Core.Theme.widgetCpu
        onClicked: Services.CpuDetail.openBtop()
    }
    ActionButton {
        iconText: "\ue30d"       // memory (chip)
        label: "nvidia-smi"
        accent: Core.Theme.widgetCpu
        active: Services.CpuDetail.nvidiaSmiAvailable
        onClicked: Services.CpuDetail.openNvidiaSmi()
    }
}
