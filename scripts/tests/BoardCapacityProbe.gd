extends SceneTree

const ProjectManager := preload("res://scripts/ProjectManager.gd")
const SimulationBridge := preload("res://scripts/SimulationBridge.gd")
const MainScene := preload("res://Main.tscn")

const BoardPath := NodePath("BoardViewport/SubViewport/CircuitBoard")
const ProbeBatchTickCount := 4_096
const ProbeDurationUsec := 250_000
const ProbeSampleCount := 3

func _init() -> void:
	call_deferred("runProbe")

func runProbe() -> void:
	var projectPath := getProjectPath()
	if projectPath.is_empty():
		fail("BoardCapacityProbe requires --boardPath=<path-to-project.ocb>.")
		return
	var main := MainScene.instantiate() as Control
	if main == null:
		fail("BoardCapacityProbe could not instantiate Main.tscn.")
		return
	root.add_child(main)
	for _frame in 5:
		await process_frame
	var board := main.get_node_or_null(BoardPath)
	if board == null:
		fail("BoardCapacityProbe could not find the circuit board.")
		return
	var projectManager := ProjectManager.new()
	var loadResult := projectManager.loadProject(board, projectPath)
	if not bool(loadResult.get("ok", false)):
		fail("BoardCapacityProbe could not load the project: %s" % String(loadResult.get("message", "ProjectOpenFailed")))
		return
	if hasArgument("--editorProbe"):
		main.call("enterSimulation")
		if not bool(main.get("IsSimulating")):
			fail("BoardCapacityProbe could not enter simulation mode.")
			return
		var capacityTicksPerSecond := float(main.get("LoopFrequencyMaximumTps"))
		var editorRunSeconds := getPositiveFloatArg("--editorRunSeconds", 0.0)
		if editorRunSeconds > 0.0:
			main.call("setLoopFrequency", capacityTicksPerSecond)
			await create_timer(editorRunSeconds).timeout
			print(
				"Editor loop: capacityTicksPerSecond=%.2f measuredTicksPerSecond=%.2f" % [
					capacityTicksPerSecond,
					float(main.get("SimulationTicksPerSecond")),
				]
			)
		else:
			print("Editor capacity probe: ticksPerSecond=%.2f" % capacityTicksPerSecond)
		main.queue_free()
		quit(OK)
		return
	var simulation := SimulationBridge.new()
	var compileResult := simulation.compile(board)
	if not bool(compileResult.get("ok", false)):
		fail("BoardCapacityProbe could not compile the project: %s" % String(compileResult.get("errorReason", "SimulationCompileFailed")))
		return
	var snapshotResult := simulation.captureState()
	if not bool(snapshotResult.get("ok", false)):
		fail("BoardCapacityProbe could not capture the initial state.")
		return
	var probeBatchTickCount := getPositiveIntArg("--probeBatchTicks", ProbeBatchTickCount)
	var probeDurationUsec := getPositiveIntArg("--probeDurationUsec", ProbeDurationUsec)
	var probeSampleCount := getPositiveIntArg("--probeSamples", ProbeSampleCount)
	var warmupResult := simulation.advanceTicksForDuration(mini(25_000, probeDurationUsec), 2147483647, probeBatchTickCount)
	if not bool(warmupResult.get("ok", false)):
		fail("BoardCapacityProbe could not warm up the simulation backend.")
		return
	var restoreResult := simulation.restoreState(snapshotResult.get("snapshot", PackedByteArray()) as PackedByteArray)
	if not bool(restoreResult.get("ok", false)):
		fail("BoardCapacityProbe could not restore the initial state.")
		return
	var ticksPerSecondSamples: Array[float] = []
	for sampleIndex in probeSampleCount:
		var advanceResult := simulation.advanceTicksForDuration(probeDurationUsec, 2147483647, probeBatchTickCount)
		if not bool(advanceResult.get("ok", false)):
			fail("BoardCapacityProbe lost the simulation backend.")
			return
		var advancedTickCount := int(advanceResult.get("advancedTickCount", 0))
		var elapsedUsec := maxi(1, int(advanceResult.get("elapsedUsec", 0)))
		ticksPerSecondSamples.append(float(advancedTickCount) * 1_000_000.0 / float(elapsedUsec))
		restoreResult = simulation.restoreState(snapshotResult.get("snapshot", PackedByteArray()) as PackedByteArray)
		if not bool(restoreResult.get("ok", false)):
			fail("BoardCapacityProbe could not restore the initial state between samples.")
			return
	ticksPerSecondSamples.sort()
	var medianTicksPerSecond := ticksPerSecondSamples[ticksPerSecondSamples.size() / 2]
	print(
		"Board capacity probe: medianTicksPerSecond=%.2f minTicksPerSecond=%.2f maxTicksPerSecond=%.2f durationUsec=%d samples=%d batchTicks=%d" % [
			medianTicksPerSecond,
			ticksPerSecondSamples.front(),
			ticksPerSecondSamples.back(),
			probeDurationUsec,
			probeSampleCount,
			probeBatchTickCount,
		]
	)
	main.queue_free()
	quit(OK)

func getProjectPath() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--boardPath="):
			return argument.trim_prefix("--boardPath=")
	return ""

func getPositiveIntArg(argumentName: String, defaultValue: int) -> int:
	var argumentPrefix := "%s=" % argumentName
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(argumentPrefix):
			return maxi(1, argument.trim_prefix(argumentPrefix).to_int())
	return defaultValue

func getPositiveFloatArg(argumentName: String, defaultValue: float) -> float:
	var argumentPrefix := "%s=" % argumentName
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(argumentPrefix):
			return maxf(0.0, argument.trim_prefix(argumentPrefix).to_float())
	return defaultValue

func hasArgument(argumentName: String) -> bool:
	return OS.get_cmdline_user_args().has(argumentName)

func fail(message: String) -> void:
	push_error(message)
	quit(1)
