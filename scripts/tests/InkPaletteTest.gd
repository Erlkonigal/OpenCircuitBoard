extends RefCounted

const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var circuitEditorDock: Control = context.getDockForSide(main, "left")
	var inkButtons: Dictionary = circuitEditorDock.get("InkButtons")
	assert(inkButtons.size() == 17)
	assert(circuitEditorDock.find_children("VariantIndicator", "Control", true, false).size() == 5)
	var toolRegistry: Dictionary = board.get("ToolRegistry")
	assert(toolRegistry.size() == 27)
	for toolId in ["cross", "mesh", "bus", "busRed", "busGreen", "busYellow", "busCyan", "busMagenta", "read", "write", "trace", "traceRed", "traceGreen", "traceBlue", "traceCyan", "traceMagenta", "buffer", "and", "or", "xor", "not", "nand", "nor", "xnor", "latch", "clock", "led"]:
		assert(toolRegistry.has(toolId))
		var toolAttributes: Dictionary = toolRegistry[toolId]
		var toolIcon := toolAttributes.get("icon") as Texture2D
		assert(toolIcon != null)
		assert(toolIcon.get_size() == Vector2(64, 64))
		assert(InkRegistry.getInk(toolId).get("icon") == toolIcon)
		var expectedDefaultIsOn := true
		assert(bool(toolAttributes.get("defaultIsOn", true)) == expectedDefaultIsOn)
		assert(bool(InkRegistry.getInk(toolId).get("defaultIsOn", true)) == expectedDefaultIsOn)
	assert(InkRegistry.getPaletteInks().size() == 17)
	assert(InkRegistry.getComponentInks().size() == 27)
	assert(not toolRegistry.has("tunnel"))
	assert(not toolRegistry.has("latchOn"))
	assert(not toolRegistry.has("latchOff"))
	assert(InkRegistry.getInkIcon("latch", true) != InkRegistry.getInkIcon("latch", false))
	assert(InkRegistry.getInkIcon("latch", false).get_size() == Vector2(64, 64))
	assert(bool(InkRegistry.getInk("mesh").get("isConfigurable", false)))
	assert(bool(InkRegistry.getInk("latch").get("isConfigurable", false)))
	assert(InkRegistry.getInkVariants("trace").size() == 6)
	assert(InkRegistry.getInkVariants("bus").size() == 6)
	context.assertInkButton(inkButtons.get("or") as Button, InkRegistry.getInk("or"), true)
	context.assertInkButton(inkButtons.get("bus") as Button, InkRegistry.getInk("bus"), false)
	context.assertInkButton(inkButtons.get("trace") as Button, InkRegistry.getInk("trace"), false)
	context.assertInkButton(inkButtons.get("clock") as Button, InkRegistry.getInk("clock"), false)
	context.assertInkButton(inkButtons.get("read") as Button, InkRegistry.getInk("read"), false)
	context.assertInkButton(inkButtons.get("write") as Button, InkRegistry.getInk("write"), false)
