extends RefCounted

const InkRegistry := preload("res://scripts/inkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.main as Control
	var board := context.board as Node2D
	var circuitEditorDock: Control = context.getDockForSide(main, "left")
	var inkButtons: Dictionary = circuitEditorDock.get("inkButtons")
	var busButton := inkButtons.get("bus") as Button
	var orButton := inkButtons.get("or") as Button
	var interactionModeBeforeMenu := int(board.get("interactionMode"))
	context.root.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames(1)
	var inkVariantMenu := main.get("inkVariantMenu") as PopupPanel
	var inkVariantMenuGrid := main.get("inkVariantMenuGrid") as GridContainer
	var busVariantButtons: Dictionary = main.get("inkVariantButtons")
	assert(inkVariantMenu.visible)
	assert(inkVariantMenuGrid.get_child_count() == 6)
	assert(busVariantButtons.size() == 6)
	assert(int(board.get("interactionMode")) == interactionModeBeforeMenu)
	context.root.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames(1)
	assert(int(board.get("interactionMode")) == interactionModeBeforeMenu)
	var busMagentaButton := busVariantButtons.get("busMagenta") as Button
	context.assertInkButton(busMagentaButton, InkRegistry.getInk("busMagenta"), false)
	busMagentaButton.emit_signal("pressed")
	await context.waitFrames(1)
	assert(String(board.get("selectedTool")) == "busMagenta")
	assert(String(circuitEditorDock.call("getSelectedInkId")) == "busMagenta")
	assert(not inkVariantMenu.visible)
	context.assertInkButton(busButton, InkRegistry.getInk("busMagenta"), true)
	circuitEditorDock.call("selectInk", InkRegistry.getInk("or"), false)
	assert(String(board.get("selectedTool")) == "or")
	context.assertInkButton(orButton, InkRegistry.getInk("or"), true)
	context.assertInkButton(busButton, InkRegistry.getInk("busMagenta"), false)
	busButton.emit_signal("pressed")
	await context.waitFrames(1)
	assert(String(board.get("selectedTool")) == "busMagenta")
	assert(String(circuitEditorDock.call("getSelectedInkId")) == "busMagenta")
	circuitEditorDock.call("selectInk", InkRegistry.getInk("or"), false)
	context.root.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames(1)
	assert(inkVariantMenu.visible)
	var rememberedButtons: Dictionary = main.get("inkVariantButtons")
	context.assertInkButton(rememberedButtons.get("busMagenta") as Button, InkRegistry.getInk("busMagenta"), true)
	context.root.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, false))
	main.call("hideInkVariantMenu")
	await context.waitFrames(1)
