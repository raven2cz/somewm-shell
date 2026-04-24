// MountsSection — one row per real mount, sourced from findmnt JSON.
// Primary `/` is pinned to the top; btrfs subvolumes that share a pool
// show up as separate rows (they do share raw numbers — we don't
// deduplicate numerically because the mount point itself is the unit).
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    function _fmtGiB(bytes) {
        if (bytes < 1073741824) return (bytes / 1048576.0).toFixed(0) + " MiB"
        return (bytes / 1073741824.0).toFixed(1) + " GiB"
    }

    readonly property var mounts: Services.StorageDetail.mounts

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "Mounts"
            accentColor: Core.Theme.widgetDisk
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: !Services.StorageDetail.mountsLoaded
            text: "Running findmnt…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: Services.StorageDetail.mountsLoaded && root.mounts.length === 0
            text: "No real mounts found."
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        Repeater {
            model: root.mounts

            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Core.Theme.spacing.sm

                    // target + fstype
                    Components.StyledText {
                        Layout.preferredWidth: Math.round(170 * Core.Theme.dpiScale)
                        text: modelData.target +
                              "  <span style='color:" + Core.Theme.fgMuted + "'>" +
                              (modelData.fstype || "") + "</span>"
                        textFormat: Text.StyledText
                        elide: Text.ElideRight
                        font.family: Core.Theme.fontUI
                        font.pixelSize: Core.Theme.fontSize.sm
                        color: modelData.target === "/" ? Core.Theme.widgetDisk
                                                        : Core.Theme.fgMain
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
                                var f = Math.max(0, Math.min(1, modelData.pct / 100.0))
                                return Math.max(2, parent.width * f)
                            }
                            height: parent.height
                            radius: height / 2
                            color: {
                                if (modelData.pct >= 90) return "#e06c75"
                                if (modelData.pct >= 75) return "#e5c07b"
                                return modelData.target === "/"
                                    ? Core.Theme.widgetDisk
                                    : Qt.rgba(Core.Theme.widgetDisk.r,
                                              Core.Theme.widgetDisk.g,
                                              Core.Theme.widgetDisk.b, 0.55)
                            }
                            Behavior on width {
                                NumberAnimation {
                                    duration: Core.Anims.duration.smooth
                                    easing.type: Core.Anims.ease.decel
                                }
                            }
                        }
                    }

                    // used/size
                    Components.StyledText {
                        Layout.preferredWidth: Math.round(140 * Core.Theme.dpiScale)
                        text: root._fmtGiB(modelData.used) + " / " +
                              root._fmtGiB(modelData.size)
                        font.family: Core.Theme.fontMono
                        font.pixelSize: Core.Theme.fontSize.sm
                        color: Core.Theme.fgMain
                        horizontalAlignment: Text.AlignRight
                    }

                    // percent
                    Components.StyledText {
                        Layout.preferredWidth: Math.round(44 * Core.Theme.dpiScale)
                        text: modelData.pct + " %"
                        font.family: Core.Theme.fontMono
                        font.pixelSize: Core.Theme.fontSize.sm
                        color: modelData.pct >= 90 ? "#e06c75" : Core.Theme.fgDim
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // secondary line: source (device path), muted
                Components.StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: Math.round(8 * Core.Theme.dpiScale)
                    text: modelData.source || ""
                    elide: Text.ElideMiddle
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.xs
                    color: Core.Theme.fgMuted
                }
            }
        }
    }
}
