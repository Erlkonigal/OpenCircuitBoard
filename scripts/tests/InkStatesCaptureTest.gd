extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")
const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.clearBoardTiles(context.CircuitBoard)
	var onLatchOn := Vector2i(-2, -2)
	var onLatchOff := Vector2i(1, -2)
	var offLatchOn := Vector2i(-2, 1)
	var offLatchOff := Vector2i(1, 1)
	assert(context.CircuitBoard.call("placeTile", onLatchOn, "latchOn"))
	assert(context.CircuitBoard.call("placeTile", onLatchOff, "latchOff"))
	assert(context.CircuitBoard.call("placeTile", offLatchOn, "latchOn"))
	assert(context.CircuitBoard.call("placeTile", offLatchOff, "latchOff"))
	assert(context.CircuitBoard.call("setTileState", onLatchOff, true))
	assert(context.CircuitBoard.call("setTileState", offLatchOn, false))
	var occupancy: Dictionary = context.CircuitBoard.get("Occupancy")
	context.assertTileIcon(occupancy[onLatchOn] as Node2D, InkRegistry.getInk("latchOn"), float(context.CircuitBoard.get("CellSize")), true)
	context.assertTileIcon(occupancy[onLatchOff] as Node2D, InkRegistry.getInk("latchOff"), float(context.CircuitBoard.get("CellSize")), true)
	context.assertTileIcon(occupancy[offLatchOn] as Node2D, InkRegistry.getInk("latchOn"), float(context.CircuitBoard.get("CellSize")), false)
	context.assertTileIcon(occupancy[offLatchOff] as Node2D, InkRegistry.getInk("latchOff"), float(context.CircuitBoard.get("CellSize")), false)
	context.CircuitBoard.set_process(false)
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
