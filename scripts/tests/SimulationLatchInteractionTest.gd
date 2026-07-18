extends RefCounted

const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var latchCoordinates := Vector2i.ZERO
	var readCoordinates := Vector2i(1, 0)
	var traceCoordinates := Vector2i(2, 0)
	assert(board.call("placeTile", latchCoordinates, "latch"))
	assert(board.call("placeTile", readCoordinates, "read"))
	assert(board.call("placeTile", traceCoordinates, "trace"))
	assert(bool(board.call("getTileState", latchCoordinates)))
	assertLatchIcon(board, latchCoordinates, true)

	main.call("enterSimulation")
	assert(bool(main.get("IsSimulating")))
	main.call("toggleLoopStepMode")
	assert(not bool(main.get("IsLooping")))
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(bool(board.call("getRuntimeTileState", traceCoordinates)))

	var canvasCenter: Vector2 = context.BoardViewport.get_global_rect().get_center()
	var clickEvent := InputEventMouseButton.new()
	clickEvent.button_index = MOUSE_BUTTON_LEFT
	clickEvent.pressed = true
	clickEvent.position = canvasCenter
	clickEvent.global_position = canvasCenter
	context.RootWindow.push_input(clickEvent)
	await context.waitFrames(1)
	assert(not bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", traceCoordinates)))
	assert(bool(board.call("getTileState", latchCoordinates)))
	assertLatchIcon(board, latchCoordinates, false)
	assert((main.get("SimulationTimeline") as Array).size() == 1)

	main.call("showNextSimulationTick")
	assert(int(main.get("SimulationTick")) == 1)
	assert(not bool(board.call("getRuntimeTileState", traceCoordinates)))
	main.call("showPreviousSimulationTick")
	assert(int(main.get("SimulationTick")) == 0)
	assert(main.call("toggleSimulationLatchAt", latchCoordinates))
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(bool(board.call("getRuntimeTileState", traceCoordinates)))
	assertLatchIcon(board, latchCoordinates, true)
	assert((main.get("SimulationTimeline") as Array).size() == 1)
	main.call("showNextSimulationTick")
	assert(bool(board.call("getRuntimeTileState", traceCoordinates)))
	assert(int(main.get("SimulationTick")) == 1)
	assert(main.call("toggleSimulationLatchAt", latchCoordinates))
	assert(not bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", traceCoordinates)))
	assertLatchIcon(board, latchCoordinates, false)
	assert((main.get("SimulationTimeline") as Array).size() == 2)
	main.call("showPreviousSimulationTick")
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(bool(board.call("getRuntimeTileState", traceCoordinates)))
	main.call("showNextSimulationTick")
	assert(not bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", traceCoordinates)))

	main.call("leaveSimulation")
	assert(bool(board.call("getTileState", latchCoordinates)))
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(not bool(board.call("hasRuntimeTileState", latchCoordinates)))
	assert(board.call("removeTile", latchCoordinates))
	assert(board.call("removeTile", readCoordinates))
	assert(board.call("removeTile", traceCoordinates))

	await context.resetMain()
	await context.waitFrames(1)
	main = context.MainSceneRoot as Control
	board = context.CircuitBoard as Node2D
	var clockCoordinates := Vector2i.ZERO
	readCoordinates = Vector2i(1, 0)
	traceCoordinates = Vector2i(2, 0)
	var writeCoordinates := Vector2i(3, 0)
	latchCoordinates = Vector2i(4, 0)
	assert(board.call("placeTile", clockCoordinates, "clock"))
	assert(board.call("placeTile", readCoordinates, "read"))
	assert(board.call("placeTile", traceCoordinates, "trace"))
	assert(board.call("placeTile", writeCoordinates, "write"))
	assert(board.call("placeTile", latchCoordinates, "latch"))
	assert(board.call("setTileState", latchCoordinates, false))
	main.call("enterSimulation")
	main.call("toggleLoopStepMode")
	main.call("showNextSimulationTick")
	assert(not bool(board.call("getRuntimeTileState", latchCoordinates)))
	main.call("showNextSimulationTick")
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	main.call("showNextSimulationTick")
	assert(not bool(board.call("getRuntimeTileState", latchCoordinates)))
	assertLatchIcon(board, latchCoordinates, false)
	main.call("leaveSimulation")
	assert(board.call("removeTile", clockCoordinates))
	assert(board.call("removeTile", readCoordinates))
	assert(board.call("removeTile", traceCoordinates))
	assert(board.call("removeTile", writeCoordinates))
	assert(board.call("removeTile", latchCoordinates))

func assertLatchIcon(board: Node2D, coordinates: Vector2i, isOn: bool) -> void:
	var occupancy: Dictionary = board.get("Occupancy")
	var latchTile := occupancy.get(coordinates) as Node2D
	var iconRect := latchTile.get_node("Icon") as TextureRect
	assert(iconRect.texture == InkRegistry.getInkIcon("latch", isOn))
