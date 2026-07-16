extends RefCounted

const TestMaximumTps := 1_000_000.0
const TestDecadeCount := 6
const TpsRelativeTolerance := 0.015

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.MainSceneRoot as Control
	var topBarContent := context.TopBarContent as Control
	var loopFrequencySlider := topBarContent.get_node("LoopFrequencySlider") as HSlider
	var loopFrequencyInput := topBarContent.get_node("LoopFrequencyInput") as LineEdit
	var simulationStatus := topBarContent.get_node("SimulationStatus") as Label

	# A sampled backend capacity defines the top of the logarithmic scale.
	applyMeasuredCapacity(main, TestMaximumTps)
	var maximumTps := getLoopFrequencyMaximumTps(main)
	assertTpsNear(maximumTps, TestMaximumTps)
	assert(is_equal_approx(loopFrequencySlider.min_value, 0.0))
	assertTpsNear(loopFrequencySlider.max_value, maximumTps)
	assert(loopFrequencySlider.visible)
	assert(not loopFrequencyInput.visible)
	assertLogarithmicSliderScale(main, loopFrequencySlider, maximumTps)

	main.set("SimulationTicksPerSecond", 1_240.0)
	assert(main.call("getSimulationThroughputText") == "1.2K TPS")
	main.set("SimulationTicksPerSecond", 1_240_000.0)
	assert(main.call("getSimulationThroughputText") == "1.2M TPS")
	main.set("SimulationTicksPerSecond", 999_950.0)
	assert(main.call("getSimulationThroughputText") == "1.0M TPS")

	main.call("enterSimulation")
	assert((main.get("SimulationTimeline") as Array).is_empty())
	assertTpsStatus(simulationStatus)
	# Do not let the background capacity probe make the input assertions depend on the host.
	applyMeasuredCapacity(main, TestMaximumTps)
	maximumTps = getLoopFrequencyMaximumTps(main)
	loopFrequencySlider.value = maximumTps * 0.5
	assert(not bool(main.get("IsLoopFrequencyFullSpeed")))
	assertTpsNear(float(main.get("LoopFrequency")), 1_000.0)

	context.RootWindow.push_input(context.makeMouseButtonEvent(loopFrequencySlider, MOUSE_BUTTON_RIGHT, true))
	context.RootWindow.push_input(context.makeMouseButtonEvent(loopFrequencySlider, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames(1)
	assert(not loopFrequencySlider.visible)
	assert(loopFrequencyInput.visible)
	assert(loopFrequencyInput.editable)

	loopFrequencyInput.text = "10000"
	loopFrequencyInput.emit_signal("text_submitted", loopFrequencyInput.text)
	await context.waitFrames(1)
	assert(not bool(main.get("IsLoopFrequencyFullSpeed")))
	assertTpsNear(float(main.get("LoopFrequency")), 10_000.0)
	assertTpsStatus(simulationStatus)

	context.RootWindow.push_input(context.makeMouseButtonEvent(loopFrequencyInput, MOUSE_BUTTON_RIGHT, true))
	context.RootWindow.push_input(context.makeMouseButtonEvent(loopFrequencyInput, MOUSE_BUTTON_RIGHT, false))
	await context.waitFrames(1)
	assert(loopFrequencySlider.visible)
	assert(not loopFrequencyInput.visible)
	maximumTps = getLoopFrequencyMaximumTps(main)
	var expectedTenThousandPosition := maximumTps * 4.0 / (log(maximumTps) / log(10.0))
	assert(absf(loopFrequencySlider.value - expectedTenThousandPosition) <= maxf(1.0, maximumTps * 0.015))

	main.call("toggleLoopStepMode")
	assert((main.get("SimulationTimeline") as Array).size() == 1)
	assert(loopFrequencySlider.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(loopFrequencySlider.focus_mode == Control.FOCUS_NONE)

func assertLogarithmicSliderScale(main: Control, slider: HSlider, maximumTps: float) -> void:
	var previousTps := 0.0
	for exponent in range(TestDecadeCount + 1):
		slider.value = maximumTps * float(exponent) / float(TestDecadeCount)
		var expectedTps := pow(10.0, float(exponent))
		var actualTps := float(main.get("LoopFrequency"))
		assertTpsNear(actualTps, expectedTps)
		if exponent > 0:
			assertTpsNear(actualTps / previousTps, 10.0)
		assert(bool(main.get("IsLoopFrequencyFullSpeed")) == (exponent == TestDecadeCount))
		previousTps = actualTps

	# The final movement is another logarithmic interval, not a special multi-million-TPS jump.
	slider.value = maximumTps * (5.9 / float(TestDecadeCount))
	var justBeforeMaximumTps := float(main.get("LoopFrequency"))
	assertTpsNear(justBeforeMaximumTps, pow(10.0, 5.9))
	slider.value = maximumTps
	assert(bool(main.get("IsLoopFrequencyFullSpeed")))
	assertTpsNear(float(main.get("LoopFrequency")), maximumTps)
	assert(float(main.get("LoopFrequency")) / justBeforeMaximumTps < 1.3)

func getLoopFrequencyMaximumTps(main: Control) -> float:
	var maximumTps := float(main.call("getLoopFrequencyMaximumTps"))
	assert(maximumTps >= 1.0)
	return maximumTps

func applyMeasuredCapacity(main: Control, measuredTps: float) -> void:
	# Capacity increases are intentionally smoothed; feed a stable measurement until it settles.
	for _sampleIndex in 48:
		main.call("updateLoopFrequencyMaximum", measuredTps)

func assertTpsNear(actualTps: float, expectedTps: float) -> void:
	assert(absf(actualTps - expectedTps) <= maxf(0.1, expectedTps * TpsRelativeTolerance))

func assertTpsStatus(status: Label) -> void:
	assert(status.visible)
	assert(not status.text.is_empty())
	assert(status.text.contains("TPS"))
