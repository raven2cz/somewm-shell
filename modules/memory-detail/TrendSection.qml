// TrendSection — anchored memory trends scoped to "since this panel open".
//
// RSS gets the sparkline + peak/current labels (Fix A) — it's the one
// metric that benefits from a shape, since operators care whether RSS
// is trending up. Lua heap and wallpaper cache change so slowly that a
// sparkline is low-information density — they get stat cards instead
// (Fix C: current, delta since open, min/max). Both flavours share
// "since open" anchoring so the labels don't drift with wall-clock time.
// Plan §4; MemoryDetail.trend*Init/*Peak/*Max/*Min track the absolutes.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    readonly property int pts: Services.MemoryDetail.trendRss.length

    function _fmtMiB(bytes) { return (bytes / 1048576.0).toFixed(1) + " MiB" }
    function _fmtKbAsMiB(kb) { return (kb / 1024.0).toFixed(1) + " MiB" }
    function _fmtDelta(cur, init) {
        if (init <= 0 || cur <= 0) return "—"
        var d = cur - init
        var s = d >= 0 ? "+" : "−"
        return s + root._fmtMiB(Math.abs(d))
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "Trend (since panel open, 5 s interval)"
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

        // --- RSS: keeps the sparkline because growth shape matters ---
        //
        // RowLayout gives us "label | line | current + peak" on one row,
        // so the graph has scale without a second stacked row wasting
        // vertical space (plan §4 Fix A).
        RowLayout {
            Layout.fillWidth: true
            visible: root.pts >= 2
            spacing: Core.Theme.spacing.sm

            Components.StyledText {
                Layout.preferredWidth: Math.round(60 * Core.Theme.dpiScale)
                text: "RSS"
                font.family: Core.Theme.fontUI
                font.pixelSize: Core.Theme.fontSize.sm
                color: Core.Theme.fgDim
            }
            Components.Graph {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(36 * Core.Theme.dpiScale)
                maxPoints: 60
                lineColor: Core.Theme.widgetMemory
                dataPoints: Services.MemoryDetail.trendRss
            }
            ColumnLayout {
                Layout.preferredWidth: Math.round(120 * Core.Theme.dpiScale)
                spacing: 0
                Components.StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: "cur " + root._fmtKbAsMiB(Services.MemoryDetail.somewmRssKB)
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                }
                Components.StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: "peak " + root._fmtKbAsMiB(Services.MemoryDetail.trendRssPeakKB)
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.xs
                    color: Core.Theme.fgMuted
                }
            }
        }

        // --- Lua + Wallpaper: stat cards (no sparkline, they barely move) ---
        //
        // GridLayout 2×1 so on any reasonable panel width the cards sit
        // side-by-side. The StatCard component is a plain Rectangle with
        // four labels; keeps the implementation legible next to the
        // bespoke RSS row above.
        GridLayout {
            Layout.fillWidth: true
            visible: root.pts >= 2
            columns: 2
            columnSpacing: Core.Theme.spacing.sm
            rowSpacing: Core.Theme.spacing.sm

            component StatCard: Rectangle {
                property string title: ""
                property color accent: Core.Theme.widgetMemory
                property string currentText: "—"
                property string deltaText: "—"
                property string minText: "—"
                property string maxText: "—"
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(78 * Core.Theme.dpiScale)
                radius: Core.Theme.radius.sm
                color: Core.Theme.surfaceContainerHigh
                border.color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Core.Theme.spacing.sm
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        Components.StyledText {
                            Layout.fillWidth: true
                            text: title
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Core.Theme.fontSize.xs
                            color: Core.Theme.fgDim
                        }
                        Components.StyledText {
                            text: deltaText
                            font.family: Core.Theme.fontMono
                            font.pixelSize: Core.Theme.fontSize.xs
                            color: accent
                        }
                    }
                    Components.StyledText {
                        Layout.fillWidth: true
                        text: currentText
                        font.family: Core.Theme.fontMono
                        font.pixelSize: Core.Theme.fontSize.lg
                        font.weight: Font.Medium
                        color: accent
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Core.Theme.spacing.md
                        Components.StyledText {
                            text: "min " + minText
                            font.family: Core.Theme.fontMono
                            font.pixelSize: Core.Theme.fontSize.xs
                            color: Core.Theme.fgMuted
                        }
                        Components.StyledText {
                            text: "max " + maxText
                            font.family: Core.Theme.fontMono
                            font.pixelSize: Core.Theme.fontSize.xs
                            color: Core.Theme.fgMuted
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            StatCard {
                title: "Lua heap"
                accent: "#98c379"
                currentText: root._fmtMiB(Services.MemoryDetail.luaBytes)
                deltaText: root._fmtDelta(Services.MemoryDetail.luaBytes,
                                          Services.MemoryDetail.trendLuaInitBytes)
                minText: root._fmtMiB(Services.MemoryDetail.trendLuaMinBytes)
                maxText: root._fmtMiB(Services.MemoryDetail.trendLuaMaxBytes)
            }
            StatCard {
                title: "Wallpaper cache"
                accent: "#d3869b"
                currentText: root._fmtMiB(Services.MemoryDetail.wallpaperEstBytes)
                deltaText: root._fmtDelta(Services.MemoryDetail.wallpaperEstBytes,
                                          Services.MemoryDetail.trendWpInitBytes)
                minText: root._fmtMiB(Services.MemoryDetail.trendWpMinBytes)
                maxText: root._fmtMiB(Services.MemoryDetail.trendWpMaxBytes)
            }
        }

        Components.StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Δ, min, max anchored to this panel open. Use " +
                  "plans/scripts/somewm-memory-trend.sh for long traces."
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.xs
            color: Core.Theme.fgMuted
        }
    }
}
