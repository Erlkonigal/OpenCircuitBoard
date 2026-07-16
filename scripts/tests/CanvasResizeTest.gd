extends RefCounted

const CanvasResizeCornerNone := -1
const TopLeftCorner := 0
const TopRightCorner := 1
const BottomLeftCorner := 2
const BottomRightCorner := 3

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var camera := context.BoardCamera as Camera2D
	var overlay := board.get("CanvasResizeOverlay") as Node2D
	var initialBounds := board.call("getGridBounds") as Rect2i
	assert(overlay != null)
	assert(bool(overlay.get("IsEnabled")))
	assert(overlay.visible)
	assert(int(overlay.get("ActiveCorner")) == CanvasResizeCornerNone)
	assertGridState(board, camera, overlay, initialBounds)

	var testCases := [
		{"corner": TopLeftCorner, "targetBoundary": initialBounds.position + Vector2i(-3, -2)},
		{"corner": TopRightCorner, "targetBoundary": Vector2i(initialBounds.end.x + 3, initialBounds.position.y - 2)},
		{"corner": BottomLeftCorner, "targetBoundary": Vector2i(initialBounds.position.x - 3, initialBounds.end.y + 2)},
		{"corner": BottomRightCorner, "targetBoundary": initialBounds.end + Vector2i(3, 2)},
	]
	for testCaseVariant in testCases:
		var testCase := testCaseVariant as Dictionary
		var corner := int(testCase.get("corner", CanvasResizeCornerNone))
		var targetBoundary := testCase.get("targetBoundary", Vector2i.ZERO) as Vector2i
		var currentBounds := board.call("getGridBounds") as Rect2i
		if currentBounds != initialBounds:
			assert(board.call("setGridBounds", initialBounds))
		var startPoint := getCornerPosition(initialBounds, corner, float(board.get("CellSize")))
		assert(board.call("beginCanvasResizeAt", startPoint))
		assert(int(board.get("CanvasResizeActiveCorner")) == corner)
		assert(int(board.get("CurrentInteractionMode")) != 0)
		assert(int(overlay.get("ActiveCorner")) == corner)
		assert(int(overlay.get("HoveredCorner")) == corner)
		assert((overlay.get("Bounds") as Rect2).is_equal_approx(board.get("ValidRect") as Rect2))

		var targetPoint := Vector2(targetBoundary) * float(board.get("CellSize"))
		assert(board.call("updateCanvasResizeAt", targetPoint))
		var expectedBounds := getExpectedBounds(initialBounds, corner, targetBoundary)
		var resizedBounds := board.call("getGridBounds") as Rect2i
		assert(resizedBounds == expectedBounds)
		assert(getOppositeCorner(resizedBounds, corner) == getOppositeCorner(initialBounds, corner))
		assertGridState(board, camera, overlay, expectedBounds)
		assert(board.call("finishCanvasResize"))
		assert(int(board.get("CurrentInteractionMode")) == 0)
		assert(int(board.get("CanvasResizeActiveCorner")) == CanvasResizeCornerNone)
		assert(int(overlay.get("ActiveCorner")) == CanvasResizeCornerNone)

	if (board.call("getGridBounds") as Rect2i) != initialBounds:
		assert(board.call("setGridBounds", initialBounds))
	var protectedCoordinates := initialBounds.position
	assert(board.call("placeTile", protectedCoordinates, "or"))
	assert(board.call("beginCanvasResizeAt", getCornerPosition(initialBounds, TopLeftCorner, float(board.get("CellSize")))))
	var shrinkTarget := Vector2(initialBounds.position + Vector2i(4, 4)) * float(board.get("CellSize"))
	assert(not bool(board.call("updateCanvasResizeAt", shrinkTarget)))
	assert((board.call("getGridBounds") as Rect2i) == initialBounds)
	assert(board.call("finishCanvasResize"))
	assert(board.call("removeTile", protectedCoordinates))

	var latchCoordinates := Vector2i.ZERO
	var readCoordinates := Vector2i(1, 0)
	var traceCoordinates := Vector2i(2, 0)
	assert(board.call("placeTile", latchCoordinates, "latch"))
	assert(board.call("placeTile", readCoordinates, "read"))
	assert(board.call("placeTile", traceCoordinates, "trace"))
	main.call("enterSimulation")
	assert(bool(main.get("IsSimulating")))
	main.call("toggleLoopStepMode")
	assert(not bool(board.get("EditorInputEnabled")))
	assert(not bool(overlay.get("IsEnabled")))
	assert(not overlay.visible)
	var disabledResizeStart := getCornerPosition(initialBounds, TopLeftCorner, float(board.get("CellSize")))
	assert(not bool(board.call("beginCanvasResizeAt", disabledResizeStart)))
	assert(int(board.get("CurrentInteractionMode")) == 0)
	main.call("leaveSimulation")
	assert(bool(board.get("EditorInputEnabled")))
	assert(bool(overlay.get("IsEnabled")))
	assert(overlay.visible)
	assert(board.call("removeTile", latchCoordinates))
	assert(board.call("removeTile", readCoordinates))
	assert(board.call("removeTile", traceCoordinates))

func assertGridState(board: Node2D, camera: Camera2D, overlay: Node2D, expectedBounds: Rect2i) -> void:
	var cellSize := float(board.get("CellSize"))
	var expectedRect := Rect2(Vector2(expectedBounds.position) * cellSize, Vector2(expectedBounds.size) * cellSize)
	var validRect := board.get("ValidRect") as Rect2
	var canvasBoard := board.get("CanvasBoard") as ColorRect
	var simulationGrid := board.call("getSimulationGrid") as Dictionary
	assert(validRect.is_equal_approx(expectedRect))
	assert(int(board.get("GridWidthCount")) == expectedBounds.size.x)
	assert(int(board.get("GridHeightCount")) == expectedBounds.size.y)
	assert(canvasBoard.position.is_equal_approx(expectedRect.position))
	assert(canvasBoard.size.is_equal_approx(expectedRect.size))
	assert((camera.get("LimitRect") as Rect2).is_equal_approx(expectedRect))
	assert((overlay.get("Bounds") as Rect2).is_equal_approx(expectedRect))
	assert(int(simulationGrid.get("width", 0)) == expectedBounds.size.x)
	assert(int(simulationGrid.get("height", 0)) == expectedBounds.size.y)
	assert((simulationGrid.get("origin", Vector2i.ZERO) as Vector2i) == expectedBounds.position)

func getCornerPosition(bounds: Rect2i, corner: int, cellSize: float) -> Vector2:
	return Vector2(getCorner(bounds, corner)) * cellSize

func getOppositeCorner(bounds: Rect2i, corner: int) -> Vector2i:
	match corner:
		TopLeftCorner:
			return bounds.end
		TopRightCorner:
			return Vector2i(bounds.position.x, bounds.end.y)
		BottomLeftCorner:
			return Vector2i(bounds.end.x, bounds.position.y)
		BottomRightCorner:
			return bounds.position
		_:
			return Vector2i.ZERO

func getCorner(bounds: Rect2i, corner: int) -> Vector2i:
	match corner:
		TopLeftCorner:
			return bounds.position
		TopRightCorner:
			return Vector2i(bounds.end.x, bounds.position.y)
		BottomLeftCorner:
			return Vector2i(bounds.position.x, bounds.end.y)
		BottomRightCorner:
			return bounds.end
		_:
			return Vector2i.ZERO

func getExpectedBounds(bounds: Rect2i, corner: int, targetBoundary: Vector2i) -> Rect2i:
	var left := bounds.position.x
	var top := bounds.position.y
	var right := bounds.end.x
	var bottom := bounds.end.y
	match corner:
		TopLeftCorner:
			left = targetBoundary.x
			top = targetBoundary.y
		TopRightCorner:
			right = targetBoundary.x
			top = targetBoundary.y
		BottomLeftCorner:
			left = targetBoundary.x
			bottom = targetBoundary.y
		BottomRightCorner:
			right = targetBoundary.x
			bottom = targetBoundary.y
	return Rect2i(Vector2i(left, top), Vector2i(right - left, bottom - top))
