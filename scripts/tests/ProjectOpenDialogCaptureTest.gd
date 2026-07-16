extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("showOpenProjectDialog")
	await context.waitFrames(2)
	var projectFileDialog := context.MainSceneRoot.get("ProjectFileDialog") as FileDialog
	assert(projectFileDialog.visible)
	assert(projectFileDialog.title == "Open .ocb Project")
	return {}
