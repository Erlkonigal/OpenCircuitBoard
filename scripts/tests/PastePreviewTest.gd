extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.CircuitBoard as Node2D
	var camera := context.BoardCamera as Camera2D
	var data := context.TestData as Dictionary
	var source := Vector2i(-12, -10)
	var sourceOther := source + Vector2i(2, 0)
	assert(board.call("placeTile", source, "or"))
	assert(board.call("placeTile", sourceOther, "xor"))
	assert(board.call("setTileState", sourceOther, false))
	board.call("setSelection", Rect2i(source, Vector2i(3, 1)))
	context.sendCtrlShortcut(board, KEY_C)
	var pasteAnchor := Vector2i(-12, -7)
	data["pasteAnchor"] = pasteAnchor
	context.sendCtrlShortcut(board, KEY_V)
	board.call("updatePastePreview", pasteAnchor)
	assert(bool(board.get("PastePreviewValid")))
	assert(not bool(board.get("IsPastePreviewBuilding")))
	var previewTiles := board.get("PreviewTiles") as Node2D
	var previewTileIds: Array[int] = []
	var previewPositions: Array[Vector2] = []
	for previewTile in previewTiles.get_children():
		previewTileIds.append(previewTile.get_instance_id())
		previewPositions.append(previewTile.position)
	context.assertPastePreviewAllowsCameraPan(board, camera)
	board.call("updatePastePreview", pasteAnchor)
	for index in previewTiles.get_child_count():
		var previewTile := previewTiles.get_child(index) as Node2D
		assert(previewTile.get_instance_id() == previewTileIds[index])
		assert(previewTile.position.is_equal_approx(previewPositions[index]))
	var movedPasteAnchor := pasteAnchor + Vector2i(1, 0)
	board.call("updatePastePreview", movedPasteAnchor)
	for index in previewTiles.get_child_count():
		var previewTile := previewTiles.get_child(index) as Node2D
		assert(previewTile.get_instance_id() == previewTileIds[index])
		assert(previewTile.position.is_equal_approx(previewPositions[index] + Vector2.RIGHT * float(board.get("CellSize"))))
	board.call("updatePastePreview", pasteAnchor)
	var firstPreviewTile := previewTiles.get_child(0) as Node2D
	board.call("confirmPastePreview")
	var tileData: Dictionary = board.get("TileValues")
	assert(tileData.has(pasteAnchor))
	assert(tileData.has(pasteAnchor + Vector2i(2, 0)))
	assert(not bool(board.call("getTileState", pasteAnchor + Vector2i(2, 0))))
	var placedTiles := board.get_node("PlacedTiles") as Node2D
	assert(placedTiles != null)
	assert(placedTiles.y_sort_enabled)
	assert(firstPreviewTile.get_parent() == placedTiles)
	assert(firstPreviewTile.get_parent() != board.get("PreviewTiles"))
	var occupancy: Dictionary = board.get("Occupancy")
	for pastedCoordinates in [pasteAnchor, pasteAnchor + Vector2i(2, 0)]:
		var pastedTile := occupancy[pastedCoordinates] as Node2D
		assert(pastedTile.get_parent() == placedTiles)
	var pastedSelection: Dictionary = board.call("getSelectionItem")
	assert((pastedSelection.get("bounds", Rect2i()) as Rect2i).position == pasteAnchor)
	assert((pastedSelection.get("cells", []) as Array).size() == 2)
	var belowPaste := pasteAnchor + Vector2i(0, 1)
	var historyBeforeBelowPaste := (board.get("UndoStack") as Array).size()
	assert(board.call("handleLeftButtonPress", belowPaste, false))
	assert(not tileData.has(belowPaste))
	assert((board.call("getSelectionItem").get("cells", []) as Array).is_empty())
	assert(board.call("handleLeftButtonPress", belowPaste, false))
	assert(tileData.has(belowPaste))
	board.call("finishStroke")
	var pastedPrimary := occupancy[pasteAnchor] as Node2D
	var belowTile := occupancy[belowPaste] as Node2D
	assert(belowTile.get_parent() == placedTiles)
	assert(pastedPrimary.get_parent() == belowTile.get_parent())
	assert(pastedPrimary.z_index == belowTile.z_index)
	assert(pastedPrimary.position.y < belowTile.position.y)
	assert((board.get("UndoStack") as Array).size() == historyBeforeBelowPaste + 1)
	context.sendCtrlShortcut(board, KEY_Z)
	assert(not tileData.has(belowPaste))
	assert((board.get("UndoStack") as Array).size() == historyBeforeBelowPaste)
	board.call("setSelection", pastedSelection.get("bounds", Rect2i()) as Rect2i)
	assert(board.call("getSelectionItem") == pastedSelection)
	data["pastedSelection"] = pastedSelection
