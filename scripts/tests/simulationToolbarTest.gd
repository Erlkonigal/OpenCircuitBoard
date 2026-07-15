extends RefCounted

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.main as Control
	var board := context.board as Node2D
	var topBarContent := context.topBarContent as Control
	var simulationModeButton := topBarContent.get_node("simulationModeButton") as Button
	var previousTickButton := topBarContent.get_node("previousTickButton") as Button
	var loopStepButton := topBarContent.get_node("loopStepButton") as Button
	var nextTickButton := topBarContent.get_node("nextTickButton") as Button
	var stepLengthControl := topBarContent.get_node("stepLengthControl") as Button
	var loopFrequencySlider := topBarContent.get_node("loopFrequencySlider") as HSlider
	var simulationStatus := topBarContent.get_node("simulationStatus") as Label
	assert(simulationModeButton.text == "Simulate")
	assert(previousTickButton.disabled)
	assert(loopStepButton.disabled)
	assert(nextTickButton.disabled)
	assert(stepLengthControl.disabled)
	assert(not simulationStatus.visible)
	main.call("enterSimulation")
	assert(bool(main.get("isSimulating")))
	assert(bool(main.get("isLooping")))
	assert(not bool(board.get("editorInputEnabled")))
	assert(simulationModeButton.text == "Edit")
	assert(simulationStatus.visible)
	assert(simulationStatus.text == "~5 TPS")
	assert(is_equal_approx(loopFrequencySlider.value, 5.0))
	main.call("setLoopFrequency", 7.0)
	assert(simulationStatus.text == "~7 TPS")
	assert(is_equal_approx(loopFrequencySlider.value, 7.0))
	main.call("toggleLoopStepMode")
	assert(not bool(main.get("isLooping")))
	assert(simulationStatus.text == "Step Mode")
	assert(previousTickButton.disabled)
	assert(not nextTickButton.disabled)
	assert(not stepLengthControl.disabled)
	main.call("setSimulationStepLength", 3)
	assert(stepLengthControl.text == "3")
	main.call("showNextSimulationTick")
	assert(int(main.get("simulationTick")) == 3)
	assert(not previousTickButton.disabled)
	main.call("showPreviousSimulationTick")
	assert(int(main.get("simulationTick")) == 0)
	main.call("leaveSimulation")
	assert(not bool(main.get("isSimulating")))
	assert(bool(board.get("editorInputEnabled")))
	assert(simulationModeButton.text == "Simulate")
	assert(not simulationStatus.visible)
	main.call("setSimulationStepLength", 1)
	assert(stepLengthControl.text == "1")
