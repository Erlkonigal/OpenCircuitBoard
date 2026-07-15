extends RefCounted

const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("activateDock", "circuitEditor")
	await context.waitFrames()
	var dock := context.getDockForSide(context.MainSceneRoot, "left") as Control
	var inkButtons: Dictionary = dock.get("InkButtons")
	var busButton := inkButtons.get("bus") as Button
	dock.call("selectInk", InkRegistry.getInk("busMagenta"), false)
	await context.waitFrames()
	context.RootWindow.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames()
	context.RootWindow.push_input(context.makeMouseButtonEvent(busButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames()
	assert((context.MainSceneRoot.get("InkVariantMenu") as PopupPanel).visible)
	return {}
