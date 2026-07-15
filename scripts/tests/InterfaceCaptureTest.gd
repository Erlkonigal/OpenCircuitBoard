extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	var simulationModeButton := context.getNodeRef(NodePath("Interface/TopBar/Content/SimulationModeButton")) as Button
	var previousTickButton := context.getNodeRef(NodePath("Interface/TopBar/Content/PreviousTickButton")) as Button
	var loopStepButton := context.getNodeRef(NodePath("Interface/TopBar/Content/LoopStepButton")) as Button
	var nextTickButton := context.getNodeRef(NodePath("Interface/TopBar/Content/NextTickButton")) as Button
	var stepLengthControl := context.getNodeRef(NodePath("Interface/TopBar/Content/StepLengthControl")) as Button
	var loopFrequencySlider := context.getNodeRef(NodePath("Interface/TopBar/Content/LoopFrequencySlider")) as HSlider
	for child in context.ProjectContent.get_children():
		var projectButton := child as Button
		if projectButton:
			context.assertTopBarIconButtonStyle(projectButton)
	for topBarButton in [
		context.TopBarContent.get_node("LeftSidebarToggle") as Button,
		context.TopBarContent.get_node("RightSidebarToggle") as Button,
		previousTickButton,
		loopStepButton,
		nextTickButton,
	]:
		context.assertTopBarIconButtonStyle(topBarButton)
	var simulationNormalStyle := simulationModeButton.get_theme_stylebox("normal") as StyleBoxFlat
	var simulationHoverStyle := simulationModeButton.get_theme_stylebox("hover") as StyleBoxFlat
	var stepLengthNormalStyle := stepLengthControl.get_theme_stylebox("normal") as StyleBoxFlat
	assert(simulationNormalStyle.bg_color.is_equal_approx(Color("00c875")))
	assert(simulationHoverStyle.bg_color.is_equal_approx(Color("18dd8a")))
	assert(stepLengthNormalStyle.bg_color.is_equal_approx(Color("2a3548")))
	assert(loopFrequencySlider.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	context.MainSceneRoot.call("setLeftSidebarOpen", false, false)
	await context.waitFrames(2)
	return {}
