extends RefCounted

const InkRegistry := preload("res://scripts/inkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.main as Control
	var board := context.board as Node2D
	var circuitEditorDock: Control = context.getDockForSide(main, "left")
	var inkButtons: Dictionary = circuitEditorDock.get("inkButtons")
	assert(inkButtons.size() == 19)
	assert(circuitEditorDock.find_children("variantIndicator", "Control", true, false).size() == 2)
	var toolRegistry: Dictionary = board.get("toolRegistry")
	assert(toolRegistry.size() == 29)
	for toolId in ["cross", "tunnel", "mesh", "bus", "busRed", "busGreen", "busYellow", "busCyan", "busMagenta", "read", "write", "trace", "traceRed", "traceGreen", "traceBlue", "traceCyan", "traceMagenta", "buffer", "and", "or", "xor", "not", "nand", "nor", "xnor", "latchOn", "latchOff", "clock", "led"]:
		assert(toolRegistry.has(toolId))
		var toolAttributes: Dictionary = toolRegistry[toolId]
		var toolIcon := toolAttributes.get("icon") as Texture2D
		assert(toolIcon != null)
		assert(toolIcon.get_size() == Vector2(64, 64))
		assert(InkRegistry.getInk(toolId).get("icon") == toolIcon)
		var expectedDefaultIsOn: bool = String(toolId) != "latchOff"
		assert(bool(toolAttributes.get("defaultIsOn", true)) == expectedDefaultIsOn)
		assert(bool(InkRegistry.getInk(toolId).get("defaultIsOn", true)) == expectedDefaultIsOn)
	assert(InkRegistry.getPaletteInks().size() == 19)
	assert(InkRegistry.getComponentInks().size() == 29)
	var latchOnColor: Color = InkRegistry.getInk("latchOn").get("color", Color.WHITE)
	var latchOffColor: Color = InkRegistry.getInk("latchOff").get("color", Color.WHITE)
	assert(latchOnColor.is_equal_approx(latchOffColor))
	assert(InkRegistry.getInkVariants("trace").size() == 6)
	assert(InkRegistry.getInkVariants("bus").size() == 6)
	context.assertInkButton(inkButtons.get("or") as Button, InkRegistry.getInk("or"), true)
	context.assertInkButton(inkButtons.get("bus") as Button, InkRegistry.getInk("bus"), false)
	context.assertInkButton(inkButtons.get("trace") as Button, InkRegistry.getInk("trace"), false)
	context.assertInkButton(inkButtons.get("read") as Button, InkRegistry.getInk("read"), false)
	context.assertInkButton(inkButtons.get("write") as Button, InkRegistry.getInk("write"), false)
