import QtQuick
import QtQuick.Layouts
import "../../core" as Core
import "../../services" as Services
import "../../components" as Components

Item {
	id: root

	property string currentCollection: ""
	property real anchorX: 0
	property real anchorY: 0
	property bool shown: false

	signal collectionSelected(string name)

	visible: shown || fadeAnim.running

	function open(gx, gy) {
		anchorX = gx
		anchorY = gy
		shown = true
	}

	function close() {
		shown = false
	}

	readonly property real sp: Core.Theme.dpiScale
	readonly property real pickerWidth: Math.round(260 * sp)
	readonly property real pickerMaxHeight: Math.round(400 * sp)

	// Semi-transparent backdrop (click to close)
	Rectangle {
		anchors.fill: parent
		color: "transparent"

		MouseArea {
			anchors.fill: parent
			onClicked: root.close()
		}
	}

	// Picker card
	Components.GlassCard {
		id: card
		x: Math.min(root.anchorX, root.parent.width - root.pickerWidth - Core.Theme.spacing.md)
		y: Math.min(root.anchorY, root.parent.height - height - Core.Theme.spacing.md)
		width: root.pickerWidth
		height: Math.min(pickerContent.implicitHeight, root.pickerMaxHeight)

		opacity: root.shown ? 1.0 : 0.0
		scale: root.shown ? 1.0 : 0.95

		Behavior on opacity {
			NumberAnimation {
				id: fadeAnim
				duration: Core.Anims.duration.fast
				easing.type: Core.Anims.ease.standard
			}
		}
		Behavior on scale { Components.Anim {} }

		ColumnLayout {
			id: pickerContent
			anchors.fill: parent
			anchors.margins: Core.Theme.spacing.sm
			spacing: Core.Theme.spacing.xs

			// Header
			Components.StyledText {
				text: "Collection"
				font.pixelSize: Core.Theme.fontSize.sm
				font.weight: Font.DemiBold
				color: Core.Theme.fgDim
				Layout.fillWidth: true
				Layout.bottomMargin: Core.Theme.spacing.xs
			}

			// Collection list
			Flickable {
				Layout.fillWidth: true
				Layout.fillHeight: true
				Layout.preferredHeight: Math.min(
					collectionCol.implicitHeight,
					root.pickerMaxHeight - Core.Theme.spacing.lg * 3
				)
				contentHeight: collectionCol.implicitHeight
				clip: true
				boundsBehavior: Flickable.StopAtBounds

				ColumnLayout {
					id: collectionCol
					width: parent.width
					spacing: Math.round(2 * root.sp)

					Repeater {
						model: Services.Portraits.collections

						Rectangle {
							required property var modelData
							required property int index

							Layout.fillWidth: true
							height: Math.round(32 * root.sp)
							radius: Core.Theme.radius.sm
							color: {
								if (modelData.name === root.currentCollection)
									return Core.Theme.accentFaint
								return itemMa.containsMouse
									? Core.Theme.glassAccentHover : "transparent"
							}

							Behavior on color { Components.CAnim {} }

							RowLayout {
								anchors.fill: parent
								anchors.leftMargin: Core.Theme.spacing.sm
								anchors.rightMargin: Core.Theme.spacing.sm
								spacing: Core.Theme.spacing.sm

								Text {
									text: modelData.name
									font.family: Core.Theme.fontUI
									font.pixelSize: Core.Theme.fontSize.sm
									font.weight: modelData.name === root.currentCollection
										? Font.DemiBold : Font.Normal
									color: modelData.name === root.currentCollection
										? Core.Theme.accent : Core.Theme.fgMain
									elide: Text.ElideRight
									Layout.fillWidth: true
								}

								Text {
									text: modelData.imageCount > 0
										? modelData.imageCount.toString() : "..."
									font.family: Core.Theme.fontMono
									font.pixelSize: Core.Theme.fontSize.xs
									color: Core.Theme.fgMuted
								}
							}

							MouseArea {
								id: itemMa
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: {
									root.collectionSelected(modelData.name)
									root.close()
								}
							}
						}
					}
				}
			}
		}
	}
}
