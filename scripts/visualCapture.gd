extends SceneTree

func _init() -> void:
	call_deferred("captureBoard")

func getCaptureZoom() -> float:
	var captureZoom := 1.25
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captureZoom="):
			captureZoom = maxf(argument.trim_prefix("--captureZoom=").to_float(), 0.01)
	return captureZoom

func shouldCaptureSelector() -> bool:
	return OS.get_cmdline_user_args().has("--captureSelector")

func shouldCaptureBoardEdge() -> bool:
	return OS.get_cmdline_user_args().has("--captureBoardEdge")

func shouldCaptureInterface() -> bool:
	return OS.get_cmdline_user_args().has("--captureInterface")

func shouldCaptureSidebar() -> bool:
	return OS.get_cmdline_user_args().has("--captureSidebar")

func assertCanvasViewIsStable(boardViewport: SubViewportContainer, subViewport: SubViewport, camera: Camera2D, expectedRect: Rect2, expectedSize: Vector2i, expectedCenter: Vector2, expectedZoom: Vector2) -> void:
	var actualRect := boardViewport.get_global_rect()
	assert(actualRect.position.is_equal_approx(expectedRect.position))
	assert(actualRect.size.is_equal_approx(expectedRect.size))
	assert(subViewport.size == expectedSize)
	assert(camera.get_screen_center_position().is_equal_approx(expectedCenter))
	assert(camera.zoom.is_equal_approx(expectedZoom))

func captureBoard() -> void:
	var captureViewportSize := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	root.size = captureViewportSize
	var mainScene := load("res://main.tscn") as PackedScene
	var main := mainScene.instantiate()
	root.add_child(main)
	for frame in 5:
		await process_frame

	var board := main.get_node("BoardViewport/SubViewport/CircuitBoard") as Node2D
	var boardViewport := main.get_node("BoardViewport") as SubViewportContainer
	var subViewport := main.get_node("BoardViewport/SubViewport") as SubViewport
	var camera := main.get_node("BoardViewport/SubViewport/BoardCamera") as Camera2D
	var initialCanvasRect := boardViewport.get_global_rect()
	var initialSubViewportSize := subViewport.size
	var initialCameraCenter := camera.get_screen_center_position()
	var initialCameraZoom := camera.zoom
	var dockHost := main.get_node("Interface/DockHost") as Control
	assert(dockHost.get_child_count() == 1)
	var circuitEditorDock := dockHost.get_child(0) as Control
	assert(circuitEditorDock.get("dockId") == "circuitEditor")
	var dockContentRoot := circuitEditorDock.get_node("background/contentRoot") as VBoxContainer
	var topBar := main.get_node("Interface/TopBar") as Control
	var configuredMinimumHeight := int(ProjectSettings.get_setting("display/window/size/min_height"))
	assert(circuitEditorDock.find_children("*", "ScrollContainer", true, false).is_empty())
	assert(dockContentRoot.size.y >= dockContentRoot.get_combined_minimum_size().y)
	assert(configuredMinimumHeight >= ceili(topBar.size.y + dockContentRoot.get_combined_minimum_size().y))
	var dockMenu := main.get("dockMenu") as PopupPanel
	assert(dockMenu.get_child_count() == 1)
	assert(dockMenu.get_child(0).get_child_count() == 1)
	var dockMenuButton := circuitEditorDock.get("dockMenuButton") as Button
	dockMenuButton.emit_signal("pressed")
	await process_frame
	assert(dockMenu.visible)
	dockMenu.hide()
	main.call("setDockWidth", 420.0)
	assert(is_equal_approx(dockHost.offset_right, 420.0))
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 1.0)
	assert(is_equal_approx(dockHost.offset_right, 208.0))
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 272.0)
	main.call("setLeftSidebarOpen", false)
	await process_frame
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	await create_timer(0.25).timeout
	assert(is_equal_approx(dockHost.offset_right, 0.0))
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setLeftSidebarOpen", true)
	await process_frame
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	await create_timer(0.25).timeout
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setRightSidebarOpen", false)
	await process_frame
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	await create_timer(0.25).timeout
	assert(is_equal_approx((main.get_node("BoardViewport") as Control).offset_right, 0.0))
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setRightSidebarOpen", true)
	await process_frame
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	await create_timer(0.25).timeout
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	var inkButtons: Dictionary = circuitEditorDock.get("inkButtons")
	assert(inkButtons.size() == 19)
	var toolRegistry: Dictionary = board.get("toolRegistry")
	assert(toolRegistry.size() == 19)
	for toolId in ["cross", "tunnel", "mesh", "bus", "read", "write", "trace", "buffer", "and", "or", "xor", "not", "nand", "nor", "xnor", "latchOn", "latchOff", "clock", "led"]:
		assert(toolRegistry.has(toolId))
	var boardBounds: Rect2 = board.get("validRect")
	board.set_process(false)
	# Place the right tile first so the capture verifies X-based depth ordering.
	board.call("placeTile", Vector2i(1, 0))
	board.call("selectTool", "xor")
	board.call("placeTile", Vector2i(0, 0))
	board.call("selectTool", "trace")
	board.call("placeTile", Vector2i(-1, 1))
	# Keep an isolated tile in view to inspect the full shadow silhouette.
	board.call("selectTool", "or")
	board.call("placeTile", Vector2i(4, -2))
	var occupancy: Dictionary = board.get("occupancy")
	var rightTile := occupancy[Vector2i(1, 0)] as Node2D
	var leftTile := occupancy[Vector2i(0, 0)] as Node2D
	assert(leftTile.z_index > rightTile.z_index)
	var selector := board.get_node("Selector") as ColorRect
	selector.visible = shouldCaptureSelector()
	if selector.visible:
		selector.position = Vector2(8, -8) * float(board.get("cellSize"))
	camera.zoom = Vector2.ONE * getCaptureZoom()
	if shouldCaptureBoardEdge():
		camera.global_position = boardBounds.position
	for frame in 5:
		await process_frame
	if shouldCaptureBoardEdge():
		assert(is_equal_approx(camera.global_position.x, boardBounds.position.x))
		assert(is_equal_approx(camera.global_position.y, boardBounds.position.y))
	if shouldCaptureInterface():
		var topBarContent := main.get_node("Interface/TopBar/Content") as Control
		for child in topBarContent.get_children():
			var topBarButton := child as Button
			if topBarButton == null:
				continue
			var normalStyle := topBarButton.get_theme_stylebox("normal") as StyleBoxFlat
			var hoverStyle := topBarButton.get_theme_stylebox("hover") as StyleBoxFlat
			var pressedStyle := topBarButton.get_theme_stylebox("pressed") as StyleBoxFlat
			var hoverPressedStyle := topBarButton.get_theme_stylebox("hover_pressed") as StyleBoxFlat
			assert(normalStyle != null)
			assert(hoverStyle != null)
			assert(pressedStyle != null)
			assert(hoverPressedStyle != null)
			assert(pressedStyle.bg_color.is_equal_approx(Color.TRANSPARENT))
			assert(hoverPressedStyle.bg_color.is_equal_approx(hoverStyle.bg_color))
			assert(is_equal_approx(normalStyle.content_margin_left, pressedStyle.content_margin_left))
			assert(is_equal_approx(normalStyle.content_margin_top, pressedStyle.content_margin_top))
			assert(is_equal_approx(normalStyle.content_margin_right, pressedStyle.content_margin_right))
			assert(is_equal_approx(normalStyle.content_margin_bottom, pressedStyle.content_margin_bottom))
			assert(topBarButton.get_theme_color("icon_pressed_color").is_equal_approx(Color("f2c94c")))
			assert(topBarButton.get_theme_color("icon_hover_pressed_color").is_equal_approx(Color("f2c94c")))
		main.call("setLeftSidebarOpen", false, false)
		for frame in 2:
			await process_frame
	if shouldCaptureSidebar():
		main.call("setLeftSidebarOpen", true, false)
		main.call("setRightSidebarOpen", true, false)
		for frame in 2:
			await process_frame

	var viewport := main.get_node("BoardViewport/SubViewport") as SubViewport
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("The subviewport image is unavailable.")
		quit(1)
		return
	var outputPath := "user://capture.png"
	var error := image.save_png(outputPath)
	print("capture=", outputPath, " error=", error, " data=", OS.get_user_data_dir())
	if shouldCaptureInterface() or shouldCaptureSidebar():
		var interfaceImage := main.get_viewport().get_texture().get_image()
		if shouldCaptureInterface():
			var interfaceError := interfaceImage.save_png("user://interfaceCapture.png")
			print("interfaceCapture=user://interfaceCapture.png error=", interfaceError)
		if shouldCaptureSidebar():
			var sidebarError := interfaceImage.save_png("user://sidebarCapture.png")
			print("sidebarCapture=user://sidebarCapture.png error=", sidebarError)
	quit(error)
