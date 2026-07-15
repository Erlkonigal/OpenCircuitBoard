extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualTiles(context.CircuitBoard)
	context.CircuitBoard.set_process(false)
	context.BoardCamera.zoom = Vector2(0.5, 0.5)
	return {}
