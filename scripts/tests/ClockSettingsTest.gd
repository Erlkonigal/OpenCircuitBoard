extends RefCounted

const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var circuitEditorDock: Control = context.getDockForSide(main, "left")
	var clockButton := (circuitEditorDock.get("InkButtons") as Dictionary).get("clock") as Button
	var selectedToolBefore := String(board.get("SelectedTool"))
	var interactionModeBefore := int(board.get("CurrentInteractionMode"))
	context.RootWindow.push_input(context.makeMouseButtonEvent(clockButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames(1)
	context.RootWindow.push_input(context.makeMouseButtonEvent(clockButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames(1)
	var clockSettingsMenu := main.get("ClockSettingsMenu") as PopupPanel
	var clockHoldTicksControl := main.get("ClockHoldTicksControl") as SpinBox
	assert(clockSettingsMenu.visible)
	assert(clockSettingsMenu.position.x >= 0)
	assert(clockSettingsMenu.position.y >= 0)
	assert(clockSettingsMenu.position.x + clockSettingsMenu.size.x <= context.RootWindow.size.x)
	assert(clockSettingsMenu.position.y + clockSettingsMenu.size.y <= context.RootWindow.size.y)
	assert(is_equal_approx(clockHoldTicksControl.min_value, 1.0))
	assert(is_equal_approx(clockHoldTicksControl.max_value, 2147483647.0))
	assert(is_equal_approx(clockHoldTicksControl.value, 1.0))
	assert(String(board.get("SelectedTool")) == selectedToolBefore)
	assert(int(board.get("CurrentInteractionMode")) == interactionModeBefore)

	clockHoldTicksControl.value = 3.0
	await context.waitFrames(1)
	assert(is_equal_approx(clockHoldTicksControl.value, 3.0))
	assert(int(board.call("getClockHoldTicks")) == 3)

	clockHoldTicksControl.value = 1.0
	await context.waitFrames(1)
	assert(is_equal_approx(clockHoldTicksControl.value, 1.0))
	assert(int(board.call("getClockHoldTicks")) == 1)

	main.call("setClockHoldTicks", 1000000)
	assert(int(board.call("getClockHoldTicks")) == 1000000)
	assert(is_equal_approx(clockHoldTicksControl.value, 1000000.0))
	main.call("setClockHoldTicks", 3)
	assert(is_equal_approx(clockHoldTicksControl.value, 3.0))
	circuitEditorDock.call("selectInk", InkRegistry.getInk("clock"), false)
	var clockCoordinates := Vector2i(-10, -8)
	assert(board.call("placeTile", clockCoordinates))
	assert(int(board.call("getTileClockHoldTicks", clockCoordinates)) == 3)
	var simulationTiles: Array = board.call("getSimulationTiles")
	assert(getClockHoldTicksFromSimulationTiles(simulationTiles, clockCoordinates) == 3)

	board.call("setSelection", Rect2i(clockCoordinates, Vector2i.ONE))
	clockHoldTicksControl.value = 7.0
	await context.waitFrames(1)
	assert(int(board.call("getClockHoldTicks")) == 7)
	assert(int(board.call("getTileClockHoldTicks", clockCoordinates)) == 7)
	board.call("clearSelection")
	assert(int(board.call("getClockHoldTicks")) == 3)
	board.call("setSelection", Rect2i(clockCoordinates, Vector2i.ONE))
	context.sendCtrlShortcut(board, KEY_C)
	var clipboardItem: Dictionary = board.call("getClipboardItem")
	var clipboardTiles: Array = clipboardItem.get("tiles", [])
	assert(clipboardTiles.size() == 1)
	assert(int((clipboardTiles[0] as Dictionary).get("clockHoldTicks", 0)) == 7)
	var pastedCoordinates := Vector2i(-8, -8)
	var pastedTiles: Dictionary = board.call("getPasteTileMap", pastedCoordinates, clipboardItem)
	assert(int((pastedTiles[pastedCoordinates] as Dictionary).get("clockHoldTicks", 0)) == 7)

	assert(board.call("importProjectData", {
		"selectedTool": "clock",
		"tiles": [{"x": 2, "y": 2, "toolId": "clock", "isOn": true}],
	}))
	assert(int(board.call("getClockHoldTicks")) == 1)
	assert(int(board.call("getTileClockHoldTicks", Vector2i(2, 2))) == 1)

func getClockHoldTicksFromSimulationTiles(simulationTiles: Array, clockCoordinates: Vector2i) -> int:
	for simulationTileVariant in simulationTiles:
		var simulationTile := simulationTileVariant as Dictionary
		if simulationTile.get("coordinates", Vector2i.ZERO) == clockCoordinates:
			return int(simulationTile.get("clockHoldTicks", 0))
	return 0
