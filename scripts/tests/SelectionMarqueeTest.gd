extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.CircuitBoard as Node2D
	var data := context.TestData as Dictionary
	var marqueeStart := Vector2i(-6, -12)
	var marqueeEnd := marqueeStart + Vector2i(1, 1)
	data["marqueeStart"] = marqueeStart
	data["marqueeEnd"] = marqueeEnd
	assert(board.call("placeTile", marqueeStart, "or"))
	assert(board.call("placeTile", marqueeEnd, "xor"))
	assert(board.call("handleLeftButtonPress", marqueeStart, true))
	var tileData: Dictionary = board.get("TileValues")
	assert(not tileData.has(marqueeStart + Vector2i(0, 1)))
	board.call("updateSelectionMarquee", marqueeEnd)
	var marqueeOverlay := board.get_node("SelectionOverlay") as Node2D
	assert(bool(marqueeOverlay.get("HasOverlay")))
	assert(not bool(marqueeOverlay.get("IsSelection")))
	board.call("finishSelection", marqueeEnd)
	var marqueeSelection: Dictionary = board.call("getSelectionItem")
	assert((marqueeSelection.get("bounds", Rect2i()) as Rect2i) == Rect2i(marqueeStart, Vector2i(2, 2)))
	assert((marqueeSelection.get("cells", []) as Array).size() == 2)
	data["marqueeSelection"] = marqueeSelection
	board.call("clearSelection")
	board.call("removeTile", marqueeStart)
	board.call("removeTile", marqueeEnd)
