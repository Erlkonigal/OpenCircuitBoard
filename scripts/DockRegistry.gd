extends RefCounted

const DockScenes := [
	preload("res://scenes/docks/CircuitEditorDock.tscn"),
	preload("res://scenes/docks/ClipboardDock.tscn"),
	preload("res://scenes/docks/EventLogDock.tscn"),
]

static func discoverDocks() -> Array[Dictionary]:
	var docks: Array[Dictionary] = []
	for dockSceneVariant in DockScenes:
		var dockScene := dockSceneVariant as PackedScene
		if dockScene == null:
			continue
		var dock := dockScene.instantiate()
		if not dock.has_method("getDockDefinition"):
			dock.free()
			continue
		var definition: Dictionary = dock.call("getDockDefinition")
		dock.free()
		if String(definition.get("dockId", "")).is_empty() or String(definition.get("dockTitle", "")).is_empty():
			push_error("DockDefinitionInvalid")
			continue
		definition["scene"] = dockScene
		docks.append(definition)
	return docks
