// ClickableCard — GlassCard with hover tracking, ripple, and `clicked` signal.
//
// Wraps a StateLayer MouseArea; an `active` flag switches the card to its
// accent-tinted variant.
import QtQuick
import "../core" as Core

GlassCard {
    id: card
    hovered: mouseArea.containsMouse

    property bool active: false
    accentTint: active

    signal clicked(var mouse)

    StateLayer {
        id: mouseArea
        anchors.fill: parent
        onClicked: (mouse) => card.clicked(mouse)
    }
}
