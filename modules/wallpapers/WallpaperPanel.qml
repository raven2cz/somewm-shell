import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

// Wallpaper Picker — 3-zone layout: top bar, carousel + tag bar, filmstrip
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: panel

        required property var modelData
        screen: modelData

        property bool shouldShow: Core.Panels.isOpen("wallpapers") &&
            Services.Compositor.isActiveScreen(modelData)

        visible: shouldShow || fadeAnim.running

        color: "transparent"
        focusable: shouldShow

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "somewm-shell:wallpapers"
        WlrLayershell.keyboardFocus: shouldShow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true; bottom: true; left: true; right: true
        }

        mask: Region { item: pickerArea }

        // === Constants (scaled ~20% up for 4K) ===
        readonly property real sp: Core.Theme.dpiScale
        readonly property int itemWidth: 480
        readonly property int itemHeight: 500
        readonly property int borderWidth: 3
        readonly property int itemSpacing: 12
        readonly property real skewFactor: -0.35
        readonly property int pickerHeight: Math.round(780 * sp)

        // === State ===
        property bool initialFocusSet: false
        property int scrollAccum: 0
        readonly property int scrollThreshold: 300

        // === Per-screen scope binding (plan §7) ===
        // Panel is bound to the screen it renders on; writer actions freeze
        // the scope at open time to avoid focus-drift misfires.
        readonly property string panelScreenName: modelData ? (modelData.name || "") : ""
        readonly property var panelScopes: panelScreenName
            ? Services.Wallpapers.scopesFor(panelScreenName)
            : []
        readonly property string panelSelectedTag: panelScreenName
            ? (Services.Wallpapers.selectedTagFor(panelScreenName) || "1")
            : (Services.Wallpapers.selectedTag || "1")
        readonly property var panelTagList: panelScreenName
            ? Services.Wallpapers.tagsFor(panelScreenName)
            : Services.Wallpapers.tagList
        readonly property var panelOverrides: panelScreenName
            ? Services.Wallpapers.overridesFor(panelScreenName)
            : Services.Wallpapers.overrides
        readonly property string panelCurrentWallpaper: panelScreenName
            ? (Services.Wallpapers.currentFor(panelScreenName)
               || Services.Wallpapers.currentWallpaper)
            : Services.Wallpapers.currentWallpaper
        // Carousel model: theme view = per-screen resolved, folder = shared scan
        readonly property var carouselModel: {
            if (Services.Wallpapers.isThemeView && panelScreenName) {
                return Services.Wallpapers.wallpapersFor(panelScreenName)
            }
            return Services.Wallpapers.wallpapers
        }
        // activeEditScope: scope that writer actions target. "" = Base.
        // Set to primary scope on open; user can click chips to change.
        property string activeEditScope: ""
        property bool addScopePopupOpen: false

        function stepToNext(direction) {
            var model = panel.carouselModel
            if (!model || model.length === 0) return
            var next = view.currentIndex + direction
            if (next >= 0 && next < model.length) {
                view.currentIndex = next
            }
        }

        function _ensureActiveEditScope() {
            // Default to primary scope on panel open; Base ("") if none
            if (panelScopes && panelScopes.length > 0) {
                // If current selection not in scopes anymore, snap to primary
                var found = false
                for (var i = 0; i < panelScopes.length; i++) {
                    if (panelScopes[i] === activeEditScope) { found = true; break }
                }
                if (!found && activeEditScope !== "") activeEditScope = panelScopes[0]
                if (activeEditScope === "" && !_baseExplicitlySelected) activeEditScope = panelScopes[0]
            } else {
                // All scopes removed — snap to Base so writer calls never
                // target a stale non-active scope.
                if (activeEditScope !== "") activeEditScope = ""
            }
        }
        // Track whether user explicitly clicked "Base" chip (to distinguish
        // from the initial empty default).
        property bool _baseExplicitlySelected: false

        onShouldShowChanged: {
            if (shouldShow) {
                initialFocusSet = false
                _baseExplicitlySelected = false
                // Seed activeEditScope from cached scopes synchronously so
                // writer actions during the refresh window don't silently
                // fall through to Base. The follow-up _ensureActiveEditScope
                // after the refresh completes will re-snap if the list has
                // changed shape.
                var cachedScopes = panelScreenName
                    ? (Services.Wallpapers.scopesFor(panelScreenName) || [])
                    : []
                activeEditScope = cachedScopes.length > 0 ? cachedScopes[0] : ""
                view.forceActiveFocus()
                if (panelScreenName) {
                    Services.Wallpapers.refreshForScreen(panelScreenName)
                    if (Services.Wallpapers.isThemeView)
                        Services.Wallpapers.refreshResolvedForScreen(panelScreenName)
                } else {
                    Services.Wallpapers.refreshSelectedTag()
                }
                Services.Wallpapers.refreshBrowseFolders()
                _ensureActiveEditScope()
                _focusCurrentWallpaper()
            }
        }

        // Re-focus carousel + seed edit scope when per-screen state updates
        Connections {
            target: Services.Wallpapers
            function onCurrentWallpaperChanged() {
                if (panel.shouldShow) panel._focusCurrentWallpaper()
            }
            function onCurrentByScreenChanged() {
                if (panel.shouldShow) panel._focusCurrentWallpaper()
            }
            function onScopesByScreenChanged() {
                panel._ensureActiveEditScope()
            }
            function onWallpapersByScreenChanged() {
                if (panel.shouldShow) panel._focusCurrentWallpaper()
            }
        }

        function _focusCurrentWallpaper() {
            var model = panel.carouselModel
            if (!model) return
            var current = panel.panelCurrentWallpaper
            for (var i = 0; i < model.length; i++) {
                if (model[i].path === current) {
                    view.currentIndex = i
                    initialFocusSet = true
                    return
                }
            }
            if (model.length > 0) initialFocusSet = true
        }

        Timer {
            id: scrollThrottle
            interval: 150
        }

        // === Keyboard shortcuts ===
        Shortcut { sequence: "Left"; onActivated: panel.stepToNext(-1) }
        Shortcut { sequence: "Right"; onActivated: panel.stepToNext(1) }
        Shortcut { sequence: "Escape"; onActivated: Core.Panels.close("wallpapers") }
        Shortcut {
            sequence: "Return"
            onActivated: {
                var model = panel.carouselModel
                if (view.currentIndex < 0 || view.currentIndex >= model.length) return
                var item = model[view.currentIndex]
                if (panel.panelScreenName) {
                    Services.Wallpapers.setWallpaperForScreen(
                        panel.panelScreenName, panel.panelSelectedTag,
                        item.path, panel.activeEditScope)
                } else {
                    Services.Wallpapers.setWallpaper(item.path)
                }
            }
        }

        function _viewTag(tagName) {
            if (panel.panelScreenName) {
                Services.Wallpapers.viewTagOnScreen(panel.panelScreenName, tagName)
            } else {
                Services.Wallpapers.viewTag(tagName)
            }
        }

        // Tag selection: 1-9
        Shortcut { sequence: "1"; onActivated: panel._viewTag("1") }
        Shortcut { sequence: "2"; onActivated: panel._viewTag("2") }
        Shortcut { sequence: "3"; onActivated: panel._viewTag("3") }
        Shortcut { sequence: "4"; onActivated: panel._viewTag("4") }
        Shortcut { sequence: "5"; onActivated: panel._viewTag("5") }
        Shortcut { sequence: "6"; onActivated: panel._viewTag("6") }
        Shortcut { sequence: "7"; onActivated: panel._viewTag("7") }
        Shortcut { sequence: "8"; onActivated: panel._viewTag("8") }
        Shortcut { sequence: "9"; onActivated: panel._viewTag("9") }

        // Folder navigation: Up/Down
        function _navigateFolder(folder) {
            if (folder.isTheme) {
                Services.Wallpapers.activeFolder = folder.path
                Services.Wallpapers.refreshResolvedWallpapers()
            } else {
                Services.Wallpapers.scanFolder(folder.path)
            }
        }

        Shortcut {
            sequence: "Up"
            onActivated: {
                var folders = Services.Wallpapers.browseFolders
                if (!folders || folders.length === 0) return
                var active = Services.Wallpapers.activeFolder
                for (var i = 0; i < folders.length; i++) {
                    if (folders[i].path === active) {
                        if (i > 0) panel._navigateFolder(folders[i - 1])
                        return
                    }
                }
            }
        }
        Shortcut {
            sequence: "Down"
            onActivated: {
                var folders = Services.Wallpapers.browseFolders
                if (!folders || folders.length === 0) return
                var active = Services.Wallpapers.activeFolder
                for (var i = 0; i < folders.length; i++) {
                    if (folders[i].path === active) {
                        if (i < folders.length - 1) panel._navigateFolder(folders[i + 1])
                        return
                    }
                }
            }
        }

        // Delete key: reset user-wallpaper override in theme view.
        // isUserOverride is computed against the screen's PRIMARY scope
        // in get_resolved_json — so reset must target primary too, not
        // activeEditScope (else badge + delete target different buckets).
        Shortcut {
            sequence: "Delete"
            onActivated: {
                if (!Services.Wallpapers.isThemeView) return
                var model = panel.carouselModel
                var idx = view.currentIndex
                if (idx < 0 || idx >= model.length) return
                var item = model[idx]
                if (!item.isUserOverride || !item.tag) return
                if (panel.panelScreenName) {
                    var primaryScope = panel.panelScopes.length > 0 ? panel.panelScopes[0] : ""
                    Services.Wallpapers.clearUserWallpaperForScreen(
                        panel.panelScreenName, item.tag, primaryScope)
                } else {
                    Services.Wallpapers.clearUserWallpaper(item.tag)
                }
            }
        }

        // === Picker area (mask target) ===
        Item {
            id: pickerArea
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: parent.height
        }

        // === Backdrop (semi-transparent, dismiss on click) ===
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.35)
            opacity: panel.shouldShow ? 1.0 : 0.0

            Behavior on opacity {
                NumberAnimation {
                    id: fadeAnim
                    duration: Core.Anims.duration.normal
                    easing.type: Core.Anims.ease.standard
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Core.Panels.close("wallpapers")
                onWheel: (wheel) => { wheel.accepted = true }
            }
        }

        // === Full-screen layout ===
        Item {
            anchors.fill: parent

            opacity: panel.shouldShow ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutQuart } }

            // === Top bar: palette toggle + themes + refresh + close ===
            Rectangle {
                id: topBar
                anchors.top: parent.top
                anchors.topMargin: panel.shouldShow ? Math.round(40 * panel.sp) : Math.round(-100 * panel.sp)
                anchors.horizontalCenter: parent.horizontalCenter
                z: 20

                height: Math.round(68 * panel.sp)
                width: topBarRow.width + Math.round(24 * panel.sp)
                radius: Math.round(14 * panel.sp)

                color: Qt.rgba(Core.Theme.bgBase.r, Core.Theme.bgBase.g, Core.Theme.bgBase.b, 0.90)
                border.color: Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.3)
                border.width: 1

                opacity: panel.shouldShow ? 1.0 : 0.0
                Behavior on anchors.topMargin { NumberAnimation { duration: 600; easing.type: Easing.OutExpo } }
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                Row {
                    id: topBarRow
                    anchors.centerIn: parent
                    spacing: Math.round(12 * panel.sp)

                    // Theme selector — gradient cards (scrollable)
                    Flickable {
                        width: Math.min(themeRepeaterRow.width, Math.round(1500 * panel.sp))
                        height: Math.round(56 * panel.sp)
                        anchors.verticalCenter: parent.verticalCenter
                        contentWidth: themeRepeaterRow.width
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick

                        Row {
                            id: themeRepeaterRow
                            spacing: Math.round(10 * panel.sp)

                            Repeater {
                                model: Services.Wallpapers.themes

                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property bool isActive: modelData.name === Services.Wallpapers.activeTheme
                                    readonly property var pal: modelData.palette || {}
                                    readonly property color accentColor: pal.border_color_active || "#ffffff"

                                    width: Math.round(200 * panel.sp)
                                    height: Math.round(56 * panel.sp)
                                    radius: Math.round(12 * panel.sp)
                                    opacity: isActive ? 1.0 : (themeMa.containsMouse ? 1.0 : 0.8)
                                    clip: true

                                    // Gradient background from theme's own colors (no border — overlay handles it)
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: pal.bg_normal || "#181818" }
                                        GradientStop { position: 1.0; color: pal.bg_focus || "#232323" }
                                    }

                                    Behavior on opacity { NumberAnimation { duration: 300 } }

                                    // Inner accent glow on hover
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        color: accentColor
                                        opacity: themeMa.containsMouse && !isActive ? 0.08 : 0
                                        Behavior on opacity { NumberAnimation { duration: 300 } }
                                    }

                                    // Logo in right part with diagonal tinted area
                                    Item {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: parent.width * 0.45
                                        clip: true

                                        // Diagonal tinted background
                                        Canvas {
                                            anchors.fill: parent
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.beginPath()
                                                ctx.moveTo(width * 0.4, 0)
                                                ctx.lineTo(width, 0)
                                                ctx.lineTo(width, height)
                                                ctx.lineTo(0, height)
                                                ctx.closePath()
                                                ctx.fillStyle = Qt.rgba(0, 0, 0, 0.18)
                                                ctx.fill()
                                            }
                                        }

                                        // Logo image — right-aligned, large
                                        Image {
                                            anchors.right: parent.right
                                            anchors.rightMargin: Math.round(8 * panel.sp)
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.round(44 * panel.sp)
                                            height: Math.round(44 * panel.sp)
                                            source: (width > 0 && height > 0 && modelData.path)
                                                ? Core.FileUtil.fileUrl(modelData.path + "logo.png") : ""
                                            fillMode: Image.PreserveAspectFit
                                            opacity: 0.75
                                            sourceSize: Qt.size(256, 256)
                                            asynchronous: true
                                        }
                                    }

                                    // Text + swatches (left-aligned)
                                    Column {
                                        anchors.left: parent.left
                                        anchors.leftMargin: Math.round(10 * panel.sp)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Math.round(4 * panel.sp)

                                        Text {
                                            text: modelData.name
                                            font.family: Core.Theme.fontUI
                                            font.pixelSize: Math.round(13 * panel.sp)
                                            font.weight: isActive ? Font.Bold : Font.Normal
                                            color: pal.fg_focus || "#d4d4d4"
                                        }

                                        Row {
                                            spacing: Math.round(4 * panel.sp)

                                            Repeater {
                                                model: {
                                                    var p = pal
                                                    var colors = []
                                                    if (p.bg_normal) colors.push(p.bg_normal)
                                                    if (p.bg_focus) colors.push(p.bg_focus)
                                                    if (p.fg_focus) colors.push(p.fg_focus)
                                                    if (p.border_color_active) colors.push(p.border_color_active)
                                                    if (p.bg_urgent) colors.push(p.bg_urgent)
                                                    if (p.widget_cpu_color) colors.push(p.widget_cpu_color)
                                                    if (p.widget_volume_color) colors.push(p.widget_volume_color)
                                                    return colors.slice(0, 7)
                                                }

                                                Rectangle {
                                                    required property string modelData
                                                    width: Math.round(12 * panel.sp)
                                                    height: width
                                                    radius: width / 2
                                                    color: modelData
                                                    border.color: Qt.rgba(1, 1, 1, 0.25)
                                                    border.width: 1
                                                }
                                            }
                                        }
                                    }

                                    // Border overlay — highest z-order, always on top
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        color: "transparent"
                                        border.width: isActive || themeMa.containsMouse ? 2 : 1
                                        border.color: isActive
                                            ? accentColor
                                            : themeMa.containsMouse
                                                ? Qt.rgba(Qt.color(accentColor).r, Qt.color(accentColor).g, Qt.color(accentColor).b, 0.6)
                                                : Qt.rgba(1, 1, 1, 0.15)
                                        Behavior on border.color { ColorAnimation { duration: 300 } }
                                        Behavior on border.width { NumberAnimation { duration: 200 } }
                                    }

                                    MouseArea {
                                        id: themeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.Wallpapers.switchTheme(modelData.name)
                                    }
                                }
                            }
                        }
                    }

                    // Refresh button
                    Rectangle {
                        width: Math.round(36 * panel.sp); height: width
                        radius: Math.round(10 * panel.sp)
                        anchors.verticalCenter: parent.verticalCenter
                        color: refreshMa.containsMouse ? Core.Theme.surfaceContainerHigh : "transparent"
                        border.color: Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.3)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "\ue863"  // refresh
                            font.family: Core.Theme.fontIcon
                            font.pixelSize: Math.round(16 * panel.sp)
                            color: refreshMa.containsMouse ? Core.Theme.accent : Core.Theme.fgDim
                        }

                        MouseArea {
                            id: refreshMa; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Wallpapers.refresh()
                        }
                    }

                    // Close button
                    Rectangle {
                        width: Math.round(36 * panel.sp); height: width
                        radius: Math.round(10 * panel.sp)
                        anchors.verticalCenter: parent.verticalCenter
                        color: closePanelMa.containsMouse ? Qt.rgba(Core.Theme.urgent.r, Core.Theme.urgent.g, Core.Theme.urgent.b, 0.15) : "transparent"
                        border.color: Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.3)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "\ue5cd"  // close
                            font.family: Core.Theme.fontIcon
                            font.pixelSize: Math.round(16 * panel.sp)
                            color: closePanelMa.containsMouse ? Core.Theme.urgent : Core.Theme.fgDim
                        }

                        MouseArea {
                            id: closePanelMa; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Core.Panels.close("wallpapers")
                        }
                    }
                }
            }

            // === Carousel (between top bar and tag bar) ===
            ListView {
                id: view
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: topBar.bottom
                anchors.topMargin: Math.round(30 * panel.sp)
                anchors.bottom: chipBar.top
                anchors.bottomMargin: Math.round(12 * panel.sp)
                spacing: 0
                orientation: ListView.Horizontal
                clip: false
                cacheBuffer: 2000
                focus: true

                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width / 2) - ((panel.itemWidth * 1.5 + panel.itemSpacing) / 2)
                preferredHighlightEnd: (width / 2) + ((panel.itemWidth * 1.5 + panel.itemSpacing) / 2)
                highlightMoveDuration: panel.initialFocusSet ? 500 : 0

                header: Item { width: Math.max(0, (view.width / 2) - ((panel.itemWidth * 1.5) / 2)) }
                footer: Item { width: Math.max(0, (view.width / 2) - ((panel.itemWidth * 1.5) / 2)) }

                model: panel.carouselModel

                add: Transition {
                    enabled: panel.initialFocusSet
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 400; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: 400; easing.type: Easing.OutBack }
                    }
                }
                addDisplaced: Transition {
                    enabled: panel.initialFocusSet
                    NumberAnimation { property: "x"; duration: 400; easing.type: Easing.OutCubic }
                }

                // Mouse wheel navigation
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton

                    onWheel: (wheel) => {
                        if (scrollThrottle.running) { wheel.accepted = true; return }

                        var dx = wheel.angleDelta.x
                        var dy = wheel.angleDelta.y
                        var delta = Math.abs(dx) > Math.abs(dy) ? dx : dy
                        panel.scrollAccum += delta

                        if (Math.abs(panel.scrollAccum) >= panel.scrollThreshold) {
                            panel.stepToNext(panel.scrollAccum > 0 ? -1 : 1)
                            panel.scrollAccum = 0
                            scrollThrottle.start()
                        }
                        wheel.accepted = true
                    }
                }

                delegate: Item {
                    id: delegateRoot

                    readonly property string safeFileName: modelData.name || ""
                    readonly property string filePath: modelData.path || ""
                    readonly property bool isCurrent: ListView.isCurrentItem

                    readonly property real targetWidth: isCurrent ? (panel.itemWidth * 1.5) : (panel.itemWidth * 0.5)
                    readonly property real targetHeight: isCurrent ? (panel.itemHeight + 30) : panel.itemHeight

                    width: targetWidth + panel.itemSpacing
                    height: targetHeight
                    opacity: isCurrent ? 1.0 : 0.6

                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    anchors.verticalCenterOffset: 15

                    z: isCurrent ? 10 : 1

                    Behavior on width { enabled: panel.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
                    Behavior on height { enabled: panel.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }
                    Behavior on opacity { enabled: panel.initialFocusSet; NumberAnimation { duration: 500; easing.type: Easing.InOutQuad } }

                    Item {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: ((panel.itemHeight - height) / 2) * panel.skewFactor
                        width: parent.width > 0 ? parent.width * (delegateRoot.targetWidth / (delegateRoot.targetWidth + panel.itemSpacing)) : 0
                        height: parent.height

                        transform: Matrix4x4 {
                            property real s: panel.skewFactor
                            matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    // Right-click: reset user-wallpaper in theme view.
                                    // Clear the primary scope — that's what the override badge reflects.
                                    if (Services.Wallpapers.isThemeView &&
                                        modelData.isUserOverride === true && modelData.tag) {
                                        if (panel.panelScreenName) {
                                            var primaryScope = panel.panelScopes.length > 0 ? panel.panelScopes[0] : ""
                                            Services.Wallpapers.clearUserWallpaperForScreen(
                                                panel.panelScreenName, modelData.tag, primaryScope)
                                        } else {
                                            Services.Wallpapers.clearUserWallpaper(modelData.tag)
                                        }
                                    }
                                } else if (Services.Wallpapers.isThemeView) {
                                    // Theme view: left-click switches to this tag (no setWallpaper)
                                    view.currentIndex = index
                                    if (modelData.tag) panel._viewTag(modelData.tag)
                                } else {
                                    view.currentIndex = index
                                    if (panel.panelScreenName) {
                                        Services.Wallpapers.setWallpaperForScreen(
                                            panel.panelScreenName, panel.panelSelectedTag,
                                            delegateRoot.filePath, panel.activeEditScope)
                                    } else {
                                        Services.Wallpapers.setWallpaper(delegateRoot.filePath)
                                    }
                                }
                            }
                        }

                        // Outer blurry border image
                        Image {
                            anchors.fill: parent
                            source: delegateRoot.filePath ? Core.FileUtil.fileUrl(delegateRoot.filePath) : ""
                            sourceSize: Qt.size(1, 1)
                            fillMode: Image.Stretch
                            asynchronous: true
                        }

                        // Inner clipped image with inverse skew
                        Item {
                            anchors.fill: parent
                            anchors.margins: panel.borderWidth
                            clip: true

                            Rectangle { anchors.fill: parent; color: "black" }

                            Image {
                                anchors.centerIn: parent
                                // Shift left to compensate inverse skew pushing bottom-right:
                                // at y=clipHeight, image shifts right by skew*height pixels
                                anchors.horizontalCenterOffset: -(parent.height + panel.borderWidth) * Math.abs(panel.skewFactor) / 2
                                width: (panel.itemWidth * 1.5) + ((panel.itemHeight + 30) * Math.abs(panel.skewFactor)) + 50
                                height: panel.itemHeight + 30
                                fillMode: Image.PreserveAspectCrop
                                source: {
                                    if (!delegateRoot.filePath) return ""
                                    // Theme view: use resolved path directly (thumbnails are from wrong dir)
                                    if (Services.Wallpapers.isThemeView)
                                        return Core.FileUtil.fileUrl(delegateRoot.filePath)
                                    return Core.FileUtil.fileUrl(Services.Wallpapers.thumbDir + "/" + delegateRoot.safeFileName)
                                }
                                onStatusChanged: {
                                    if (status === Image.Error && delegateRoot.filePath) {
                                        source = Core.FileUtil.fileUrl(delegateRoot.filePath)
                                    }
                                }
                                asynchronous: true

                                transform: Matrix4x4 {
                                    property real s: -panel.skewFactor
                                    matrix: Qt.matrix4x4(1, s, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
                                }
                            }

                            // Tag label pill (bottom-left, theme view only)
                            Rectangle {
                                visible: Services.Wallpapers.isThemeView && (modelData.tag || "") !== ""
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.margins: Math.round(8 * panel.sp)
                                width: tagLabelText.width + Math.round(16 * panel.sp)
                                height: Math.round(24 * panel.sp)
                                radius: Math.round(12 * panel.sp)
                                color: Qt.rgba(0, 0, 0, 0.65)

                                Text {
                                    id: tagLabelText
                                    anchors.centerIn: parent
                                    text: "Tag " + (modelData.tag || "")
                                    font.family: Core.Theme.fontUI
                                    font.pixelSize: Math.round(11 * panel.sp)
                                    font.bold: true
                                    color: "#ffffff"
                                }
                            }

                            // User-override badge button (top-right, theme view only)
                            // Click to reset user-wallpaper and revert to theme default
                            Rectangle {
                                id: overrideBadge
                                visible: Services.Wallpapers.isThemeView && modelData.isUserOverride === true
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: Math.round(8 * panel.sp)
                                width: Math.round(28 * panel.sp)
                                height: width
                                radius: width / 2
                                color: badgeMa.containsMouse
                                    ? Core.Theme.urgent
                                    : Qt.rgba(Core.Theme.accent.r, Core.Theme.accent.g, Core.Theme.accent.b, 0.85)
                                scale: badgeMa.containsMouse ? 1.15 : 1.0
                                z: 10

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                Text {
                                    anchors.centerIn: parent
                                    text: badgeMa.containsMouse ? "\ue5cd" : "\ue3c9"
                                    font.family: Core.Theme.fontIcon
                                    font.pixelSize: Math.round(14 * panel.sp)
                                    color: "#ffffff"
                                }

                                MouseArea {
                                    id: badgeMa
                                    anchors.fill: parent
                                    anchors.margins: Math.round(-4 * panel.sp)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!modelData.tag) return
                                        if (panel.panelScreenName) {
                                            var primaryScope = panel.panelScopes.length > 0 ? panel.panelScopes[0] : ""
                                            Services.Wallpapers.clearUserWallpaperForScreen(
                                                panel.panelScreenName, modelData.tag, primaryScope)
                                        } else {
                                            Services.Wallpapers.clearUserWallpaper(modelData.tag)
                                        }
                                    }
                                    onContainsMouseChanged: {
                                        if (containsMouse) badgeTooltip.show()
                                        else badgeTooltip.hide()
                                    }
                                }

                                Components.Tooltip {
                                    id: badgeTooltip
                                    target: overrideBadge
                                    text: "Reset to default"
                                }
                            }
                        }
                    }
                }
            }

            // === Scope chip bar (just above tag bar, plan §7) ===
            // Renders the screen's active scope set + Base + add button.
            // Click a chip to change activeEditScope. Right-click a manual
            // scope to remove it.
            Rectangle {
                id: chipBar
                anchors.bottom: tagBar.top
                anchors.bottomMargin: Math.round(8 * panel.sp)
                anchors.horizontalCenter: parent.horizontalCenter
                z: 20

                height: Math.round(40 * panel.sp)
                width: chipRow.width + Math.round(20 * panel.sp)
                radius: Math.round(12 * panel.sp)

                color: Qt.rgba(Core.Theme.bgBase.r, Core.Theme.bgBase.g, Core.Theme.bgBase.b, 0.85)
                border.color: Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.3)
                border.width: 1

                visible: panel.panelScreenName !== ""

                opacity: panel.shouldShow ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Math.round(6 * panel.sp)

                    // Screen label (e.g. "DP-2")
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.panelScreenName
                        font.family: Core.Theme.fontUI
                        font.pixelSize: Math.round(11 * panel.sp)
                        font.weight: Font.Bold
                        color: Core.Theme.fgDim
                        rightPadding: Math.round(6 * panel.sp)
                    }

                    // Active manual + auto scopes
                    Repeater {
                        model: panel.panelScopes

                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool isEditing: panel.activeEditScope === modelData
                                && !panel._baseExplicitlySelected

                            width: chipText.width + Math.round(22 * panel.sp)
                            height: Math.round(28 * panel.sp)
                            radius: Math.round(14 * panel.sp)
                            color: isEditing
                                ? Qt.rgba(Core.Theme.accent.r, Core.Theme.accent.g, Core.Theme.accent.b, 0.3)
                                : (chipMa.containsMouse ? Core.Theme.surfaceContainerHigh : "transparent")
                            border.color: isEditing ? Core.Theme.accent
                                : Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.4)
                            border.width: isEditing ? 2 : 1
                            anchors.verticalCenter: parent.verticalCenter

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: Math.round(4 * panel.sp)

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.round(6 * panel.sp); height: width
                                    radius: width / 2
                                    color: isEditing ? Core.Theme.accent : Core.Theme.fgDim
                                    opacity: isEditing ? 1.0 : 0.6
                                }

                                Text {
                                    id: chipText
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData
                                    font.family: Core.Theme.fontUI
                                    font.pixelSize: Math.round(11 * panel.sp)
                                    font.weight: isEditing ? Font.Bold : Font.Normal
                                    color: isEditing ? Core.Theme.accent : Core.Theme.fgDim
                                }
                            }

                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        Services.Wallpapers.removeScopeFromScreen(
                                            panel.panelScreenName, modelData)
                                    } else {
                                        panel.activeEditScope = modelData
                                        panel._baseExplicitlySelected = false
                                    }
                                }
                            }
                        }
                    }

                    // Base pseudo-chip (always present, unscoped baseline)
                    Rectangle {
                        readonly property bool isEditing: panel._baseExplicitlySelected
                            || (panel.panelScopes.length === 0 && panel.activeEditScope === "")

                        width: baseText.width + Math.round(22 * panel.sp)
                        height: Math.round(28 * panel.sp)
                        radius: Math.round(14 * panel.sp)
                        color: isEditing
                            ? Qt.rgba(Core.Theme.accent.r, Core.Theme.accent.g, Core.Theme.accent.b, 0.3)
                            : (baseMa.containsMouse ? Core.Theme.surfaceContainerHigh : "transparent")
                        border.color: isEditing ? Core.Theme.accent
                            : Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.4)
                        border.width: isEditing ? 2 : 1
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Text {
                            id: baseText
                            anchors.centerIn: parent
                            text: "Base"
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Math.round(11 * panel.sp)
                            font.weight: parent.isEditing ? Font.Bold : Font.Normal
                            color: parent.isEditing ? Core.Theme.accent : Core.Theme.fgDim
                        }

                        MouseArea {
                            id: baseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                panel.activeEditScope = ""
                                panel._baseExplicitlySelected = true
                            }
                        }
                    }

                    // Add button → opens popup listing registered-but-
                    // unbound scopes for quick add.
                    Rectangle {
                        width: Math.round(28 * panel.sp); height: width
                        radius: width / 2
                        color: addMa.containsMouse ? Core.Theme.surfaceContainerHigh : "transparent"
                        border.color: Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.4)
                        border.width: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Math.round(16 * panel.sp)
                            font.weight: Font.Bold
                            color: Core.Theme.fgDim
                        }

                        MouseArea {
                            id: addMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.addScopePopupOpen = !panel.addScopePopupOpen
                        }
                    }
                }

                // Add-scope popup: lists registered scopes not already on
                // this screen. Click to add (LIFO — prepend).
                Rectangle {
                    id: addPopup
                    anchors.top: parent.bottom
                    anchors.topMargin: Math.round(6 * panel.sp)
                    anchors.right: parent.right
                    visible: panel.addScopePopupOpen && availableScopes.length > 0
                    width: Math.round(200 * panel.sp)
                    height: Math.min(availableScopes.length * Math.round(32 * panel.sp)
                        + Math.round(12 * panel.sp), Math.round(200 * panel.sp))
                    radius: Math.round(10 * panel.sp)
                    color: Qt.rgba(Core.Theme.bgBase.r, Core.Theme.bgBase.g, Core.Theme.bgBase.b, 0.95)
                    border.color: Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.4)
                    border.width: 1
                    z: 100

                    readonly property var availableScopes: {
                        var all = Services.Wallpapers.registeredScopes || []
                        var active = panel.panelScopes || []
                        var activeSet = {}
                        for (var i = 0; i < active.length; i++) activeSet[active[i]] = true
                        return all.filter(function(s) { return !activeSet[s] })
                    }

                    ListView {
                        anchors.fill: parent
                        anchors.margins: Math.round(6 * panel.sp)
                        model: addPopup.availableScopes
                        spacing: Math.round(2 * panel.sp)
                        clip: true

                        delegate: Rectangle {
                            required property string modelData
                            width: ListView.view.width
                            height: Math.round(28 * panel.sp)
                            radius: Math.round(6 * panel.sp)
                            color: itemMa.containsMouse ? Core.Theme.surfaceContainerHigh : "transparent"

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Math.round(10 * panel.sp)
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData
                                font.family: Core.Theme.fontUI
                                font.pixelSize: Math.round(11 * panel.sp)
                                color: Core.Theme.fgDim
                            }

                            MouseArea {
                                id: itemMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.Wallpapers.addScopeToScreen(
                                        panel.panelScreenName, modelData)
                                    panel.addScopePopupOpen = false
                                    panel.activeEditScope = modelData
                                    panel._baseExplicitlySelected = false
                                }
                            }
                        }
                    }
                }
            }

            // === Tag selector bar (just above filmstrip) ===
            Rectangle {
                id: tagBar
                anchors.bottom: filmstrip.top
                anchors.bottomMargin: Math.round(8 * panel.sp)
                anchors.horizontalCenter: parent.horizontalCenter
                z: 20

                height: Math.round(44 * panel.sp)
                width: tagRow.width + Math.round(20 * panel.sp)
                radius: Math.round(12 * panel.sp)

                color: Qt.rgba(Core.Theme.bgBase.r, Core.Theme.bgBase.g, Core.Theme.bgBase.b, 0.85)
                border.color: Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.3)
                border.width: 1

                visible: panel.panelTagList.length > 0

                opacity: panel.shouldShow ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                Row {
                    id: tagRow
                    anchors.centerIn: parent
                    spacing: Math.round(6 * panel.sp)

                    Repeater {
                        model: panel.panelTagList

                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool isSelected: modelData === panel.panelSelectedTag
                            readonly property bool hasOverride: {
                                var ov = panel.panelOverrides
                                return ov && ov[modelData] !== undefined
                            }

                            width: Math.round(36 * panel.sp)
                            height: Math.round(32 * panel.sp)
                            radius: Math.round(8 * panel.sp)
                            color: isSelected
                                ? Qt.rgba(Core.Theme.accent.r, Core.Theme.accent.g, Core.Theme.accent.b, 0.25)
                                : (tagMa.containsMouse ? Core.Theme.surfaceContainerHigh : "transparent")
                            border.color: isSelected ? Core.Theme.accent
                                : Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.3)
                            border.width: isSelected ? 2 : 1

                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                font.family: Core.Theme.fontUI
                                font.pixelSize: Math.round(13 * panel.sp)
                                font.weight: isSelected ? Font.Bold : Font.Normal
                                color: isSelected ? Core.Theme.accent : Core.Theme.fgDim
                            }

                            // Override indicator dot
                            Rectangle {
                                visible: hasOverride
                                width: Math.round(6 * panel.sp)
                                height: width
                                radius: width / 2
                                color: Core.Theme.accent
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: Math.round(2 * panel.sp)
                                anchors.rightMargin: Math.round(2 * panel.sp)
                            }

                            MouseArea {
                                id: tagMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel._viewTag(modelData)
                            }
                        }
                    }
                }
            }

            // === Bottom filmstrip (folder browser) — anchored to screen bottom ===
            Rectangle {
                id: filmstrip
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.round(6 * panel.sp)
                anchors.horizontalCenter: parent.horizontalCenter
                z: 20

                height: Math.round(90 * panel.sp)
                width: Math.min(filmstripList.contentWidth + Math.round(20 * panel.sp), parent.width * 0.9)
                radius: Math.round(14 * panel.sp)

                color: Qt.rgba(Core.Theme.bgBase.r, Core.Theme.bgBase.g, Core.Theme.bgBase.b, 0.85)
                border.color: Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.3)
                border.width: 1

                visible: Services.Wallpapers.browseFolders.length > 0

                opacity: panel.shouldShow ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

                ListView {
                    id: filmstripList
                    anchors.fill: parent
                    anchors.margins: Math.round(8 * panel.sp)
                    orientation: ListView.Horizontal
                    spacing: Math.round(8 * panel.sp)
                    clip: true

                    model: Services.Wallpapers.browseFolders

                    delegate: Item {
                        required property var modelData
                        readonly property bool isActive: modelData.path === Services.Wallpapers.activeFolder

                        width: Math.round(120 * panel.sp)
                        height: filmstripList.height

                        Rectangle {
                            anchors.fill: parent
                            radius: Math.round(8 * panel.sp)
                            color: isActive
                                ? Qt.rgba(Core.Theme.accent.r, Core.Theme.accent.g, Core.Theme.accent.b, 0.15)
                                : (folderMa.containsMouse ? Core.Theme.surfaceContainerHigh : "transparent")
                            border.color: isActive ? Core.Theme.accent
                                : Qt.rgba(Core.Theme.fgMuted.r, Core.Theme.fgMuted.g, Core.Theme.fgMuted.b, 0.2)
                            border.width: isActive ? 2 : 1

                            Behavior on color { ColorAnimation { duration: 200 } }
                            Behavior on border.color { ColorAnimation { duration: 200 } }

                            // Folder preview thumbnail (first wallpaper from scan)
                            Image {
                                id: folderThumb
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Math.round(4 * panel.sp)
                                height: parent.height - folderLabel.height - Math.round(10 * panel.sp)
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(160, 100)
                                asynchronous: true
                                // Use firstImage from browse folder model if available
                                source: modelData.firstImage ? Core.FileUtil.fileUrl(modelData.firstImage) : ""

                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    radius: Math.round(4 * panel.sp)
                                    border.color: Qt.rgba(0, 0, 0, 0.1)
                                    border.width: 1
                                }
                            }

                            // Folder name
                            Text {
                                id: folderLabel
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottomMargin: Math.round(3 * panel.sp)
                                text: modelData.name
                                font.family: Core.Theme.fontUI
                                font.pixelSize: Math.round(10 * panel.sp)
                                font.weight: isActive ? Font.Bold : Font.Normal
                                color: isActive ? Core.Theme.accent : Core.Theme.fgDim
                                elide: Text.ElideRight
                                width: parent.width - Math.round(8 * panel.sp)
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Theme badge
                            Rectangle {
                                visible: modelData.isTheme
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: Math.round(2 * panel.sp)
                                anchors.rightMargin: Math.round(2 * panel.sp)
                                width: Math.round(8 * panel.sp)
                                height: width
                                radius: width / 2
                                color: Core.Theme.accent
                            }

                            MouseArea {
                                id: folderMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.isTheme) {
                                        Services.Wallpapers.activeFolder = modelData.path
                                        Services.Wallpapers.refreshResolvedWallpapers()
                                    } else {
                                        Services.Wallpapers.scanFolder(modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
