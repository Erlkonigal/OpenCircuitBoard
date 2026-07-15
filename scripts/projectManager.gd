extends RefCounted

const projectFormatVersion := 1
const projectEntryName := "project.json"
const recentProjectsSettingsPath := "user://recentProjects.cfg"
const recentProjectsSection := "projects"
const recentProjectsKey := "recentProjectPaths"
const recentProjectsLimit := 8

var currentProjectPath := ""
var recentProjectPaths: Array[String] = []

func _init() -> void:
	loadRecentProjects()

func hasCurrentProject() -> bool:
	return not currentProjectPath.is_empty()

func clearCurrentProject() -> void:
	currentProjectPath = ""

func getRecentProjectPaths() -> Array[String]:
	return recentProjectPaths.duplicate()

func saveProject(board: Node) -> Dictionary:
	if currentProjectPath.is_empty():
		return makeFailure("ProjectPathMissing")
	return saveProjectAs(board, currentProjectPath)

func saveProjectAs(board: Node, requestedPath: String) -> Dictionary:
	if board == null or not board.has_method("exportProjectData"):
		return makeFailure("ProjectBoardUnavailable")
	var projectPath := normalizeProjectPath(requestedPath)
	if projectPath.is_empty():
		return makeFailure("ProjectPathInvalid")
	var archiveData := {
		"formatVersion": projectFormatVersion,
		"board": board.call("exportProjectData"),
	}
	var packer := ZIPPacker.new()
	var openError := packer.open(projectPath)
	if openError != OK:
		return makeFailure("ProjectSaveOpenFailed")
	var startError := packer.start_file(projectEntryName)
	if startError != OK:
		packer.close()
		return makeFailure("ProjectSaveStartFailed")
	var writeError := packer.write_file(JSON.stringify(archiveData, "\t").to_utf8_buffer())
	var closeFileError := packer.close_file()
	var closeError := packer.close()
	if writeError != OK or closeFileError != OK or closeError != OK:
		return makeFailure("ProjectSaveWriteFailed")
	currentProjectPath = projectPath
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
	if not reader.file_exists(projectEntryName):
		reader.close()
		return makeFailure("ProjectEntryMissing")
	var projectText := reader.read_file(projectEntryName).get_string_from_utf8()
	reader.close()
	var json := JSON.new()
	if json.parse(projectText) != OK or not (json.data is Dictionary):
		return makeFailure("ProjectFormatInvalid")
	var archiveData := json.data as Dictionary
	if int(archiveData.get("formatVersion", 0)) != projectFormatVersion:
		return makeFailure("ProjectVersionUnsupported")
	var boardData: Variant = archiveData.get("board", {})
	if not (boardData is Dictionary) or not bool(board.call("importProjectData", boardData)):
		return makeFailure("ProjectBoardInvalid")
	currentProjectPath = projectPath
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
	recentProjectPaths.erase(projectPath)
	recentProjectPaths.push_front(projectPath)
	if recentProjectPaths.size() > recentProjectsLimit:
		recentProjectPaths.resize(recentProjectsLimit)
	saveRecentProjects()

func loadRecentProjects() -> void:
	recentProjectPaths.clear()
	var settings := ConfigFile.new()
	if settings.load(recentProjectsSettingsPath) != OK:
		return
	var storedPaths: Variant = settings.get_value(recentProjectsSection, recentProjectsKey, [])
	if not (storedPaths is Array):
		return
	for storedPathVariant in storedPaths:
		var storedPath := normalizeProjectPath(String(storedPathVariant))
		if storedPath.is_empty() or recentProjectPaths.has(storedPath):
			continue
		recentProjectPaths.append(storedPath)
		if recentProjectPaths.size() >= recentProjectsLimit:
			return

func saveRecentProjects() -> void:
	var settings := ConfigFile.new()
	settings.set_value(recentProjectsSection, recentProjectsKey, recentProjectPaths)
	settings.save(recentProjectsSettingsPath)

func makeSuccess() -> Dictionary:
	return {"ok": true}

func makeFailure(message: String) -> Dictionary:
	return {
		"ok": false,
		"message": message,
	}
