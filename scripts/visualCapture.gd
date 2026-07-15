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

func shouldCaptureClipboardDock() -> bool:
	return OS.get_cmdline_user_args().has("--captureClipboardDock")

func shouldCaptureSelection() -> bool:
	return OS.get_cmdline_user_args().has("--captureSelection")

func shouldCapturePastePreview() -> bool:
	return OS.get_cmdline_user_args().has("--capturePastePreview")

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

func findDockDefinition(definitions: Array[Dictionary], dockId: String) -> Dictionary:
	for definition in definitions:
		if String(definition.get("dockId", "")) == dockId:
			return definition
	return {}

func findDockMenuButton(grid: GridContainer, dockTitle: String) -> Button:
	for buttonNode in grid.get_children():
		var button := buttonNode as Button
		if button and button.tooltip_text == dockTitle:
			return button
	return null

func assertIconButton(button: Button) -> void:
	assert(button != null)
	assert(button.icon != null)
	assert(not button.expand_icon)
	assert(button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER)
	assert(button.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER)
	assert(button.icon.get_size() == Vector2(16, 16))

func assertClipboardDock(dockHost: Control, clipboardDock: Control, expectedClipboard: Dictionary) -> void:
	assert(String(clipboardDock.get("dockId")) == "clipboard")
	assertDockLayout(dockHost, clipboardDock)
	var dockIcon := clipboardDock.get("dockIcon") as Texture2D
	assert(dockIcon != null)
	assert(dockIcon.get_size() == Vector2(16, 16))
	var dockMenuButton := clipboardDock.get("dockMenuButton") as Button
	assertIconButton(dockMenuButton)
	var itemButton := clipboardDock.find_child("clipboardItem", true, false) as Button
	var itemTitle := clipboardDock.find_child("clipboardItemTitle", true, false) as Label
	var itemDetails := clipboardDock.find_child("clipboardItemDetails", true, false) as Label
	var preview := clipboardDock.find_child("clipboardPreview", true, false) as Control
	assert(itemButton != null)
	assert(itemTitle != null)
	assert(itemDetails != null)
	assert(preview != null)
	assert(not itemButton.disabled)
	assert(itemButton.button_pressed)
	assert(itemTitle.text == "Selection")
	var boundsSize: Vector2i = expectedClipboard.get("boundsSize", Vector2i.ZERO)
	var tileCount := (expectedClipboard.get("tiles", []) as Array).size()
	assert(itemDetails.text.contains("%d x %d" % [boundsSize.x, boundsSize.y]))
	assert(itemDetails.text.contains("%d tiles" % tileCount))
	assert(preview.custom_minimum_size.y >= 64.0)

func sendCtrlShortcut(board: Node2D, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.ctrl_pressed = true
	event.keycode = keycode
	board.call("handleKeyInput", event)

func assertBoardEditingInteractions(board: Node2D) -> Dictionary:
	# Each direct sequence mirrors one pointer gesture and must create one command.
	var strokeStart := Vector2i(-18, -12)
	var strokeEnd := Vector2i(-15, -12)
	var historyStart := (board.get("undoStack") as Array).size()
	board.call("selectTool", "and")
	board.call("beginStroke", strokeStart, true)
	board.call("appendStrokeTo", strokeEnd)
	board.call("finishStroke")
	var tileData: Dictionary = board.get("tileData")
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(tileData.has(Vector2i(x, strokeStart.y)))
	assert((board.get("undoStack") as Array).size() == historyStart + 1)
	sendCtrlShortcut(board, KEY_Z)
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(not tileData.has(Vector2i(x, strokeStart.y)))
	assert((board.get("undoStack") as Array).size() == historyStart)
	sendCtrlShortcut(board, KEY_U)
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(tileData.has(Vector2i(x, strokeStart.y)))
	assert((board.get("undoStack") as Array).size() == historyStart + 1)

	board.call("beginStroke", strokeStart, false)
	board.call("appendStrokeTo", strokeEnd)
	board.call("finishStroke")
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(not tileData.has(Vector2i(x, strokeStart.y)))
	assert((board.get("undoStack") as Array).size() == historyStart + 2)
	sendCtrlShortcut(board, KEY_Z)
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(tileData.has(Vector2i(x, strokeStart.y)))
	sendCtrlShortcut(board, KEY_U)
	for x in range(strokeStart.x, strokeEnd.x + 1):
		assert(not tileData.has(Vector2i(x, strokeStart.y)))
	sendCtrlShortcut(board, KEY_Z)
	sendCtrlShortcut(board, KEY_Z)
	assert((board.get("undoStack") as Array).size() == historyStart)

	var source := Vector2i(-12, -10)
	var sourceOther := source + Vector2i(2, 0)
	assert(board.call("placeTile", source, "or"))
	assert(board.call("placeTile", sourceOther, "xor"))
	board.call("setSelection", Rect2i(source, Vector2i(3, 1)))
	var sourceSelection: Dictionary = board.call("getSelectionItem")
	assert((sourceSelection.get("cells", []) as Array).size() == 2)
	sendCtrlShortcut(board, KEY_C)
	var clipboard: Dictionary = board.call("getClipboardItem")
	assert((clipboard.get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(3, 1))
	assert((clipboard.get("tiles", []) as Array).size() == 2)

	var pasteAnchor := Vector2i(-12, -7)
	sendCtrlShortcut(board, KEY_V)
	board.call("updatePastePreview", pasteAnchor)
	assert(bool(board.get("pastePreviewValid")))
	board.call("confirmPastePreview")
	assert(tileData.has(pasteAnchor))
	assert(tileData.has(pasteAnchor + Vector2i(2, 0)))
	var pastedSelection: Dictionary = board.call("getSelectionItem")
	assert((pastedSelection.get("bounds", Rect2i()) as Rect2i).position == pasteAnchor)
	assert((pastedSelection.get("cells", []) as Array).size() == 2)

	var occupiedTileCount := tileData.size()
	board.call("beginPastePreview")
	board.call("updatePastePreview", pasteAnchor)
	assert(not bool(board.get("pastePreviewValid")))
	board.call("confirmPastePreview")
	assert(tileData.size() == occupiedTileCount)
	board.call("cancelPastePreview")

	var collisionOffset := Vector2i(0, 2)
	var collisionCoordinates := pasteAnchor + collisionOffset
	assert(board.call("placeTile", collisionCoordinates, "nor"))
	board.call("beginMove", pasteAnchor)
	board.call("updateMovePreview", pasteAnchor + collisionOffset)
	assert(not bool(board.get("movePreviewValid")))
	board.call("finishMove")
	assert(tileData.has(pasteAnchor))
	assert(tileData.has(collisionCoordinates))

	var moveOffset := Vector2i(4, 2)
	var movedPrimary := pasteAnchor + moveOffset
	var movedOther := movedPrimary + Vector2i(2, 0)
	var historyBeforeMove := (board.get("undoStack") as Array).size()
	board.call("beginMove", pasteAnchor)
	board.call("updateMovePreview", movedPrimary)
	assert(bool(board.get("movePreviewValid")))
	board.call("finishMove")
	assert(not tileData.has(pasteAnchor))
	assert(not tileData.has(pasteAnchor + Vector2i(2, 0)))
	assert(tileData.has(movedPrimary))
	assert(tileData.has(movedOther))
	assert((board.get("undoStack") as Array).size() == historyBeforeMove + 1)
	sendCtrlShortcut(board, KEY_Z)
	assert(tileData.has(pasteAnchor))
	assert(tileData.has(pasteAnchor + Vector2i(2, 0)))
	sendCtrlShortcut(board, KEY_U)
	assert(tileData.has(movedPrimary))
	assert(tileData.has(movedOther))

	# Leave only the visual-capture tiles in the board while retaining the clipboard item.
	sendCtrlShortcut(board, KEY_Z)
	sendCtrlShortcut(board, KEY_Z)
	board.call("clearSelection")
	for coordinates in [source, sourceOther, collisionCoordinates]:
		board.call("removeTile", coordinates)
	assert((board.get("undoStack") as Array).size() == historyStart)
	return clipboard

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
		assertIconButton(topBarButton)
	var dockRect := dockHost.get_global_rect()
	assert(is_equal_approx(dockRect.size.x, 272.0))
	assert(circuitEditorDock.find_children("*", "CheckBox", true, false).is_empty())
	assert(circuitEditorDock.find_children("*", "SpinBox", true, false).size() == 4)
	for labelNode in circuitEditorDock.find_children("*", "Label", true, false):
		var label := labelNode as Label
		assert(label.text != "Layers")
		assert(label.text != "Tools")
	var dockDefinitions: Array[Dictionary] = main.get("dockDefinitions")
	assert(dockDefinitions.size() == 3)
	var circuitEditorDefinition := findDockDefinition(dockDefinitions, "circuitEditor")
	var clipboardDefinition := findDockDefinition(dockDefinitions, "clipboard")
	var eventLogDefinition := findDockDefinition(dockDefinitions, "eventLog")
	assert(not circuitEditorDefinition.is_empty())
	assert(not clipboardDefinition.is_empty())
	assert(not eventLogDefinition.is_empty())
	for definition in [circuitEditorDefinition, clipboardDefinition, eventLogDefinition]:
		var definitionIcon := definition.get("dockIcon") as Texture2D
		assert(definitionIcon != null)
		assert(definitionIcon.get_size() == Vector2(16, 16))
	var dockMenu := main.get("dockMenu") as PopupPanel
	assert(dockMenu.get_child_count() == 1)
	var dockMenuGrid := dockMenu.get_child(0) as GridContainer
	assert(dockMenuGrid.get_child_count() == dockDefinitions.size())
	var dockMenuButton := circuitEditorDock.get("dockMenuButton") as Button
	assertIconButton(dockMenuButton)
	for dockButtonNode in circuitEditorDock.find_children("*", "Button", true, false):
		var dockButton := dockButtonNode as Button
		if dockButton.icon != null:
			assertIconButton(dockButton)
	for menuButtonNode in dockMenuGrid.get_children():
		var menuButton := menuButtonNode as Button
		assertIconButton(menuButton)
	var circuitEditorMenuButton := findDockMenuButton(dockMenuGrid, "CircuitEditor")
	var clipboardMenuButton := findDockMenuButton(dockMenuGrid, "Clipboard")
	var eventLogMenuButton := findDockMenuButton(dockMenuGrid, "EventLog")
	assert(circuitEditorMenuButton != null)
	assert(clipboardMenuButton != null)
	assert(eventLogMenuButton != null)
	assert(circuitEditorMenuButton.icon == dockMenuButton.icon)
	assert(clipboardMenuButton.icon == clipboardDefinition.get("dockIcon"))
	assert(eventLogMenuButton.icon == eventLogDefinition.get("dockIcon"))
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
	var copiedClipboard := assertBoardEditingInteractions(board)
	await process_frame
	assert(dockHost.get_child_count() == 1)
	var clipboardDock := main.get("currentDock") as Control
	assertClipboardDock(dockHost, clipboardDock, copiedClipboard)
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	var clipboardItemButton := clipboardDock.find_child("clipboardItem", true, false) as Button
	clipboardItemButton.emit_signal("pressed")
	await process_frame
	assertClipboardDock(dockHost, main.get("currentDock") as Control, copiedClipboard)
	main.call("activateDock", "eventLog")
	await process_frame
	main.call("activateDock", "clipboard")
	await process_frame
	clipboardDock = main.get("currentDock") as Control
	assertClipboardDock(dockHost, clipboardDock, copiedClipboard)
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	var selector := board.get_node("Selector") as ColorRect
	selector.visible = shouldCaptureSelector()
	if selector.visible:
		selector.position = Vector2(8, -8) * float(board.get("cellSize"))
	if shouldCaptureSelection():
		board.call("setSelection", Rect2i(Vector2i(-1, 0), Vector2i(3, 2)))
		var selectionOverlay := board.get_node("SelectionOverlay") as Node2D
		assert(bool(selectionOverlay.get("hasOverlay")))
		assert(bool(selectionOverlay.get("isSelection")))
	if shouldCapturePastePreview():
		board.call("beginPastePreview")
		board.call("updatePastePreview", Vector2i(5, 2))
		assert(bool(board.get("pastePreviewValid")))
		assert((board.get_node("PreviewTiles") as Node2D).get_child_count() == 2)
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
	if shouldCaptureClipboardDock():
		main.call("activateDock", "clipboard")
		await process_frame
	if shouldCaptureSidebar() or shouldCaptureEventLogDock() or shouldCaptureClipboardDock() or shouldCaptureDockMenu():
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
	if shouldCaptureInterface() or shouldCaptureSidebar() or shouldCaptureEventLogDock() or shouldCaptureClipboardDock() or shouldCaptureDockMenu():
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
		if shouldCaptureClipboardDock():
			var clipboardDockError := interfaceImage.save_png("user://clipboardDockCapture.png")
			print("clipboardDockCapture=user://clipboardDockCapture.png error=", clipboardDockError)
		if shouldCaptureDockMenu():
			var dockMenuError := interfaceImage.save_png("user://dockMenuCapture.png")
			print("dockMenuCapture=user://dockMenuCapture.png error=", dockMenuError)
	quit(error)
