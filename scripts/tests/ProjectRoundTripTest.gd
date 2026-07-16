extends RefCounted

const ProjectManager := preload("res://scripts/ProjectManager.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var projectTitle := context.getNodeRef(NodePath("Interface/TopBar/ProjectTitle")) as Label
	var initialGridBounds := board.call("getGridBounds") as Rect2i
	assert(projectTitle.text == "New Project - Open Circuit Board")
	var resizedGridBounds := Rect2i(Vector2i(-24, -17), Vector2i(52, 34))
	assert(board.call("setGridBounds", resizedGridBounds))
	assert(board.call("placeTile", Vector2i(-3, 2), "xor"))
	assert(board.call("placeTile", Vector2i(4, -1), "latch"))
	main.call("setClockHoldTicks", 4)
	assert(board.call("placeTile", Vector2i(6, 3), "clock"))
	assert(board.call("setTileState", Vector2i(4, -1), false))
	assert(board.call("setMeshId", 17))
	assert(board.call("placeTile", Vector2i(-6, 3), "mesh"))
	board.call("selectTool", "busMagenta")
	var expectedProjectData := board.call("exportProjectData") as Dictionary
	var projectPath := "user://frontendTestProject.ocb"
	var legacyProjectPath := "user://frontendTestProjectWithoutGrid.ocb"
	var unsupportedProjectPath := "user://frontendTestUnsupportedV1.ocb"
	var recentProjectsPath := "user://recentProjects.cfg"
	var hadProject := FileAccess.file_exists(projectPath)
	var previousProject := FileAccess.get_file_as_bytes(projectPath) if hadProject else PackedByteArray()
	var hadLegacyProject := FileAccess.file_exists(legacyProjectPath)
	var previousLegacyProject := FileAccess.get_file_as_bytes(legacyProjectPath) if hadLegacyProject else PackedByteArray()
	var hadUnsupportedProject := FileAccess.file_exists(unsupportedProjectPath)
	var previousUnsupportedProject := FileAccess.get_file_as_bytes(unsupportedProjectPath) if hadUnsupportedProject else PackedByteArray()
	var hadRecentProjects := FileAccess.file_exists(recentProjectsPath)
	var previousRecentProjects := FileAccess.get_file_as_bytes(recentProjectsPath) if hadRecentProjects else PackedByteArray()
	main.set("PendingProjectFileAction", "save")
	main.call("handleProjectFileSelected", projectPath)
	assert(projectTitle.text == "frontendTestProject.ocb - Open Circuit Board")
	assert(getProjectFormatVersion(projectPath) == ProjectManager.ProjectFormatVersion)
	board.call("clearProjectData")
	assert((board.call("getSimulationTiles") as Array).is_empty())
	assert((board.call("getGridBounds") as Rect2i) == initialGridBounds)
	main.set("PendingProjectFileAction", "open")
	main.call("handleProjectFileSelected", projectPath)
	assert(projectTitle.text == "frontendTestProject.ocb - Open Circuit Board")
	var restoredProjectData := board.call("exportProjectData") as Dictionary
	assert(JSON.stringify(restoredProjectData) == JSON.stringify(expectedProjectData))
	assert((board.call("getGridBounds") as Rect2i) == resizedGridBounds)
	assert(int(board.call("getTileClockHoldTicks", Vector2i(6, 3))) == 4)
	assert(int(board.call("getTileMeshId", Vector2i(-6, 3))) == 17)
	var legacyProjectData := expectedProjectData.duplicate(true)
	legacyProjectData.erase("grid")
	writeProjectArchive(legacyProjectPath, ProjectManager.ProjectFormatVersion, legacyProjectData)
	var legacyLoadResult := ProjectManager.new().loadProject(board, legacyProjectPath)
	assert(bool(legacyLoadResult.get("ok", false)))
	assert((board.call("getGridBounds") as Rect2i) == initialGridBounds)
	writeProjectArchive(unsupportedProjectPath, 1, expectedProjectData)
	var unsupportedLoadResult := ProjectManager.new().loadProject(board, unsupportedProjectPath)
	assert(not bool(unsupportedLoadResult.get("ok", false)))
	assert(String(unsupportedLoadResult.get("message", "")) == "ProjectVersionUnsupported")
	main.call("createNewProject")
	assert(projectTitle.text == "New Project - Open Circuit Board")
	restoreFile(projectPath, hadProject, previousProject)
	restoreFile(legacyProjectPath, hadLegacyProject, previousLegacyProject)
	restoreFile(unsupportedProjectPath, hadUnsupportedProject, previousUnsupportedProject)
	restoreFile(recentProjectsPath, hadRecentProjects, previousRecentProjects)

func writeProjectArchive(projectPath: String, formatVersion: int, boardData: Dictionary) -> void:
	var packer := ZIPPacker.new()
	assert(packer.open(projectPath) == OK)
	assert(packer.start_file("project.json") == OK)
	assert(packer.write_file(JSON.stringify({"formatVersion": formatVersion, "board": boardData}).to_utf8_buffer()) == OK)
	assert(packer.close_file() == OK)
	assert(packer.close() == OK)

func restoreFile(path: String, hadFile: bool, previousContents: PackedByteArray) -> void:
	if hadFile:
		var file := FileAccess.open(path, FileAccess.WRITE)
		assert(file != null)
		file.store_buffer(previousContents)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func getProjectFormatVersion(projectPath: String) -> int:
	var reader := ZIPReader.new()
	assert(reader.open(projectPath) == OK)
	assert(reader.file_exists("project.json"))
	var json := JSON.new()
	assert(json.parse(reader.read_file("project.json").get_string_from_utf8()) == OK)
	reader.close()
	assert(json.data is Dictionary)
	return int((json.data as Dictionary).get("formatVersion", 0))
