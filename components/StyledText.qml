// StyledText — Text pre-styled with the UI font and default foreground color.
//
// Base typography element — override fontSize/color per use site as needed.
import QtQuick
import "../core" as Core

Text {
    font.family: Core.Theme.fontUI
    font.pixelSize: Core.Theme.fontSize.base
    color: Core.Theme.fgMain
}
