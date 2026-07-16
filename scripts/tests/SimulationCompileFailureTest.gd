extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var invalidReadCoordinates := Vector2i(-12, -12)
	assert(board.call("placeTile", invalidReadCoordinates, "read"))
	main.call("enterSimulation")
	assert(not bool(main.get("IsSimulating")))
	assert(bool(board.get("EditorInputEnabled")))
	assert((main.get("SimulationTimeline") as Array).is_empty())
	var eventHistory := main.get("EventHistory") as Array
	assert(not eventHistory.is_empty())
	assert(
		String(eventHistory.back()).begins_with("Simulation error at (-12, -12):"),
		"Unexpected simulation diagnostic: %s" % String(eventHistory.back())
	)
	assert(board.call("removeTile", invalidReadCoordinates))
