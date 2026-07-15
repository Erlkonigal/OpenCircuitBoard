extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.main as Control
	var boardViewport := context.boardViewport as SubViewportContainer
	var subViewport := context.subViewport as SubViewport
	var camera := context.camera as Camera2D
	var initialCanvasRect := boardViewport.get_global_rect()
	var initialSubViewportSize := subViewport.size
	var initialCameraCenter := camera.get_screen_center_position()
	var initialCameraZoom := camera.zoom
	var initialDockState: Dictionary = context.assertDualDockState(main)
	var dockHost := initialDockState.get("leftDockHost") as Control
	var rightDockHost := initialDockState.get("rightDockHost") as Control
	var dockResizeHandle := main.get_node("Interface/DockResizeHandle") as Control
	var rightDockResizeHandle := main.get_node("Interface/RightDockResizeHandle") as Control
	var dockMenu := main.get("dockMenu") as PopupPanel
	var dockMenuGrid := dockMenu.get_child(0) as GridContainer
	var circuitEditorDock := initialDockState.get("leftDock") as Control
	var dockMenuButton := circuitEditorDock.get("dockMenuButton") as Button
	context.assertIconButton(dockMenuButton)
	for menuButtonNode in dockMenuGrid.get_children():
		context.assertIconButton(menuButtonNode as Button)
	assert(context.findDockMenuButton(dockMenuGrid, "Circuit Editor") != null)
	assert(context.findDockMenuButton(dockMenuGrid, "Clipboard") != null)
	assert(context.findDockMenuButton(dockMenuGrid, "Event Log") != null)
	dockMenuButton.emit_signal("pressed")
	await context.waitFrames(1)
	context.assertDockMenuFitsViewport(dockMenu)
	dockMenu.hide()
	await context.assertDualDockSwap(main, dockMenu, dockMenuGrid)

	circuitEditorDock = context.getDockForSide(main, "left")
	var rightDock: Control = context.getDockForSide(main, "right")
	assert(String(circuitEditorDock.get("dockId")) == "circuitEditor")
	assert(String(rightDock.get("dockId")) == "clipboard")
	main.call("setDockWidth", 420.0)
	assert(is_equal_approx(dockHost.offset_right, 420.0))
	main.call("setRightDockWidth", 420.0)
	assert(is_equal_approx(rightDockHost.offset_left, -420.0))
	assert(is_equal_approx(rightDockResizeHandle.offset_left, -426.0))
	context.assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 1.0)
	assert(is_equal_approx(dockHost.offset_right, 208.0))
	main.call("setRightDockWidth", 1.0)
	assert(is_equal_approx(rightDockHost.offset_left, -208.0))
	assert(is_equal_approx(rightDockResizeHandle.offset_left, -214.0))
	await context.waitFrames(1)
	context.assertDockLayout(dockHost, circuitEditorDock)
	context.assertDockLayout(rightDockHost, rightDock)
	context.assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)

	main.call("setDockWidth", 272.0)
	main.call("setRightDockWidth", 272.0)
	main.call("setLeftSidebarOpen", false)
	await context.waitFrames(1)
	context.assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	await context.waitSeconds(0.25)
	assert(is_equal_approx(dockHost.offset_right, 0.0))
	main.call("setLeftSidebarOpen", true)
	await context.waitFrames(1)
	await context.waitSeconds(0.25)
	context.assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setRightSidebarOpen", false)
	await context.waitFrames(1)
	await context.waitSeconds(0.25)
	assert(is_equal_approx(rightDockHost.offset_left, 0.0))
	assert(not rightDockResizeHandle.visible)
	main.call("setRightSidebarOpen", true)
	await context.waitFrames(1)
	assert(rightDockResizeHandle.visible)
	await context.waitSeconds(0.25)
	context.assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	assert(dockResizeHandle.visible)
