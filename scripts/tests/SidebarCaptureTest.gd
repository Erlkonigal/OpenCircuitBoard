extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("activateDock", "circuitEditor")
	context.MainSceneRoot.call("setLeftSidebarOpen", true, false)
	context.MainSceneRoot.call("setRightSidebarOpen", true, false)
	await context.waitFrames(2)
	return {}
