extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualTiles(context.CircuitBoard)
	var boardBounds: Rect2 = context.CircuitBoard.get("ValidRect")
	context.BoardCamera.global_position = boardBounds.position
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	await context.waitFrames(5)
	assert(is_equal_approx(context.BoardCamera.global_position.x, boardBounds.position.x))
	assert(is_equal_approx(context.BoardCamera.global_position.y, boardBounds.position.y))
	return {}
