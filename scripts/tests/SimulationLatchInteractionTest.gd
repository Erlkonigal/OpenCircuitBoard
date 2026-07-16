extends RefCounted

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

	main.call("enterSimulation")
	assert(bool(main.get("IsSimulating")))
	main.call("toggleLoopStepMode")
	assert(not bool(main.get("IsLooping")))
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", traceCoordinates)))

	var canvasCenter: Vector2 = context.BoardViewport.get_global_rect().get_center()
	var clickEvent := InputEventMouseButton.new()
	clickEvent.button_index = MOUSE_BUTTON_LEFT
	clickEvent.pressed = true
	clickEvent.position = canvasCenter
	clickEvent.global_position = canvasCenter
	context.RootWindow.push_input(clickEvent)
	await context.waitFrames(1)
	assert(not bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(bool(board.call("getTileState", latchCoordinates)))
	assert((main.get("SimulationTimeline") as Array).size() == 1)

	main.call("showNextSimulationTick")
	assert(int(main.get("SimulationTick")) == 1)
	assert(not bool(board.call("getRuntimeTileState", traceCoordinates)))
	main.call("showPreviousSimulationTick")
	assert(int(main.get("SimulationTick")) == 0)
	assert(main.call("toggleSimulationLatchAt", latchCoordinates))
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert((main.get("SimulationTimeline") as Array).size() == 1)
	main.call("showNextSimulationTick")
	assert(bool(board.call("getRuntimeTileState", traceCoordinates)))

	main.call("leaveSimulation")
	assert(bool(board.call("getTileState", latchCoordinates)))
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	assert(not bool(board.call("hasRuntimeTileState", latchCoordinates)))
	assert(board.call("removeTile", latchCoordinates))
	assert(board.call("removeTile", readCoordinates))
	assert(board.call("removeTile", traceCoordinates))
