extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	context.main.call("activateDock", "circuitEditor", "left")
	await context.waitFrames()
	context.main.call("activateDock", "clipboard", "right")
	await context.waitFrames()
	var dualDockState := context.assertDualDockState(context.main)
	assert(String((dualDockState.get("leftDock") as Control).get("dockId")) == "circuitEditor")
	assert(String((dualDockState.get("rightDock") as Control).get("dockId")) == "clipboard")
	var tiles := FrontendTestFixtures.setupVisualTiles(context.board)
	var circuitEditorDock := dualDockState.get("leftDock") as Control
	var leftCoordinates: Vector2i = (tiles.get("coordinates", {}) as Dictionary).get("left", Vector2i.ZERO)
	context.assertHoveredInkForCanvasTile(context.board, circuitEditorDock, leftCoordinates)
	context.main.set_process(false)
	context.board.set_process(false)
	context.camera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
