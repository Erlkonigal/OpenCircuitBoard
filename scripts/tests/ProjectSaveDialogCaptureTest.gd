extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("showSaveProjectDialog")
	await context.waitFrames(2)
	var projectFileDialog := context.MainSceneRoot.get("ProjectFileDialog") as FileDialog
	assert(projectFileDialog.visible)
	assert(projectFileDialog.title == "Save .ocb Project")
	return {}
