extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualBoardWithClipboard(context.board)
	context.main.call("activateDock", "clipboard")
	context.main.call("setLeftSidebarOpen", true, false)
	context.main.call("setRightSidebarOpen", true, false)
	await context.waitFrames(2)
	return {}
