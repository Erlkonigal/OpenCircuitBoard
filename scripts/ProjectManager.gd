extends RefCounted

const ProjectFormatVersion := 2
const ProjectEntryName := "project.json"
const RecentProjectsSettingsPath := "user://recentProjects.cfg"
const RecentProjectsSection := "projects"
const RecentProjectsKey := "recentProjectPaths"
const RecentProjectsLimit := 8

var CurrentProjectPath := ""
var RecentProjectPaths: Array[String] = []

func _init() -> void:
	loadRecentProjects()

func hasCurrentProject() -> bool:
	return not CurrentProjectPath.is_empty()

func clearCurrentProject() -> void:
	CurrentProjectPath = ""

func getRecentProjectPaths() -> Array[String]:
	return RecentProjectPaths.duplicate()

func saveProject(board: Node) -> Dictionary:
	if CurrentProjectPath.is_empty():
		return makeFailure("ProjectPathMissing")
	return saveProjectAs(board, CurrentProjectPath)

func saveProjectAs(board: Node, requestedPath: String) -> Dictionary:
	if board == null or not board.has_method("exportProjectData"):
		return makeFailure("ProjectBoardUnavailable")
	var projectPath := normalizeProjectPath(requestedPath)
	if projectPath.is_empty():
		return makeFailure("ProjectPathInvalid")
	var archiveData := {
		"formatVersion": ProjectFormatVersion,
		"board": board.call("exportProjectData"),
	}
	var packer := ZIPPacker.new()
	var openError := packer.open(projectPath)
	if openError != OK:
		return makeFailure("ProjectSaveOpenFailed")
	var startError := packer.start_file(ProjectEntryName)
	if startError != OK:
		packer.close()
		return makeFailure("ProjectSaveStartFailed")
	var writeError := packer.write_file(JSON.stringify(archiveData, "\t").to_utf8_buffer())
	var closeFileError := packer.close_file()
	var closeError := packer.close()
	if writeError != OK or closeFileError != OK or closeError != OK:
		return makeFailure("ProjectSaveWriteFailed")
	CurrentProjectPath = projectPath
	touchRecentProject(projectPath)
	return makeSuccess()

func loadProject(board: Node, requestedPath: String) -> Dictionary:
	if board == null or not board.has_method("importProjectData"):
		return makeFailure("ProjectBoardUnavailable")
	var projectPath := normalizeProjectPath(requestedPath)
	if projectPath.is_empty() or not FileAccess.file_exists(projectPath):
		return makeFailure("ProjectFileMissing")
	var reader := ZIPReader.new()
	var openError := reader.open(projectPath)
	if openError != OK:
		return makeFailure("ProjectOpenFailed")
	if not reader.file_exists(ProjectEntryName):
		reader.close()
		return makeFailure("ProjectEntryMissing")
	var projectText := reader.read_file(ProjectEntryName).get_string_from_utf8()
	reader.close()
	var json := JSON.new()
	if json.parse(projectText) != OK or not (json.data is Dictionary):
		return makeFailure("ProjectFormatInvalid")
	var archiveData := json.data as Dictionary
	if int(archiveData.get("formatVersion", 0)) != ProjectFormatVersion:
		return makeFailure("ProjectVersionUnsupported")
	var boardData: Variant = archiveData.get("board", {})
	if not (boardData is Dictionary) or not bool(board.call("importProjectData", boardData)):
		return makeFailure("ProjectBoardInvalid")
	CurrentProjectPath = projectPath
	touchRecentProject(projectPath)
	return makeSuccess()

func normalizeProjectPath(requestedPath: String) -> String:
	var projectPath := requestedPath.strip_edges()
	if projectPath.is_empty():
		return ""
	if projectPath.get_extension().to_lower() != "ocb":
		projectPath += ".ocb"
	return projectPath

func touchRecentProject(projectPath: String) -> void:
	RecentProjectPaths.erase(projectPath)
	RecentProjectPaths.push_front(projectPath)
	if RecentProjectPaths.size() > RecentProjectsLimit:
		RecentProjectPaths.resize(RecentProjectsLimit)
	saveRecentProjects()

func loadRecentProjects() -> void:
	RecentProjectPaths.clear()
	var settings := ConfigFile.new()
	if settings.load(RecentProjectsSettingsPath) != OK:
		return
	var storedPaths: Variant = settings.get_value(RecentProjectsSection, RecentProjectsKey, [])
	if not (storedPaths is Array):
		return
	for storedPathVariant in storedPaths:
		var storedPath := normalizeProjectPath(String(storedPathVariant))
		if storedPath.is_empty() or RecentProjectPaths.has(storedPath):
			continue
		RecentProjectPaths.append(storedPath)
		if RecentProjectPaths.size() >= RecentProjectsLimit:
			return

func saveRecentProjects() -> void:
	var settings := ConfigFile.new()
	settings.set_value(RecentProjectsSection, RecentProjectsKey, RecentProjectPaths)
	settings.save(RecentProjectsSettingsPath)

func makeSuccess() -> Dictionary:
	return {"ok": true}

func makeFailure(message: String) -> Dictionary:
	return {
		"ok": false,
		"message": message,
	}
