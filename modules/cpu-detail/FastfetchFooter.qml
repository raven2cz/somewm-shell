// FastfetchFooter — static system identity line (plan §8.6). Loads
// once on first panel open and stays put; none of these values change
// during a session.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.xs

        Components.SectionHeader {
            title: "System identity"
            accentColor: Core.Theme.widgetCpu
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: !Services.CpuDetail.footerLoaded
            text: "Loading…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.xs
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            visible: Services.CpuDetail.footerLoaded
            columns: 2
            columnSpacing: Core.Theme.spacing.md
            rowSpacing: 2

            component Row: RowLayout {
                property string label: ""
                property string value: ""
                Layout.fillWidth: true
                spacing: Core.Theme.spacing.sm
                Components.StyledText {
                    Layout.preferredWidth: Math.round(72 * Core.Theme.dpiScale)
                    text: label
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.xs
                    color: Core.Theme.fgDim
                }
                Components.StyledText {
                    Layout.fillWidth: true
                    text: value || "—"
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.xs
                    color: Core.Theme.fgMain
                    elide: Text.ElideRight
                }
            }

            Row { label: "OS";    value: Services.CpuDetail.osName }
            Row { label: "Arch";  value: Services.CpuDetail.arch }
            Row { label: "Shell"; value: Services.CpuDetail.shellName }
            Row { label: "RAM";   value: Services.CpuDetail.totalRamHuman }
            Row {
                label: "Display"
                value: Services.CpuDetail.resolutions || "(somewm)"
            }
            Row { label: "WM"; value: "somewm" }
        }
    }
}
