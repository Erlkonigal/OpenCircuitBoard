extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var dock := context.getDockForSide(main, "left") as Control
	await testMeshSettings(context, main, board)
	await testClockSettings(context, main, board)
	await testLatchSettings(context, main, board)
	await testVariantSettings(context, main, board)
	testCursorInfo(board, dock)
	testIneligibleSelectionFallsBackToDelete(board)

func testMeshSettings(context, main: Control, board: Node2D) -> void:
	var first := Vector2i(-14, -12)
	var second := Vector2i(-13, -12)
	assert(board.call("placeTile", first, "mesh"))
	assert(board.call("placeTile", second, "mesh"))
	assert(board.call("setTileMeshId", second, 7))
	board.call("setSelection", Rect2i(first, Vector2i(2, 1)))
	var historyBefore := (board.get("UndoStack") as Array).size()
	assert(board.call("handleRightButtonPress", first, true))
	await context.waitFrames(1)
	var menu := main.get("MeshSettingsMenu") as PopupPanel
	var control := main.get("MeshIdControl") as SpinBox
	assert(menu.visible)
	assert(is_equal_approx(control.value, 1.0))
	control.value = 11.0
	await context.waitFrames(1)
	assert(int(board.call("getTileMeshId", first)) == 11)
	assert(int(board.call("getTileMeshId", second)) == 11)
	assert((board.get("UndoStack") as Array).size() == historyBefore + 1)
	context.sendCtrlShortcut(board, KEY_Z)
	assert(int(board.call("getTileMeshId", first)) == 1)
	assert(int(board.call("getTileMeshId", second)) == 7)
	context.sendCtrlShortcut(board, KEY_U)
	assert(int(board.call("getTileMeshId", first)) == 11)
	assert(int(board.call("getTileMeshId", second)) == 11)
	board.call("clearSelection")
	main.call("hideMeshSettingsMenu")

func testClockSettings(context, main: Control, board: Node2D) -> void:
	var first := Vector2i(-11, -12)
	var second := Vector2i(-10, -12)
	assert(board.call("placeTile", first, "clock"))
	assert(board.call("placeTile", second, "clock"))
	assert(board.call("setTileClockHoldTicks", second, 5))
	board.call("setSelection", Rect2i(first, Vector2i(2, 1)))
	assert(board.call("handleRightButtonPress", first, true))
	await context.waitFrames(1)
	var menu := main.get("ClockSettingsMenu") as PopupPanel
	var control := main.get("ClockHoldTicksControl") as SpinBox
	assert(menu.visible)
	assert(is_equal_approx(control.value, 1.0))
	control.value = 9.0
	await context.waitFrames(1)
	assert(int(board.call("getTileClockHoldTicks", first)) == 9)
	assert(int(board.call("getTileClockHoldTicks", second)) == 9)
	board.call("clearSelection")
	main.call("hideClockSettingsMenu")

func testLatchSettings(context, main: Control, board: Node2D) -> void:
	var first := Vector2i(-8, -12)
	var second := Vector2i(-7, -12)
	assert(board.call("placeTile", first, "latch"))
	assert(board.call("placeTile", second, "latch"))
	assert(board.call("setTileLatchInitialState", second, false))
	board.call("setSelection", Rect2i(first, Vector2i(2, 1)))
	assert(board.call("handleRightButtonPress", first, true))
	await context.waitFrames(1)
	var menu := main.get("LatchSettingsMenu") as PopupPanel
	var offButton := main.get("LatchDisabledStateButton") as Button
	assert(menu.visible)
	offButton.emit_signal("pressed")
	assert(not bool(board.call("getTileState", first)))
	assert(not bool(board.call("getTileState", second)))
	board.call("clearSelection")
	main.call("hideLatchSettingsMenu")

func testVariantSettings(context, main: Control, board: Node2D) -> void:
	var first := Vector2i(-5, -12)
	var second := Vector2i(-3, -12)
	assert(board.call("placeTile", first, "busRed"))
	assert(board.call("placeTile", second, "busGreen"))
	board.call("setSelection", Rect2i(first, Vector2i(3, 1)))
	var selectedToolBefore := String(board.get("SelectedTool"))
	assert(board.call("handleRightButtonPress", first + Vector2i.RIGHT, true))
	await context.waitFrames(1)
	var menu := main.get("InkVariantMenu") as PopupPanel
	var buttons: Dictionary = main.get("InkVariantButtons")
	assert(menu.visible)
	(buttons.get("busMagenta") as Button).emit_signal("pressed")
	assert(String(board.call("getToolIdAt", first)) == "busMagenta")
	assert(String(board.call("getToolIdAt", second)) == "busMagenta")
	assert(String(board.get("SelectedTool")) == selectedToolBefore)
	board.call("clearSelection")
	var traceFirst := Vector2i(1, -12)
	var traceSecond := Vector2i(2, -12)
	assert(board.call("placeTile", traceFirst, "traceRed"))
	assert(board.call("placeTile", traceSecond, "traceBlue"))
	board.call("setSelection", Rect2i(traceFirst, Vector2i(2, 1)))
	assert(board.call("handleRightButtonPress", traceFirst, true))
	await context.waitFrames(1)
	buttons = main.get("InkVariantButtons")
	(buttons.get("traceCyan") as Button).emit_signal("pressed")
	assert(String(board.call("getToolIdAt", traceFirst)) == "traceCyan")
	assert(String(board.call("getToolIdAt", traceSecond)) == "traceCyan")
	board.call("clearSelection")

func testCursorInfo(board: Node2D, dock: Control) -> void:
	assert(String((board.call("getCursorInfoAt", Vector2i(-14, -12)) as Dictionary).get("propertyText", "")) == "Mesh ID 11")
	var busInfo := board.call("getCursorInfoAt", Vector2i(-5, -12)) as Dictionary
	assert(String(busInfo.get("propertyText", "")) == "Color #C66AF6", str(busInfo))
	assert(String((board.call("getCursorInfoAt", Vector2i(-8, -12)) as Dictionary).get("propertyText", "")) == "State Off")
	assert(String((board.call("getCursorInfoAt", Vector2i(-11, -12)) as Dictionary).get("propertyText", "")) == "Hold 9 ticks")
	dock.call("updateCursorInfo", Vector2i(-14, -12), true, "Mesh #11", "Mesh ID 11")
	assert((dock.get("HoveredPropertyLabel") as Label).text == "Mesh ID 11")

func testIneligibleSelectionFallsBackToDelete(board: Node2D) -> void:
	var first := Vector2i(-2, -12)
	var second := Vector2i(-1, -12)
	assert(board.call("placeTile", first, "or"))
	assert(board.call("placeTile", second, "latch"))
	board.call("setSelection", Rect2i(first, Vector2i(2, 1)))
	assert(board.call("handleRightButtonPress", first, true))
	assert(not (board.get("TileValues") as Dictionary).has(first))
	assert(not (board.get("TileValues") as Dictionary).has(second))
