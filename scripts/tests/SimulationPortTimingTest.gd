extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var directClockCoordinates := Vector2i(-9, -4)
	var directReadCoordinates := Vector2i(-8, -4)
	var directWriteCoordinates := Vector2i(-7, -4)
	var directBufferCoordinates := Vector2i(-6, -4)
	var directTraceCoordinates := Vector2i(-8, -3)
	var peerClockCoordinates := Vector2i(-9, 2)
	var peerFirstReadCoordinates := Vector2i(-8, 2)
	var peerFirstTraceCoordinates := Vector2i(-7, 2)
	var peerFirstWriteCoordinates := Vector2i(-6, 2)
	var peerSecondReadCoordinates := Vector2i(-5, 2)
	var peerSecondTraceCoordinates := Vector2i(-4, 2)
	var peerSecondWriteCoordinates := Vector2i(-3, 2)
	var peerBufferCoordinates := Vector2i(-2, 2)
	var placements: Array[Dictionary] = [
		{"coordinates": directClockCoordinates, "toolId": "clock"},
		{"coordinates": directReadCoordinates, "toolId": "read"},
		{"coordinates": directWriteCoordinates, "toolId": "write"},
		{"coordinates": directBufferCoordinates, "toolId": "buffer"},
		{"coordinates": directTraceCoordinates, "toolId": "trace"},
		{"coordinates": peerClockCoordinates, "toolId": "clock"},
		{"coordinates": peerFirstReadCoordinates, "toolId": "read"},
		{"coordinates": peerFirstTraceCoordinates, "toolId": "trace"},
		{"coordinates": peerFirstWriteCoordinates, "toolId": "write"},
		{"coordinates": peerSecondReadCoordinates, "toolId": "read"},
		{"coordinates": peerSecondTraceCoordinates, "toolId": "trace"},
		{"coordinates": peerSecondWriteCoordinates, "toolId": "write"},
		{"coordinates": peerBufferCoordinates, "toolId": "buffer"},
	]
	for placement in placements:
		assert(board.call("placeTile", placement["coordinates"], placement["toolId"]))

	main.call("enterSimulation")
	assert(bool(main.get("IsSimulating")))
	assert((main.get("EventHistory") as Array).is_empty())
	main.call("toggleLoopStepMode")
	assert(not bool(main.get("IsLooping")))
	assert(not bool(board.call("getRuntimeTileState", directClockCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", directReadCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", directWriteCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", directTraceCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", directBufferCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerClockCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerFirstReadCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerFirstTraceCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerFirstWriteCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerSecondReadCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerSecondTraceCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerSecondWriteCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerBufferCoordinates)))

	main.call("showNextSimulationTick")
	assert(int(main.get("SimulationTick")) == 1)
	assert(bool(board.call("getRuntimeTileState", directClockCoordinates)))
	assert(bool(board.call("getRuntimeTileState", directReadCoordinates)))
	assert(bool(board.call("getRuntimeTileState", directTraceCoordinates)))
	assert(bool(board.call("getRuntimeTileState", directWriteCoordinates)), "Read feeds Write in the same tick")
	assert(not bool(board.call("getRuntimeTileState", directBufferCoordinates)))
	assert(bool(board.call("getRuntimeTileState", peerClockCoordinates)))
	assert(bool(board.call("getRuntimeTileState", peerFirstReadCoordinates)))
	assert(bool(board.call("getRuntimeTileState", peerFirstTraceCoordinates)))
	assert(bool(board.call("getRuntimeTileState", peerFirstWriteCoordinates)))
	assert(bool(board.call("getRuntimeTileState", peerSecondReadCoordinates)), "Write feeds Read in the same tick")
	assert(bool(board.call("getRuntimeTileState", peerSecondTraceCoordinates)))
	assert(bool(board.call("getRuntimeTileState", peerSecondWriteCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerBufferCoordinates)))

	main.call("showNextSimulationTick")
	assert(int(main.get("SimulationTick")) == 2)
	assert(not bool(board.call("getRuntimeTileState", directClockCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", directReadCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", directWriteCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", directTraceCoordinates)))
	assert(bool(board.call("getRuntimeTileState", directBufferCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerClockCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerFirstReadCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerFirstTraceCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerFirstWriteCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerSecondReadCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerSecondTraceCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", peerSecondWriteCoordinates)))
	assert(bool(board.call("getRuntimeTileState", peerBufferCoordinates)))

	main.call("leaveSimulation")
	for placement in placements:
		assert(board.call("removeTile", placement["coordinates"]))
