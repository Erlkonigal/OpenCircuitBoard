extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.board as Node2D
	var tilePosition := Vector2i(-8, -12)
	var historyBeforeDelete := (board.get("undoStack") as Array).size()
	assert(board.call("placeTile", tilePosition, "and"))
	assert(board.call("handleRightButtonPress", tilePosition))
	var tileData: Dictionary = board.get("tileData")
	assert(not tileData.has(tilePosition))
	board.call("finishStroke")
	assert((board.get("undoStack") as Array).size() == historyBeforeDelete + 1)
	context.sendCtrlShortcut(board, KEY_Z)
	assert(tileData.has(tilePosition))
	board.call("removeTile", tilePosition)
	assert((board.get("undoStack") as Array).size() == historyBeforeDelete)
