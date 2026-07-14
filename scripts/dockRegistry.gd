extends RefCounted

const dockDirectory := "res://scenes/docks"

static func discoverDocks() -> Array[Dictionary]:
	var directory := DirAccess.open(dockDirectory)
	if directory == null:
		push_error("DockDirectoryUnavailable")
		return []
	var scenePaths: Array[String] = []
	directory.list_dir_begin()
	var fileName := directory.get_next()
	while not fileName.is_empty():
		if not directory.current_is_dir() and fileName.ends_with(".tscn"):
			scenePaths.append("%s/%s" % [dockDirectory, fileName])
		fileName = directory.get_next()
	directory.list_dir_end()
	scenePaths.sort()

	var docks: Array[Dictionary] = []
	for scenePath in scenePaths:
		var dockScene := load(scenePath) as PackedScene
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
