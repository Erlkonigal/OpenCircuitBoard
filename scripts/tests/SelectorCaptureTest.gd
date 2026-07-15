extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualTiles(context.CircuitBoard)
	var selector := context.CircuitBoard.get_node("Selector") as ColorRect
	selector.visible = true
	selector.position = Vector2(3, -2) * float(context.CircuitBoard.get("CellSize"))
	context.CircuitBoard.set_process(false)
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
