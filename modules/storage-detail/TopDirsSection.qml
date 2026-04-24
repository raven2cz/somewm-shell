// TopDirsSection — biggest top-level directories under $HOME (depth 1).
// Values are a logical-size estimate from `du -sxb` and will differ from
// on-disk consumption when compression / reflinks / sparse files are in
// play (btrfs, bees). Use baobab/filelight for deeper analysis.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    function _fmt(bytes) {
        if (bytes < 1073741824) return (bytes / 1048576.0).toFixed(0) + " MiB"
        return (bytes / 1073741824.0).toFixed(2) + " GiB"
    }

    readonly property var dirs: Services.StorageDetail.topDirs
    readonly property int maxBytes: dirs.length > 0 ? dirs[0].bytes : 1
    // True $HOME total — denominator for the % column. 0 means "not yet
    // loaded" (homeTotalProc running in parallel with topDirsProc); UI
    // renders `—` in that case rather than a wrong-denominator number.
    readonly property double homeTotal: Services.StorageDetail.homeTotalBytes

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "Top $HOME dirs"
            accentColor: Core.Theme.widgetDisk
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: !Services.StorageDetail.topDirsLoaded || Services.StorageDetail.topDirsRunning
            text: "Scanning $HOME (du -sxb)…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: Services.StorageDetail.topDirsLoaded &&
                     !Services.StorageDetail.topDirsRunning &&
                     root.dirs.length === 0
            text: "No readable directories."
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        // Column header — anchors the columns below and gives the "%"
        // column an explicit denominator ("% of $HOME"). Without the
        // header the percent column would be ambiguous — could be read
        // as % of top-10 sum or % of $HOME. The spacer widths mirror
        // the delegate below so the header lines up.
        RowLayout {
            Layout.fillWidth: true
            visible: Services.StorageDetail.topDirsLoaded && root.dirs.length > 0
            spacing: Core.Theme.spacing.sm

            Item { Layout.preferredWidth: Math.round(22 * Core.Theme.dpiScale) }
            Components.StyledText {
                Layout.preferredWidth: Math.round(170 * Core.Theme.dpiScale)
                text: "dir"
                font.pixelSize: Core.Theme.fontSize.xs
                color: Core.Theme.fgDim
            }
            Item { Layout.fillWidth: true }
            Components.StyledText {
                Layout.preferredWidth: Math.round(84 * Core.Theme.dpiScale)
                text: "size"
                font.pixelSize: Core.Theme.fontSize.xs
                color: Core.Theme.fgDim
                horizontalAlignment: Text.AlignRight
            }
            Components.StyledText {
                Layout.preferredWidth: Math.round(42 * Core.Theme.dpiScale)
                text: "% $HOME"
                font.pixelSize: Core.Theme.fontSize.xs
                color: Core.Theme.fgDim
                horizontalAlignment: Text.AlignRight
            }
        }

        Repeater {
            model: root.dirs

            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: Core.Theme.spacing.sm

                // index
                Components.StyledText {
                    Layout.preferredWidth: Math.round(22 * Core.Theme.dpiScale)
                    text: (index + 1) + "."
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMuted
                    horizontalAlignment: Text.AlignRight
                }

                // name
                Components.StyledText {
                    Layout.preferredWidth: Math.round(170 * Core.Theme.dpiScale)
                    text: "~/" + modelData.path
                    elide: Text.ElideMiddle
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                }

                // bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(10 * Core.Theme.dpiScale)
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.04)

                    Rectangle {
                        id: fillBar
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: {
                            var m = Math.max(1, root.maxBytes)
                            return Math.max(2, parent.width * (modelData.bytes / m))
                        }
                        height: parent.height
                        radius: height / 2
                        color: Qt.rgba(Core.Theme.widgetDisk.r,
                                       Core.Theme.widgetDisk.g,
                                       Core.Theme.widgetDisk.b, 0.65)

                        // NO Behavior on width here. The Repeater model is
                        // a JS array that the service replaces whole on
                        // each refresh; QML destroys every delegate and
                        // re-creates it fresh. Any `Behavior on width` —
                        // even with an `_ready` gate flipped in
                        // Component.onCompleted — animates from 0 → target
                        // on EVERY recreation (the first real width
                        // assignment lands AFTER the first layout pass,
                        // and the gate has already opened by then). The
                        // user reads that as a from-zero sweep every
                        // refresh tick.
                        //
                        // Smooth per-tick animation would require a stable
                        // delegate identity (ListModel + setProperty diff)
                        // which is a larger refactor. Snapping to target
                        // is honest and not misleading.
                    }
                }

                // value (absolute GiB/MiB)
                Components.StyledText {
                    Layout.preferredWidth: Math.round(84 * Core.Theme.dpiScale)
                    text: root._fmt(modelData.bytes)
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                    horizontalAlignment: Text.AlignRight
                }

                // share of $HOME (independent of top-10 sum — honest
                // denominator, see services/StorageDetail.qml homeTotalProc).
                // Until that probe lands we show `—` rather than a wrong
                // number. Muted colour keeps the bar the primary visual cue.
                Components.StyledText {
                    Layout.preferredWidth: Math.round(42 * Core.Theme.dpiScale)
                    text: root.homeTotal > 0
                        ? Math.round(100 * modelData.bytes / root.homeTotal) + "%"
                        : "—"
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMuted
                    horizontalAlignment: Text.AlignRight
                }
            }
        }

        Components.StyledText {
            Layout.fillWidth: true
            visible: Services.StorageDetail.topDirsLoaded && root.dirs.length > 0
            wrapMode: Text.WordWrap
            text: "Logical-size estimate (du -sxb). Btrfs reflinks/compression " +
                  "make this differ from on-disk. For exact view open baobab/filelight."
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.xs
            color: Core.Theme.fgMuted
        }
    }
}
