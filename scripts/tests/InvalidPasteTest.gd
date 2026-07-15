extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.CircuitBoard as Node2D
	var data := context.TestData as Dictionary
	var source := Vector2i(-12, -7)
	var sourceOther := source + Vector2i(2, 0)
	assert(board.call("placeTile", source, "or"))
	assert(board.call("placeTile", sourceOther, "xor"))
	assert(board.call("setTileState", sourceOther, false))
	board.call("setSelection", Rect2i(source, Vector2i(3, 1)))
	context.sendCtrlShortcut(board, KEY_C)
	var occupiedTileCount := (board.get("TileValues") as Dictionary).size()
	data["occupiedTileCount"] = occupiedTileCount
	board.call("beginPastePreview")
	board.call("updatePastePreview", source)
	assert(not bool(board.get("PastePreviewValid")))
	board.call("confirmPastePreview")
	assert((board.get("TileValues") as Dictionary).size() == occupiedTileCount)
	board.call("cancelPastePreview")
