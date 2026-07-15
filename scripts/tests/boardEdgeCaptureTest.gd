extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualTiles(context.board)
	var boardBounds: Rect2 = context.board.get("validRect")
	context.camera.global_position = boardBounds.position
	context.camera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	await context.waitFrames(5)
	assert(is_equal_approx(context.camera.global_position.x, boardBounds.position.x))
	assert(is_equal_approx(context.camera.global_position.y, boardBounds.position.y))
	return {}
