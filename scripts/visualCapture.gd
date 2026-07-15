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

func shouldCaptureDualDock() -> bool:
	return OS.get_cmdline_user_args().has("--captureDualDock")

func getDockForSide(main: Control, dockSide: String) -> Control:
	assert(main.has_method("getDockForSide"))
	var dock := main.call("getDockForSide", dockSide) as Control
	assert(dock != null)
	return dock

func getDockHostForSide(main: Control, dockSide: String) -> Control:
	assert(main.has_method("getDockHostForSide"))
	var dockHost := main.call("getDockHostForSide", dockSide) as Control
	assert(dockHost != null)
	return dockHost

func getActiveDockState(main: Control, dockId: String) -> Dictionary:
	for dockSide in ["left", "right"]:
		var dock := getDockForSide(main, dockSide)
		if String(dock.get("dockId")) == dockId:
			return {
				"dock": dock,
				"dockHost": getDockHostForSide(main, dockSide),
				"dockSide": dockSide,
			}
	return {}

func assertDualDockState(main: Control) -> Dictionary:
	assert(main.get_node_or_null("Interface/RightDock") == null)
	assert(main.get_node_or_null("Interface/RightDockHost") != null)
	var leftDock := getDockForSide(main, "left")
	var rightDock := getDockForSide(main, "right")
	var leftDockHost := getDockHostForSide(main, "left")
	var rightDockHost := getDockHostForSide(main, "right")
	assert(leftDock != rightDock)
	assert(not String(leftDock.get("dockId")).is_empty())
	assert(not String(rightDock.get("dockId")).is_empty())
	assert(String(leftDock.get("dockId")) != String(rightDock.get("dockId")))
	assert(leftDockHost.get_child_count() == 1)
	assert(rightDockHost.get_child_count() == 1)
	assert(leftDockHost.get_child(0) == leftDock)
	assert(rightDockHost.get_child(0) == rightDock)
	assertDockLayout(leftDockHost, leftDock)
	assertDockLayout(rightDockHost, rightDock)
	return {
		"leftDock": leftDock,
		"rightDock": rightDock,
		"leftDockHost": leftDockHost,
		"rightDockHost": rightDockHost,
	}

func assertDockMenuFitsViewport(dockMenu: PopupPanel) -> void:
	assert(dockMenu.visible)
	assert(dockMenu.position.x >= 0)
	assert(dockMenu.position.y >= 0)
	assert(dockMenu.position.x + dockMenu.size.x <= root.size.x)
	assert(dockMenu.position.y + dockMenu.size.y <= root.size.y)

func assertDualDockSwap(main: Control, dockMenu: PopupPanel, dockMenuGrid: GridContainer) -> void:
	main.call("activateDock", "circuitEditor", "left")
	await process_frame
	main.call("activateDock", "clipboard", "right")
	await process_frame
	var initialState := assertDualDockState(main)
	assert(String((initialState.get("leftDock") as Control).get("dockId")) == "circuitEditor")
	assert(String((initialState.get("rightDock") as Control).get("dockId")) == "clipboard")
	var clipboardMenuButton := findDockMenuButton(dockMenuGrid, "Clipboard")
	assert(clipboardMenuButton != null)

	var leftDockMenuButton := (initialState.get("leftDock") as Control).get("dockMenuButton") as Button
	assertIconButton(leftDockMenuButton)
	leftDockMenuButton.emit_signal("pressed")
	await process_frame
	assertDockMenuFitsViewport(dockMenu)
	assert(String(main.get("dockMenuTargetSide")) == "left")
	clipboardMenuButton.emit_signal("pressed")
	await process_frame
	var swappedState := assertDualDockState(main)
	assert(String((swappedState.get("leftDock") as Control).get("dockId")) == "clipboard")
	assert(String((swappedState.get("rightDock") as Control).get("dockId")) == "circuitEditor")

	var rightDockMenuButton := (swappedState.get("rightDock") as Control).get("dockMenuButton") as Button
	assertIconButton(rightDockMenuButton)
	rightDockMenuButton.emit_signal("pressed")
	await process_frame
	assertDockMenuFitsViewport(dockMenu)
	assert(String(main.get("dockMenuTargetSide")) == "right")
	clipboardMenuButton.emit_signal("pressed")
	await process_frame
	var restoredState := assertDualDockState(main)
	assert(String((restoredState.get("leftDock") as Control).get("dockId")) == "circuitEditor")
	assert(String((restoredState.get("rightDock") as Control).get("dockId")) == "clipboard")
	dockMenu.hide()

func assertHoveredInkForCanvasTile(board: Node2D, circuitEditorDock: Control, coordinates: Vector2i) -> void:
	assert(board.has_method("getInkAt"))
	assert(circuitEditorDock.has_method("updateCursorInfo"))
	var hoveredInk := board.call("getInkAt", coordinates) as Dictionary
	assert(String(hoveredInk.get("toolId", "")) == "xor")
	assert(String(hoveredInk.get("title", "")) == "Xor")
	circuitEditorDock.call("updateCursorInfo", coordinates, true, String(hoveredInk.get("title", "")))
	var hoveredInkLabel := circuitEditorDock.get("hoveredInkLabel") as Label
	assert(hoveredInkLabel != null)
	assert(hoveredInkLabel.text == "Xor")
	circuitEditorDock.call("updateCursorInfo", coordinates, false, String(hoveredInk.get("title", "")))
	assert(hoveredInkLabel.text == "None")

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

func assertClipboardDock(dockHost: Control, clipboardDock: Control, expectedHistory: Array, expectedSelectedIndex: int) -> void:
	assert(String(clipboardDock.get("dockId")) == "clipboard")
	assertDockLayout(dockHost, clipboardDock)
	var dockIcon := clipboardDock.get("dockIcon") as Texture2D
	assert(dockIcon != null)
	assert(dockIcon.get_size() == Vector2(16, 16))
	var dockMenuButton := clipboardDock.get("dockMenuButton") as Button
	assertIconButton(dockMenuButton)
	var historyGrid := clipboardDock.find_child("clipboardHistory", true, false) as GridContainer
	var emptyHistoryLabel := clipboardDock.find_child("emptyClipboardHistory", true, false) as Label
	assert(historyGrid != null)
	assert(emptyHistoryLabel != null)
	assert(historyGrid.columns == 1)
	assert((clipboardDock.get("clipboardHistory") as Array).size() == expectedHistory.size())
	assert(int(clipboardDock.get("selectedClipboardIndex")) == expectedSelectedIndex)
	assert(historyGrid.get_child_count() == expectedHistory.size())
	assert(historyGrid.visible == not expectedHistory.is_empty())
	assert(emptyHistoryLabel.visible == expectedHistory.is_empty())
	for index in expectedHistory.size():
		var expectedItem: Dictionary = expectedHistory[index]
		var itemButton := historyGrid.get_child(index) as Button
		assert(itemButton != null)
		var itemTitle := itemButton.find_child("clipboardItemTitle", true, false) as Label
		var itemDetails := itemButton.find_child("clipboardItemDetails", true, false) as Label
		var preview := itemButton.find_child("clipboardPreview", true, false) as Control
		assert(itemTitle != null)
		assert(itemDetails != null)
		assert(preview != null)
		assert(itemButton.toggle_mode)
		assert(itemButton.button_pressed == (index == expectedSelectedIndex))
		assert(itemButton.size_flags_vertical == Control.SIZE_SHRINK_BEGIN)
		assert(itemButton.custom_minimum_size.y <= 80.0)
		assert(itemButton.get_global_rect().size.x >= historyGrid.get_global_rect().size.x - 0.5)
		assert(itemTitle.text == "Selection %d" % (index + 1))
		var boundsSize: Vector2i = expectedItem.get("boundsSize", Vector2i.ZERO)
		var tileCount := (expectedItem.get("tiles", []) as Array).size()
		assert(itemDetails.text.contains("%d x %d" % [boundsSize.x, boundsSize.y]))
		assert(itemDetails.text.contains("%d tiles" % tileCount))
		assert(preview.custom_minimum_size.x <= 58.0)
		assert(preview.custom_minimum_size.y <= 58.0)

func sendCtrlShortcut(board: Node2D, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.ctrl_pressed = true
	event.keycode = keycode
	board.call("handleKeyInput", event)

func assertPastePreviewAllowsCameraPan(board: Node2D, camera: Camera2D) -> void:
	assert(board.has_method("updatePastePreviewAtPointer"))
	var initialCameraPosition := camera.global_position
	var pressEvent := InputEventMouseButton.new()
	pressEvent.button_index = MOUSE_BUTTON_MIDDLE
	pressEvent.pressed = true
	pressEvent.position = Vector2(480, 300)
	camera.call("_unhandled_input", pressEvent)
	var motionEvent := InputEventMouseMotion.new()
	motionEvent.position = Vector2(432, 300)
	motionEvent.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	var pasteAnchorBefore: Vector2i = board.get("pasteAnchorCoordinates")
	board.call("handleMouseMotion", motionEvent)
	assert((board.get("pasteAnchorCoordinates") as Vector2i) == pasteAnchorBefore)
	camera.call("_unhandled_input", motionEvent)
	assert(not camera.global_position.is_equal_approx(initialCameraPosition))
	var clipboardItem: Dictionary = board.call("getClipboardItem")
	assert((board.get_node("PreviewTiles") as Node2D).get_child_count() == (clipboardItem.get("tiles", []) as Array).size())
	var releaseEvent := InputEventMouseButton.new()
	releaseEvent.button_index = MOUSE_BUTTON_MIDDLE
	releaseEvent.pressed = false
	releaseEvent.position = motionEvent.position
	camera.call("_unhandled_input", releaseEvent)
	camera.global_position = initialCameraPosition
	camera.force_update_scroll()

func assertBoardEditingInteractions(main: Control, board: Node2D, camera: Camera2D) -> Dictionary:
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
	var outsideSelection := source + Vector2i(0, 2)
	assert(not tileData.has(outsideSelection))
	assert(board.call("handleLeftButtonPress", Vector2.ZERO, outsideSelection))
	var clearedSelection: Dictionary = board.call("getSelectionItem")
	assert((clearedSelection.get("cells", []) as Array).is_empty())
	assert(not tileData.has(outsideSelection))
	board.call("setSelection", Rect2i(source, Vector2i(3, 1)))
	var historyBeforeCut := (board.get("undoStack") as Array).size()
	var clipboardDockStateBeforeCut := getActiveDockState(main, "clipboard")
	var clipboardDockBeforeCut := clipboardDockStateBeforeCut.get("dock") as Control
	var clipboardSideBeforeCut := String(clipboardDockStateBeforeCut.get("dockSide", ""))
	assert(clipboardDockBeforeCut != null)
	assert(not clipboardSideBeforeCut.is_empty())
	sendCtrlShortcut(board, KEY_X)
	var clipboard: Dictionary = board.call("getClipboardItem")
	var clipboardHistoryAfterCut: Array = board.call("getClipboardHistory")
	assert((clipboard.get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(3, 1))
	assert((clipboard.get("tiles", []) as Array).size() == 2)
	assert(clipboardHistoryAfterCut.size() == 1)
	assert(int(board.call("getSelectedClipboardIndex")) == 0)
	assert(not tileData.has(source))
	assert(not tileData.has(sourceOther))
	assert((board.get("undoStack") as Array).size() == historyBeforeCut + 1)
	var clipboardDockState := getActiveDockState(main, "clipboard")
	assert(not clipboardDockState.is_empty())
	var clipboardDock := clipboardDockState.get("dock") as Control
	assert(clipboardDock != null)
	assert(clipboardDock == clipboardDockBeforeCut)
	assert(String(clipboardDockState.get("dockSide", "")) == clipboardSideBeforeCut)
	sendCtrlShortcut(board, KEY_Z)
	assert(tileData.has(source))
	assert(tileData.has(sourceOther))
	assert((board.get("undoStack") as Array).size() == historyBeforeCut)
	assert(board.call("getClipboardItem") == clipboard)
	assert(board.call("getClipboardHistory") == clipboardHistoryAfterCut)
	sendCtrlShortcut(board, KEY_U)
	assert(not tileData.has(source))
	assert(not tileData.has(sourceOther))
	assert((board.get("undoStack") as Array).size() == historyBeforeCut + 1)
	assert(board.call("getClipboardItem") == clipboard)
	assert(board.call("getClipboardHistory") == clipboardHistoryAfterCut)
	sendCtrlShortcut(board, KEY_Z)
	assert(tileData.has(source))
	assert(tileData.has(sourceOther))
	assert((board.get("undoStack") as Array).size() == historyBeforeCut)

	var pasteAnchor := Vector2i(-12, -7)
	sendCtrlShortcut(board, KEY_V)
	board.call("updatePastePreview", pasteAnchor)
	assert(bool(board.get("pastePreviewValid")))
	assertPastePreviewAllowsCameraPan(board, camera)
	board.call("updatePastePreview", pasteAnchor)
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

	var moveStartInSelection := pasteAnchor + Vector2i(1, 0)
	assert(not tileData.has(moveStartInSelection))
	assert((pastedSelection.get("bounds", Rect2i()) as Rect2i).has_point(moveStartInSelection))
	assert(board.call("canStartMoveAt", moveStartInSelection))
	var collisionOffset := Vector2i(0, 2)
	var collisionCoordinates := pasteAnchor + collisionOffset
	assert(board.call("placeTile", collisionCoordinates, "nor"))
	assert(board.call("beginMove", moveStartInSelection))
	board.call("updateMovePreview", moveStartInSelection + collisionOffset)
	assert(not bool(board.get("movePreviewValid")))
	board.call("finishMove")
	assert(tileData.has(pasteAnchor))
	assert(tileData.has(collisionCoordinates))

	var moveOffset := Vector2i(4, 2)
	var movedPrimary := pasteAnchor + moveOffset
	var movedOther := movedPrimary + Vector2i(2, 0)
	var historyBeforeMove := (board.get("undoStack") as Array).size()
	assert(board.call("beginMove", moveStartInSelection))
	board.call("updateMovePreview", moveStartInSelection + moveOffset)
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

	# Leave only the visual-capture tiles in the board, then fill the four-item clipboard history.
	sendCtrlShortcut(board, KEY_Z)
	sendCtrlShortcut(board, KEY_Z)
	board.call("clearSelection")
	for coordinates in [source, sourceOther, collisionCoordinates]:
		board.call("removeTile", coordinates)
	assert((board.get("undoStack") as Array).size() == historyStart)
	var historySelections: Array[Rect2i] = [
		Rect2i(Vector2i(1, 0), Vector2i(1, 1)),
		Rect2i(Vector2i(0, 0), Vector2i(2, 1)),
		Rect2i(Vector2i(-1, 1), Vector2i(1, 1)),
		Rect2i(Vector2i(4, -2), Vector2i(1, 1)),
	]
	for bounds in historySelections:
		board.call("setSelection", bounds)
		sendCtrlShortcut(board, KEY_C)
	var clipboardHistory: Array = board.call("getClipboardHistory")
	assert(clipboardHistory.size() == 4)
	assert(int(board.call("getSelectedClipboardIndex")) == 0)
	for item in clipboardHistory:
		assert((item.get("boundsSize", Vector2i.ZERO) as Vector2i) != Vector2i(3, 1))
	assert((clipboardHistory[0].get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(1, 1))
	assert((clipboardHistory[1].get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(1, 1))
	assert((clipboardHistory[2].get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(2, 1))
	assert((clipboardHistory[3].get("boundsSize", Vector2i.ZERO) as Vector2i) == Vector2i(1, 1))
	assert((clipboardHistory[0].get("tiles", []) as Array).size() == 1)
	assert((clipboardHistory[1].get("tiles", []) as Array).size() == 1)
	assert((clipboardHistory[2].get("tiles", []) as Array).size() == 2)
	assert((clipboardHistory[3].get("tiles", []) as Array).size() == 1)
	assert(String((clipboardHistory[0].get("tiles", []) as Array)[0].get("toolId", "")) == "or")
	assert(String((clipboardHistory[1].get("tiles", []) as Array)[0].get("toolId", "")) == "trace")
	assert(String((clipboardHistory[2].get("tiles", []) as Array)[0].get("toolId", "")) == "xor")
	assert(String((clipboardHistory[3].get("tiles", []) as Array)[0].get("toolId", "")) == "or")
	return {
		"history": clipboardHistory,
		"selectedIndex": int(board.call("getSelectedClipboardIndex")),
	}

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
	var initialDockState := assertDualDockState(main)
	var dockHost := initialDockState.get("leftDockHost") as Control
	var rightDockHost := initialDockState.get("rightDockHost") as Control
	var dockResizeHandle := main.get_node("Interface/DockResizeHandle") as Control
	var rightDockResizeHandle := main.get_node("Interface/RightDockResizeHandle") as Control
	var circuitEditorDock := initialDockState.get("leftDock") as Control
	var rightDock := initialDockState.get("rightDock") as Control
	assert(String(circuitEditorDock.get("dockId")) == "circuitEditor")
	assert(String(rightDock.get("dockId")) == "eventLog")
	var dockContentRoot := circuitEditorDock.get_node("background/contentFrame/contentRoot") as VBoxContainer
	var topBar := main.get_node("Interface/TopBar") as Control
	var topBarTitle := main.get_node("Interface/TopBar/Content/Title") as Label
	var configuredMinimumHeight := int(ProjectSettings.get_setting("display/window/size/min_height"))
	assert(configuredMinimumHeight >= ceili(topBar.size.y + dockContentRoot.get_combined_minimum_size().y))
	assert(topBarTitle.get_theme_font_size("font_size") == 16)
	for topBarChild in (main.get_node("Interface/TopBar/Content") as Control).get_children():
		var topBarButton := topBarChild as Button
		if topBarButton == null:
			continue
		assertIconButton(topBarButton)
	var dockRect := dockHost.get_global_rect()
	assert(is_equal_approx(dockRect.size.x, 272.0))
	assert(is_equal_approx(rightDockHost.get_global_rect().size.x, 272.0))
	assert(dockResizeHandle.mouse_default_cursor_shape == Control.CURSOR_HSIZE)
	assert(rightDockResizeHandle.mouse_default_cursor_shape == Control.CURSOR_HSIZE)
	assert(is_equal_approx(dockResizeHandle.get_global_rect().position.x, 272.0))
	assert(is_equal_approx(rightDockResizeHandle.get_global_rect().position.x, 1002.0))
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
	assertDockMenuFitsViewport(dockMenu)
	dockMenu.hide()
	await assertDualDockSwap(main, dockMenu, dockMenuGrid)
	circuitEditorDock = getDockForSide(main, "left")
	rightDock = getDockForSide(main, "right")
	dockMenuButton = circuitEditorDock.get("dockMenuButton") as Button
	assert(String(circuitEditorDock.get("dockId")) == "circuitEditor")
	assert(String(rightDock.get("dockId")) == "clipboard")
	main.call("setDockWidth", 420.0)
	assert(is_equal_approx(dockHost.offset_right, 420.0))
	main.call("setRightDockWidth", 420.0)
	assert(is_equal_approx(rightDockHost.offset_left, -420.0))
	assert(is_equal_approx(rightDockResizeHandle.offset_left, -426.0))
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 1.0)
	assert(is_equal_approx(dockHost.offset_right, 208.0))
	main.call("setRightDockWidth", 1.0)
	assert(is_equal_approx(rightDockHost.offset_left, -208.0))
	assert(is_equal_approx(rightDockResizeHandle.offset_left, -214.0))
	await process_frame
	assertDockLayout(dockHost, circuitEditorDock)
	assertDockLayout(rightDockHost, rightDock)
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 272.0)
	main.call("setRightDockWidth", 272.0)
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
	assert(is_equal_approx(rightDockHost.offset_left, 0.0))
	assert(not rightDockResizeHandle.visible)
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setRightSidebarOpen", true)
	await process_frame
	assert(rightDockResizeHandle.visible)
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
	assertHoveredInkForCanvasTile(board, circuitEditorDock, Vector2i(0, 0))
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
	var clipboardState: Dictionary = assertBoardEditingInteractions(main, board, camera)
	var clipboardHistory: Array = clipboardState.get("history", [])
	var selectedClipboardIndex := int(clipboardState.get("selectedIndex", -1))
	await process_frame
	var clipboardDockState := getActiveDockState(main, "clipboard")
	assert(not clipboardDockState.is_empty())
	var clipboardDock := clipboardDockState.get("dock") as Control
	var clipboardDockHost := clipboardDockState.get("dockHost") as Control
	assertClipboardDock(clipboardDockHost, clipboardDock, clipboardHistory, selectedClipboardIndex)
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 1.0)
	await process_frame
	assertClipboardDock(clipboardDockHost, clipboardDock, clipboardHistory, selectedClipboardIndex)
	assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 272.0)
	await process_frame
	var clipboardHistoryGrid := clipboardDock.find_child("clipboardHistory", true, false) as GridContainer
	assert(clipboardHistoryGrid != null)
	var selectedHistoryIndex := 2
	var clipboardItemButton := clipboardHistoryGrid.get_child(selectedHistoryIndex) as Button
	assert(clipboardItemButton != null)
	clipboardItemButton.emit_signal("pressed")
	await process_frame
	assert(int(board.call("getSelectedClipboardIndex")) == selectedHistoryIndex)
	assert(board.call("getClipboardItem") == clipboardHistory[selectedHistoryIndex])
	assertClipboardDock(clipboardDockHost, clipboardDock, clipboardHistory, selectedHistoryIndex)
	sendCtrlShortcut(board, KEY_V)
	var selectedHistoryPasteAnchor := Vector2i(10, 8)
	board.call("updatePastePreview", selectedHistoryPasteAnchor)
	assert(bool(board.get("pastePreviewValid")))
	assert((board.get_node("PreviewTiles") as Node2D).get_child_count() == (clipboardHistory[selectedHistoryIndex].get("tiles", []) as Array).size())
	board.call("cancelPastePreview")
	main.call("activateDock", "eventLog")
	await process_frame
	main.call("activateDock", "clipboard")
	await process_frame
	clipboardDockState = getActiveDockState(main, "clipboard")
	clipboardDock = clipboardDockState.get("dock") as Control
	clipboardDockHost = clipboardDockState.get("dockHost") as Control
	assertClipboardDock(clipboardDockHost, clipboardDock, clipboardHistory, selectedHistoryIndex)
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
		var selectedClipboard: Dictionary = board.call("getClipboardItem")
		assert((board.get_node("PreviewTiles") as Node2D).get_child_count() == (selectedClipboard.get("tiles", []) as Array).size())
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
	if shouldCaptureDualDock():
		main.call("activateDock", "circuitEditor", "left")
		await process_frame
		main.call("activateDock", "clipboard", "right")
		await process_frame
		var dualDockState := assertDualDockState(main)
		var dualCircuitEditorDock := dualDockState.get("leftDock") as Control
		assert(String(dualCircuitEditorDock.get("dockId")) == "circuitEditor")
		assert(String((dualDockState.get("rightDock") as Control).get("dockId")) == "clipboard")
	if shouldCaptureSidebar() or shouldCaptureEventLogDock() or shouldCaptureClipboardDock() or shouldCaptureDockMenu() or shouldCaptureDualDock():
		main.call("setLeftSidebarOpen", true, false)
		main.call("setRightSidebarOpen", true, false)
		for frame in 2:
			await process_frame
	if shouldCaptureDockMenu():
		var activeDock := getDockForSide(main, "left")
		var activeDockMenuButton := activeDock.get("dockMenuButton") as Button
		activeDockMenuButton.emit_signal("pressed")
		await process_frame
	if shouldCaptureDualDock():
		var captureCircuitEditorState := getActiveDockState(main, "circuitEditor")
		assert(not captureCircuitEditorState.is_empty())
		var captureCircuitEditorDock := captureCircuitEditorState.get("dock") as Control
		assert(captureCircuitEditorDock != null)
		var captureHoveredInk := board.call("getInkAt", Vector2i(0, 0)) as Dictionary
		captureCircuitEditorDock.call("updateCursorInfo", Vector2i(0, 0), true, String(captureHoveredInk.get("title", "None")))
		main.set_process(false)
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
	if shouldCaptureInterface() or shouldCaptureSidebar() or shouldCaptureEventLogDock() or shouldCaptureClipboardDock() or shouldCaptureDockMenu() or shouldCaptureDualDock():
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
		if shouldCaptureDualDock():
			var dualDockError := interfaceImage.save_png("user://dualDockCapture.png")
			print("dualDockCapture=user://dualDockCapture.png error=", dualDockError)
	quit(error)
