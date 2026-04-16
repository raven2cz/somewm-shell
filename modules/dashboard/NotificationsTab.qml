// NotificationsTab — dashboard notification view (Caelestia-style).
//
// Display shell for Core.NotifStore. Swipe-to-dismiss, expand-on-click,
// count badge + clear-all header. No IPC logic here — store owns it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../core" as Core
import "../../components" as Components

Item {
    id: root

    readonly property real sp: Core.Theme.dpiScale
    readonly property real spacNorm: Math.round(12 * sp)
    readonly property real spacSm: Math.round(8 * sp)
    readonly property real padLg: Math.round(15 * sp)
    readonly property real roundLg: Math.round(25 * sp)
    readonly property real roundNorm: Math.round(16 * sp)

    // Content-driven width matching other tabs; height is flexible
    implicitWidth: Math.round(500 * sp)
    implicitHeight: headerRow.implicitHeight + spacNorm + listArea.contentHeight + spacNorm

    readonly property var notifications: Core.NotifStore.notifications
    property int expandedIndex: -1

    function refresh() { Core.NotifStore.refresh() }
    function clearAll() {
        Core.NotifStore.clearAll()
        root.expandedIndex = -1
    }
    function dismissOne(idx) { Core.NotifStore.dismissOne(idx) }
    function copyToClipboard(title, message) { Core.NotifStore.copyToClipboard(title, message) }

    // === Header row ===
    RowLayout {
        id: headerRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: spacSm

        Text {
            text: "\ue7f4"
            font.family: Core.Theme.fontIcon
            font.pixelSize: Math.round(18 * sp)
            color: Core.Theme.accent
        }

        Text {
            Layout.fillWidth: true
            text: "Notifications"
            font.family: Core.Theme.fontUI
            font.pixelSize: Math.round(13 * sp)
            font.weight: Font.DemiBold
            color: Core.Theme.fgMain
        }

        // Count badge
        Rectangle {
            visible: root.notifications.length > 0
            width: countText.implicitWidth + spacNorm * 2
            height: Math.round(24 * sp)
            radius: height / 2
            color: Core.Theme.accentFaint

            Text {
                id: countText
                anchors.centerIn: parent
                text: root.notifications.length
                font.family: Core.Theme.fontMono
                font.pixelSize: Math.round(11 * sp)
                font.weight: Font.Bold
                color: Core.Theme.accent
            }
        }

        // Clear all button
        Rectangle {
            visible: root.notifications.length > 0
            width: Math.round(36 * sp); height: width
            radius: width / 2
            color: clearMa.containsMouse ? Qt.rgba(Core.Theme.urgent.r, Core.Theme.urgent.g, Core.Theme.urgent.b, 0.15) : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\ue872"  // delete_sweep
                font.family: Core.Theme.fontIcon
                font.pixelSize: Math.round(18 * sp)
                color: clearMa.containsMouse ? Core.Theme.urgent : Core.Theme.fgMuted
            }
            MouseArea {
                id: clearMa; anchors.fill: parent
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.clearAll()
            }
        }

        // Refresh button
        Rectangle {
            width: Math.round(32 * sp); height: width
            radius: width / 2
            color: refreshMa.containsMouse ? Core.Theme.accentFaint : "transparent"

            Text {
                anchors.centerIn: parent
                text: "\ue863"  // refresh
                font.family: Core.Theme.fontIcon
                font.pixelSize: Math.round(16 * sp)
                color: refreshMa.containsMouse ? Core.Theme.accent : Core.Theme.fgMuted
            }
            MouseArea {
                id: refreshMa; anchors.fill: parent
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
            }
        }
    }

    // === Notification list ===
    Flickable {
        id: listArea
        anchors.top: headerRow.bottom
        anchors.topMargin: spacNorm
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentHeight: notifColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: notifColumn
            width: listArea.width
            spacing: spacSm

            Repeater {
                model: root.notifications

                // Individual notification card (Caelestia-inspired)
                Rectangle {
                    id: notifCard
                    Layout.fillWidth: true
                    implicitHeight: notifContent.implicitHeight + spacNorm * 2

                    required property var modelData
                    required property int index

                    property bool isExpanded: root.expandedIndex === index
                    property bool isHovered: notifMouse.containsMouse
                    property bool isCritical: modelData.urgency === "critical"

                    color: isCritical
                        ? Qt.rgba(Core.Theme.urgent.r, Core.Theme.urgent.g, Core.Theme.urgent.b, 0.08)
                        : Core.Theme.surfaceContainer
                    radius: roundNorm
                    clip: true

                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: Core.Anims.duration.normal
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Core.Anims.curves.standard
                        }
                    }

                    // Swipe to dismiss
                    property real swipeX: 0
                    Behavior on swipeX {
                        NumberAnimation { duration: Core.Anims.duration.fast }
                    }
                    transform: Translate { x: notifCard.swipeX }
                    opacity: 1.0 - Math.abs(swipeX) / (notifCard.width * 0.5)

                    MouseArea {
                        id: notifMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        property real startX: 0
                        property real startY: 0
                        property bool dragging: false

                        onPressed: (mouse) => {
                            startX = mouse.x
                            startY = mouse.y
                            dragging = false
                        }
                        onPositionChanged: (mouse) => {
                            if (!pressed) return
                            var dx = mouse.x - startX
                            var dy = mouse.y - startY
                            // Only start horizontal drag if dx > dy threshold
                            if (!dragging && Math.abs(dx) > Math.round(20 * sp) && Math.abs(dx) > Math.abs(dy) * 1.5)
                                dragging = true
                            if (dragging) notifCard.swipeX = dx

                            // Vertical drag = expand/collapse (Caelestia pattern)
                            if (!dragging && Math.abs(dy) > Math.round(30 * sp)) {
                                root.expandedIndex = dy > 0 ? notifCard.index : -1
                            }
                        }
                        onReleased: {
                            if (dragging && Math.abs(notifCard.swipeX) > notifCard.width * 0.3) {
                                notifCard.swipeX = notifCard.swipeX > 0 ? notifCard.width : -notifCard.width
                                root.dismissOne(notifCard.index)
                            } else if (dragging) {
                                notifCard.swipeX = 0
                            } else {
                                root.expandedIndex = notifCard.isExpanded ? -1 : notifCard.index
                            }
                            dragging = false
                        }
                    }

                    ColumnLayout {
                        id: notifContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: spacNorm
                        spacing: Math.round(4 * sp)

                        // Top row: urgency dot + title + app name + actions
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: spacSm

                            // Urgency dot
                            Rectangle {
                                width: Math.round(8 * sp)
                                height: width; radius: width / 2
                                color: notifCard.isCritical ? Core.Theme.urgent : Core.Theme.accent
                            }

                            // Title
                            Text {
                                Layout.fillWidth: true
                                text: modelData.title || "Notification"
                                font.family: Core.Theme.fontUI
                                font.pixelSize: Math.round(12 * sp)
                                font.weight: Font.DemiBold
                                color: Core.Theme.fgMain
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            // App name
                            Text {
                                visible: modelData.app !== ""
                                text: modelData.app
                                font.family: Core.Theme.fontUI
                                font.pixelSize: Math.round(10 * sp)
                                color: Core.Theme.fgMuted
                            }

                            // Expand/collapse icon
                            Text {
                                visible: modelData.message !== ""
                                text: notifCard.isExpanded ? "\ue5ce" : "\ue5cf"  // expand_less / expand_more
                                font.family: Core.Theme.fontIcon
                                font.pixelSize: Math.round(16 * sp)
                                color: Core.Theme.fgMuted

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.expandedIndex = notifCard.isExpanded ? -1 : notifCard.index
                                }
                            }

                            // Hover actions (no hoverEnabled on children — prevents flicker loop)
                            Row {
                                visible: notifCard.isHovered && !notifMouse.dragging
                                spacing: Math.round(4 * sp)

                                Text {
                                    text: "\ue14d"  // content_copy
                                    font.family: Core.Theme.fontIcon
                                    font.pixelSize: Math.round(14 * sp)
                                    color: Core.Theme.fgDim
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.copyToClipboard(modelData.title, modelData.message)
                                    }
                                }
                                Text {
                                    text: "\ue5cd"  // close
                                    font.family: Core.Theme.fontIcon
                                    font.pixelSize: Math.round(14 * sp)
                                    color: Core.Theme.fgDim
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.dismissOne(notifCard.index)
                                    }
                                }
                            }
                        }

                        // Body preview (collapsed: 1 line)
                        Text {
                            visible: modelData.message !== "" && !notifCard.isExpanded
                            Layout.fillWidth: true
                            text: modelData.message
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Math.round(11 * sp)
                            color: Core.Theme.fgDim
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        // Body full (expanded: all lines)
                        Text {
                            visible: modelData.message !== "" && notifCard.isExpanded
                            Layout.fillWidth: true
                            text: modelData.message
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Math.round(11 * sp)
                            color: Core.Theme.fgDim
                            wrapMode: Text.WordWrap
                        }

                        // Expand hint
                        Text {
                            visible: !notifCard.isExpanded && modelData.message.length > 60
                            text: "Swipe to dismiss \u00B7 Click to expand"
                            font.family: Core.Theme.fontUI
                            font.pixelSize: Math.round(9 * sp)
                            font.italic: true
                            color: Core.Theme.fgMuted
                            opacity: 0.7
                        }
                    }
                }
            }

        }
    }

    // Empty state — centered in full tab area
    ColumnLayout {
        visible: root.notifications.length === 0
        anchors.centerIn: parent
        spacing: spacNorm

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "\ue7f7"  // notifications_none
            font.family: Core.Theme.fontIcon
            font.pixelSize: Math.round(48 * sp)
            color: Core.Theme.fgMuted
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "No notifications"
            font.family: Core.Theme.fontUI
            font.pixelSize: Math.round(13 * sp)
            color: Core.Theme.fgMuted
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Notifications will appear here"
            font.family: Core.Theme.fontUI
            font.pixelSize: Math.round(11 * sp)
            color: Core.Theme.fgMuted
            opacity: 0.6
        }
    }

    Component.onCompleted: refresh()
}
