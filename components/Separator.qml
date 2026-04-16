// Separator — 1px horizontal (default) or vertical divider line.
//
// Toggle orientation with the `vertical` property; color from the theme.
import QtQuick
import "../core" as Core

Rectangle {
    property bool vertical: false

    width: vertical ? 1 : undefined
    height: vertical ? undefined : 1
    color: Core.Theme.glassBorder
}
