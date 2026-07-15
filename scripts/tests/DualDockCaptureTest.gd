extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("activateDock", "circuitEditor", "left")
	await context.waitFrames()
	context.MainSceneRoot.call("activateDock", "clipboard", "right")
	await context.waitFrames()
	var dualDockState := context.assertDualDockState(context.MainSceneRoot)
	assert(String((dualDockState.get("leftDock") as Control).get("DockId")) == "circuitEditor")
	assert(String((dualDockState.get("rightDock") as Control).get("DockId")) == "clipboard")
	var tiles := FrontendTestFixtures.setupVisualTiles(context.CircuitBoard)
	var circuitEditorDock := dualDockState.get("leftDock") as Control
	var leftCoordinates: Vector2i = (tiles.get("coordinates", {}) as Dictionary).get("left", Vector2i.ZERO)
	context.assertHoveredInkForCanvasTile(context.CircuitBoard, circuitEditorDock, leftCoordinates)
	context.MainSceneRoot.set_process(false)
	context.CircuitBoard.set_process(false)
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
