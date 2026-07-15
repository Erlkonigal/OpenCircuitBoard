extends RefCounted

const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var boardViewport := context.BoardViewport as SubViewportContainer
	var subViewport := context.BoardSubViewport as SubViewport
	var camera := context.BoardCamera as Camera2D
	var initialCanvasRect := boardViewport.get_global_rect()
	var initialSubViewportSize := subViewport.size
	var initialCameraCenter := camera.get_screen_center_position()
	var initialCameraZoom := camera.zoom
	var initialState: Dictionary = context.assertDualDockState(main)
	var dockHost := initialState.get("leftDockHost") as Control
	var circuitEditorDock := initialState.get("leftDock") as Control
	circuitEditorDock.call("selectInk", InkRegistry.getInk("traceBlue"), false)
	circuitEditorDock.call("selectInk", InkRegistry.getInk("busMagenta"), false)
	circuitEditorDock.call("recordEvent", "HistoryMarkerOne")
	await context.waitFrames(1)
	var dockMenu := main.get("DockMenu") as PopupPanel
	var dockMenuGrid := dockMenu.get_child(0) as GridContainer
	var circuitEditorMenuButton: Button = context.findDockMenuButton(dockMenuGrid, "Circuit Editor")
	var eventLogMenuButton: Button = context.findDockMenuButton(dockMenuGrid, "Event Log")
	assert(circuitEditorMenuButton != null)
	assert(eventLogMenuButton != null)
	var dockMenuButton := circuitEditorDock.get("DockMenuButton") as Button
	dockMenuButton.emit_signal("pressed")
	await context.waitFrames(1)
	eventLogMenuButton.emit_signal("pressed")
	await context.waitFrames(1)
	assert(dockHost.get_child_count() == 1)
	var eventLogDock := dockHost.get_child(0) as Control
	assert(String(eventLogDock.get("DockId")) == "eventLog")
	context.assertDockLayout(dockHost, eventLogDock)
	context.assertCanvasViewIsStable(boardViewport, subViewport, camera, initialCanvasRect, initialSubViewportSize, initialCameraCenter, initialCameraZoom)
	var eventLogDockMenuButton := eventLogDock.get("DockMenuButton") as Button
	context.assertIconButton(eventLogDockMenuButton)
	assert(eventLogDockMenuButton.icon == eventLogMenuButton.icon)
	var eventLogContent := eventLogDock.get_node("Background/ContentFrame/ContentRoot") as VBoxContainer
	var eventLogHeader := eventLogContent.get_child(0) as HBoxContainer
	assert((eventLogHeader.get_child(1) as Label).text == "Event Log")
	var eventLog := eventLogDock.get_node("Background/ContentFrame/ContentRoot/EventLog") as RichTextLabel
	assert(eventLog.get_parsed_text().contains("HistoryMarkerOne"))
	main.call("setDockWidth", 1.0)
	await context.waitFrames(1)
	context.assertDockLayout(dockHost, eventLogDock)
	main.call("setDockWidth", 272.0)
	eventLogDockMenuButton.emit_signal("pressed")
	await context.waitFrames(1)
	circuitEditorMenuButton.emit_signal("pressed")
	await context.waitFrames(1)
	var restoredCircuitEditorDock := dockHost.get_child(0) as Control
	assert(String(restoredCircuitEditorDock.get("DockId")) == "circuitEditor")
	context.assertDockLayout(dockHost, restoredCircuitEditorDock)
	var restoredInkButtons: Dictionary = restoredCircuitEditorDock.get("InkButtons")
	context.assertInkButton(restoredInkButtons.get("trace") as Button, InkRegistry.getInk("traceBlue"), false)
	context.assertInkButton(restoredInkButtons.get("bus") as Button, InkRegistry.getInk("busMagenta"), true)
	restoredCircuitEditorDock.call("recordEvent", "HistoryMarkerTwo")
	await context.waitFrames(1)
	main.call("activateDock", "eventLog")
	await context.waitFrames(1)
	eventLogDock = dockHost.get_child(0) as Control
	eventLog = eventLogDock.get_node("Background/ContentFrame/ContentRoot/EventLog") as RichTextLabel
	var eventLogText := eventLog.get_parsed_text()
	var firstMarkerIndex := eventLogText.find("HistoryMarkerOne")
	var secondMarkerIndex := eventLogText.find("HistoryMarkerTwo")
	assert(firstMarkerIndex >= 0)
	assert(secondMarkerIndex > firstMarkerIndex)
	assert(eventLogText.find("HistoryMarkerOne", firstMarkerIndex + 1) == -1)
	assert(eventLogText.find("HistoryMarkerTwo", secondMarkerIndex + 1) == -1)
