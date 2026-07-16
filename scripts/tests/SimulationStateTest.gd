extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.CircuitBoard as Node2D
	var data := context.TestData as Dictionary
	var stateOnCoordinates := Vector2i(-13, -14)
	var stateOffCoordinates := Vector2i(-11, -14)
	data["stateOnCoordinates"] = stateOnCoordinates
	data["stateOffCoordinates"] = stateOffCoordinates
	assert(board.call("placeTile", stateOnCoordinates, "latch"))
	assert(board.call("placeTile", stateOffCoordinates, "latch"))
	assert(bool(board.call("getTileState", stateOnCoordinates)))
	assert(bool(board.call("getTileState", stateOffCoordinates)))
	assert(board.call("setTileState", stateOffCoordinates, false))
	assert(not bool(board.call("getTileState", stateOffCoordinates)))
	var stateHistoryBeforeUpdate := (board.get("UndoStack") as Array).size()
	assert(board.call("setTileState", stateOnCoordinates, false))
	assert(not bool(board.call("getTileState", stateOnCoordinates)))
	assert((board.get("UndoStack") as Array).size() == stateHistoryBeforeUpdate)
	board.call("applyTileStates", [
		{"coordinates": stateOnCoordinates, "isOn": true},
		{"coordinates": stateOffCoordinates, "isOn": true},
	])
	assert(bool(board.call("getTileState", stateOnCoordinates)))
	assert(bool(board.call("getTileState", stateOffCoordinates)))
	board.call("applyRuntimeTileStates", [
		{"coordinates": stateOnCoordinates, "isOn": false},
	])
	assert(bool(board.call("getTileState", stateOnCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", stateOnCoordinates)))
	var occupancy: Dictionary = board.get("Occupancy")
	assert(not bool((occupancy[stateOnCoordinates] as Node2D).get("IsOn")))
	board.call("clearRuntimeTileStates")
	assert(bool(board.call("getRuntimeTileState", stateOnCoordinates)))
	assert(bool((occupancy[stateOnCoordinates] as Node2D).get("IsOn")))
	var simulationTiles: Array = board.call("getSimulationTiles")
	var capturedStates := {}
	for simulationTileVariant in simulationTiles:
		var simulationTile := simulationTileVariant as Dictionary
		capturedStates[simulationTile.get("coordinates", Vector2i.ZERO)] = bool(simulationTile.get("isOn", false))
	assert(bool(capturedStates.get(stateOnCoordinates, false)))
	assert(bool(capturedStates.get(stateOffCoordinates, false)))
	data["capturedStates"] = capturedStates
	board.call("removeTile", stateOnCoordinates)
	board.call("removeTile", stateOffCoordinates)
