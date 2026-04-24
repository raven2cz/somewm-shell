// HotspotsSection — Arch hotspots (pacman cache, journald, coredumps,
// AUR helpers, ~/.cache, trash). Pacman cache has the two-click
// paccache flow: dry-run preview → pkexec clean.
//
// Hard rule: the only destructive action is paccache -rk2 through
// pkexec. Everything else is read-only.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    function _fmt(bytes) {
        if (bytes < 0) return "—"
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1048576) return (bytes / 1024.0).toFixed(1) + " KiB"
        if (bytes < 1073741824) return (bytes / 1048576.0).toFixed(1) + " MiB"
        return (bytes / 1073741824.0).toFixed(2) + " GiB"
    }

    readonly property var hotspots: Services.StorageDetail.hotspots

    // Inline pill-style button used by PaccacheControls. Flat — Qt QML
    // does not allow `component` declarations nested inside another
    // `component`, so this lives at the Item scope and is instantiated
    // from PaccacheControls below.
    //
    // We avoid the name `enabled` (Item.enabled shadowing warning) and
    // use `active` instead.
    component PillButton: Rectangle {
        property string label: ""
        property color accent: Core.Theme.accent
        property bool active: true
        signal clicked()
        implicitHeight: Math.round(28 * Core.Theme.dpiScale)
        implicitWidth: btnLabel.implicitWidth + Core.Theme.spacing.md * 2
        radius: height / 2
        opacity: active ? 1.0 : 0.4
        color: mouseArea.containsMouse && active
            ? Qt.rgba(accent.r, accent.g, accent.b, 0.20)
            : Qt.rgba(accent.r, accent.g, accent.b, 0.10)
        border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.30)
        border.width: 1
        Behavior on color { Components.CAnim {} }

        Components.StyledText {
            id: btnLabel
            anchors.centerIn: parent
            text: label
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.xs
            color: accent
        }
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (parent.active) parent.clicked()
        }
    }

    component PaccacheControls: RowLayout {
        spacing: Core.Theme.spacing.sm

        readonly property bool avail: Services.StorageDetail.paccacheAvailable
        readonly property bool pkexec: Services.StorageDetail.pkexecAvailable
        readonly property bool busy:  Services.StorageDetail.paccacheBusy
        readonly property string st:  Services.StorageDetail.paccacheStatus

        // Dry-run button
        PillButton {
            label: busy && st !== "dryrun" ? "Running…" : "Dry-run (keep 2)"
            accent: Core.Theme.accent
            active: avail && !busy
            onClicked: Services.StorageDetail.paccacheDryRun(2)
        }

        // Clean button — only active after a successful dry-run
        PillButton {
            label: {
                if (busy && st === "dryrun") return "Cleaning…"
                if (st === "dryrun" && Services.StorageDetail.paccachePreviewCount > 0)
                    return "Clean " + Services.StorageDetail.paccachePreviewCount +
                           " pkgs — requires admin approval"
                return "Clean (keep 2) — requires admin approval"
            }
            accent: "#e06c75"
            active: avail && pkexec && !busy &&
                    st === "dryrun" &&
                    Services.StorageDetail.paccachePreviewCount > 0
            onClicked: Services.StorageDetail.paccacheClean(2)
        }

        Components.StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: {
                if (!avail) return "paccache not installed (pacman-contrib)"
                if (st === "dryrun") {
                    var b = Services.StorageDetail.paccachePreviewBytes
                    return "Would free " + (b > 0 ? (b / 1073741824.0).toFixed(2) + " GiB" : "?") +
                           " (" + Services.StorageDetail.paccachePreviewCount + " pkgs)"
                }
                if (st === "cleaned")   return "Cleaned. Pacman cache refreshed."
                if (st === "cancelled") return "Cancelled (pkexec prompt dismissed)."
                if (st === "error")     return "paccache failed — check system log."
                if (st === "empty")     return "Nothing to clean."
                return "Preview before cleaning."
            }
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.xs
            color: st === "error" ? "#f38ba8" : Core.Theme.fgMuted
        }
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "Arch system hotspots"
            accentColor: Core.Theme.widgetDisk
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: !Services.StorageDetail.hotspotsLoaded
            text: "Probing hotspots…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        // Main hotspot rows
        Repeater {
            model: root.hotspots

            delegate: ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Core.Theme.spacing.sm

                    // label + path
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Components.StyledText {
                            Layout.fillWidth: true
                            text: modelData.label
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Core.Theme.fontSize.sm
                            color: Core.Theme.fgMain
                        }
                        Components.StyledText {
                            Layout.fillWidth: true
                            text: modelData.path || modelData.hint
                            elide: Text.ElideMiddle
                            font.family: Core.Theme.fontMono
                            font.pixelSize: Core.Theme.fontSize.xs
                            color: Core.Theme.fgMuted
                        }
                    }

                    // size
                    Components.StyledText {
                        Layout.preferredWidth: Math.round(100 * Core.Theme.dpiScale)
                        text: root._fmt(modelData.bytes)
                        font.family: Core.Theme.fontMono
                        font.pixelSize: Core.Theme.fontSize.sm
                        color: Core.Theme.fgMain
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Pacman cache actions (keyed row)
                Loader {
                    Layout.fillWidth: true
                    Layout.leftMargin: Math.round(6 * Core.Theme.dpiScale)
                    active: modelData.key === "pacman_cache"
                    visible: active
                    sourceComponent: PaccacheControls {}
                }
            }
        }

        Components.StyledText {
            Layout.fillWidth: true
            visible: Services.StorageDetail.hotspotsLoaded
            wrapMode: Text.WordWrap
            text: "Only paccache -rk2 is destructive; it runs via pkexec with an " +
                  "explicit preview first. Everything else is read-only."
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.xs
            color: Core.Theme.fgMuted
        }
    }
}
