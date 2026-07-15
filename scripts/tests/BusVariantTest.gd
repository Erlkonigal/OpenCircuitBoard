extends RefCounted

const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var circuitEditorDock: Control = context.getDockForSide(main, "left")
	var inkButtons: Dictionary = circuitEditorDock.get("InkButtons")
	var busButton := inkButtons.get("bus") as Button
	var orButton := inkButtons.get("or") as Button
	var interactionModeBeforeMenu := int(board.get("CurrentInteractionMode"))
	context.RootWindow.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames(1)
	var inkVariantMenu := main.get("InkVariantMenu") as PopupPanel
	var inkVariantMenuGrid := main.get("InkVariantMenuGrid") as GridContainer
	var busVariantButtons: Dictionary = main.get("InkVariantButtons")
	assert(inkVariantMenu.visible)
	assert(inkVariantMenuGrid.get_child_count() == 6)
	assert(busVariantButtons.size() == 6)
	assert(int(board.get("CurrentInteractionMode")) == interactionModeBeforeMenu)
	context.RootWindow.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames(1)
	assert(int(board.get("CurrentInteractionMode")) == interactionModeBeforeMenu)
	var busMagentaButton := busVariantButtons.get("busMagenta") as Button
	context.assertInkButton(busMagentaButton, InkRegistry.getInk("busMagenta"), false)
	busMagentaButton.emit_signal("pressed")
	await context.waitFrames(1)
	assert(String(board.get("SelectedTool")) == "busMagenta")
	assert(String(circuitEditorDock.call("getSelectedInkId")) == "busMagenta")
	assert(not inkVariantMenu.visible)
	context.assertInkButton(busButton, InkRegistry.getInk("busMagenta"), true)
	circuitEditorDock.call("selectInk", InkRegistry.getInk("or"), false)
	assert(String(board.get("SelectedTool")) == "or")
	context.assertInkButton(orButton, InkRegistry.getInk("or"), true)
	context.assertInkButton(busButton, InkRegistry.getInk("busMagenta"), false)
	busButton.emit_signal("pressed")
	await context.waitFrames(1)
	assert(String(board.get("SelectedTool")) == "busMagenta")
	assert(String(circuitEditorDock.call("getSelectedInkId")) == "busMagenta")
	circuitEditorDock.call("selectInk", InkRegistry.getInk("or"), false)
	context.RootWindow.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames(1)
	assert(inkVariantMenu.visible)
	var rememberedButtons: Dictionary = main.get("InkVariantButtons")
	context.assertInkButton(rememberedButtons.get("busMagenta") as Button, InkRegistry.getInk("busMagenta"), true)
	context.RootWindow.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, false))
	main.call("hideInkVariantMenu")
	await context.waitFrames(1)
