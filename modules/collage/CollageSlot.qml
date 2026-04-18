import QtQuick
import QtQuick.Effects
import "../../core" as Core
import "../../services" as Services

Item {
	id: root

	// Layout properties (from JSON config, logical pixels)
	property real slotX: 0
	property real slotY: 0
	property real maxHeight: 400
	property int imageIndex: 0
	property string collectionName: ""
	property bool editMode: false

	// Signals to parent
	signal indexPersist(int newIndex)
	signal slotMoved(real newX, real newY)
	signal slotResized(real newMaxHeight)
	signal middleClicked(real globalX, real globalY)
	signal rightClicked()

	readonly property real sp: Core.Theme.dpiScale

	x: Math.round(slotX * sp)
	y: Math.round(slotY * sp)
	width: _imageWidth
	height: Math.round(maxHeight * sp)

	// Computed image dimensions (preserve aspect ratio, use active image)
	property real _imageWidth: {
		var img = _useFront ? imgFront : imgBack
		if (img.sourceSize.width > 0 && img.sourceSize.height > 0) {
			var ratio = img.sourceSize.width / img.sourceSize.height
			return Math.round(height * ratio)
		}
		// Fallback: try the other image
		var other = _useFront ? imgBack : imgFront
		if (other.sourceSize.width > 0 && other.sourceSize.height > 0) {
			var ratio2 = other.sourceSize.width / other.sourceSize.height
			return Math.round(height * ratio2)
		}
		// Default aspect ratio before image loads
		return Math.round(height * 0.667)
	}

	property string _currentPath: ""

	// === Crossfade: two stacked images ===

	property bool _useFront: true

	onImageIndexChanged: _loadImage()
	onCollectionNameChanged: _loadImage()

	// Retry image load when portrait cache updates (async scan may not be ready
	// at Component.onCompleted time)
	Connections {
		target: Services.Portraits
		function onCollectionScanned(name) {
			if (name === root.collectionName && root._currentPath === "")
				root._loadImage()
		}
	}

	function _loadImage() {
		var newPath = Services.Portraits.getImage(collectionName, imageIndex)
		if (newPath === "" || newPath === _currentPath) return

		// First load: set directly without crossfade
		if (_currentPath === "") {
			imgFront.source = "file://" + newPath
			_currentPath = newPath
			return
		}

		if (_useFront) {
			imgBack.source = "file://" + newPath
		} else {
			imgFront.source = "file://" + newPath
		}
		_useFront = !_useFront
		_currentPath = newPath
	}

	Component.onCompleted: _loadImage()

	// Crossfade container (hidden, used as source for single MultiEffect mask)
	Item {
		id: crossfadeSource
		anchors.fill: parent
		visible: false
		layer.enabled: true

		Image {
			id: imgBack
			anchors.fill: parent
			asynchronous: true
			fillMode: Image.PreserveAspectCrop
			cache: true
			sourceSize.height: Math.round(root.maxHeight * root.sp * 2)
			opacity: root._useFront ? 0.0 : 1.0

			Behavior on opacity {
				NumberAnimation {
					duration: Core.Anims.duration.normal
					easing.type: Core.Anims.ease.standard
				}
			}
		}

		Image {
			id: imgFront
			anchors.fill: parent
			asynchronous: true
			fillMode: Image.PreserveAspectCrop
			cache: true
			sourceSize.height: Math.round(root.maxHeight * root.sp * 2)
			source: ""  // Set imperatively by _loadImage()
			opacity: root._useFront ? 1.0 : 0.0

			Behavior on opacity {
				NumberAnimation {
					duration: Core.Anims.duration.normal
					easing.type: Core.Anims.ease.standard
				}
			}
		}
	}

	// Rounded corner mask
	Item {
		id: roundedMask
		anchors.fill: parent
		visible: false
		layer.enabled: true
		Rectangle { anchors.fill: parent; radius: Core.Theme.radius.lg }
	}

	// Shadow + rounded corners
	Item {
		id: frameContainer
		anchors.fill: parent

		layer.enabled: true
		layer.effect: MultiEffect {
			shadowEnabled: true
			shadowColor: Qt.rgba(0, 0, 0, 0.65)
			shadowVerticalOffset: Math.round(14 * root.sp)
			shadowHorizontalOffset: Math.round(6 * root.sp)
			shadowBlur: 1.0
		}

		// Placeholder while active image loads
		Rectangle {
			anchors.fill: parent
			radius: Core.Theme.radius.lg
			color: Core.Theme.glass2
			visible: {
				var active = root._useFront ? imgFront : imgBack
				return active.status !== Image.Ready
			}
		}

		// Single masked output (crossfade happens inside source)
		MultiEffect {
			anchors.fill: parent
			source: crossfadeSource
			maskEnabled: true
			maskSource: roundedMask
		}

		// Edit mode border
		Rectangle {
			anchors.fill: parent
			radius: Core.Theme.radius.lg
			color: "transparent"
			border.width: root.editMode ? Math.round(2 * root.sp) : 0
			border.color: Core.Theme.accent
			visible: root.editMode

			Behavior on border.width {
				NumberAnimation { duration: Core.Anims.duration.fast }
			}
		}
	}

	// === Edit mode: resize handle (bottom-right corner) ===
	Rectangle {
		id: resizeHandle
		visible: root.editMode
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.margins: Math.round(-4 * root.sp)
		width: Math.round(16 * root.sp)
		height: Math.round(16 * root.sp)
		radius: Math.round(8 * root.sp)
		color: Core.Theme.accent
		opacity: resizeMa.containsMouse ? 1.0 : 0.7

		MouseArea {
			id: resizeMa
			anchors.fill: parent
			preventStealing: true
			hoverEnabled: true
			cursorShape: Qt.SizeFDiagCursor
			property real _startY: 0
			property real _startHeight: 0
			property bool _dirty: false

			// Commit resize only on release / cancel. Emitting slotResized on
			// every pixel reassigned layoutData in the parent, which churned
			// Repeater bindings and left the per-slot DragHandler unable to
			// start a new move until edit mode was re-entered.
			onPressed: (mouse) => {
				_startY = mouse.y + resizeHandle.y + root.y
				_startHeight = root.maxHeight
				_dirty = false
			}
			onPositionChanged: (mouse) => {
				if (!pressed) return
				var currentY = mouse.y + resizeHandle.y + root.y
				var delta = (currentY - _startY) / root.sp
				var newH = Math.max(100, _startHeight + delta)
				root.maxHeight = Math.round(newH)
				_dirty = true
			}
			onReleased: {
				if (_dirty) {
					root.slotResized(Math.round(root.maxHeight))
					_dirty = false
				}
			}
			onCanceled: {
				if (_dirty) {
					root.slotResized(Math.round(root.maxHeight))
					_dirty = false
				}
			}
		}
	}
}
