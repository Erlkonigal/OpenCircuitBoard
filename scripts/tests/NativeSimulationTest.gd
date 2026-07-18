extends SceneTree

const ExtensionPath := "res://OcbSimulation.gdextension"

func _init() -> void:
	call_deferred("runNativeSimulationTest")

func runNativeSimulationTest() -> void:
	if not FileAccess.file_exists(ExtensionPath):
		push_error("OcbSimulationManifestMissing")
		quit(1)
		return
	var extension := load(ExtensionPath)
	if extension == null or not ClassDB.class_exists("OcbSimulation"):
		push_error("OcbSimulationUnavailable")
		quit(1)
		return
	var simulation := ClassDB.instantiate("OcbSimulation") as RefCounted
	if simulation == null:
		push_error("OcbSimulationInstantiateFailed")
		quit(1)
		return
	var kinds := PackedInt32Array([26, 15, 1, 16, 27])
	var initialStates := PackedInt32Array([0, 0, 0, 0, 0])
	var holds := PackedInt32Array([1, 1, 1, 1, 1])
	var meshIds := PackedInt32Array([1, 1, 1, 1, 1])
	var compileResult: Dictionary = simulation.call("compileGrid", kinds, initialStates, holds, meshIds, 5, 1)
	if not bool(compileResult.get("ok", false)):
		push_error("OcbSimulationCompileFailed:%s" % String(compileResult.get("errorReason", "Unknown")))
		quit(1)
		return
	var snapshot: PackedByteArray = simulation.call("captureState") as PackedByteArray
	if snapshot.is_empty():
		push_error("OcbSimulationSnapshotMissing")
		quit(1)
		return
	var changes: Variant = simulation.call("advanceTick")
	if not (changes is PackedInt32Array):
		push_error("OcbSimulationAdvanceInvalid")
		quit(1)
		return
	var batchChanges: Variant = simulation.call("advanceTicks", 3)
	if not (batchChanges is PackedInt32Array):
		push_error("OcbSimulationBatchAdvanceInvalid")
		quit(1)
		return
	var noOpBatchChanges: Variant = simulation.call("advanceTicks", 0)
	if not (noOpBatchChanges is PackedInt32Array) or not (noOpBatchChanges as PackedInt32Array).is_empty():
		push_error("OcbSimulationNoOpBatchAdvanceInvalid")
		quit(1)
		return
	simulation.call("advanceTicksSilent", 3)
	var timedAdvance: Variant = simulation.call("advanceTicksForDuration", 1_000, 1_000, 64)
	if not (timedAdvance is Dictionary):
		push_error("OcbSimulationTimedAdvanceInvalid")
		quit(1)
		return
	var timedAdvanceResult := timedAdvance as Dictionary
	if int(timedAdvanceResult.get("advancedTickCount", 0)) <= 0 or int(timedAdvanceResult.get("advancedTickCount", 0)) > 1_000:
		push_error("OcbSimulationTimedAdvanceCountInvalid")
		quit(1)
		return
	if int(timedAdvanceResult.get("elapsedUsec", -1)) < 0:
		push_error("OcbSimulationTimedAdvanceElapsedInvalid")
		quit(1)
		return
	var timedAdvanceAndDrain: Variant = simulation.call("advanceTicksForDurationAndDrainStateChanges", 1_000, 1_000, 64)
	if not (timedAdvanceAndDrain is Dictionary):
		push_error("OcbSimulationTimedAdvanceAndDrainInvalid")
		quit(1)
		return
	var timedAdvanceAndDrainResult := timedAdvanceAndDrain as Dictionary
	if not (timedAdvanceAndDrainResult.get("changes", null) is PackedInt32Array):
		push_error("OcbSimulationTimedAdvanceAndDrainChangesInvalid")
		quit(1)
		return
	var drainedChanges: Variant = simulation.call("drainStateChanges")
	if not (drainedChanges is PackedInt32Array):
		push_error("OcbSimulationDrainStateChangesInvalid")
		quit(1)
		return
	var drainedChangesAgain: Variant = simulation.call("drainStateChanges")
	if not (drainedChangesAgain is PackedInt32Array) or not (drainedChangesAgain as PackedInt32Array).is_empty():
		push_error("OcbSimulationDrainStateChangesNotCleared")
		quit(1)
		return
	var restoreResult: Dictionary = simulation.call("restoreState", snapshot)
	if not bool(restoreResult.get("ok", false)):
		push_error("OcbSimulationRestoreFailed:%s" % String(restoreResult.get("errorReason", "Unknown")))
		quit(1)
		return
	var restoredChanges: Variant = restoreResult.get("changes", PackedInt32Array())
	if not (restoredChanges is PackedInt32Array) or (restoredChanges as PackedInt32Array).is_empty():
		push_error("OcbSimulationRestoreChangesMissing")
		quit(1)
		return
	var asyncStart: Variant = simulation.call("startAsync", 64, 1_000)
	if not (asyncStart is Dictionary) or not bool((asyncStart as Dictionary).get("ok", false)):
		push_error("OcbSimulationAsyncStartInvalid")
		quit(1)
		return
	var asyncPollResult: Dictionary = {}
	var receivedAsyncTick := false
	for _attempt in 20:
		await create_timer(0.01).timeout
		var asyncPoll: Variant = simulation.call("pollAsync")
		if not (asyncPoll is Dictionary):
			continue
		asyncPollResult = asyncPoll as Dictionary
		if not bool(asyncPollResult.get("ok", false)) or not bool(asyncPollResult.get("running", false)):
			continue
		if int(asyncPollResult.get("advancedTickCount", 0)) <= 0 or not (asyncPollResult.get("changes", null) is PackedInt32Array):
			continue
		receivedAsyncTick = true
		break
	if not receivedAsyncTick:
		push_error("OcbSimulationAsyncPollValuesInvalid")
		quit(1)
		return
	var asyncStop: Variant = simulation.call("stopAsync")
	if not (asyncStop is Dictionary) or not bool((asyncStop as Dictionary).get("ok", false)):
		push_error("OcbSimulationAsyncStopInvalid")
		quit(1)
		return
	var statesAfterAsync: Variant = simulation.call("getStates")
	if not (statesAfterAsync is PackedInt32Array) or (statesAfterAsync as PackedInt32Array).size() != kinds.size():
		push_error("OcbSimulationAsyncStatesInvalid")
		quit(1)
		return
	quit(OK)
