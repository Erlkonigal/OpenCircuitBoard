extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.CircuitBoard as Node2D
	var data := context.TestData as Dictionary
	var source := Vector2i(-12, -10)
	var sourceOther := source + Vector2i(2, 0)
	var outsideSelection := source + Vector2i(0, 2)
	data["source"] = source
	data["sourceOther"] = sourceOther
	data["outsideSelection"] = outsideSelection
	assert(board.call("placeTile", source, "or"))
	assert(board.call("placeTile", sourceOther, "xor"))
	assert(board.call("setTileState", sourceOther, false))
	assert(not bool(board.call("getTileState", sourceOther)))
	board.call("setSelection", Rect2i(source, Vector2i(3, 1)))
	var sourceSelection: Dictionary = board.call("getSelectionItem")
	assert((sourceSelection.get("cells", []) as Array).size() == 2)
	assert(board.call("placeTile", outsideSelection, "nor"))
	var tileData: Dictionary = board.get("TileValues")
	var historyBeforeLeftSelectionCancel := (board.get("UndoStack") as Array).size()
	assert(board.call("handleLeftButtonPress", outsideSelection, false))
	var clearedSelection: Dictionary = board.call("getSelectionItem")
	assert((clearedSelection.get("cells", []) as Array).is_empty())
	assert(String((tileData[outsideSelection] as Dictionary).get("toolId", "")) == "nor")
	assert((board.get("UndoStack") as Array).size() == historyBeforeLeftSelectionCancel)

	board.call("setSelection", Rect2i(source, Vector2i(3, 1)))
	var historyBeforeRightSelectionCancel := (board.get("UndoStack") as Array).size()
	assert(board.call("handleRightButtonPress", outsideSelection))
	assert((board.call("getSelectionItem").get("cells", []) as Array).is_empty())
	assert(String((tileData[outsideSelection] as Dictionary).get("toolId", "")) == "nor")
	assert((board.get("UndoStack") as Array).size() == historyBeforeRightSelectionCancel)
	board.call("removeTile", outsideSelection)
