extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.CircuitBoard as Node2D
	var data := context.TestData as Dictionary
	var strokeStart := Vector2i(-18, -12)
	var strokeEnd := Vector2i(-15, -12)
	var historyStart := (board.get("UndoStack") as Array).size()
	data["strokeStart"] = strokeStart
	data["strokeEnd"] = strokeEnd
	board.call("selectTool", "and")
	assert(board.call("handleLeftButtonPress", strokeStart, false))
	var tileData: Dictionary = board.get("TileValues")
	assert(tileData.has(strokeStart))
	assert(bool(board.call("getTileState", strokeStart)))
	assert((board.get("UndoStack") as Array).size() == historyStart)
	board.call("appendStrokeTo", strokeEnd)
	board.call("finishStroke")
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(tileData.has(Vector2i(x, strokeStart.y)))
	assert((board.get("UndoStack") as Array).size() == historyStart + 1)
	context.sendCtrlShortcut(board, KEY_Z)
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(not tileData.has(Vector2i(x, strokeStart.y)))
	assert((board.get("UndoStack") as Array).size() == historyStart)
	context.sendCtrlShortcut(board, KEY_U)
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(tileData.has(Vector2i(x, strokeStart.y)))
	assert((board.get("UndoStack") as Array).size() == historyStart + 1)

	board.call("beginStroke", strokeStart, false)
	board.call("appendStrokeTo", strokeEnd)
	board.call("finishStroke")
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(not tileData.has(Vector2i(x, strokeStart.y)))
	assert((board.get("UndoStack") as Array).size() == historyStart + 2)
	context.sendCtrlShortcut(board, KEY_Z)
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(tileData.has(Vector2i(x, strokeStart.y)))
	context.sendCtrlShortcut(board, KEY_U)
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(not tileData.has(Vector2i(x, strokeStart.y)))
	context.sendCtrlShortcut(board, KEY_Z)
	context.sendCtrlShortcut(board, KEY_Z)
	assert((board.get("UndoStack") as Array).size() == historyStart)
