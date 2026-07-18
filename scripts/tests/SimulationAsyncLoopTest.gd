extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var latchCoordinates := Vector2i(-12, -12)
	assert(board.call("placeTile", latchCoordinates, "latch"))
	assert(board.call("setTileState", latchCoordinates, false))
	main.call("enterSimulation")
	assert(bool(main.get("IsSimulating")))
	main.call("setLoopFrequency", float(main.call("getLoopFrequencyMaximumTps")))
	await context.waitFrames(2)
	assert(bool(main.get("IsAsyncSimulationRunning")))
	assert(main.call("toggleSimulationLatchAt", latchCoordinates))
	await context.waitSeconds(0.15)
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	main.call("toggleLoopStepMode")
	assert(not bool(main.get("IsAsyncSimulationRunning")))
	assert(not bool(main.get("IsLooping")))
	assert((main.get("SimulationTimeline") as Array).size() == 1)
	assert(bool(board.call("getRuntimeTileState", latchCoordinates)))
	main.call("leaveSimulation")
	assert(not bool(main.get("IsSimulating")))
	assert(board.call("removeTile", latchCoordinates))
