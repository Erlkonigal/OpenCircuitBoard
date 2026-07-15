extends SceneTree

const FrontendTestContext := preload("res://scripts/tests/frontendTestContext.gd")
const FrontendTestRegistry := preload("res://scripts/tests/frontendTestRegistry.gd")
const FrontendTestSuite := preload("res://scripts/tests/frontendTestSuite.gd")

func _init() -> void:
	call_deferred("runFrontendTests")

func runFrontendTests() -> void:
	var context := FrontendTestContext.new(self)
	var selection: Dictionary = FrontendTestRegistry.resolveRequestedEntry(context.getUserArgs())
	if selection.has("error"):
		push_error(String(selection.get("error", "FrontendTestSelectionFailed")))
		quit(1)
		return
	var suite := FrontendTestSuite.new()
	var result: Dictionary = await suite.runEntry(context, selection) if not selection.is_empty() else await suite.runDefault(context)
	await context.waitFrames(5)
	var captureError := context.saveBoardCapture()
	if captureError != OK:
		quit(captureError)
		return
	print("capture=user://capture.png error=", captureError, " data=", OS.get_user_data_dir())
	var interfaceOutputPath := String(result.get("interfaceOutputPath", selection.get("interfaceOutputPath", "")))
	if not interfaceOutputPath.is_empty():
		var interfaceError := context.saveInterfaceCapture(interfaceOutputPath)
		if interfaceError != OK:
			quit(interfaceError)
			return
		print("interfaceCapture=", interfaceOutputPath, " error=", interfaceError)
	quit(OK)
