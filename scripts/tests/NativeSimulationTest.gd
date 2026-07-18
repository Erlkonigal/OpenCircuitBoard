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
	simulation.call("advanceTicksSilent", 2)
	var silentRestoreResult: Variant = simulation.call("restoreStateSilent", snapshot)
	if not (silentRestoreResult is Dictionary) or not bool((silentRestoreResult as Dictionary).get("ok", false)):
		push_error("OcbSimulationSilentRestoreFailed")
		quit(1)
		return
	var invalidBudgetStart: Variant = simulation.call("startAsyncWithBudget", 64, 1_000, 0)
	if not (invalidBudgetStart is Dictionary) or bool((invalidBudgetStart as Dictionary).get("ok", true)):
		push_error("OcbSimulationAsyncInvalidBudgetAccepted")
		quit(1)
		return
	var asyncStart: Variant = simulation.call("startAsync", 64, 1_000)
	if not (asyncStart is Dictionary) or not bool((asyncStart as Dictionary).get("ok", false)):
		push_error("OcbSimulationAsyncStartInvalid")
		quit(1)
		return
	var asyncPollResult: Dictionary = {}
	var receivedAsyncTick := false
	var receivedAsyncChanges := false
	var receivedAsyncFullState := false
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
		if not (asyncPollResult.get("changes", PackedInt32Array()) as PackedInt32Array).is_empty():
			receivedAsyncChanges = true
			receivedAsyncFullState = bool(asyncPollResult.get("isFullState", false))
			break
	if not receivedAsyncTick:
		push_error("OcbSimulationAsyncPollValuesInvalid")
		quit(1)
		return
	if not receivedAsyncChanges:
		push_error("OcbSimulationAsyncDeltaMissing")
		quit(1)
		return
	if not receivedAsyncFullState:
		push_error("OcbSimulationAsyncFullStateFallbackMissing")
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
	var stateBytesAfterAsync: Variant = simulation.call("getStateBytes")
	if not (stateBytesAfterAsync is PackedByteArray) or (stateBytesAfterAsync as PackedByteArray).size() != kinds.size():
		push_error("OcbSimulationAsyncStateBytesInvalid")
		quit(1)
		return
	for stateIndex in (statesAfterAsync as PackedInt32Array).size():
		if int((statesAfterAsync as PackedInt32Array)[stateIndex]) != int((stateBytesAfterAsync as PackedByteArray)[stateIndex]):
			push_error("OcbSimulationAsyncStateBytesMismatch")
			quit(1)
			return
	var budgetedAsyncStart: Variant = simulation.call("startAsyncWithBudget", 64, 1_000, 200)
	if not (budgetedAsyncStart is Dictionary) or not bool((budgetedAsyncStart as Dictionary).get("ok", false)):
		push_error("OcbSimulationAsyncBudgetStartInvalid")
		quit(1)
		return
	await create_timer(0.01).timeout
	var budgetedAsyncStop: Variant = simulation.call("stopAsync")
	if not (budgetedAsyncStop is Dictionary) or not bool((budgetedAsyncStop as Dictionary).get("ok", false)):
		push_error("OcbSimulationAsyncBudgetStopInvalid")
		quit(1)
		return
	quit(OK)
