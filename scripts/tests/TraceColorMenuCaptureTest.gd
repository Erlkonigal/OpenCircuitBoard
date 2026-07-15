extends RefCounted

const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("activateDock", "circuitEditor")
	await context.waitFrames()
	var dock := context.getDockForSide(context.MainSceneRoot, "left") as Control
	var inkButtons: Dictionary = dock.get("InkButtons")
	var traceButton := inkButtons.get("trace") as Button
	dock.call("selectInk", InkRegistry.getInk("traceBlue"), false)
	await context.waitFrames()
	context.RootWindow.push_input(context.makeMouseButtonEvent(traceButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames()
	context.RootWindow.push_input(context.makeMouseButtonEvent(traceButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames()
	assert((context.MainSceneRoot.get("InkVariantMenu") as PopupPanel).visible)
	return {}
