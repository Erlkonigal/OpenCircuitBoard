extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.main.call("activateDock", "eventLog")
	context.main.call("setLeftSidebarOpen", true, false)
	context.main.call("setRightSidebarOpen", true, false)
	await context.waitFrames(2)
	return {}
