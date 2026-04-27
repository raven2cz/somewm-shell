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
    // True $HOME total — single denominator for both the % column and
    // the bar fill. Falls back to dirs[0].bytes only until homeTotalProc
    // finishes; that fallback would scale the largest dir to 100 %, which
    // is visually meaningless ("biggest of top-10" tells the user nothing
    // about disk pressure). Once homeTotal lands, the largest dir reads
    // as its real share of $HOME — typically 20–40 % — and smaller dirs
    // shrink proportionally instead of looking near-empty next to a
    // 100 %-bar.
    readonly property double homeTotal: Services.StorageDetail.homeTotalBytes
    readonly property double barDenom: homeTotal > 0
        ? homeTotal
        : (dirs.length > 0 ? dirs[0].bytes : 1)

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

        // Column header — anchors the columns below. Layout order is
        // [#] [dir] [size] [% $HOME] [bar]: numeric data left of the
        // colored bar so percentages and sizes always sit on the dark
        // panel background, never on the colored bar itself.
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
            Components.StyledText {
                Layout.preferredWidth: Math.round(84 * Core.Theme.dpiScale)
                text: "size"
                font.pixelSize: Core.Theme.fontSize.xs
                color: Core.Theme.fgDim
                horizontalAlignment: Text.AlignRight
            }
            Components.StyledText {
                Layout.preferredWidth: Math.round(48 * Core.Theme.dpiScale)
                text: "% $HOME"
                font.pixelSize: Core.Theme.fontSize.xs
                color: Core.Theme.fgDim
                horizontalAlignment: Text.AlignRight
            }
            Item { Layout.fillWidth: true }
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

                // value (absolute GiB/MiB)
                Components.StyledText {
                    Layout.preferredWidth: Math.round(84 * Core.Theme.dpiScale)
                    text: root._fmt(modelData.bytes)
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                    horizontalAlignment: Text.AlignRight
                }

                // share of $HOME — shown as honest percentage of the
                // $HOME total (see services/StorageDetail.qml
                // homeTotalProc). `—` until that probe lands.
                Components.StyledText {
                    Layout.preferredWidth: Math.round(48 * Core.Theme.dpiScale)
                    text: root.homeTotal > 0
                        ? Math.round(100 * modelData.bytes / root.homeTotal) + "%"
                        : "—"
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
                    horizontalAlignment: Text.AlignRight
                }

                // bar — width is the dir's true share of $HOME, so a dir
                // that owns ~30 % of $HOME draws ~30 % of the bar. The
                // largest dir never reaches 100 % unless one dir owns all
                // of $HOME, which is the honest visual cue. clip:true on
                // the track guards against any pixel-rounding overflow
                // landing in the next row.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(10 * Core.Theme.dpiScale)
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.04)
                    clip: true

                    Rectangle {
                        id: fillBar
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: {
                            var d = Math.max(1, root.barDenom)
                            var w = parent.width * (modelData.bytes / d)
                            return Math.max(2, Math.min(parent.width, w))
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
