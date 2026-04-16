// Anim — default NumberAnimation preset (standard duration + easing).
//
// Drop-in inside `Behavior on <prop>`; respects `Core.Anims.reducedMotion`.
import QtQuick
import "../core" as Core

NumberAnimation {
    duration: Core.Anims.reducedMotion ? 0 : Core.Anims.duration.normal
    easing.type: Core.Anims.ease.standard
}
