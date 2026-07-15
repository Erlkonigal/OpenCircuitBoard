extends RefCounted

const ProjectManager := preload("res://scripts/ProjectManager.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.CircuitBoard as Node2D
	assert(board.call("placeTile", Vector2i(-3, 2), "xor"))
	assert(board.call("placeTile", Vector2i(4, -1), "latchOff"))
	assert(board.call("setTileState", Vector2i(4, -1), true))
	board.call("selectTool", "busMagenta")
	var expectedProjectData := board.call("exportProjectData") as Dictionary
	var projectPath := "user://frontendTestProject.ocb"
	var recentProjectsPath := "user://recentProjects.cfg"
	var hadProject := FileAccess.file_exists(projectPath)
	var previousProject := FileAccess.get_file_as_bytes(projectPath) if hadProject else PackedByteArray()
	var hadRecentProjects := FileAccess.file_exists(recentProjectsPath)
	var previousRecentProjects := FileAccess.get_file_as_bytes(recentProjectsPath) if hadRecentProjects else PackedByteArray()
	var projectManager := ProjectManager.new()
	var saveResult: Dictionary = projectManager.saveProjectAs(board, projectPath)
	assert(bool(saveResult.get("ok", false)))
	assert(projectManager.hasCurrentProject())
	board.call("clearProjectData")
	assert((board.call("getSimulationTiles") as Array).is_empty())
	var loadResult: Dictionary = projectManager.loadProject(board, projectPath)
	assert(bool(loadResult.get("ok", false)))
	var restoredProjectData := board.call("exportProjectData") as Dictionary
	assert(JSON.stringify(restoredProjectData) == JSON.stringify(expectedProjectData))
	restoreFile(projectPath, hadProject, previousProject)
	restoreFile(recentProjectsPath, hadRecentProjects, previousRecentProjects)

func restoreFile(path: String, hadFile: bool, previousContents: PackedByteArray) -> void:
	if hadFile:
		var file := FileAccess.open(path, FileAccess.WRITE)
		assert(file != null)
		file.store_buffer(previousContents)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
