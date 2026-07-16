extends RefCounted

func run(context) -> void:
	await context.resetMain()
	assert(bool(ProjectSettings.get_setting("display/window/subwindows/embed_subwindows")))
	var main := context.MainSceneRoot as Control
	var projectFileDialog := main.get("ProjectFileDialog") as FileDialog
	var projectNoticeDialog := main.get("ProjectNoticeDialog") as AcceptDialog
	assert(projectFileDialog != null)
	assert(projectNoticeDialog != null)
	assert(projectFileDialog.transparent_bg)
	assert(projectNoticeDialog.transparent_bg)
	var panelStyle := projectFileDialog.get_theme_stylebox("panel") as StyleBoxFlat
	assert(panelStyle != null)
	assert(panelStyle.bg_color.is_equal_approx(Color("17212f")))
	assert(projectFileDialog.get_theme_color("font_color", "Label").is_equal_approx(Color("d8e1ef")))
	assert(projectFileDialog.get_theme_color("folder_icon_color", "FileDialog").is_equal_approx(Color("8fb4e8")))
	main.call("showOpenProjectDialog")
	assert(projectFileDialog.visible)
	assert(projectFileDialog.title == "Open .ocb Project")
	assert(projectFileDialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE)
	projectFileDialog.hide()
	main.call("showSaveProjectDialog")
	assert(projectFileDialog.visible)
	assert(projectFileDialog.title == "Save .ocb Project")
	assert(projectFileDialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE)
	assert(projectFileDialog.current_file == "Untitled.ocb")
	projectFileDialog.hide()
