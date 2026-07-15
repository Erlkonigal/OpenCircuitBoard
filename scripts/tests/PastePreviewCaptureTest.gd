extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualBoardWithClipboard(context.CircuitBoard)
	context.CircuitBoard.call("beginPastePreview")
	context.CircuitBoard.call("updatePastePreview", Vector2i(5, 2))
	assert(bool(context.CircuitBoard.get("PastePreviewValid")))
	var selectedClipboard: Dictionary = context.CircuitBoard.call("getClipboardItem")
	assert((context.CircuitBoard.get_node("PreviewTiles") as Node2D).get_child_count() == (selectedClipboard.get("tiles", []) as Array).size())
	context.CircuitBoard.set_process(false)
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
