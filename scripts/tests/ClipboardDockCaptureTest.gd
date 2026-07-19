extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualBoardWithClipboard(context.CircuitBoard)
	context.MainSceneRoot.call("activateDock", "clipboard")
	context.MainSceneRoot.call("setLeftSidebarOpen", true, false)
	context.MainSceneRoot.call("setRightSidebarOpen", true, false)
	await context.waitFrames(1)
	var clipboardDockState: Dictionary = context.getActiveDockState(context.MainSceneRoot, "clipboard")
	var clipboardDock := clipboardDockState.get("dock") as Control
	assert(clipboardDock != null)
	clipboardDock.call("setClipboardHistory", FrontendTestFixtures.makeOversizedClipboardHistory(), 0)
	await context.waitFrames(2)
	return {}
