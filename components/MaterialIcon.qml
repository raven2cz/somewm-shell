// MaterialIcon — Text glyph styled with the Material icon font.
//
// Accepts an `icon` codepoint and `size` (px); centered horizontally/vertically.
import QtQuick
import "../core" as Core

Text {
    property string icon: ""
    property int size: Core.Theme.fontSize.xl

    text: icon
    font.family: Core.Theme.fontIcon
    font.pixelSize: size
    color: Core.Theme.fgMain
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
