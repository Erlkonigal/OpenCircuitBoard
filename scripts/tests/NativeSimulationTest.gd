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
	var idleAsyncPoll: Variant = simulation.call("pollAsync")
	if not (idleAsyncPoll is Dictionary):
		push_error("OcbSimulationIdleAsyncPollInvalid")
		quit(1)
		return
	var idleAsyncPollResult := idleAsyncPoll as Dictionary
	if not bool(idleAsyncPollResult.get("ok", false)) or bool(idleAsyncPollResult.get("isFullState", true)) or not (idleAsyncPollResult.get("changes", null) is PackedInt32Array) or not (idleAsyncPollResult.get("states", null) is PackedByteArray) or not (idleAsyncPollResult.get("changes", PackedInt32Array()) as PackedInt32Array).is_empty() or not (idleAsyncPollResult.get("states", PackedByteArray()) as PackedByteArray).is_empty():
		push_error("OcbSimulationIdleAsyncPollPayloadInvalid")
		quit(1)
		return
	var asyncStart: Variant = simulation.call("startAsync", 64, 1_000)
	if not (asyncStart is Dictionary) or not bool((asyncStart as Dictionary).get("ok", false)):
		push_error("OcbSimulationAsyncStartInvalid")
		quit(1)
		return
	var asyncPollResult: Dictionary = {}
	var receivedAsyncTick := false
	var receivedAsyncFullState := false
	for _attempt in 20:
		await create_timer(0.01).timeout
		var asyncPoll: Variant = simulation.call("pollAsync")
		if not (asyncPoll is Dictionary):
			continue
		asyncPollResult = asyncPoll as Dictionary
		if not bool(asyncPollResult.get("ok", false)) or not bool(asyncPollResult.get("running", false)):
			continue
		if int(asyncPollResult.get("advancedTickCount", 0)) <= 0 or not (asyncPollResult.get("isFullState", null) is bool) or not (asyncPollResult.get("changes", null) is PackedInt32Array) or not (asyncPollResult.get("states", null) is PackedByteArray):
			continue
		receivedAsyncTick = true
		var asyncChanges := asyncPollResult.get("changes", PackedInt32Array()) as PackedInt32Array
		var asyncStates := asyncPollResult.get("states", PackedByteArray()) as PackedByteArray
		if bool(asyncPollResult.get("isFullState", false)):
			if not asyncChanges.is_empty() or asyncStates.size() != kinds.size():
				push_error("OcbSimulationAsyncFullStatePayloadInvalid")
				quit(1)
				return
			receivedAsyncFullState = true
			break
		if not asyncStates.is_empty():
			push_error("OcbSimulationAsyncDeltaPayloadInvalid")
			quit(1)
			return
	if not receivedAsyncTick:
		push_error("OcbSimulationAsyncPollValuesInvalid")
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
	var sparseKinds := PackedInt32Array()
	var sparseInitialStates := PackedInt32Array()
	var sparseHolds := PackedInt32Array()
	var sparseMeshIds := PackedInt32Array()
	sparseKinds.resize(64)
	sparseInitialStates.resize(64)
	sparseHolds.resize(64)
	sparseMeshIds.resize(64)
	sparseKinds[0] = 25
	var sparseCompileResult: Dictionary = simulation.call(
		"compileGrid",
		sparseKinds,
		sparseInitialStates,
		sparseHolds,
		sparseMeshIds,
		64,
		1
	)
	if not bool(sparseCompileResult.get("ok", false)):
		push_error("OcbSimulationSparseCompileFailed")
		quit(1)
		return
	var sparseAsyncStart: Variant = simulation.call("startAsync", 1, 1_000)
	if not (sparseAsyncStart is Dictionary) or not bool((sparseAsyncStart as Dictionary).get("ok", false)):
		push_error("OcbSimulationSparseAsyncStartInvalid")
		quit(1)
		return
	var sparseToggle: Variant = simulation.call("toggleLatch", 0)
	if not (sparseToggle is Dictionary) or not bool((sparseToggle as Dictionary).get("ok", false)):
		push_error("OcbSimulationSparseAsyncToggleInvalid")
		quit(1)
		return
	var receivedAsyncDelta := false
	for _attempt in 20:
		await create_timer(0.01).timeout
		var sparseAsyncPoll: Variant = simulation.call("pollAsync")
		if not (sparseAsyncPoll is Dictionary):
			continue
		var sparseAsyncPollResult := sparseAsyncPoll as Dictionary
		if not bool(sparseAsyncPollResult.get("ok", false)) or not bool(sparseAsyncPollResult.get("running", false)):
			continue
		if not (sparseAsyncPollResult.get("isFullState", null) is bool) or not (sparseAsyncPollResult.get("changes", null) is PackedInt32Array) or not (sparseAsyncPollResult.get("states", null) is PackedByteArray):
			continue
		var sparseChanges := sparseAsyncPollResult.get("changes", PackedInt32Array()) as PackedInt32Array
		var sparseStates := sparseAsyncPollResult.get("states", PackedByteArray()) as PackedByteArray
		if bool(sparseAsyncPollResult.get("isFullState", false)):
			push_error("OcbSimulationAsyncDeltaUnexpectedFullState")
			quit(1)
			return
		if sparseChanges.is_empty():
			continue
		if not sparseStates.is_empty():
			push_error("OcbSimulationAsyncDeltaPayloadInvalid")
			quit(1)
			return
		receivedAsyncDelta = true
		break
	if not receivedAsyncDelta:
		push_error("OcbSimulationAsyncDeltaMissing")
		quit(1)
		return
	var sparseAsyncStop: Variant = simulation.call("stopAsync")
	if not (sparseAsyncStop is Dictionary) or not bool((sparseAsyncStop as Dictionary).get("ok", false)):
		push_error("OcbSimulationSparseAsyncStopInvalid")
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
