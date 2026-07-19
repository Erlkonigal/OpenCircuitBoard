extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var boardViewport := context.BoardViewport as SubViewportContainer
	var subViewport := context.BoardSubViewport as SubViewport
	var camera := context.BoardCamera as Camera2D
	var initialCanvasRect := boardViewport.get_global_rect()
	var initialSubViewportSize := subViewport.size
	var initialCameraCenter := camera.get_screen_center_position()
	var initialCameraZoom := camera.zoom
	var fixtureState := FrontendTestFixtures.setupVisualBoardWithClipboard(board)
	var clipboardHistory: Array = fixtureState.get("history", [])
	var selectedClipboardIndex := int(fixtureState.get("selectedIndex", -1))
	await context.waitFrames(1)
	main.call("activateDock", "clipboard")
	await context.waitFrames(1)
	var clipboardDockState: Dictionary = context.getActiveDockState(main, "clipboard")
	assert(not clipboardDockState.is_empty())
	var clipboardDock := clipboardDockState.get("dock") as Control
	var clipboardDockHost := clipboardDockState.get("dockHost") as Control
	context.assertClipboardDock(clipboardDockHost, clipboardDock, clipboardHistory, selectedClipboardIndex)
	context.assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	main.call("setDockWidth", 1.0)
	await context.waitFrames(1)
	context.assertClipboardDock(clipboardDockHost, clipboardDock, clipboardHistory, selectedClipboardIndex)
	main.call("setDockWidth", 272.0)
	await context.waitFrames(1)
	var clipboardHistoryGrid := clipboardDock.find_child("ClipboardHistory", true, false) as GridContainer
	assert(clipboardHistoryGrid != null)
	var selectedHistoryIndex := 2
	var clipboardItemButton := clipboardHistoryGrid.get_child(selectedHistoryIndex) as Button
	clipboardItemButton.emit_signal("pressed")
	await context.waitFrames(1)
	assert(int(board.call("getSelectedClipboardIndex")) == selectedHistoryIndex)
	assert(board.call("getClipboardItem") == clipboardHistory[selectedHistoryIndex])
	context.assertClipboardDock(clipboardDockHost, clipboardDock, clipboardHistory, selectedHistoryIndex)
	context.sendCtrlShortcut(board, KEY_V)
	var selectedHistoryPasteAnchor := Vector2i(10, 8)
	board.call("updatePastePreview", selectedHistoryPasteAnchor)
	assert(bool(board.get("PastePreviewValid")))
	assert((board.get_node("PreviewTiles") as Node2D).get_child_count() == (clipboardHistory[selectedHistoryIndex].get("tiles", []) as Array).size())
	board.call("cancelPastePreview")
	main.call("activateDock", "eventLog")
	await context.waitFrames(1)
	main.call("activateDock", "clipboard")
	await context.waitFrames(1)
	clipboardDockState = context.getActiveDockState(main, "clipboard")
	clipboardDock = clipboardDockState.get("dock") as Control
	clipboardDockHost = clipboardDockState.get("dockHost") as Control
	context.assertClipboardDock(clipboardDockHost, clipboardDock, clipboardHistory, selectedHistoryIndex)
	var oversizedHistory := FrontendTestFixtures.makeOversizedClipboardHistory()
	clipboardDock.call("setClipboardHistory", oversizedHistory, 0)
	await context.waitFrames(1)
	context.assertClipboardDock(clipboardDockHost, clipboardDock, oversizedHistory, 0)
	var oversizedHistoryGrid := clipboardDock.find_child("ClipboardHistory", true, false) as GridContainer
	assert(oversizedHistoryGrid != null)
	for index in oversizedHistory.size():
		var item := oversizedHistory[index]
		var itemButton := oversizedHistoryGrid.get_child(index) as Button
		var preview := itemButton.find_child("ClipboardPreview", true, false) as Control
		assert(preview != null)
		assert(preview.clip_contents)
		assert(preview.has_method("getPreviewRect"))
		var previewRect: Rect2 = preview.call("getPreviewRect")
		var dimensions: Vector2i = item.get("boundsSize", Vector2i.ONE)
		var availableRect := Rect2(Vector2(4.0, 4.0), preview.size - Vector2(8.0, 8.0))
		assert(previewRect.position.x >= availableRect.position.x - 0.01)
		assert(previewRect.position.y >= availableRect.position.y - 0.01)
		assert(previewRect.end.x <= availableRect.end.x + 0.01)
		assert(previewRect.end.y <= availableRect.end.y + 0.01)
		assert(is_equal_approx(previewRect.size.x / previewRect.size.y, float(dimensions.x) / float(dimensions.y)))
