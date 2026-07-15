extends Control

@export var DockId := ""
@export var DockTitle := ""
@export var DockWidth := 272.0
var DockIcon: Texture2D

func getDockDefinition() -> Dictionary:
	return {
		"dockId": DockId,
		"dockTitle": DockTitle,
		"dockWidth": DockWidth,
		"dockIcon": DockIcon,
	}
