extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualBoardWithClipboard(context.board)
	var capturePasteAnchor := Vector2i(5, 2)
	context.board.call("beginPastePreview")
	context.board.call("updatePastePreview", capturePasteAnchor)
	assert(bool(context.board.get("pastePreviewValid")))
	context.board.call("confirmPastePreview")
	var captureBelowPaste := capturePasteAnchor + Vector2i(0, 1)
	assert(context.board.call("handleLeftButtonPress", captureBelowPaste, false))
	assert((context.board.call("getSelectionItem").get("cells", []) as Array).is_empty())
	assert(context.board.call("handleLeftButtonPress", captureBelowPaste, false))
	assert((context.board.get("tileData") as Dictionary).has(captureBelowPaste))
	context.board.call("finishStroke")
	context.board.set_process(false)
	context.camera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
