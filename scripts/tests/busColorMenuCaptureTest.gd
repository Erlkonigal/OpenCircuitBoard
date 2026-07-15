extends RefCounted

const InkRegistry := preload("res://scripts/inkRegistry.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	context.main.call("activateDock", "circuitEditor")
	await context.waitFrames()
	var dock := context.getDockForSide(context.main, "left") as Control
	var inkButtons: Dictionary = dock.get("inkButtons")
	var busButton := inkButtons.get("bus") as Button
	dock.call("selectInk", InkRegistry.getInk("busMagenta"), false)
	await context.waitFrames()
	context.root.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames()
	context.root.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames()
	assert((context.main.get("inkVariantMenu") as PopupPanel).visible)
	return {}
