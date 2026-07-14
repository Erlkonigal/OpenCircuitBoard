extends Control

@export var dockId := ""
@export var dockTitle := ""
@export var dockWidth := 272.0
var dockIcon: Texture2D

func getDockDefinition() -> Dictionary:
	return {
		"dockId": dockId,
		"dockTitle": dockTitle,
		"dockWidth": dockWidth,
		"dockIcon": dockIcon,
	}
