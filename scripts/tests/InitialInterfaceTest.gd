extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var topBar := context.TopBar as Control
	var projectContent := context.ProjectContent as Control
	var topBarContent := context.TopBarContent as Control
	var projectTitle := context.getNodeRef(NodePath("Interface/TopBar/ProjectTitle")) as Label
	assert(context.getConfiguredViewportSize() == Vector2i(1280, 720))
	assert(context.RootWindow.size == Vector2i(1280, 720))
	assert(int(ProjectSettings.get_setting("display/window/size/min_width")) == 1280)
	assert(int(ProjectSettings.get_setting("display/window/size/min_height")) == 720)
	assert(not Input.is_using_accumulated_input())
	assert(context.BoardCamera.zoom.is_equal_approx(Vector2(0.5, 0.5)))

	var dockState: Dictionary = context.assertDualDockState(main)
	var dockHost := dockState.get("leftDockHost") as Control
	var rightDockHost := dockState.get("rightDockHost") as Control
	var circuitEditorDock := dockState.get("leftDock") as Control
	var rightDock := dockState.get("rightDock") as Control
	assert(String(circuitEditorDock.get("DockId")) == "circuitEditor")
	assert(String(rightDock.get("DockId")) == "eventLog")
	var dockContentRoot := circuitEditorDock.get_node("Background/ContentFrame/ContentRoot") as VBoxContainer
	assert(int(ProjectSettings.get_setting("display/window/size/min_height")) >= ceili(topBar.size.y + dockContentRoot.get_combined_minimum_size().y))
	assert(is_equal_approx(topBar.size.y, 62.0))
	assert(is_equal_approx(dockHost.get_global_rect().size.x, 272.0))
	assert(is_equal_approx(rightDockHost.get_global_rect().size.x, 272.0))

	for projectButtonName in ["NewProjectButton", "OpenProjectButton", "SaveProjectButton", "SaveAsProjectButton", "RecentProjectsButton"]:
		context.assertIconButton(projectContent.get_node(projectButtonName) as Button)
	assert(projectTitle.text == "New Project - Open Circuit Board")
	assert(projectTitle.clip_text)
	assert(is_equal_approx(projectTitle.get_global_rect().get_center().x, topBar.get_global_rect().get_center().x))
	var simulationModeButton := topBarContent.get_node("SimulationModeButton") as Button
	var previousTickButton := topBarContent.get_node("PreviousTickButton") as Button
	var loopStepButton := topBarContent.get_node("LoopStepButton") as Button
	var nextTickButton := topBarContent.get_node("NextTickButton") as Button
	var stepLengthControl := topBarContent.get_node("StepLengthControl") as Button
	var loopFrequencySlider := topBarContent.get_node("LoopFrequencySlider") as HSlider
	var simulationStatus := topBarContent.get_node("SimulationStatus") as Label
	var rightSidebarSeparator := topBarContent.get_node("RightSidebarSeparator") as ColorRect
	var rightSidebarToggle := topBarContent.get_node("RightSidebarToggle") as Button
	for topBarButton in [
		topBarContent.get_node("LeftSidebarToggle") as Button,
		topBarContent.get_node("RightSidebarToggle") as Button,
		previousTickButton,
		loopStepButton,
		nextTickButton,
	]:
		context.assertIconButton(topBarButton as Button)
	assert(simulationModeButton.text == "Simulate")
	assert(simulationModeButton.get_theme_font_size("font_size") == 16)
	assert(previousTickButton.disabled)
	assert(loopStepButton.disabled)
	assert(nextTickButton.disabled)
	assert(stepLengthControl.disabled)
	assert(stepLengthControl.text == "1")
	assert(is_equal_approx(loopFrequencySlider.value, 5.0))
	assert(not simulationStatus.visible)
	assert(topBarContent.get_child(topBarContent.get_child_count() - 2) == rightSidebarSeparator)
	assert(topBarContent.get_child(topBarContent.get_child_count() - 1) == rightSidebarToggle)
	assert(is_equal_approx(rightSidebarSeparator.size.x, 1.0))
	assert(rightSidebarSeparator.color.is_equal_approx(Color("263346")))
	assert(is_equal_approx(rightSidebarToggle.get_global_rect().end.x, topBarContent.get_global_rect().end.x))

	var dockResizeHandle := main.get_node("Interface/DockResizeHandle") as Control
	var rightDockResizeHandle := main.get_node("Interface/RightDockResizeHandle") as Control
	assert(dockResizeHandle.mouse_default_cursor_shape == Control.CURSOR_HSIZE)
	assert(rightDockResizeHandle.mouse_default_cursor_shape == Control.CURSOR_HSIZE)
	assert(is_equal_approx(dockResizeHandle.get_global_rect().position.x, 272.0))
	assert(is_equal_approx(rightDockResizeHandle.get_global_rect().position.x, 1002.0))
	assert(circuitEditorDock.find_children("*", "CheckBox", true, false).is_empty())
	assert(circuitEditorDock.find_children("*", "SpinBox", true, false).is_empty())
	var circuitEditorLabelTexts: Array[String] = []
	for labelNode in circuitEditorDock.find_children("*", "Label", true, false):
		circuitEditorLabelTexts.append((labelNode as Label).text)
	assert(circuitEditorLabelTexts.has("Circuit Editor"))
	assert(circuitEditorLabelTexts.has("Cursor Info"))
	for unexpectedLabel in ["CircuitEditor", "CursorInfo", "Array", "Repeat", "Angle", "OffsetX", "OffsetY"]:
		assert(not circuitEditorLabelTexts.has(unexpectedLabel))

	var dockDefinitions: Array[Dictionary] = main.get("DockDefinitions")
	assert(dockDefinitions.size() == 3)
	var circuitEditorDefinition: Dictionary = context.findDockDefinition(dockDefinitions, "circuitEditor")
	var clipboardDefinition: Dictionary = context.findDockDefinition(dockDefinitions, "clipboard")
	var eventLogDefinition: Dictionary = context.findDockDefinition(dockDefinitions, "eventLog")
	assert(not circuitEditorDefinition.is_empty())
	assert(not clipboardDefinition.is_empty())
	assert(not eventLogDefinition.is_empty())
	assert(String(circuitEditorDefinition.get("dockTitle", "")) == "Circuit Editor")
	assert(String(eventLogDefinition.get("dockTitle", "")) == "Event Log")
	for definition in [circuitEditorDefinition, clipboardDefinition, eventLogDefinition]:
		var definitionIcon := definition.get("dockIcon") as Texture2D
		assert(definitionIcon != null)
		assert(definitionIcon.get_size() == Vector2(16, 16))
	assert(board != null)
