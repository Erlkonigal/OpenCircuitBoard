extends RefCounted
class_name SimulationBridge

const NativeExtensionPath := "res://OcbSimulation.gdextension"
const KindEmpty := 0
const KindTrace := 1
const KindTraceRed := 2
const KindTraceGreen := 3
const KindTraceBlue := 4
const KindTraceCyan := 5
const KindTraceMagenta := 6
const KindBus := 7
const KindBusRed := 8
const KindBusGreen := 9
const KindBusYellow := 10
const KindBusCyan := 11
const KindBusMagenta := 12
const KindCross := 13
const KindMesh := 14
const KindRead := 15
const KindWrite := 16
const KindBuffer := 17
const KindAnd := 18
const KindOr := 19
const KindXor := 20
const KindNot := 21
const KindNand := 22
const KindNor := 23
const KindXnor := 24
const KindLatch := 25
const KindClock := 26
const KindLed := 27

const KindByToolId := {
	"trace": KindTrace,
	"traceRed": KindTraceRed,
	"traceGreen": KindTraceGreen,
	"traceBlue": KindTraceBlue,
	"traceCyan": KindTraceCyan,
	"traceMagenta": KindTraceMagenta,
	"bus": KindBus,
	"busRed": KindBusRed,
	"busGreen": KindBusGreen,
	"busYellow": KindBusYellow,
	"busCyan": KindBusCyan,
	"busMagenta": KindBusMagenta,
	"cross": KindCross,
	"mesh": KindMesh,
	"read": KindRead,
	"write": KindWrite,
	"buffer": KindBuffer,
	"and": KindAnd,
	"or": KindOr,
	"xor": KindXor,
	"not": KindNot,
	"nand": KindNand,
	"nor": KindNor,
	"xnor": KindXnor,
	"latch": KindLatch,
	"clock": KindClock,
	"led": KindLed,
}

var NativeExtension: Resource
var NativeSimulation: Object
var GridWidth := 0
var GridHeight := 0
var GridOrigin := Vector2i.ZERO
var CoordinatesByCellIndex: Dictionary[int, Vector2i] = {}

func compile(board: Node) -> Dictionary:
	release()
	var gridResult := buildGrid(board)
	if not bool(gridResult.get("ok", false)):
		return gridResult
	if not loadNativeExtension():
		return failAndRelease(-1, -1, "BackendUnavailable")
	NativeSimulation = ClassDB.instantiate("OcbSimulation")
	if NativeSimulation == null:
		return failAndRelease(-1, -1, "BackendUnavailable")
	var resultVariant: Variant = NativeSimulation.call(
		"compileGrid",
		gridResult["kinds"],
		gridResult["initialStates"],
		gridResult["clockHoldTicks"],
		gridResult["meshIds"],
		GridWidth,
		GridHeight
	)
	if not (resultVariant is Dictionary):
		return failAndRelease(-1, -1, "OcbSimulationCompileResultInvalid")
	var result := resultVariant as Dictionary
	if bool(result.get("ok", false)):
		return {"ok": true}
	return failAndRelease(
		int(result.get("errorX", -1)),
		int(result.get("errorY", -1)),
		String(result.get("errorReason", "OcbSimulationCompileFailed")),
		true
	)

func getCurrentUpdates() -> Dictionary:
	if not hasNativeSimulation():
		return makeFailure(-1, -1, "BackendUnavailable")
	var statesVariant: Variant = NativeSimulation.call("getStates")
	if not (statesVariant is PackedInt32Array):
		return makeFailure(-1, -1, "OcbSimulationStatesInvalid")
	return {
		"ok": true,
		"updates": makeFullStateUpdates(statesVariant as PackedInt32Array),
	}

func toggleLatchAt(coordinates: Vector2i) -> Dictionary:
	if not hasNativeSimulation():
		return makeFailure(-1, -1, "BackendUnavailable")
	var cellIndex := getCellIndex(coordinates)
	if cellIndex < 0:
		return makeFailure(coordinates.x, coordinates.y, "SimulationLatchOutsideGrid", false, true)
	var resultVariant: Variant = NativeSimulation.call("toggleLatch", cellIndex)
	if not (resultVariant is Dictionary):
		return makeFailure(coordinates.x, coordinates.y, "OcbSimulationLatchToggleResultInvalid", false, true)
	var result := resultVariant as Dictionary
	if not bool(result.get("ok", false)):
		return makeFailure(
			coordinates.x,
			coordinates.y,
			String(result.get("errorReason", "OcbSimulationLatchToggleFailed")),
			false,
			true
		)
	var changesVariant: Variant = result.get("changes", PackedInt32Array())
	if not (changesVariant is PackedInt32Array):
		return makeFailure(coordinates.x, coordinates.y, "OcbSimulationLatchToggleChangesInvalid", false, true)
	return {
		"ok": true,
		"updates": makeDeltaUpdates(changesVariant as PackedInt32Array),
	}

func advanceTick() -> Dictionary:
	if not hasNativeSimulation():
		return makeFailure(-1, -1, "BackendUnavailable")
	var changesVariant: Variant = NativeSimulation.call("advanceTick")
	if not (changesVariant is PackedInt32Array):
		return makeFailure(-1, -1, "OcbSimulationAdvanceResultInvalid")
	return {
		"ok": true,
		"updates": makeDeltaUpdates(changesVariant as PackedInt32Array),
	}

func reset() -> Dictionary:
	if not hasNativeSimulation():
		return makeFailure(-1, -1, "BackendUnavailable")
	var changesVariant: Variant = NativeSimulation.call("reset")
	if not (changesVariant is PackedInt32Array):
		return makeFailure(-1, -1, "OcbSimulationResetResultInvalid")
	return {
		"ok": true,
		"updates": makeDeltaUpdates(changesVariant as PackedInt32Array),
	}

func captureState() -> Dictionary:
	if not hasNativeSimulation():
		return makeFailure(-1, -1, "BackendUnavailable")
	var snapshotVariant: Variant = NativeSimulation.call("captureState")
	if not (snapshotVariant is PackedByteArray):
		return makeFailure(-1, -1, "OcbSimulationSnapshotInvalid")
	return {
		"ok": true,
		"snapshot": snapshotVariant as PackedByteArray,
	}

func restoreState(snapshot: PackedByteArray) -> Dictionary:
	if not hasNativeSimulation():
		return makeFailure(-1, -1, "BackendUnavailable")
	var resultVariant: Variant = NativeSimulation.call("restoreState", snapshot)
	if not (resultVariant is Dictionary):
		return makeFailure(-1, -1, "OcbSimulationRestoreResultInvalid")
	var result := resultVariant as Dictionary
	if not bool(result.get("ok", false)):
		return makeFailure(-1, -1, String(result.get("errorReason", "OcbSimulationRestoreFailed")))
	var changesVariant: Variant = result.get("changes", PackedInt32Array())
	if not (changesVariant is PackedInt32Array):
		return makeFailure(-1, -1, "OcbSimulationRestoreChangesInvalid")
	return {
		"ok": true,
		"updates": makeDeltaUpdates(changesVariant as PackedInt32Array),
	}

func release() -> void:
	NativeSimulation = null
	GridWidth = 0
	GridHeight = 0
	GridOrigin = Vector2i.ZERO
	CoordinatesByCellIndex.clear()

func hasNativeSimulation() -> bool:
	return NativeSimulation != null and is_instance_valid(NativeSimulation)

func loadNativeExtension() -> bool:
	if NativeExtension != null:
		return true
	if not ResourceLoader.exists(NativeExtensionPath):
		return false
	NativeExtension = load("res://OcbSimulation.gdextension") as Resource
	return NativeExtension != null

func buildGrid(board: Node) -> Dictionary:
	if board == null or not board.has_method("getSimulationTiles"):
		return makeFailure(-1, -1, "SimulationBoardUnavailable")
	GridWidth = int(board.get("GridWidthCount"))
	GridHeight = int(board.get("GridHeightCount"))
	if GridWidth <= 0 or GridHeight <= 0:
		return failAndRelease(-1, -1, "SimulationGridInvalid")
	GridOrigin = getBoardGridOrigin(board)
	var cellCount := GridWidth * GridHeight
	var kinds := PackedInt32Array()
	var initialStates := PackedInt32Array()
	var clockHoldTicks := PackedInt32Array()
	var meshIds := PackedInt32Array()
	kinds.resize(cellCount)
	initialStates.resize(cellCount)
	clockHoldTicks.resize(cellCount)
	meshIds.resize(cellCount)
	kinds.fill(KindEmpty)
	initialStates.fill(0)
	clockHoldTicks.fill(1)
	meshIds.fill(1)
	CoordinatesByCellIndex.clear()
	var tilesVariant: Variant = board.call("getSimulationTiles")
	if not (tilesVariant is Array):
		return failAndRelease(-1, -1, "SimulationTilesInvalid")
	for tileVariant in tilesVariant as Array:
		if not (tileVariant is Dictionary):
			return failAndRelease(-1, -1, "SimulationTileInvalid")
		var tile := tileVariant as Dictionary
		var coordinatesVariant: Variant = tile.get("coordinates", null)
		if not (coordinatesVariant is Vector2i):
			return failAndRelease(-1, -1, "SimulationTileCoordinatesInvalid")
		var coordinates := coordinatesVariant as Vector2i
		var cellIndex := getCellIndex(coordinates)
		if cellIndex < 0:
			return failAndRelease(coordinates.x, coordinates.y, "SimulationTileOutsideGrid", false, true)
		if CoordinatesByCellIndex.has(cellIndex):
			return failAndRelease(coordinates.x, coordinates.y, "SimulationTileDuplicate", false, true)
		var toolId := String(tile.get("toolId", ""))
		if not KindByToolId.has(toolId):
			return failAndRelease(coordinates.x, coordinates.y, "SimulationToolUnsupported:%s" % toolId, false, true)
		CoordinatesByCellIndex[cellIndex] = coordinates
		kinds[cellIndex] = int(KindByToolId[toolId])
		initialStates[cellIndex] = 1 if bool(tile.get("isOn", false)) else 0
		clockHoldTicks[cellIndex] = maxi(1, int(tile.get("clockHoldTicks", 1)))
		meshIds[cellIndex] = maxi(1, int(tile.get("meshId", 1)))
	return {
		"ok": true,
		"kinds": kinds,
		"initialStates": initialStates,
		"clockHoldTicks": clockHoldTicks,
		"meshIds": meshIds,
	}

func getBoardGridOrigin(board: Node) -> Vector2i:
	if board.has_method("getSimulationGridOrigin"):
		var originVariant: Variant = board.call("getSimulationGridOrigin")
		if originVariant is Vector2i:
			return originVariant as Vector2i
	var cellSize := maxi(1, int(board.get("CellSize")))
	var validRect: Variant = board.get("ValidRect")
	if validRect is Rect2:
		var boardRect := validRect as Rect2
		return Vector2i(
			floori(boardRect.position.x / float(cellSize)),
			floori(boardRect.position.y / float(cellSize))
		)
	return Vector2i(-floori(float(GridWidth) / 2.0), -floori(float(GridHeight) / 2.0))

func getCellIndex(coordinates: Vector2i) -> int:
	var localCoordinates := coordinates - GridOrigin
	if localCoordinates.x < 0 or localCoordinates.y < 0 or localCoordinates.x >= GridWidth or localCoordinates.y >= GridHeight:
		return -1
	return localCoordinates.y * GridWidth + localCoordinates.x

func makeFullStateUpdates(states: PackedInt32Array) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	for cellIndexVariant in CoordinatesByCellIndex:
		var cellIndex := int(cellIndexVariant)
		if cellIndex < 0 or cellIndex >= states.size():
			continue
		updates.append({
			"coordinates": CoordinatesByCellIndex[cellIndex],
			"isOn": states[cellIndex] != 0,
		})
	return updates

func makeDeltaUpdates(changes: PackedInt32Array) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	var pairCount := changes.size() / 2
	for pairIndex in pairCount:
		var offset := pairIndex * 2
		var cellIndex := changes[offset]
		if not CoordinatesByCellIndex.has(cellIndex):
			continue
		updates.append({
			"coordinates": CoordinatesByCellIndex[cellIndex],
			"isOn": changes[offset + 1] != 0,
		})
	return updates

func failAndRelease(errorX: int, errorY: int, errorReason: String, coordinatesAreNative := false, hasCoordinates := false) -> Dictionary:
	var result := makeFailure(errorX, errorY, errorReason, coordinatesAreNative, hasCoordinates)
	release()
	return result

func makeFailure(errorX: int, errorY: int, errorReason: String, coordinatesAreNative := false, hasCoordinates := false) -> Dictionary:
	var resolvedCoordinates := Vector2i(errorX, errorY)
	if coordinatesAreNative and errorX >= 0 and errorY >= 0:
		resolvedCoordinates += GridOrigin
		hasCoordinates = true
	return {
		"ok": false,
		"errorX": resolvedCoordinates.x,
		"errorY": resolvedCoordinates.y,
		"hasCoordinates": hasCoordinates,
		"errorReason": errorReason,
	}
