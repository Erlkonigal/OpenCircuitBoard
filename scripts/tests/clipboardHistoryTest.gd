extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.board as Node2D
	var data := context.data as Dictionary
	assert(board.call("placeTile", Vector2i(1, 0), "or"))
	assert(board.call("placeTile", Vector2i(0, 0), "xor"))
	assert(board.call("placeTile", Vector2i(-3, 1), "busMagenta"))
	assert(board.call("placeTile", Vector2i(-1, 1), "traceBlue"))
	assert(board.call("placeTile", Vector2i(-2, 1), "traceRed"))
	assert(board.call("placeTile", Vector2i(4, -2), "or"))
	var historySelections: Array[Rect2i] = [
		Rect2i(Vector2i(1, 0), Vector2i(1, 1)),
		Rect2i(Vector2i(0, 0), Vector2i(2, 1)),
		Rect2i(Vector2i(-2, 1), Vector2i(2, 1)),
		Rect2i(Vector2i(4, -2), Vector2i(1, 1)),
	]
	for bounds in historySelections:
		board.call("setSelection", bounds)
		context.sendCtrlShortcut(board, KEY_C)
	var clipboardHistory: Array = board.call("getClipboardHistory")
	assert(clipboardHistory.size() == 4)
	assert(int(board.call("getSelectedClipboardIndex")) == 0)
	for item in clipboardHistory:
		assert((item.get("boundsSize", Vector2i.ZERO) as Vector2i) != Vector2i(3, 1))
	assert((clipboardHistory[0].get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(1, 1))
	assert((clipboardHistory[1].get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(2, 1))
	assert((clipboardHistory[2].get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(2, 1))
	assert((clipboardHistory[3].get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(1, 1))
	assert((clipboardHistory[0].get("tiles", []) as Array).size() == 1)
	assert((clipboardHistory[1].get("tiles", []) as Array).size() == 2)
	assert((clipboardHistory[2].get("tiles", []) as Array).size() == 2)
	assert((clipboardHistory[3].get("tiles", []) as Array).size() == 1)
	assert(String((clipboardHistory[0].get("tiles", []) as Array)[0].get("toolId", "")) == "or")
	assert(String((clipboardHistory[1].get("tiles", []) as Array)[0].get("toolId", "")) == "traceRed")
	assert(String((clipboardHistory[1].get("tiles", []) as Array)[1].get("toolId", "")) == "traceBlue")
	assert(String((clipboardHistory[2].get("tiles", []) as Array)[0].get("toolId", "")) == "xor")
	assert(String((clipboardHistory[3].get("tiles", []) as Array)[0].get("toolId", "")) == "or")
	data["clipboardHistory"] = clipboardHistory
	data["selectedClipboardIndex"] = int(board.call("getSelectedClipboardIndex"))
