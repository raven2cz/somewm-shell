// CAnim — default ColorAnimation preset (standard duration + easing).
//
// Drop-in inside `Behavior on color`; respects `Core.Anims.reducedMotion`.
import QtQuick
import "../core" as Core

ColorAnimation {
    duration: Core.Anims.reducedMotion ? 0 : Core.Anims.duration.normal
    easing.type: Core.Anims.ease.standard
}
