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
	quit(OK)
