extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualTiles(context.board)
	context.board.set_process(false)
	context.camera.zoom = Vector2(0.5, 0.5)
	return {}
