extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("activateDock", "circuitEditor")
	await context.waitFrames()
	var dock := context.getDockForSide(context.MainSceneRoot, "left") as Control
	var clockButton := (dock.get("InkButtons") as Dictionary).get("clock") as Button
	context.RootWindow.push_input(context.makeMouseButtonEvent(clockButton, MOUSE_BUTTON_RIGHT, true))
	await context.waitFrames()
	context.RootWindow.push_input(context.makeMouseButtonEvent(clockButton, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames()
	assert((context.MainSceneRoot.get("ClockSettingsMenu") as PopupPanel).visible)
	return {}
