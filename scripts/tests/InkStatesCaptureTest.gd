extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")
const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.clearBoardTiles(context.CircuitBoard)
	var onLatchLeft := Vector2i(-2, -2)
	var onLatchRight := Vector2i(1, -2)
	var offLatchLeft := Vector2i(-2, 1)
	var offLatchRight := Vector2i(1, 1)
	assert(context.CircuitBoard.call("placeTile", onLatchLeft, "latch"))
	assert(context.CircuitBoard.call("placeTile", onLatchRight, "latch"))
	assert(context.CircuitBoard.call("placeTile", offLatchLeft, "latch"))
	assert(context.CircuitBoard.call("placeTile", offLatchRight, "latch"))
	assert(context.CircuitBoard.call("setTileState", offLatchLeft, false))
	assert(context.CircuitBoard.call("setTileState", offLatchRight, false))
	var occupancy: Dictionary = context.CircuitBoard.get("Occupancy")
	context.assertTileIcon(occupancy[onLatchLeft] as Node2D, InkRegistry.getInk("latch"), float(context.CircuitBoard.get("CellSize")), true)
	context.assertTileIcon(occupancy[onLatchRight] as Node2D, InkRegistry.getInk("latch"), float(context.CircuitBoard.get("CellSize")), true)
	context.assertTileIcon(occupancy[offLatchLeft] as Node2D, InkRegistry.getInk("latch"), float(context.CircuitBoard.get("CellSize")), false)
	context.assertTileIcon(occupancy[offLatchRight] as Node2D, InkRegistry.getInk("latch"), float(context.CircuitBoard.get("CellSize")), false)
	context.CircuitBoard.set_process(false)
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
