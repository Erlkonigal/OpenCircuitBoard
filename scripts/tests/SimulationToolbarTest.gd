extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var board := context.CircuitBoard as Node2D
	var topBarContent := context.TopBarContent as Control
	var simulationModeButton := topBarContent.get_node("SimulationModeButton") as Button
	var previousTickButton := topBarContent.get_node("PreviousTickButton") as Button
	var loopStepButton := topBarContent.get_node("LoopStepButton") as Button
	var nextTickButton := topBarContent.get_node("NextTickButton") as Button
	var stepLengthControl := topBarContent.get_node("StepLengthControl") as Button
	var loopFrequencySlider := topBarContent.get_node("LoopFrequencySlider") as HSlider
	var simulationStatus := topBarContent.get_node("SimulationStatus") as Label
	assert(simulationModeButton.text == "Simulate")
	assert(previousTickButton.disabled)
	assert(loopStepButton.disabled)
	assert(nextTickButton.disabled)
	assert(stepLengthControl.disabled)
	assert(loopFrequencySlider.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(loopFrequencySlider.focus_mode == Control.FOCUS_NONE)
	assert(not simulationStatus.visible)
	main.call("enterSimulation")
	assert(bool(main.get("IsSimulating")))
	assert(bool(main.get("IsLooping")))
	assert(not bool(board.get("EditorInputEnabled")))
	assert(simulationModeButton.text == "Edit")
	assert(simulationStatus.visible)
	assert(simulationStatus.text == "~5 TPS")
	assert(stepLengthControl.disabled)
	assert(is_equal_approx(loopFrequencySlider.value, 5.0))
	assert(loopFrequencySlider.mouse_filter == Control.MOUSE_FILTER_STOP)
	assert(loopFrequencySlider.focus_mode == Control.FOCUS_ALL)
	main.call("setLoopFrequency", 7.0)
	assert(simulationStatus.text == "~7 TPS")
	assert(is_equal_approx(loopFrequencySlider.value, 7.0))
	main.call("toggleLoopStepMode")
	assert(not bool(main.get("IsLooping")))
	assert(simulationStatus.text == "Step Mode")
	assert(previousTickButton.disabled)
	assert(not nextTickButton.disabled)
	assert(not stepLengthControl.disabled)
	assert(loopFrequencySlider.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(loopFrequencySlider.focus_mode == Control.FOCUS_NONE)
	main.call("setSimulationStepLength", 3)
	assert(stepLengthControl.text == "3")
	main.call("showNextSimulationTick")
	assert(int(main.get("SimulationTick")) == 3)
	assert(not previousTickButton.disabled)
	main.call("showPreviousSimulationTick")
	assert(int(main.get("SimulationTick")) == 0)
	main.call("leaveSimulation")
	assert(not bool(main.get("IsSimulating")))
	assert(bool(board.get("EditorInputEnabled")))
	assert(simulationModeButton.text == "Simulate")
	assert(not simulationStatus.visible)
	assert(stepLengthControl.disabled)
	assert(loopFrequencySlider.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(loopFrequencySlider.focus_mode == Control.FOCUS_NONE)
	main.call("setSimulationStepLength", 1)
	assert(stepLengthControl.text == "1")
