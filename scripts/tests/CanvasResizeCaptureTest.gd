extends RefCounted

const TopLeftCorner := 0

func run(context) -> Dictionary:
	await context.resetMain()
	var board := context.CircuitBoard as Node2D
	var initialBounds := board.call("getGridBounds") as Rect2i
	var cellSize := float(board.get("CellSize"))
	var topLeft := Vector2(initialBounds.position) * cellSize
	assert(board.call("beginCanvasResizeAt", topLeft))
	assert(board.call("updateCanvasResizeAt", topLeft - Vector2(cellSize * 2.0, cellSize)))
	var overlay := board.get("CanvasResizeOverlay") as Node2D
	var boardBounds := board.get("ValidRect") as Rect2
	assert(overlay != null)
	assert(overlay.visible)
	assert(int(overlay.get("ActiveCorner")) == TopLeftCorner)
	assert((overlay.get("Bounds") as Rect2).is_equal_approx(boardBounds))
	context.BoardCamera.global_position = boardBounds.position
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	await context.waitFrames(5)
	assert(context.BoardCamera.global_position.is_equal_approx(boardBounds.position))
	return {}
