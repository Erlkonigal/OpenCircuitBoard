extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.main as Control
	var board := context.board as Node2D
	var boardViewport := context.boardViewport as SubViewportContainer
	var subViewport := context.subViewport as SubViewport
	var camera := context.camera as Camera2D
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
	var clipboardHistoryGrid := clipboardDock.find_child("clipboardHistory", true, false) as GridContainer
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
	assert(bool(board.get("pastePreviewValid")))
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
