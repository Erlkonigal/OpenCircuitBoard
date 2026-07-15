extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.main.call("activateDock", "circuitEditor")
	await context.waitFrames()
	var dock := context.getDockForSide(context.main, "left")
	var dockMenuButton := dock.get("dockMenuButton") as Button
	dockMenuButton.emit_signal("pressed")
	await context.waitFrames()
	var dockMenu := context.main.get("dockMenu") as PopupPanel
	context.assertDockMenuFitsViewport(dockMenu)
	return {}
