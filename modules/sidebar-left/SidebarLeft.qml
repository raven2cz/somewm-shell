// SidebarLeft — left-edge slide-in panel with tab bar.
//
// General-purpose multi-tab left sidebar. Currently hosts a single tab
// (Portraits gallery); the TabBar structure is kept so further tabs can
// be added without touching the panel chrome.
//
// Layer:   wlr-layershell Top (above regular windows, below overlays).
// Width:   narrow (460dp) ↔ extended (900dp), toggled via header button.
// Edge:    left (slides in from the screen edge).
// Close:   click × button, Escape key (via FocusScope — Keys cannot
//          attach directly to PanelWindow), or IPC toggle.
// Screens: only rendered on the active screen to avoid duplicates
//          across multi-monitor setups.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Variants {
    model: Quickshell.screens

    Components.SlidePanel {
        id: panel

        required property var modelData
        screen: modelData

        edge: "left"
        // Width animated via Behavior on panelWidth (SlidePanel binds
        // contentArea.width: panelWidth and implicitWidth: panelWidth).
        panelWidth: panel.expanded
            ? Math.round(900 * Core.Theme.dpiScale)
            : Math.round(460 * Core.Theme.dpiScale)

        // Inset content so wibar stays visible on top + symmetric gap below.
        // Matches typical wibar height (~44dp).
        contentTopMargin: Math.round(44 * Core.Theme.dpiScale)
        contentBottomMargin: Math.round(44 * Core.Theme.dpiScale)

        // Only show on the focused screen to avoid duplicate panels.
        shown: Core.Panels.isOpen("sidebar-left") &&
               Services.Compositor.isActiveScreen(modelData)

        property bool expanded: false
        property int currentTab: 0

        Behavior on panelWidth {
            NumberAnimation {
                duration: Core.Anims.duration.normal
                easing.type: Core.Anims.ease.standard
            }
        }

        FocusScope {
            anchors.fill: parent
            focus: panel.shown

            Keys.onEscapePressed: Core.Panels.close("sidebar-left")

            ColumnLayout {
                anchors.fill: parent
                spacing: Core.Theme.spacing.md

                // === Header: tab bar + expand + close ===
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Core.Theme.spacing.sm

                    Components.TabBar {
                        id: tabBar
                        Layout.fillWidth: true
                        currentIndex: panel.currentTab
                        tabs: [
                            { label: "Portraits" }
                        ]
                        onTabChanged: (idx) => panel.currentTab = idx
                    }

                    // Expand toggle
                    Item {
                        Layout.preferredWidth: Math.round(32 * Core.Theme.dpiScale)
                        Layout.preferredHeight: Math.round(32 * Core.Theme.dpiScale)

                        Components.MaterialIcon {
                            anchors.centerIn: parent
                            // "keyboard_double_arrow_right" when narrow,
                            // "keyboard_double_arrow_left" when expanded.
                            icon: panel.expanded ? "\uebe7" : "\uebe4"
                            size: Core.Theme.fontSize.xl
                            color: panel.expanded ? Core.Theme.accent : Core.Theme.fgDim
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: panel.expanded = !panel.expanded
                        }
                    }

                    // Close
                    Item {
                        Layout.preferredWidth: Math.round(32 * Core.Theme.dpiScale)
                        Layout.preferredHeight: Math.round(32 * Core.Theme.dpiScale)

                        Components.MaterialIcon {
                            anchors.centerIn: parent
                            icon: "\ue5cd"
                            size: Core.Theme.fontSize.xl
                            color: Core.Theme.fgDim
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: Core.Panels.close("sidebar-left")
                        }
                    }
                }

                // === Content area: lazy-loaded tabs ===
                //
                // Each tab is a Loader keyed on `panel.currentTab`. A tab
                // exists only while its Loader is active — switching tabs
                // destroys the previous one and frees its scene graph.
                // (Tab 0 is active on first open, so the default tab is
                // constructed immediately.)
                Item {
                    id: content
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Loader {
                        id: portraitsLoader
                        anchors.fill: parent
                        active: panel.currentTab === 0
                        sourceComponent: Component { PortraitsGallery {} }
                    }
                }
            }
        }
    }
}
