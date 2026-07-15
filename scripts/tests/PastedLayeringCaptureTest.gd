extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.setupVisualBoardWithClipboard(context.CircuitBoard)
	var capturePasteAnchor := Vector2i(5, 2)
	context.CircuitBoard.call("beginPastePreview")
	context.CircuitBoard.call("updatePastePreview", capturePasteAnchor)
	assert(bool(context.CircuitBoard.get("PastePreviewValid")))
	context.CircuitBoard.call("confirmPastePreview")
	var captureBelowPaste := capturePasteAnchor + Vector2i(0, 1)
	assert(context.CircuitBoard.call("handleLeftButtonPress", captureBelowPaste, false))
	assert((context.CircuitBoard.call("getSelectionItem").get("cells", []) as Array).is_empty())
	assert(context.CircuitBoard.call("handleLeftButtonPress", captureBelowPaste, false))
	assert((context.CircuitBoard.get("TileValues") as Dictionary).has(captureBelowPaste))
	context.CircuitBoard.call("finishStroke")
	context.CircuitBoard.set_process(false)
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}
