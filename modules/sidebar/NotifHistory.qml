// NotifHistory — sidebar notification list.
//
// Display shell for Core.NotifStore. No IPC logic here — the store owns
// fetching/dismiss/clear/copy and the somewm-shell:notifications handler.
// Bind to Core.NotifStore.notifications, call its functions for actions.

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../core" as Core
import "../../components" as Components

Item {
    id: root

    property int expandedIndex: -1
    readonly property var notifications: Core.NotifStore.notifications

    function refresh() { Core.NotifStore.refresh() }
    function clearAll() {
        Core.NotifStore.clearAll()
        root.expandedIndex = -1
    }
    function dismissOne(idx) { Core.NotifStore.dismissOne(idx) }
    function copyToClipboard(title, message) { Core.NotifStore.copyToClipboard(title, message) }

    ColumnLayout {
        anchors.fill: parent
        spacing: Core.Theme.spacing.sm

        // Header
        RowLayout {
            Layout.fillWidth: true

            Components.StyledText {
                text: "Notifications"
                font.pixelSize: Core.Theme.fontSize.base
                font.weight: Font.DemiBold
                color: Core.Theme.fgDim
                Layout.fillWidth: true
            }

            // Notification count badge
            Text {
                visible: root.notifications.length > 0
                text: root.notifications.length
                font.family: Core.Theme.fontMono
                font.pixelSize: Core.Theme.fontSize.xs
                color: Core.Theme.accent
            }

            // Clear all button
            Components.MaterialIcon {
                visible: root.notifications.length > 0
                icon: "\ue872"  // delete_sweep
                size: Core.Theme.fontSize.lg
                color: hovered ? Core.Theme.urgent : Core.Theme.fgMuted
                property bool hovered: false

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: parent.hovered = true
                    onExited: parent.hovered = false
                    onClicked: root.clearAll()
                }
            }

            Components.MaterialIcon {
                icon: "\ue863"  // refresh
                size: Core.Theme.fontSize.lg
                color: Core.Theme.fgMuted
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refresh()
                }
            }
        }

        // Notification list
        Flickable {
            id: flickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: notifColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: notifColumn
                width: flickable.width
                spacing: Core.Theme.spacing.xs

                Repeater {
                    model: root.notifications

                    Components.GlassCard {
                        id: notifCard
                        Layout.fillWidth: true
                        Layout.preferredHeight: notifContent.implicitHeight + Core.Theme.spacing.md * 2

                        required property var modelData
                        required property int index

                        property bool isExpanded: root.expandedIndex === index
                        property bool isHovered: false

                        // Subtle hover highlight
                        border.color: isHovered ? Core.Theme.glassBorder : "transparent"
                        border.width: isHovered ? 1 : 0

                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: notifCard.isHovered = true
                            onExited: notifCard.isHovered = false
                            onClicked: {
                                root.expandedIndex = notifCard.isExpanded ? -1 : notifCard.index
                            }
                        }

                        ColumnLayout {
                            id: notifContent
                            anchors.fill: parent
                            anchors.margins: Core.Theme.spacing.md
                            spacing: Core.Theme.spacing.xs

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Core.Theme.spacing.xs

                                Components.MaterialIcon {
                                    icon: "\ue7f4"  // notifications
                                    size: Core.Theme.fontSize.base
                                    color: Core.Theme.accent
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    font.family: Core.Theme.fontUI
                                    font.pixelSize: Core.Theme.fontSize.sm
                                    font.weight: Font.DemiBold
                                    color: Core.Theme.fgMain
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: modelData.app !== ""
                                    text: modelData.app
                                    font.family: Core.Theme.fontUI
                                    font.pixelSize: Core.Theme.fontSize.xs
                                    color: Core.Theme.fgMuted
                                }

                                // Action buttons (visible on hover)
                                Row {
                                    visible: notifCard.isHovered
                                    spacing: Core.Theme.spacing.xs

                                    // Copy to clipboard
                                    Components.MaterialIcon {
                                        icon: "\ue14d"  // content_copy
                                        size: Core.Theme.fontSize.sm
                                        color: copyMa.containsMouse ? Core.Theme.accent : Core.Theme.fgMuted
                                        MouseArea {
                                            id: copyMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.copyToClipboard(modelData.title, modelData.message)
                                        }
                                    }

                                    // Dismiss
                                    Components.MaterialIcon {
                                        icon: "\ue5cd"  // close
                                        size: Core.Theme.fontSize.sm
                                        color: dismissMa.containsMouse ? Core.Theme.urgent : Core.Theme.fgMuted
                                        MouseArea {
                                            id: dismissMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.dismissOne(notifCard.index)
                                        }
                                    }
                                }
                            }

                            // Message (collapsed: 2 lines, expanded: full)
                            Text {
                                visible: modelData.message !== ""
                                Layout.fillWidth: true
                                text: modelData.message
                                font.family: Core.Theme.fontUI
                                font.pixelSize: Core.Theme.fontSize.sm
                                color: Core.Theme.fgDim
                                wrapMode: Text.WordWrap
                                maximumLineCount: notifCard.isExpanded ? 999 : 2
                                elide: notifCard.isExpanded ? Text.ElideNone : Text.ElideRight
                            }

                            // Expand hint
                            Text {
                                visible: !notifCard.isExpanded && modelData.message.length > 80
                                text: "Click to expand..."
                                font.family: Core.Theme.fontUI
                                font.pixelSize: Core.Theme.fontSize.xs
                                font.italic: true
                                color: Core.Theme.fgMuted
                            }
                        }
                    }
                }

                // Empty state
                Text {
                    visible: root.notifications.length === 0
                    Layout.fillWidth: true
                    Layout.topMargin: Core.Theme.spacing.lg
                    horizontalAlignment: Text.AlignHCenter
                    text: "No notifications"
                    font.family: Core.Theme.fontUI
                    font.pixelSize: Core.Theme.fontSize.sm
                    color: Core.Theme.fgMuted
                }
            }
        }
    }
}
