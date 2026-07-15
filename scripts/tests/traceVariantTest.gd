extends RefCounted

const InkRegistry := preload("res://scripts/inkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.main as Control
	var board := context.board as Node2D
	var circuitEditorDock: Control = context.getDockForSide(main, "left")
	var inkButtons: Dictionary = circuitEditorDock.get("inkButtons")
	var traceButton := inkButtons.get("trace") as Button
	var orButton := inkButtons.get("or") as Button
	var interactionModeBeforeMenu := int(board.get("interactionMode"))
	context.root.push_input(context.makeMouseButtonEvent(traceButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames(1)
	var inkVariantMenu := main.get("inkVariantMenu") as PopupPanel
	var inkVariantMenuGrid := main.get("inkVariantMenuGrid") as GridContainer
	var inkVariantButtons: Dictionary = main.get("inkVariantButtons")
	assert(inkVariantMenu.visible)
	assert(inkVariantMenuGrid.get_child_count() == 6)
	assert(inkVariantButtons.size() == 6)
	assert(inkVariantMenu.position.x >= 0)
	assert(inkVariantMenu.position.y >= 0)
	assert(inkVariantMenu.position.x + inkVariantMenu.size.x <= context.root.size.x)
	assert(inkVariantMenu.position.y + inkVariantMenu.size.y <= context.root.size.y)
	assert(int(board.get("interactionMode")) == interactionModeBeforeMenu)
	context.root.push_input(context.makeMouseButtonEvent(traceButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames(1)
	assert(int(board.get("interactionMode")) == interactionModeBeforeMenu)
	var traceBlueButton := inkVariantButtons.get("traceBlue") as Button
	context.assertInkButton(traceBlueButton, InkRegistry.getInk("traceBlue"), false)
	traceBlueButton.emit_signal("pressed")
	await context.waitFrames(1)
	assert(String(board.get("selectedTool")) == "traceBlue")
	assert(String(circuitEditorDock.call("getSelectedInkId")) == "traceBlue")
	assert(not inkVariantMenu.visible)
	context.assertInkButton(traceButton, InkRegistry.getInk("traceBlue"), true)
	circuitEditorDock.call("selectInk", InkRegistry.getInk("or"), false)
	assert(String(board.get("selectedTool")) == "or")
	context.assertInkButton(orButton, InkRegistry.getInk("or"), true)
	context.assertInkButton(traceButton, InkRegistry.getInk("traceBlue"), false)
	traceButton.emit_signal("pressed")
	await context.waitFrames(1)
	assert(String(board.get("selectedTool")) == "traceBlue")
	assert(String(circuitEditorDock.call("getSelectedInkId")) == "traceBlue")
	circuitEditorDock.call("selectInk", InkRegistry.getInk("or"), false)
	context.root.push_input(context.makeMouseButtonEvent(traceButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames(1)
	assert(inkVariantMenu.visible)
	var rememberedButtons: Dictionary = main.get("inkVariantButtons")
	context.assertInkButton(rememberedButtons.get("traceBlue") as Button, InkRegistry.getInk("traceBlue"), true)
	context.root.push_input(context.makeMouseButtonEvent(traceButton, MOUSE_BUTTON_RIGHT, false))
	main.call("hideInkVariantMenu")
	await context.waitFrames(1)
