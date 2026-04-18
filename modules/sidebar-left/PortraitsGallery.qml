// PortraitsGallery — collection picker + Pinterest-style image grid.
//
// Collection dropdown feeds from Services.Portraits.collections. GridView
// renders uniform 2:3 cells with PreserveAspectCrop images and OpacityMask
// rounded corners; only visible delegates are alive (GridView recycles).
// Click → qimgv as argv (Process, no shell).
//
// Columns scale with panel width: ≥720 → 3 cols, ≥1100 → 4 cols, else 2.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../core" as Core
import "../../services" as Services

Item {
    id: root

    // Internal state
    property string _currentCollection: ""
    property var _images: []    // absolute paths for the active collection

    // Seed initial collection from Services.Portraits when its scan completes.
    // If already scanned, we pick up immediately.
    Component.onCompleted: _tryAutoSelect()
    Connections {
        target: Services.Portraits
        function onCollectionsChanged() { root._tryAutoSelect() }
        function onCollectionScanned(name) {
            if (name === root._currentCollection) root._reloadImages()
        }
    }

    function _tryAutoSelect() {
        if (_currentCollection !== "") return
        var cols = Services.Portraits.collections
        if (!cols || cols.length === 0) return
        // Prefer first collection with images; fallback to first
        for (var i = 0; i < cols.length; i++) {
            if ((cols[i].imageCount || 0) > 0) {
                root._setCollection(cols[i].name)
                return
            }
        }
        root._setCollection(cols[0].name)
    }

    function _setCollection(name) {
        if (name === _currentCollection) return
        _currentCollection = name
        _reloadImages()
    }

    function _reloadImages() {
        if (_currentCollection === "") {
            _images = []
            return
        }
        _images = Services.Portraits.getImagesForCollection(_currentCollection)
    }

    // === Column count based on available width ===
    readonly property int columnCount: {
        var w = root.width
        var dp = Core.Theme.dpiScale
        if (w >= Math.round(1100 * dp)) return 4
        if (w >= Math.round(720  * dp)) return 3
        return 2
    }

    // === Spawn qimgv via argv (no shell) ===
    Process { id: qimgvProc }
    function _openInViewer(path) {
        if (qimgvProc.running) return
        qimgvProc.command = ["qimgv", path]
        qimgvProc.running = true
    }

    // === Layout ===
    ColumnLayout {
        anchors.fill: parent
        spacing: Core.Theme.spacing.md

        // Collection picker row
        RowLayout {
            Layout.fillWidth: true
            spacing: Core.Theme.spacing.sm

            Text {
                text: "Collection"
                font.family: Core.Theme.fontUI
                font.pixelSize: Core.Theme.fontSize.sm
                font.weight: Font.DemiBold
                color: Core.Theme.fgDim
            }

            ComboBox {
                id: collectionCombo
                Layout.fillWidth: true
                flat: true
                model: Services.Portraits.collections
                textRole: "name"
                valueRole: "name"

                // Sync currentIndex from _currentCollection
                property bool _syncing: false
                function _syncFromState() {
                    if (!model) return
                    _syncing = true
                    var target = root._currentCollection
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].name === target) {
                            currentIndex = i
                            break
                        }
                    }
                    _syncing = false
                }
                Component.onCompleted: _syncFromState()
                onModelChanged: _syncFromState()

                onCurrentIndexChanged: {
                    if (_syncing) return
                    if (currentIndex < 0 || !model || !model[currentIndex]) return
                    root._setCollection(model[currentIndex].name)
                }

                // Custom styling to match theme
                background: Rectangle {
                    color: collectionCombo.hovered ? Core.Theme.glass2 : Core.Theme.glass1
                    radius: Core.Theme.radius.md
                    border.color: Core.Theme.glassBorder
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Core.Anims.duration.fast } }
                }
                contentItem: Text {
                    leftPadding: Core.Theme.spacing.md
                    rightPadding: collectionCombo.indicator.width + Core.Theme.spacing.sm
                    text: collectionCombo.displayText
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.base
                    color: Core.Theme.fgMain
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            Text {
                text: root._images.length + " imgs"
                font.family: Core.Theme.fontUI
                font.pixelSize: Core.Theme.fontSize.xs
                color: Core.Theme.fgMuted
            }
        }

        // === Grid ===
        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            property real spacingPx: Math.round(10 * Core.Theme.dpiScale)
            cellWidth: width / Math.max(1, root.columnCount)
            // 2:3 portrait aspect for uniform cells
            cellHeight: Math.round(cellWidth * 1.5)

            model: root._images
            cacheBuffer: Math.round(height * 1.5)

            boundsBehavior: Flickable.StopAtBounds
            maximumFlickVelocity: Math.round(3500 * Core.Theme.dpiScale)
            flickDeceleration: Math.round(5000 * Core.Theme.dpiScale)

            focus: true
            keyNavigationEnabled: true
            keyNavigationWraps: false

            // Scroll bar indicator
            ScrollBar.vertical: ScrollBar {
                active: grid.moving || hovered
                policy: ScrollBar.AsNeeded
            }

            delegate: Item {
                id: cellRoot

                required property int index
                required property string modelData

                width: grid.cellWidth
                height: grid.cellHeight

                Item {
                    id: inner
                    anchors.fill: parent
                    anchors.margins: grid.spacingPx / 2

                    scale: cellMouse.pressed ? 0.97 :
                           cellMouse.containsMouse ? 1.02 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: Core.Anims.duration.fast
                            easing.type: Core.Anims.ease.standard
                        }
                    }

                    // Loading placeholder
                    Rectangle {
                        anchors.fill: parent
                        radius: Core.Theme.radius.md
                        color: Core.Theme.glass2
                        visible: img.status !== Image.Ready
                    }

                    // Masked rounded image
                    Image {
                        id: img
                        anchors.fill: parent
                        source: "file://" + cellRoot.modelData
                        asynchronous: true
                        cache: false
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: Math.round(grid.cellWidth * 2)
                        sourceSize.height: Math.round(grid.cellHeight * 2)
                        smooth: true
                        mipmap: true

                        opacity: status === Image.Ready ? 1.0 : 0.0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Core.Anims.duration.normal
                                easing.type: Core.Anims.ease.decel
                            }
                        }

                        // GPU-masked rounded corners (Qt.labs effects MultiEffect
                        // is part of QtQuick.Effects; we use layer+OpacityMask
                        // since Image.layer is already available and proven).
                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: maskItem
                            maskThresholdMin: 0.5
                        }
                    }

                    Item {
                        id: maskItem
                        anchors.fill: parent
                        layer.enabled: true
                        visible: false
                        Rectangle {
                            anchors.fill: parent
                            radius: Core.Theme.radius.md
                            color: "white"
                        }
                    }

                    // Hover glow
                    Rectangle {
                        anchors.fill: parent
                        radius: Core.Theme.radius.md
                        color: "transparent"
                        border.color: Core.Theme.accent
                        border.width: cellMouse.containsMouse ? 2 : 0
                        opacity: cellMouse.containsMouse ? 0.6 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Core.Anims.duration.fast }
                        }
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._openInViewer(cellRoot.modelData)
                    }
                }
            }

            // Empty / loading state
            Item {
                anchors.centerIn: parent
                width: parent.width * 0.7
                visible: root._images.length === 0

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Core.Theme.spacing.md

                    BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: Services.Portraits.loading ||
                                 root._currentCollection !== ""
                        visible: running
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Services.Portraits.loading
                            ? "Scanning portrait collections…"
                            : (root._currentCollection === ""
                                ? "No collections found"
                                : "Collection is empty")
                        font.family: Core.Theme.fontUI
                        font.pixelSize: Core.Theme.fontSize.sm
                        color: Core.Theme.fgDim
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
