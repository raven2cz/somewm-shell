// SomewmInternalsSection — numbers from root.memory_stats(true) plus
// /proc/<somewm_pid>/smaps_rollup. Two-column grid of rows.
import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    implicitHeight: content.implicitHeight

    function _fmtMiB(bytes) { return (bytes / 1048576.0).toFixed(1) + " MiB" }
    function _fmtKiB(bytes) { return (bytes / 1024.0).toFixed(1) + " KiB" }

    readonly property int rssKB: Services.MemoryDetail.somewmRssKB
    readonly property int pssKB: Services.MemoryDetail.somewmPssKB
    readonly property bool loaded: Services.MemoryDetail.somewmLoaded || rssKB > 0

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Core.Theme.spacing.sm

        Components.SectionHeader {
            title: "somewm internals"
            accentColor: Core.Theme.widgetMemory
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: !root.loaded
            text: "Waiting for somewm-client eval…"
            font.family: Core.Theme.fontMono
            font.pixelSize: Core.Theme.fontSize.sm
            color: Core.Theme.fgMuted
            Layout.fillWidth: true
        }

        Components.StyledText {
            visible: Services.MemoryDetail.somewmError !== ""
            text: "Error: " + Services.MemoryDetail.somewmError
            color: "#f38ba8"
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.sm
            Layout.fillWidth: true
        }

        GridLayout {
            Layout.fillWidth: true
            visible: root.loaded
            columns: 2
            rowSpacing: Math.round(4 * Core.Theme.dpiScale)
            columnSpacing: Core.Theme.spacing.md

            component KV: RowLayout {
                property string k: ""
                property string v: ""
                property color c: Core.Theme.fgMain
                Layout.fillWidth: true
                spacing: Core.Theme.spacing.sm
                Components.StyledText {
                    Layout.preferredWidth: Math.round(130 * Core.Theme.dpiScale)
                    text: k
                    color: Core.Theme.fgDim
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.sm
                }
                Components.StyledText {
                    Layout.fillWidth: true
                    text: v
                    color: c
                    font.family: Core.Theme.fontMono
                    font.pixelSize: Core.Theme.fontSize.sm
                    horizontalAlignment: Text.AlignRight
                }
            }

            KV {
                k: "RSS"
                v: root._fmtMiB(root.rssKB * 1024)
                c: Core.Theme.widgetMemory
            }
            KV {
                k: "PSS"
                v: root._fmtMiB(root.pssKB * 1024)
            }
            KV {
                k: "Private dirty"
                v: root._fmtMiB(Services.MemoryDetail.somewmPrivDirtyKB * 1024)
            }
            KV {
                k: "Lua heap"
                v: root._fmtKiB(Services.MemoryDetail.luaBytes)
                c: "#98c379"
            }
            KV {
                k: "Clients"
                v: String(Services.MemoryDetail.clientsCount)
            }
            KV {
                k: "Wibox count"
                v: String(Services.MemoryDetail.wiboxCount)
            }
            KV {
                k: "Drawable SHM"
                v: root._fmtMiB(Services.MemoryDetail.drawableShmBytes) +
                   " / " + Services.MemoryDetail.drawableShmCount + " buf"
            }
            KV {
                k: "Drawable surfaces"
                v: root._fmtKiB(Services.MemoryDetail.drawableSurfaceBytes)
            }
            KV {
                k: "Wibox surfaces"
                v: root._fmtKiB(Services.MemoryDetail.wiboxSurfaceBytes)
            }
            KV {
                k: "Wallpaper cache"
                v: root._fmtMiB(Services.MemoryDetail.wallpaperEstBytes) +
                   " / " + Services.MemoryDetail.wallpaperEntries + " entries"
            }
            KV {
                k: "Wallpaper cairo"
                v: root._fmtMiB(Services.MemoryDetail.wallpaperCairoBytes)
            }
            KV {
                k: "Wallpaper SHM"
                v: root._fmtMiB(Services.MemoryDetail.wallpaperShmBytes)
            }
            KV {
                k: "malloc used"
                v: root._fmtMiB(Services.MemoryDetail.mallocUsedBytes)
            }
            KV {
                k: "malloc free"
                v: root._fmtMiB(Services.MemoryDetail.mallocFreeBytes)
            }
            KV {
                k: "malloc releasable"
                v: root._fmtMiB(Services.MemoryDetail.mallocReleasableBytes)
            }
        }

        // Baseline hint
        Components.StyledText {
            Layout.fillWidth: true
            visible: root.loaded
            wrapMode: Text.WordWrap
            text: "somewm baseline on this hardware ≈ 2× sway — AwesomeWM Lua " +
                  "+ cairo widgets + wallpaper preload cache. Stable memory " +
                  "pattern, not a leak. See plans/docs/memory-baseline.md."
            font.family: Core.Theme.fontUI
            font.pixelSize: Core.Theme.fontSize.xs
            color: Core.Theme.fgMuted
        }
    }
}
