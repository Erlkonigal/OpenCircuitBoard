extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualTiles(context.board)
	var selector := context.board.get_node("Selector") as ColorRect
	selector.visible = true
	selector.position = Vector2(3, -2) * float(context.board.get("cellSize"))
	context.board.set_process(false)
	context.camera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
