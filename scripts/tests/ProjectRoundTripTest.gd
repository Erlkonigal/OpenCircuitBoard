extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var projectTitle := context.getNodeRef(NodePath("Interface/TopBar/ProjectTitle")) as Label
	assert(projectTitle.text == "New Project - Open Circuit Board")
	assert(board.call("placeTile", Vector2i(-3, 2), "xor"))
	assert(board.call("placeTile", Vector2i(4, -1), "latchOff"))
	main.call("setClockHoldTicks", 4)
	assert(board.call("placeTile", Vector2i(6, 3), "clock"))
	assert(board.call("setTileState", Vector2i(4, -1), true))
	board.call("selectTool", "busMagenta")
	var expectedProjectData := board.call("exportProjectData") as Dictionary
	var projectPath := "user://frontendTestProject.ocb"
	var recentProjectsPath := "user://recentProjects.cfg"
	var hadProject := FileAccess.file_exists(projectPath)
	var previousProject := FileAccess.get_file_as_bytes(projectPath) if hadProject else PackedByteArray()
	var hadRecentProjects := FileAccess.file_exists(recentProjectsPath)
	var previousRecentProjects := FileAccess.get_file_as_bytes(recentProjectsPath) if hadRecentProjects else PackedByteArray()
	main.set("PendingProjectFileAction", "save")
	main.call("handleProjectFileSelected", projectPath)
	assert(projectTitle.text == "frontendTestProject.ocb - Open Circuit Board")
	board.call("clearProjectData")
	assert((board.call("getSimulationTiles") as Array).is_empty())
	main.set("PendingProjectFileAction", "open")
	main.call("handleProjectFileSelected", projectPath)
	assert(projectTitle.text == "frontendTestProject.ocb - Open Circuit Board")
	var restoredProjectData := board.call("exportProjectData") as Dictionary
	assert(JSON.stringify(restoredProjectData) == JSON.stringify(expectedProjectData))
	assert(int(board.call("getTileClockHoldTicks", Vector2i(6, 3))) == 4)
	main.call("createNewProject")
	assert(projectTitle.text == "New Project - Open Circuit Board")
	restoreFile(projectPath, hadProject, previousProject)
	restoreFile(recentProjectsPath, hadRecentProjects, previousRecentProjects)

func restoreFile(path: String, hadFile: bool, previousContents: PackedByteArray) -> void:
	if hadFile:
		var file := FileAccess.open(path, FileAccess.WRITE)
		assert(file != null)
		file.store_buffer(previousContents)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
