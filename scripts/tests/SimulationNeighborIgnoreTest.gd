extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var readSourceCoordinates := Vector2i(-8, -10)
	var readCoordinates := Vector2i(-7, -10)
	var readOutputCoordinates := Vector2i(-6, -10)
	var readIgnoredBusCoordinates := Vector2i(-7, -11)
	var writeSourceCoordinates := Vector2i(-8, -6)
	var writeReadCoordinates := Vector2i(-7, -6)
	var writeCoordinates := Vector2i(-6, -6)
	var writeTargetCoordinates := Vector2i(-5, -6)
	var writeIgnoredBusCoordinates := Vector2i(-7, -7)
	var writeIgnoredClockCoordinates := Vector2i(-6, -7)
	var alternatingLatchCoordinates := Vector2i(-8, 10)
	var alternatingFirstReadCoordinates := Vector2i(-7, 10)
	var alternatingFirstWriteCoordinates := Vector2i(-6, 10)
	var alternatingSecondReadCoordinates := Vector2i(-5, 10)
	var alternatingSecondWriteCoordinates := Vector2i(-4, 10)
	var alternatingLedCoordinates := Vector2i(-3, 10)
	var crossSourceCoordinates := Vector2i(-8, 0)
	var crossReadCoordinates := Vector2i(-7, 0)
	var crossInputCoordinates := Vector2i(-6, 0)
	var crossCoordinates := Vector2i(-5, 0)
	var crossOutputCoordinates := Vector2i(-4, 0)
	var crossIgnoredBlueCoordinates := Vector2i(-5, -1)
	var crossIgnoredRedCoordinates := Vector2i(-5, 1)
	var meshSourceCoordinates := Vector2i(-8, 6)
	var meshReadCoordinates := Vector2i(-7, 6)
	var meshInputCoordinates := Vector2i(-6, 6)
	var meshCoordinates := Vector2i(-5, 6)
	var meshOutputCoordinates := Vector2i(-4, 6)
	var meshIgnoredBlueCoordinates := Vector2i(-5, 5)
	var meshIgnoredBufferCoordinates := Vector2i(-5, 7)
	var placements: Array[Dictionary] = [
		{"coordinates": readSourceCoordinates, "toolId": "latch"},
		{"coordinates": readCoordinates, "toolId": "read"},
		{"coordinates": readOutputCoordinates, "toolId": "trace"},
		{"coordinates": readIgnoredBusCoordinates, "toolId": "busYellow"},
		{"coordinates": writeSourceCoordinates, "toolId": "latch"},
		{"coordinates": writeReadCoordinates, "toolId": "read"},
		{"coordinates": writeCoordinates, "toolId": "write"},
		{"coordinates": writeTargetCoordinates, "toolId": "led"},
		{"coordinates": writeIgnoredBusCoordinates, "toolId": "busYellow"},
		{"coordinates": writeIgnoredClockCoordinates, "toolId": "clock"},
		{"coordinates": alternatingLatchCoordinates, "toolId": "latch"},
		{"coordinates": alternatingFirstReadCoordinates, "toolId": "read"},
		{"coordinates": alternatingFirstWriteCoordinates, "toolId": "write"},
		{"coordinates": alternatingSecondReadCoordinates, "toolId": "read"},
		{"coordinates": alternatingSecondWriteCoordinates, "toolId": "write"},
		{"coordinates": alternatingLedCoordinates, "toolId": "led"},
		{"coordinates": crossSourceCoordinates, "toolId": "latch"},
		{"coordinates": crossReadCoordinates, "toolId": "read"},
		{"coordinates": crossInputCoordinates, "toolId": "trace"},
		{"coordinates": crossCoordinates, "toolId": "cross"},
		{"coordinates": crossOutputCoordinates, "toolId": "trace"},
		{"coordinates": crossIgnoredBlueCoordinates, "toolId": "traceBlue"},
		{"coordinates": crossIgnoredRedCoordinates, "toolId": "traceRed"},
		{"coordinates": meshSourceCoordinates, "toolId": "latch"},
		{"coordinates": meshReadCoordinates, "toolId": "read"},
		{"coordinates": meshInputCoordinates, "toolId": "traceRed"},
		{"coordinates": meshCoordinates, "toolId": "mesh"},
		{"coordinates": meshOutputCoordinates, "toolId": "traceRed"},
		{"coordinates": meshIgnoredBlueCoordinates, "toolId": "traceBlue"},
		{"coordinates": meshIgnoredBufferCoordinates, "toolId": "buffer"},
	]
	for placement in placements:
		assert(board.call("placeTile", placement["coordinates"], placement["toolId"]))

	main.call("enterSimulation")
	assert(bool(main.get("IsSimulating")))
	assert((main.get("EventHistory") as Array).is_empty())
	main.call("toggleLoopStepMode")
	assert(not bool(main.get("IsLooping")))
	assert(bool(board.call("getRuntimeTileState", readOutputCoordinates)))
	assert(bool(board.call("getRuntimeTileState", writeReadCoordinates)))
	assert(bool(board.call("getRuntimeTileState", writeCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", writeTargetCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingFirstReadCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingFirstWriteCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingSecondReadCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingSecondWriteCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", alternatingLedCoordinates)))
	assert(bool(board.call("getRuntimeTileState", crossOutputCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", crossIgnoredBlueCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", crossIgnoredRedCoordinates)))
	assert(bool(board.call("getRuntimeTileState", meshOutputCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", meshIgnoredBlueCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", meshIgnoredBufferCoordinates)))

	main.call("showNextSimulationTick")
	assert(int(main.get("SimulationTick")) == 1)
	assert(bool(board.call("getRuntimeTileState", readOutputCoordinates)))
	assert(bool(board.call("getRuntimeTileState", writeReadCoordinates)))
	assert(bool(board.call("getRuntimeTileState", writeCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingFirstReadCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingFirstWriteCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingSecondReadCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingSecondWriteCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingLedCoordinates)))
	assert(bool(board.call("getRuntimeTileState", crossOutputCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", crossIgnoredBlueCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", crossIgnoredRedCoordinates)))
	assert(bool(board.call("getRuntimeTileState", meshOutputCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", meshIgnoredBlueCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", meshIgnoredBufferCoordinates)))
	assert(bool(board.call("getRuntimeTileState", writeTargetCoordinates)))

	main.call("showNextSimulationTick")
	assert(int(main.get("SimulationTick")) == 2)
	assert(bool(board.call("getRuntimeTileState", writeTargetCoordinates)))
	assert(bool(board.call("getRuntimeTileState", alternatingLedCoordinates)))
	main.call("leaveSimulation")
	for placement in placements:
		assert(board.call("removeTile", placement["coordinates"]))
