// TrendSection — three small parallel sparklines for RSS, Lua, wallpaper.
// In-memory ring buffer only; use somewm-memory-trend.sh for long traces.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    readonly property int pts: Services.MemoryDetail.trendRss.length

    // Bindings on MiniGraph.samples → Graph.dataPoints propagate array
    // changes automatically — no Connections block needed.

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.xs

        Components.SectionHeader {
            title: "Trend (last 5 min, 5 s interval)"
            accentColor: Core.Theme.widgetMemory
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: root.pts < 2
            text: "Collecting samples…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            visible: root.pts >= 2
            columns: 3
            columnSpacing: Core.Theme.spacing.sm

            component MiniGraph: ColumnLayout {
                property string label: ""
                property color graphColor: Core.Theme.widgetMemory
                property alias graph: _g
                // Renamed from `data` — Item has a default property named
                // `data` that would shadow this and confuse bindings.
                property var samples: []
                spacing: 2
                Components.StyledText {
                    text: label
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.xs
                    color: Core.Theme.fgDim
                }
                Components.Graph {
                    id: _g
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(48 * Core.Theme.dpiScale)
                    maxPoints: 60
                    lineColor: parent.graphColor
                    dataPoints: parent.samples
                    function repaint() { /* data change already triggers repaint */ }
                }
            }

            MiniGraph {
                id: rssGraph
                Layout.fillWidth: true
                label: "RSS"
                graphColor: Core.Theme.widgetMemory
                samples: Services.MemoryDetail.trendRss
            }
            MiniGraph {
                id: luaGraph
                Layout.fillWidth: true
                label: "Lua"
                graphColor: "#98c379"
                samples: Services.MemoryDetail.trendLua
            }
            MiniGraph {
                id: wpGraph
                Layout.fillWidth: true
                label: "Wallpaper"
                graphColor: "#d3869b"
                samples: Services.MemoryDetail.trendWallpaper
            }
        }

        Components.StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Sparks are normalised — RSS/PSS/wallpaper as fraction of " +
                  "RSS. For long traces use plans/scripts/somewm-memory-trend.sh."
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.xs
            color: Core.Theme.fgMuted
        }
    }
}
