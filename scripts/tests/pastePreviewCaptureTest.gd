extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualBoardWithClipboard(context.board)
	context.board.call("beginPastePreview")
	context.board.call("updatePastePreview", Vector2i(5, 2))
	assert(bool(context.board.get("pastePreviewValid")))
	var selectedClipboard: Dictionary = context.board.call("getClipboardItem")
	assert((context.board.get_node("PreviewTiles") as Node2D).get_child_count() == (selectedClipboard.get("tiles", []) as Array).size())
	context.board.set_process(false)
	context.camera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
