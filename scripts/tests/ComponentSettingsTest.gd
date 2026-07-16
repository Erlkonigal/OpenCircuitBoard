extends RefCounted

const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var circuitEditorDock: Control = context.getDockForSide(main, "left")
	var inkButtons: Dictionary = circuitEditorDock.get("InkButtons")
	var latchButton := inkButtons.get("latch") as Button
	var meshButton := inkButtons.get("mesh") as Button
	assert(latchButton != null)
	assert(meshButton != null)

	context.RootWindow.push_input(context.makeMouseButtonEvent(latchButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames(1)
	context.RootWindow.push_input(context.makeMouseButtonEvent(latchButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames(1)
	var latchSettingsMenu := main.get("LatchSettingsMenu") as PopupPanel
	var latchEnabledStateButton := main.get("LatchEnabledStateButton") as Button
	var latchDisabledStateButton := main.get("LatchDisabledStateButton") as Button
	assert(latchSettingsMenu.visible)
	assert(latchEnabledStateButton.button_pressed)
	assert(not latchDisabledStateButton.button_pressed)
	latchDisabledStateButton.emit_signal("pressed")
	assert(not bool(board.call("getLatchInitialState")))
	assert(not latchEnabledStateButton.button_pressed)
	assert(latchDisabledStateButton.button_pressed)
	circuitEditorDock.call("selectInk", InkRegistry.getInk("latch"), false)
	var latchCoordinates := Vector2i(-12, -12)
	assert(board.call("placeTile", latchCoordinates))
	assert(not bool(board.call("getTileState", latchCoordinates)))
	board.call("setSelection", Rect2i(latchCoordinates, Vector2i.ONE))
	latchEnabledStateButton.emit_signal("pressed")
	assert(bool(board.call("getTileState", latchCoordinates)))
	board.call("clearSelection")
	assert(not bool(board.call("getLatchInitialState")))
	main.call("hideLatchSettingsMenu")
	await context.waitFrames(1)

	context.RootWindow.push_input(context.makeMouseButtonEvent(meshButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames(1)
	context.RootWindow.push_input(context.makeMouseButtonEvent(meshButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames(1)
	var meshSettingsMenu := main.get("MeshSettingsMenu") as PopupPanel
	var meshIdControl := main.get("MeshIdControl") as SpinBox
	assert(meshSettingsMenu.visible)
	assert(is_equal_approx(meshIdControl.min_value, 1.0))
	meshIdControl.value = 7.0
	await context.waitFrames(1)
	assert(int(board.call("getMeshId")) == 7)
	circuitEditorDock.call("selectInk", InkRegistry.getInk("mesh"), false)
	var meshCoordinates := Vector2i(-10, -12)
	assert(board.call("placeTile", meshCoordinates))
	assert(int(board.call("getTileMeshId", meshCoordinates)) == 7)
	board.call("setSelection", Rect2i(meshCoordinates, Vector2i.ONE))
	meshIdControl.value = 11.0
	await context.waitFrames(1)
	assert(int(board.call("getTileMeshId", meshCoordinates)) == 11)
	assert(String((board.call("getCursorInfoAt", meshCoordinates) as Dictionary).get("hoveredInkTitle", "")) == "Mesh #11")
	board.call("clearSelection")
	assert(int(board.call("getMeshId")) == 7)
	assert(board.call("removeTile", latchCoordinates))
	assert(board.call("removeTile", meshCoordinates))
