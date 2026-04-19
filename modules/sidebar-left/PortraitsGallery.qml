// PortraitsGallery — collection picker + Pinterest-style image grid.
//
// Data source:
//   Services.Portraits — enumerates collection subdirs and image files.
//
// First-open selection (auto):
//   1. Services.Portraits.defaultCollection (from ~/.config/somewm/.default_portrait,
//      shared with Lua notifications fallback — see fishlive.services.portraits).
//   2. First collection that has imageCount > 0.
//   3. First collection (even if empty).
//   The default may arrive asynchronously after the fallback has been
//   chosen; `_tryAutoSelect` is re-run on defaultCollectionChanged and
//   upgrades the selection as long as the user has not manually picked.
//
// Rendering:
//   GridView with uniform 2:3 portrait cells; PreserveAspectCrop images,
//   GPU-masked rounded corners via MultiEffect. GridView virtualizes
//   delegates as the user scrolls (cacheBuffer keeps a buffer alive
//   around the viewport so scrolling stays smooth).
//
// Interaction:
//   Click cell → qimgv as argv (Process, no shell).
//   Wheel / touchpad → smooth animated contentY (dots-hyprland pattern).
//   Columns scale with panel width: ≥1100dp → 4, ≥720dp → 3, else 2.
//
// File URLs:
//   All image paths go through Core.FileUtil.fileUrl(…) so characters
//   such as `%`, `#`, `?` in filenames survive Qt's URL parser.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
    id: root

    // === Layout tuning ===
    readonly property int comboHeight: Math.round(40 * Core.Theme.dpiScale)
    readonly property int widthBreakpointMedium: Math.round(720 * Core.Theme.dpiScale)
    readonly property int widthBreakpointWide: Math.round(1100 * Core.Theme.dpiScale)
    // Scroll animation — OutExpo curve feels natural at ~400 ms; shorter
    // reads as a jump, longer feels laggy during rapid wheel spins.
    readonly property int scrollAnimDuration: 400
    // Mouse wheels step in ±120 units per tick; touchpads produce smaller
    // continuous deltas. `wheelTickUnit` is Qt's convention for ONE tick.
    readonly property int wheelTickUnit: 120
    // Touchpad scroll: small deltas → treat as pixel-accurate units of
    // this size; keeps two-finger scroll smooth without runaway momentum.
    readonly property int touchpadStepPx: Math.round(40 * Core.Theme.dpiScale)
    // Flickable's maximum flick velocity. 3500 matches dots-hyprland's
    // baseline; scales with DPI so hi-DPI screens keep the same feel.
    readonly property int maxFlickVelocity: Math.round(3500 * Core.Theme.dpiScale)

    // === Internal state ===
    property string _currentCollection: ""
    property var _images: []    // absolute paths for the active collection
    // True once the user explicitly picks a collection via the combobox.
    // Auto-select must not override a deliberate user choice.
    property bool _userPicked: false

    // Seed the initial collection from Services.Portraits when it finishes
    // scanning. Also re-runs when the shared default collection (used by
    // Lua notifications) resolves after the panel opened — first-open UX
    // should land on the user's chosen default even if the FileView reads
    // the state file slightly later than the directory scan.
    Component.onCompleted: _tryAutoSelect()
    Connections {
        target: Services.Portraits
        function onCollectionsChanged() { root._tryAutoSelect() }
        function onDefaultCollectionChanged() { root._tryAutoSelect() }
        function onCollectionScanned(name) {
            if (name === root._currentCollection) root._reloadImages()
        }
    }

    function _tryAutoSelect() {
        if (_userPicked) return
        var cols = Services.Portraits.collections
        if (!cols || cols.length === 0) return
        // 1. User's configured default (shared with notifications menu).
        //    Upgrade from an earlier fallback if default arrives later.
        var def = Services.Portraits.defaultCollection
        if (def) {
            for (var i = 0; i < cols.length; i++) {
                if (cols[i].name === def) {
                    if (_currentCollection !== def) root._setCollection(def)
                    return
                }
            }
        }
        // No default yet — only do a fallback pick if we haven't chosen one.
        if (_currentCollection !== "") return
        // 2. First collection with images
        for (var j = 0; j < cols.length; j++) {
            if ((cols[j].imageCount || 0) > 0) {
                root._setCollection(cols[j].name)
                return
            }
        }
        // 3. First collection
        root._setCollection(cols[0].name)
    }

    function _setCollection(name) {
        if (name === _currentCollection) return
        _currentCollection = name
        _reloadImages()
        // Keep combobox closed-state label in sync when the switch comes
        // from auto-select (user clicks update currentIndex themselves).
        collectionCombo._syncFromState()
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
        if (root.width >= widthBreakpointWide) return 4
        if (root.width >= widthBreakpointMedium) return 3
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
                Layout.preferredHeight: root.comboHeight
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
                    var found = -1
                    if (target !== "") {
                        for (var i = 0; i < model.length; i++) {
                            if (model[i].name === target) {
                                found = i
                                break
                            }
                        }
                    }
                    currentIndex = found
                    _syncing = false
                }
                Component.onCompleted: _syncFromState()
                onModelChanged: _syncFromState()

                // Use `activated` (user chose via click/keyboard) — NOT
                // `currentIndexChanged`, which also fires when Qt auto-sets
                // currentIndex=0 as the model populates and would falsely
                // flip _userPicked, blocking the async default-collection
                // upgrade.
                onActivated: (index) => {
                    if (index < 0 || !model || !model[index]) return
                    root._userPicked = true
                    root._setCollection(model[index].name)
                }

                // === Displayed selection (closed state) ===
                background: Rectangle {
                    implicitHeight: root.comboHeight
                    color: collectionCombo.pressed
                        ? Core.Theme.glass2
                        : (collectionCombo.hovered ? Core.Theme.glass2 : Core.Theme.glass1)
                    radius: Core.Theme.radius.md
                    border.color: collectionCombo.hovered
                        ? Core.Theme.accentBorder
                        : Core.Theme.glassBorder
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Core.Anims.duration.fast } }
                    Behavior on border.color { ColorAnimation { duration: Core.Anims.duration.fast } }
                }
                contentItem: Text {
                    leftPadding: Core.Theme.spacing.lg
                    rightPadding: collectionCombo.indicator.width + Core.Theme.spacing.sm
                    text: collectionCombo.displayText
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.base
                    font.weight: Font.Medium
                    color: Core.Theme.fgMain
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                // === Dropdown arrow indicator ===
                indicator: Components.MaterialIcon {
                    x: collectionCombo.width - width - Core.Theme.spacing.sm
                    y: (collectionCombo.height - height) / 2
                    icon: "\ue5c5"  // arrow_drop_down
                    size: Core.Theme.fontSize.xl
                    color: Core.Theme.fgDim
                    rotation: collectionCombo.popup.visible ? 180 : 0
                    Behavior on rotation {
                        NumberAnimation { duration: Core.Anims.duration.fast }
                    }
                }

                // === Dropdown popup ===
                popup: Popup {
                    y: collectionCombo.height + Math.round(4 * Core.Theme.dpiScale)
                    width: collectionCombo.width
                    implicitHeight: Math.min(
                        contentItem.implicitHeight + topPadding + bottomPadding,
                        Math.round(320 * Core.Theme.dpiScale))
                    padding: Math.round(6 * Core.Theme.dpiScale)

                    background: Rectangle {
                        color: Core.Theme.surfaceContainerHigh
                        radius: Core.Theme.radius.md
                        border.color: Core.Theme.glassBorder
                        border.width: 1
                    }

                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: collectionCombo.popup.visible ? collectionCombo.delegateModel : null
                        currentIndex: collectionCombo.highlightedIndex
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                }

                // === Per-item delegate (consistent look with dropdown) ===
                delegate: ItemDelegate {
                    id: itemDelegate
                    required property int index
                    required property var modelData
                    width: collectionCombo.width - Math.round(12 * Core.Theme.dpiScale)
                    height: Math.round(36 * Core.Theme.dpiScale)
                    padding: 0
                    highlighted: collectionCombo.highlightedIndex === index

                    background: Rectangle {
                        radius: Core.Theme.radius.sm
                        color: itemDelegate.highlighted
                            ? Core.Theme.glassAccent
                            : (itemDelegate.hovered ? Core.Theme.glass2 : "transparent")
                        Behavior on color { ColorAnimation { duration: Core.Anims.duration.fast } }
                    }

                    contentItem: RowLayout {
                        spacing: Core.Theme.spacing.sm

                        Components.MaterialIcon {
                            Layout.leftMargin: Core.Theme.spacing.md
                            icon: (itemDelegate.modelData && itemDelegate.modelData.name === root._currentCollection)
                                ? "\ue876"  // check
                                : "\uf1c5"  // image
                            size: Core.Theme.fontSize.base
                            color: (itemDelegate.modelData && itemDelegate.modelData.name === root._currentCollection)
                                ? Core.Theme.accent
                                : Core.Theme.fgDim
                        }

                        Text {
                            Layout.fillWidth: true
                            text: itemDelegate.modelData ? itemDelegate.modelData.name : ""
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Core.Theme.fontSize.base
                            color: Core.Theme.fgMain
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.rightMargin: Core.Theme.spacing.md
                            text: (itemDelegate.modelData && itemDelegate.modelData.imageCount !== undefined)
                                ? itemDelegate.modelData.imageCount
                                : ""
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Core.Theme.fontSize.xs
                            color: Core.Theme.fgMuted
                        }
                    }
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

            // Reserve a strip on the right for the scrollbar so it doesn't
            // overlap the cells (professional look). cellWidth excludes it.
            readonly property int scrollBarWidth: Math.round(10 * Core.Theme.dpiScale)
            readonly property int scrollBarGap: Math.round(4 * Core.Theme.dpiScale)
            readonly property int usableWidth: width - scrollBarWidth - scrollBarGap

            property real spacingPx: Math.round(10 * Core.Theme.dpiScale)
            cellWidth: Math.floor(usableWidth / Math.max(1, root.columnCount))
            // 2:3 portrait aspect for uniform cells
            cellHeight: Math.round(cellWidth * 1.5)

            model: root._images
            cacheBuffer: Math.round(height * 1.5)

            boundsBehavior: Flickable.StopAtBounds
            maximumFlickVelocity: root.maxFlickVelocity

            focus: true
            keyNavigationEnabled: true
            keyNavigationWraps: false

            // === Smooth wheel scrolling (dots-hyprland StyledFlickable pattern) ===
            // Animate contentY via Behavior, accumulate destination across
            // ticks in _scrollTargetY so rapid spins don't lose deltas, and
            // let touchpad (small deltas) use a smaller multiplier for a
            // natural pixel-accurate feel. WheelHandler proved unreliable
            // at preempting GridView's built-in Flickable wheel handling —
            // a MouseArea with Qt.NoButton sits above delegates, captures
            // wheel events, and clicks fall through because no mouse button
            // is accepted.
            property real _scrollTargetY: 0
            onContentYChanged: if (!scrollAnim.running) _scrollTargetY = contentY

            Behavior on contentY {
                NumberAnimation {
                    id: scrollAnim
                    duration: root.scrollAnimDuration
                    easing.type: Easing.OutExpo
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: (wheel) => {
                    var absDelta = Math.abs(wheel.angleDelta.y)
                    var isMouseWheel = absDelta >= root.wheelTickUnit
                    // Mouse wheel tick → ~half a row (snappy but not jarring);
                    // touchpad → small per-pixel delta.
                    var factor = isMouseWheel
                        ? Math.round(grid.cellHeight * 0.6)
                        : root.touchpadStepPx
                    var delta = wheel.angleDelta.y / root.wheelTickUnit
                    var maxY = Math.max(0, grid.contentHeight - grid.height)
                    var base = scrollAnim.running ? grid._scrollTargetY : grid.contentY
                    var target = Math.max(0, Math.min(maxY, base - delta * factor))
                    grid._scrollTargetY = target
                    grid.contentY = target
                    wheel.accepted = true
                }
            }

            // Styled scrollbar — lives in the reserved right strip.
            ScrollBar.vertical: ScrollBar {
                id: vScroll
                active: grid.moving || hovered || scrollAnim.running
                policy: ScrollBar.AsNeeded
                width: grid.scrollBarWidth
                padding: Math.round(2 * Core.Theme.dpiScale)
                minimumSize: 0.08

                contentItem: Rectangle {
                    implicitWidth: Math.round(6 * Core.Theme.dpiScale)
                    radius: width / 2
                    color: vScroll.pressed
                        ? Core.Theme.accent
                        : (vScroll.hovered ? Core.Theme.fgDim : Core.Theme.fgMuted)
                    opacity: vScroll.active ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation { duration: Core.Anims.duration.fast }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Core.Anims.duration.fast }
                    }
                }

                background: Rectangle {
                    color: "transparent"
                }
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
                        source: Core.FileUtil.fileUrl(cellRoot.modelData)
                        asynchronous: true
                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: Math.round(grid.cellWidth * 2)
                        sourceSize.height: Math.round(grid.cellHeight * 2)
                        smooth: true
                        mipmap: true

                        onStatusChanged: {
                            if (status === Image.Error) {
                                console.warn("PortraitsGallery: failed to load",
                                    cellRoot.modelData, "→", errorString)
                            }
                        }

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

                    // Show the spinner while something is actually in
                    // flight — either the top-level directory scan, or
                    // a per-collection image scan for the chosen one.
                    // A collection whose scan completed with zero images
                    // should NOT spin forever; it should display the
                    // "Collection is empty" message below.
                    readonly property bool awaitingCollectionScan:
                        root._currentCollection !== "" &&
                        !Services.Portraits.isScanned(root._currentCollection)

                    BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: Services.Portraits.loading ||
                                 parent.awaitingCollectionScan
                        visible: running
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Services.Portraits.loading
                            ? "Scanning portrait collections…"
                            : parent.awaitingCollectionScan
                                ? "Loading collection…"
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
