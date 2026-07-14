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

func shouldCaptureEventLogDock() -> bool:
	return OS.get_cmdline_user_args().has("--captureEventLogDock")

func shouldCaptureDockMenu() -> bool:
	return OS.get_cmdline_user_args().has("--captureDockMenu")

func shouldCaptureDefaultZoom() -> bool:
	return OS.get_cmdline_user_args().has("--captureDefaultZoom")

func assertCanvasViewIsStable(boardViewport: SubViewportContainer, subViewport: SubViewport, camera: Camera2D, expectedRect: Rect2, expectedSize: Vector2i, expectedCenter: Vector2, expectedZoom: Vector2) -> void:
	var actualRect := boardViewport.get_global_rect()
	assert(actualRect.position.is_equal_approx(expectedRect.position))
	assert(actualRect.size.is_equal_approx(expectedRect.size))
	assert(subViewport.size == expectedSize)
	assert(camera.get_screen_center_position().is_equal_approx(expectedCenter))
	assert(camera.zoom.is_equal_approx(expectedZoom))

func assertSidebarControlsFit(contentRoot: Control) -> void:
	var contentRect := contentRoot.get_global_rect()
	for child in contentRoot.find_children("*", "Control", true, false):
		var control := child as Control
		if control == null or not control.visible:
			continue
		var controlRect := control.get_global_rect()
		assert(controlRect.position.x >= contentRect.position.x - 0.5)
		assert(controlRect.end.x <= contentRect.end.x + 0.5)
		assert(control.get_combined_minimum_size().x <= control.size.x + 0.5)

func assertDockLayout(dockHost: Control, dock: Control) -> void:
	var contentRoot := dock.get_node("background/contentFrame/contentRoot") as VBoxContainer
	assert(dock.find_children("*", "ScrollContainer", true, false).is_empty())
	assert(contentRoot.size.y >= contentRoot.get_combined_minimum_size().y)
	var dockRect := dockHost.get_global_rect()
	var contentRect := contentRoot.get_global_rect()
	assert(contentRect.position.x >= dockRect.position.x + 8.0 - 0.5)
	assert(contentRect.end.x <= dockRect.end.x - 8.0 + 0.5)
	assertSidebarControlsFit(contentRoot)

func countButtonTooltip(dock: Control, tooltipText: String) -> int:
	var count := 0
	for buttonNode in dock.find_children("*", "Button", true, false):
		var button := buttonNode as Button
		if button.tooltip_text == tooltipText:
			count += 1
	return count

func captureBoard() -> void:
	var captureViewportSize := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)
	assert(captureViewportSize == Vector2i(1280, 720))
	assert(int(ProjectSettings.get_setting("display/window/size/min_width")) == 1280)
	assert(int(ProjectSettings.get_setting("display/window/size/min_height")) == 720)
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
	var expectedDefaultZoom := Vector2(0.5, 0.5)
	assert(initialCameraZoom.is_equal_approx(expectedDefaultZoom))
	var dockHost := main.get_node("Interface/DockHost") as Control
	assert(dockHost.get_child_count() == 1)
	var circuitEditorDock := dockHost.get_child(0) as Control
	assert(circuitEditorDock.get("dockId") == "circuitEditor")
	var dockContentRoot := circuitEditorDock.get_node("background/contentFrame/contentRoot") as VBoxContainer
	var topBar := main.get_node("Interface/TopBar") as Control
	var topBarTitle := main.get_node("Interface/TopBar/Content/Title") as Label
	var configuredMinimumHeight := int(ProjectSettings.get_setting("display/window/size/min_height"))
	assertDockLayout(dockHost, circuitEditorDock)
	assert(configuredMinimumHeight >= ceili(topBar.size.y + dockContentRoot.get_combined_minimum_size().y))
	assert(topBarTitle.get_theme_font_size("font_size") == 16)
	for topBarChild in (main.get_node("Interface/TopBar/Content") as Control).get_children():
		var topBarButton := topBarChild as Button
		if topBarButton == null:
			continue
		assert(topBarButton.icon != null)
		assert(not topBarButton.expand_icon)
		assert(topBarButton.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER)
		assert(topBarButton.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER)
		assert(topBarButton.icon.get_size() == Vector2(16, 16))
	var dockRect := dockHost.get_global_rect()
	assert(is_equal_approx(dockRect.size.x, 272.0))
	assert(circuitEditorDock.find_children("*", "CheckBox", true, false).is_empty())
	assert(circuitEditorDock.find_children("*", "SpinBox", true, false).size() == 4)
	var sectionTitleCount := 0
	for labelNode in circuitEditorDock.find_children("*", "Label", true, false):
		var label := labelNode as Label
		assert(label.text != "Layers")
		if label.text == "Tools":
			sectionTitleCount += 1
	assert(sectionTitleCount == 1)
	for actionName in ["Add", "Image", "Duplicate", "Undo", "Redo", "Draw", "Edit", "Erase", "Sample", "Select", "Transform"]:
		assert(countButtonTooltip(circuitEditorDock, actionName) == 1)
	var dockDefinitions: Array[Dictionary] = main.get("dockDefinitions")
	assert(dockDefinitions.size() == 2)
	assert(String(dockDefinitions[0].dockId) == "circuitEditor")
	assert(String(dockDefinitions[1].dockId) == "eventLog")
	var dockMenu := main.get("dockMenu") as PopupPanel
	assert(dockMenu.get_child_count() == 1)
	var dockMenuGrid := dockMenu.get_child(0) as GridContainer
	assert(dockMenuGrid.get_child_count() == dockDefinitions.size())
	var dockMenuButton := circuitEditorDock.get("dockMenuButton") as Button
	assert(dockMenuButton.icon != null)
	assert(not dockMenuButton.expand_icon)
	assert(dockMenuButton.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER)
	assert(dockMenuButton.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER)
	assert(dockMenuButton.icon.get_size() == Vector2(16, 16))
	for dockButtonNode in circuitEditorDock.find_children("*", "Button", true, false):
		var dockButton := dockButtonNode as Button
		if dockButton.icon != null:
			assert(dockButton.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER)
			assert(dockButton.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER)
			assert(dockButton.icon.get_size() == Vector2(16, 16))
	var foundCircuitEditorIcon := false
	var foundEventLogIcon := false
	var circuitEditorMenuButton: Button
	var eventLogMenuButton: Button
	for menuButtonNode in dockMenuGrid.get_children():
		var menuButton := menuButtonNode as Button
		assert(menuButton.icon != null)
		assert(not menuButton.expand_icon)
		assert(menuButton.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER)
		assert(menuButton.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER)
		assert(menuButton.icon.get_size() == Vector2(16, 16))
		if menuButton.tooltip_text == "CircuitEditor":
			assert(menuButton.icon == dockMenuButton.icon)
			circuitEditorMenuButton = menuButton
			foundCircuitEditorIcon = true
		elif menuButton.tooltip_text == "EventLog":
			eventLogMenuButton = menuButton
			foundEventLogIcon = true
	assert(foundCircuitEditorIcon)
	assert(foundEventLogIcon)
	assert(circuitEditorMenuButton != null)
	assert(eventLogMenuButton != null)
	dockMenuButton.emit_signal("pressed")
	await process_frame
	assert(dockMenu.visible)
	assert(dockMenu.position.x >= 0)
	assert(dockMenu.position.x + dockMenu.size.x <= root.size.x)
	assert(dockMenu.position.y + dockMenu.size.y <= root.size.y)
	dockMenu.hide()
	main.call("setDockWidth", 420.0)
	assert(is_equal_approx(dockHost.offset_right, 420.0))
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 1.0)
	assert(is_equal_approx(dockHost.offset_right, 208.0))
	await process_frame
	assertDockLayout(dockHost, circuitEditorDock)
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
	circuitEditorDock.call("recordEvent", "HistoryMarkerOne")
	await process_frame
	dockMenuButton.emit_signal("pressed")
	await process_frame
	eventLogMenuButton.emit_signal("pressed")
	await process_frame
	assert(dockHost.get_child_count() == 1)
	var eventLogDock := dockHost.get_child(0) as Control
	assert(eventLogDock.get("dockId") == "eventLog")
	assertDockLayout(dockHost, eventLogDock)
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	var eventLogDockMenuButton := eventLogDock.get("dockMenuButton") as Button
	assert(eventLogDockMenuButton.icon != null)
	assert(not eventLogDockMenuButton.expand_icon)
	assert(eventLogDockMenuButton.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER)
	assert(eventLogDockMenuButton.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER)
	assert(eventLogDockMenuButton.icon.get_size() == Vector2(16, 16))
	assert(eventLogDockMenuButton.icon == eventLogMenuButton.icon)
	var eventLog := eventLogDock.get_node("background/contentFrame/contentRoot/eventLog") as RichTextLabel
	assert(eventLog.get_parsed_text().contains("HistoryMarkerOne"))
	main.call("setDockWidth", 1.0)
	await process_frame
	assertDockLayout(dockHost, eventLogDock)
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 272.0)
	eventLogDockMenuButton.emit_signal("pressed")
	await process_frame
	circuitEditorMenuButton.emit_signal("pressed")
	await process_frame
	assert(dockHost.get_child_count() == 1)
	var restoredCircuitEditorDock := dockHost.get_child(0) as Control
	assert(restoredCircuitEditorDock.get("dockId") == "circuitEditor")
	assertDockLayout(dockHost, restoredCircuitEditorDock)
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	restoredCircuitEditorDock.call("recordEvent", "HistoryMarkerTwo")
	await process_frame
	main.call("activateDock", "eventLog")
	await process_frame
	eventLogDock = dockHost.get_child(0) as Control
	eventLog = eventLogDock.get_node("background/contentFrame/contentRoot/eventLog") as RichTextLabel
	var eventLogText := eventLog.get_parsed_text()
	var firstMarkerIndex := eventLogText.find("HistoryMarkerOne")
	var secondMarkerIndex := eventLogText.find("HistoryMarkerTwo")
	assert(firstMarkerIndex >= 0)
	assert(secondMarkerIndex > firstMarkerIndex)
	assert(eventLogText.find("HistoryMarkerOne", firstMarkerIndex + 1) == -1)
	assert(eventLogText.find("HistoryMarkerTwo", secondMarkerIndex + 1) == -1)
	var selector := board.get_node("Selector") as ColorRect
	selector.visible = shouldCaptureSelector()
	if selector.visible:
		selector.position = Vector2(8, -8) * float(board.get("cellSize"))
	if shouldCaptureDefaultZoom():
		camera.zoom = initialCameraZoom
	else:
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
	if shouldCaptureSidebar() or shouldCaptureDockMenu():
		main.call("activateDock", "circuitEditor")
		await process_frame
	if shouldCaptureEventLogDock():
		main.call("activateDock", "eventLog")
		await process_frame
	if shouldCaptureSidebar() or shouldCaptureEventLogDock() or shouldCaptureDockMenu():
		main.call("setLeftSidebarOpen", true, false)
		main.call("setRightSidebarOpen", true, false)
		for frame in 2:
			await process_frame
	if shouldCaptureDockMenu():
		var activeDock := main.get("currentDock") as Control
		var activeDockMenuButton := activeDock.get("dockMenuButton") as Button
		activeDockMenuButton.emit_signal("pressed")
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
	if shouldCaptureInterface() or shouldCaptureSidebar() or shouldCaptureEventLogDock() or shouldCaptureDockMenu():
		var interfaceImage := main.get_viewport().get_texture().get_image()
		if shouldCaptureInterface():
			var interfaceError := interfaceImage.save_png("user://interfaceCapture.png")
			print("interfaceCapture=user://interfaceCapture.png error=", interfaceError)
		if shouldCaptureSidebar():
			var sidebarError := interfaceImage.save_png("user://sidebarCapture.png")
			print("sidebarCapture=user://sidebarCapture.png error=", sidebarError)
		if shouldCaptureEventLogDock():
			var eventLogDockError := interfaceImage.save_png("user://eventLogDockCapture.png")
			print("eventLogDockCapture=user://eventLogDockCapture.png error=", eventLogDockError)
		if shouldCaptureDockMenu():
			var dockMenuError := interfaceImage.save_png("user://dockMenuCapture.png")
			print("dockMenuCapture=user://dockMenuCapture.png error=", dockMenuError)
	quit(error)
