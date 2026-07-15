extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("activateDock", "circuitEditor")
	await context.waitFrames()
	var dock := context.getDockForSide(context.MainSceneRoot, "left")
	var dockMenuButton := dock.get("DockMenuButton") as Button
	dockMenuButton.emit_signal("pressed")
	await context.waitFrames()
	var dockMenu := context.MainSceneRoot.get("DockMenu") as PopupPanel
	context.assertDockMenuFitsViewport(dockMenu)
	return {}
