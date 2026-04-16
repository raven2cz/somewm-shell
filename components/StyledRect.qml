// StyledRect — themed Rectangle (surface color + md radius + color anim).
//
// Convenience base used as the common styled background in the shell.
import QtQuick
import "../core" as Core
import "." as Components

Rectangle {
    color: Core.Theme.bgSurface
    radius: Core.Theme.radius.md

    Behavior on color { Components.CAnim {} }
}
