extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")
const InkRegistry := preload("res://scripts/inkRegistry.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.clearBoardTiles(context.board)
	var onLatchOn := Vector2i(-2, -2)
	var onLatchOff := Vector2i(1, -2)
	var offLatchOn := Vector2i(-2, 1)
	var offLatchOff := Vector2i(1, 1)
	assert(context.board.call("placeTile", onLatchOn, "latchOn"))
	assert(context.board.call("placeTile", onLatchOff, "latchOff"))
	assert(context.board.call("placeTile", offLatchOn, "latchOn"))
	assert(context.board.call("placeTile", offLatchOff, "latchOff"))
	assert(context.board.call("setTileState", onLatchOff, true))
	assert(context.board.call("setTileState", offLatchOn, false))
	var occupancy: Dictionary = context.board.get("occupancy")
	context.assertTileIcon(occupancy[onLatchOn] as Node2D, InkRegistry.getInk("latchOn"), float(context.board.get("cellSize")), true)
	context.assertTileIcon(occupancy[onLatchOff] as Node2D, InkRegistry.getInk("latchOff"), float(context.board.get("cellSize")), true)
	context.assertTileIcon(occupancy[offLatchOn] as Node2D, InkRegistry.getInk("latchOn"), float(context.board.get("cellSize")), false)
	context.assertTileIcon(occupancy[offLatchOff] as Node2D, InkRegistry.getInk("latchOff"), float(context.board.get("cellSize")), false)
	context.board.set_process(false)
	context.camera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
