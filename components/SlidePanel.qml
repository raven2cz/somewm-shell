// SlidePanel — side-anchored wlr-layershell panel that slides in/out.
//
// `edge` = "left" | "right"; `shown` toggles a slide animation on the inner
// content area; uses a Region mask so the transparent area stays click-through.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core" as Core
import "." as Components

PanelWindow {
    id: panel

    required property bool shown
    required property string edge  // "left" | "right"
    property int panelWidth: 460

    // Vertical margins on the content surface. The window still spans the
    // full height (layer-shell anchored top+bottom), but the visible/
    // interactive area can be inset so the panel doesn't overlap with
    // wibar or leave an asymmetric bottom gap. mask: Region { item: contentArea }
    // keeps the top/bottom margin strips click-through.
    property int contentTopMargin: 0
    property int contentBottomMargin: 0

    // Content slot: declared on root so consumers add children correctly
    default property alias content: contentContainer.data

    visible: shown || slideAnim.running
    color: "transparent"
    focusable: shown

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "somewm-shell:" + edge
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true; bottom: true
        left:  edge === "left"
        right: edge === "right"
    }

    implicitWidth: panelWidth

    // Click-through for transparent area
    mask: Region { item: contentArea }

    // Content with slide animation via logical x (Region tracks logical bounds)
    Rectangle {
        id: contentArea
        y: panel.contentTopMargin
        width: panelWidth
        height: parent.height - panel.contentTopMargin - panel.contentBottomMargin
        color: Core.Theme.glass1
        radius: Core.Theme.radius.lg

        // Animate logical x so Region follows correctly on Wayland
        x: panel.shown ? 0 :
           (panel.edge === "left" ? -panelWidth : panelWidth)

        Behavior on x {
            NumberAnimation {
                id: slideAnim
                duration: panel.shown ? Core.Anims.duration.smooth : Core.Anims.duration.normal
                easing.type: panel.shown ? Core.Anims.ease.expressive : Core.Anims.ease.accel
                easing.overshoot: panel.shown ? Core.Anims.overshoot : 0
            }
        }

        // Border glow
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: "transparent"
            border.color: Core.Theme.glassBorder; border.width: 1
        }

        Item {
            id: contentContainer
            anchors.fill: parent
            anchors.margins: Core.Theme.spacing.lg
        }
    }
}
