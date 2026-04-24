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

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "Biggest top-level directories under $HOME"
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
                        Behavior on width {
                            NumberAnimation {
                                duration: Core.Anims.duration.smooth
                                easing.type: Core.Anims.ease.decel
                            }
                        }
                    }
                }

                // value
                Components.StyledText {
                    Layout.preferredWidth: Math.round(90 * Core.Theme.dpiScale)
                    text: root._fmt(modelData.bytes)
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMain
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
