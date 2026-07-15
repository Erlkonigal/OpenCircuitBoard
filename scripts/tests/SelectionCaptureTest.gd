extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualTiles(context.CircuitBoard)
	context.CircuitBoard.call("setSelection", Rect2i(Vector2i(-1, 0), Vector2i(3, 2)))
	var selectionOverlay := context.CircuitBoard.get_node("SelectionOverlay") as Node2D
	assert(bool(selectionOverlay.get("HasOverlay")))
	assert(bool(selectionOverlay.get("IsSelection")))
	context.CircuitBoard.set_process(false)
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
