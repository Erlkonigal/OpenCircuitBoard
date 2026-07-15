extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.main as Control
	var board := context.board as Node2D
	var data := context.data as Dictionary
	main.call("activateDock", "clipboard", "right")
	await context.waitFrames(1)
	var source := Vector2i(-12, -10)
	var sourceOther := source + Vector2i(2, 0)
	data["source"] = source
	data["sourceOther"] = sourceOther
	assert(board.call("placeTile", source, "or"))
	assert(board.call("placeTile", sourceOther, "xor"))
	assert(board.call("setTileState", sourceOther, false))
	assert(not bool(board.call("getTileState", sourceOther)))
	board.call("setSelection", Rect2i(source, Vector2i(3, 1)))
	var historyBeforeCut := (board.get("undoStack") as Array).size()
	var clipboardDockStateBeforeCut: Dictionary = context.getActiveDockState(main, "clipboard")
	var clipboardDockBeforeCut := clipboardDockStateBeforeCut.get("dock") as Control
	var clipboardSideBeforeCut := String(clipboardDockStateBeforeCut.get("dockSide", ""))
	assert(clipboardDockBeforeCut != null)
	assert(not clipboardSideBeforeCut.is_empty())
	context.sendCtrlShortcut(board, KEY_X)
	await context.waitFrames(1)
	var clipboard: Dictionary = board.call("getClipboardItem")
	var clipboardHistoryAfterCut: Array = board.call("getClipboardHistory")
	assert((clipboard.get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(3, 1))
	assert((clipboard.get("tiles", []) as Array).size() == 2)
	assert(not bool(((clipboard.get("tiles", []) as Array)[1] as Dictionary).get("isOn", true)))
	assert(clipboardHistoryAfterCut.size() == 1)
	assert(int(board.call("getSelectedClipboardIndex")) == 0)
	var tileData: Dictionary = board.get("tileData")
	assert(not tileData.has(source))
	assert(not tileData.has(sourceOther))
	assert((board.get("undoStack") as Array).size() == historyBeforeCut + 1)
	var clipboardDockState: Dictionary = context.getActiveDockState(main, "clipboard")
	assert(not clipboardDockState.is_empty())
	var clipboardDock := clipboardDockState.get("dock") as Control
	assert(clipboardDock != null)
	assert(clipboardDock == clipboardDockBeforeCut)
	assert(String(clipboardDockState.get("dockSide", "")) == clipboardSideBeforeCut)
	context.sendCtrlShortcut(board, KEY_Z)
	assert(tileData.has(source))
	assert(tileData.has(sourceOther))
	assert(not bool(board.call("getTileState", sourceOther)))
	assert((board.get("undoStack") as Array).size() == historyBeforeCut)
	assert(board.call("getClipboardItem") == clipboard)
	assert(board.call("getClipboardHistory") == clipboardHistoryAfterCut)
	context.sendCtrlShortcut(board, KEY_U)
	assert(not tileData.has(source))
	assert(not tileData.has(sourceOther))
	assert((board.get("undoStack") as Array).size() == historyBeforeCut + 1)
	assert(board.call("getClipboardItem") == clipboard)
	assert(board.call("getClipboardHistory") == clipboardHistoryAfterCut)
	context.sendCtrlShortcut(board, KEY_Z)
	assert(tileData.has(source))
	assert(tileData.has(sourceOther))
	assert((board.get("undoStack") as Array).size() == historyBeforeCut)
	data["clipboard"] = clipboard
	data["clipboardHistory"] = clipboardHistoryAfterCut
