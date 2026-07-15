extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualTiles(context.board)
	context.board.call("setSelection", Rect2i(Vector2i(-1, 0), Vector2i(3, 2)))
	var selectionOverlay := context.board.get_node("SelectionOverlay") as Node2D
	assert(bool(selectionOverlay.get("hasOverlay")))
	assert(bool(selectionOverlay.get("isSelection")))
	context.board.set_process(false)
	context.camera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
