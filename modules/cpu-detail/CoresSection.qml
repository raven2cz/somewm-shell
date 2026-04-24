// CoresSection — per-core utilisation bars (plan §8.2).
//
// The first entry in perCoreUsage is "All" (aggregate); we render it
// at the top as a wider headline bar, then cpu0..cpuN below in a
// compact grid so a 12/16-core box doesn't stretch the panel.
//
// Colour: green (cool) → orange → red (hot) by pct. Same _ready gate
// as the Memory panel's top-procs bars so the 2 s refresh doesn't
// sweep every bar from zero each tick.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    readonly property var usage: Services.CpuDetail.perCoreUsage
    readonly property var aggregate: usage.length > 0 && usage[0].core === "All"
                                     ? usage[0] : null
    readonly property var cores: usage.length > 0 && usage[0].core === "All"
                                 ? usage.slice(1) : usage

    // Temperature-style colour ramp: 0..40 green, 40..75 amber, 75+ red.
    function _barColor(pct) {
        if (pct < 40) return "#98c379"
        if (pct < 75) return Core.Theme.widgetCpu
        return "#e06c75"
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "Per-core utilisation"
            accentColor: Core.Theme.widgetCpu
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: !Services.CpuDetail.statsLoaded
            text: "Sampling /proc/stat…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        // Aggregate "All" — single wider bar
        RowLayout {
            Layout.fillWidth: true
            visible: root.aggregate !== null
            spacing: Core.Theme.spacing.sm

            Components.StyledText {
                Layout.preferredWidth: Math.round(40 * Core.Theme.dpiScale)
                text: "All"
                font.family: Core.Theme.fontMono
                font.pixelSize: Core.Theme.fontSize.sm
                color: Core.Theme.fgDim
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(14 * Core.Theme.dpiScale)
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.06)
                clip: true

                Rectangle {
                    id: allBar
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(2, Math.round(parent.width *
                           (root.aggregate ? root.aggregate.pct : 0) / 100))
                    radius: height / 2
                    color: root._barColor(root.aggregate ? root.aggregate.pct : 0)
                    property bool _ready: false
                    Component.onCompleted: _ready = true
                    Behavior on width {
                        enabled: allBar._ready
                        NumberAnimation {
                            duration: Core.Anims.duration.smooth
                            easing.type: Core.Anims.ease.decel
                        }
                    }
                    Behavior on color { Components.CAnim {} }
                }
            }
            Components.StyledText {
                Layout.preferredWidth: Math.round(48 * Core.Theme.dpiScale)
                text: root.aggregate
                    ? Math.round(root.aggregate.pct) + "%"
                    : "—"
                font.family: Core.Theme.fontMono
                font.pixelSize: Core.Theme.fontSize.sm
                color: Core.Theme.fgMain
                horizontalAlignment: Text.AlignRight
            }
        }

        // Per-core grid (2 columns — keeps a 12-core box compact)
        GridLayout {
            Layout.fillWidth: true
            visible: root.cores.length > 0
            columns: 2
            rowSpacing: Core.Theme.spacing.xs
            columnSpacing: Core.Theme.spacing.md

            Repeater {
                model: root.cores
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Core.Theme.spacing.xs
                    Components.StyledText {
                        Layout.preferredWidth: Math.round(32 * Core.Theme.dpiScale)
                        text: modelData.core
                        font.family: Core.Theme.fontMono
                        font.pixelSize: Core.Theme.fontSize.xs
                        color: Core.Theme.fgDim
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(8 * Core.Theme.dpiScale)
                        radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.05)
                        clip: true

                        Rectangle {
                            id: coreBar
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.max(2, Math.round(parent.width *
                                   modelData.pct / 100))
                            radius: height / 2
                            color: root._barColor(modelData.pct)
                            property bool _ready: false
                            Component.onCompleted: _ready = true
                            Behavior on width {
                                enabled: coreBar._ready
                                NumberAnimation {
                                    duration: Core.Anims.duration.smooth
                                    easing.type: Core.Anims.ease.decel
                                }
                            }
                            Behavior on color { Components.CAnim {} }
                        }
                    }
                    Components.StyledText {
                        Layout.preferredWidth: Math.round(40 * Core.Theme.dpiScale)
                        text: Math.round(modelData.pct) + "%"
                        font.family: Core.Theme.fontMono
                        font.pixelSize: Core.Theme.fontSize.xs
                        color: Core.Theme.fgMain
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
