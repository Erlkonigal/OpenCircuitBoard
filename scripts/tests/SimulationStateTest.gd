extends RefCounted

const SimulationBridge := preload("res://scripts/SimulationBridge.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.CircuitBoard as Node2D
	var data := context.TestData as Dictionary
	var emptySimulation := SimulationBridge.new()
	var emptyCompileResult := emptySimulation.compile(board)
	assert(bool(emptyCompileResult.get("ok", false)))
	assert(emptySimulation.GridWidth == 1)
	assert(emptySimulation.GridHeight == 1)
	assert(emptySimulation.GridOrigin == board.call("getSimulationGridOrigin"))
	var emptyStatesResult := emptySimulation.getCurrentStates()
	assert(bool(emptyStatesResult.get("ok", false)))
	assert((emptyStatesResult.get("states", PackedByteArray()) as PackedByteArray).size() == 1)
	emptySimulation.release()
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
	var compactSimulation := SimulationBridge.new()
	var compactCompileResult := compactSimulation.compile(board)
	assert(bool(compactCompileResult.get("ok", false)))
	assert(compactSimulation.GridOrigin == stateOnCoordinates)
	assert(compactSimulation.GridWidth == 3)
	assert(compactSimulation.GridHeight == 1)
	var compactStatesResult := compactSimulation.getCurrentStates()
	assert(bool(compactStatesResult.get("ok", false)))
	assert((compactStatesResult.get("states", PackedByteArray()) as PackedByteArray).size() == 3)
	board.call("applyRuntimeTileStatesFromGrid", PackedByteArray([0, 0, 1]), compactSimulation.GridWidth, compactSimulation.GridOrigin)
	assert(not bool(board.call("getRuntimeTileState", stateOnCoordinates)))
	assert(bool(board.call("getRuntimeTileState", stateOffCoordinates)))
	board.call("clearRuntimeTileStates")
	compactSimulation.release()
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
	var gridWidth := int(board.get("GridWidthCount"))
	var gridHeight := int(board.get("GridHeightCount"))
	var gridOrigin := board.call("getSimulationGridOrigin") as Vector2i
	var stateOnIndex := (stateOnCoordinates.y - gridOrigin.y) * gridWidth + stateOnCoordinates.x - gridOrigin.x
	var stateOffIndex := (stateOffCoordinates.y - gridOrigin.y) * gridWidth + stateOffCoordinates.x - gridOrigin.x
	var packedStates := PackedInt32Array()
	packedStates.resize(gridWidth * gridHeight)
	packedStates.fill(0)
	packedStates[stateOffIndex] = 1
	board.call("applyRuntimeTileStatesFromGrid", packedStates, gridWidth, gridOrigin)
	assert(not bool(board.call("getRuntimeTileState", stateOnCoordinates)))
	assert(bool(board.call("getRuntimeTileState", stateOffCoordinates)))
	var packedChanges := PackedInt32Array([stateOnIndex, 1, stateOffIndex, 0])
	board.call("applyRuntimeTileStateChanges", packedChanges, gridWidth, gridOrigin)
	assert(bool(board.call("getRuntimeTileState", stateOnCoordinates)))
	assert(not bool(board.call("getRuntimeTileState", stateOffCoordinates)))
	board.call("clearRuntimeTileStates")
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
