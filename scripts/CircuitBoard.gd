extends Node2D

const InkRegistry := preload("res://scripts/InkRegistry.gd")
const SelectionOverlayScript := preload("res://scripts/SelectionOverlay.gd")
const CanvasResizeOverlayScript := preload("res://scripts/CanvasResizeOverlay.gd")
const CircuitTile := preload("res://scripts/CircuitTile.gd")
const ClipboardHistoryLimit := 4
const PreviewBuildBatchSize := 64
const PreviewBuildThreshold := 128
const ClockHoldTicksMinimum := 1
const MeshIdMinimum := 1
const PositiveIntegerMaximum := 2147483647
const MinimumGridSize := Vector2i(4, 4)
const CanvasResizeHitRadiusPixels := 18.0
const CanvasResizeHandleRadiusPixels := 7.0

enum InteractionMode {
	Idle,
	Painting,
	Deleting,
	Selecting,
	Moving,
	Pasting,
	ResizingCanvas,
}

enum CanvasResizeCorner {
	TopLeft,
	TopRight,
	BottomLeft,
	BottomRight,
}

const CanvasResizeCornerNone := -1

signal clipboardChanged(history: Array[Dictionary], selectedIndex: int)
signal clipboardCopied(history: Array[Dictionary], selectedIndex: int)
signal selectionChanged(item: Dictionary)
signal clockHoldTicksChanged(holdTicks: int)
signal meshIdChanged(meshId: int)
signal latchInitialStateChanged(isOn: bool)

@export_group("Board")
@export var CellSize := 64
@export var GridWidthCount := 40
@export var GridHeightCount := 28
@export var TileScene: PackedScene
@export var CanvasBackground: ColorRect
@export var CanvasShadow: ColorRect
@export var CanvasBoard: ColorRect
@export var BoardCamera: Camera2D
@export var CanvasCornerRadius := 64.0
@export var CanvasBackgroundMargin := 8192.0
@export var CanvasShadowMargin := 256.0

@onready var Selector: ColorRect = $Selector
@onready var PlacedTiles: Node2D = $PlacedTiles

var ValidRect := Rect2()
var GridBounds := Rect2i()
var InitialGridBounds := Rect2i()
var Occupancy: Dictionary[Vector2i, Node2D] = {}
var TileValues: Dictionary[Vector2i, Dictionary] = {}
var RuntimeTileStates: Dictionary[Vector2i, bool] = {}
var SelectedTool := "or"
var ClockHoldTicks := ClockHoldTicksMinimum
var MeshId := MeshIdMinimum
var LatchInitialState := true
var ToolRegistry: Dictionary = {}
var EditorInputEnabled := true
var CurrentInteractionMode := InteractionMode.Idle
var SelectionStartCoordinates := Vector2i.ZERO
var MoveStartCoordinates := Vector2i.ZERO
var MoveOffset := Vector2i.ZERO
var MovePreviewValid := false
var PasteAnchorCoordinates := Vector2i.ZERO
var PastePreviewValid := false
var PastePreviewValues: Dictionary[Vector2i, Dictionary] = {}
var LastStrokeCoordinates := Vector2i.ZERO
var HasLastStrokeCoordinates := false
var ActiveChanges: Dictionary[Vector2i, Dictionary] = {}
var ActiveSelectionBefore: Dictionary = {}
var SelectedCells: Dictionary[Vector2i, bool] = {}
var SelectionBounds := Rect2i()
var ClipboardHistory: Array[Dictionary] = []
var SelectedClipboardIndex := -1
var UndoStack: Array[Dictionary] = []
var RedoStack: Array[Dictionary] = []
var SelectionOverlay: Node2D
var PreviewTiles: Node2D
var CanvasResizeOverlay: Node2D
var PreviewTileByCoordinates: Dictionary[Vector2i, Node2D] = {}
var PreviewBuildGeneration := 0
var PreviewBuildState: Dictionary = {}
var IsPastePreviewBuilding := false
var CanvasResizeStartBounds := Rect2i()
var CanvasResizeHoveredCorner := CanvasResizeCornerNone
var CanvasResizeActiveCorner := CanvasResizeCornerNone

func _ready() -> void:
	ToolRegistry = InkRegistry.getBoardToolRegistry()
	CircuitTile.warmGeometry(float(CellSize))
	InitialGridBounds = makeCenteredGridBounds(GridWidthCount, GridHeightCount)
	applyGridBounds(InitialGridBounds)
	Selector.size = Vector2.ONE * CellSize
	PreviewTiles = createPreviewTiles()
	SelectionOverlay = SelectionOverlayScript.new()
	SelectionOverlay.name = "SelectionOverlay"
	add_child(SelectionOverlay)
	CanvasResizeOverlay = CanvasResizeOverlayScript.new()
	CanvasResizeOverlay.name = "CanvasResizeOverlay"
	add_child(CanvasResizeOverlay)
	refreshGridLayers()
	refreshCanvasResizeOverlay()

func makeCenteredGridBounds(width: int, height: int) -> Rect2i:
	var gridSize := Vector2i(maxi(MinimumGridSize.x, width), maxi(MinimumGridSize.y, height))
	var origin := Vector2i(-floori(float(gridSize.x) / 2.0), -floori(float(gridSize.y) / 2.0))
	return Rect2i(origin, gridSize)

func getGridBounds() -> Rect2i:
	return GridBounds

func setGridBounds(requestedBounds: Rect2i) -> bool:
	if not isGridBoundsValid(requestedBounds) or not doesGridBoundsContainTiles(requestedBounds):
		return false
	if requestedBounds == GridBounds:
		return false
	applyGridBounds(requestedBounds)
	return true

func applyGridBounds(nextBounds: Rect2i) -> void:
	GridBounds = nextBounds
	GridWidthCount = GridBounds.size.x
	GridHeightCount = GridBounds.size.y
	var boardSize := Vector2(GridBounds.size) * float(CellSize)
	ValidRect = Rect2(Vector2(GridBounds.position) * float(CellSize), boardSize)
	configurePatternCanvas(
		CanvasBackground,
		boardSize + Vector2.ONE * CanvasBackgroundMargin * 2.0,
		ValidRect.position - Vector2.ONE * CanvasBackgroundMargin,
		0.0
	)
	configureCanvasShadow(boardSize)
	configurePatternCanvas(CanvasBoard, boardSize, ValidRect.position, CanvasCornerRadius)
	if BoardCamera and BoardCamera.has_method("setDragBounds"):
		BoardCamera.call("setDragBounds", ValidRect)
	refreshGridLayers()
	refreshCanvasResizeOverlay()

func isGridBoundsValid(bounds: Rect2i) -> bool:
	return bounds.size.x >= MinimumGridSize.x and bounds.size.y >= MinimumGridSize.y

func doesGridBoundsContainTiles(bounds: Rect2i) -> bool:
	for coordinatesVariant in TileValues:
		if not bounds.has_point(coordinatesVariant as Vector2i):
			return false
	return true

func refreshGridLayers() -> void:
	Selector.z_index = min(GridWidthCount * 2 + 100, RenderingServer.CANVAS_ITEM_Z_MAX)
	if PreviewTiles:
		PreviewTiles.z_index = GridWidthCount * 3
		for previewTileVariant in PreviewTiles.get_children():
			var previewTile := previewTileVariant as Node2D
			if previewTile and previewTile.has_method("updateGridCoordinates"):
				previewTile.call("updateGridCoordinates", self, previewTile.get("GridCoordinates") as Vector2i)
	if SelectionOverlay:
		SelectionOverlay.z_index = min(GridWidthCount * 4 + 100, RenderingServer.CANVAS_ITEM_Z_MAX)
	if CanvasResizeOverlay:
		CanvasResizeOverlay.z_index = min(GridWidthCount * 4 + 110, RenderingServer.CANVAS_ITEM_Z_MAX)
	for coordinatesVariant in Occupancy:
		var coordinates := coordinatesVariant as Vector2i
		var tile := Occupancy[coordinates] as Node2D
		if tile and tile.has_method("updateGridCoordinates"):
			tile.call("updateGridCoordinates", self, coordinates)

func configurePatternCanvas(patternCanvas: ColorRect, patternCanvasSize: Vector2, patternCanvasPosition: Vector2, radius: float) -> void:
	if patternCanvas == null:
		return
	patternCanvas.size = patternCanvasSize
	patternCanvas.position = patternCanvasPosition
	var material := patternCanvas.material as ShaderMaterial
	if material:
		material.set_shader_parameter("PatternSize", float(CellSize * 16))
		material.set_shader_parameter("BoardSize", patternCanvasSize)
		material.set_shader_parameter("PatternOrigin", patternCanvasPosition)
		material.set_shader_parameter("CornerRadius", radius)

func configureCanvasShadow(boardSize: Vector2) -> void:
	if CanvasShadow == null:
		return
	var shadowMargin := Vector2.ONE * CanvasShadowMargin
	CanvasShadow.size = boardSize + shadowMargin * 2.0
	CanvasShadow.position = ValidRect.position - shadowMargin
	var material := CanvasShadow.material as ShaderMaterial
	if material:
		material.set_shader_parameter("BoardSize", boardSize)
		material.set_shader_parameter("FrameSize", CanvasShadow.size)
		material.set_shader_parameter("BoardOffset", shadowMargin)
		material.set_shader_parameter("CornerRadius", CanvasCornerRadius)

func getCanvasResizeHandleRadius() -> float:
	var zoom := BoardCamera.zoom.x if BoardCamera else 1.0
	return CanvasResizeHandleRadiusPixels / maxf(zoom, 0.01)

func getCanvasResizeHitRadius() -> float:
	var zoom := BoardCamera.zoom.x if BoardCamera else 1.0
	return CanvasResizeHitRadiusPixels / maxf(zoom, 0.01)

func getCanvasResizeCornerAt(boardPosition: Vector2) -> int:
	if not EditorInputEnabled:
		return CanvasResizeCornerNone
	var corners := getCanvasResizeCorners()
	var hitRadiusSquared := pow(getCanvasResizeHitRadius(), 2.0)
	var closestCorner := CanvasResizeCornerNone
	var closestDistanceSquared := INF
	for cornerIndex in range(corners.size()):
		var distanceSquared := boardPosition.distance_squared_to(corners[cornerIndex] as Vector2)
		if distanceSquared <= hitRadiusSquared and distanceSquared < closestDistanceSquared:
			closestCorner = cornerIndex
			closestDistanceSquared = distanceSquared
	return closestCorner

func getCanvasResizeCorners() -> Array[Vector2]:
	return [
		ValidRect.position,
		Vector2(ValidRect.end.x, ValidRect.position.y),
		Vector2(ValidRect.position.x, ValidRect.end.y),
		ValidRect.end,
	]

func beginCanvasResizeAt(boardPosition: Vector2) -> bool:
	if not EditorInputEnabled or CurrentInteractionMode != InteractionMode.Idle:
		return false
	var corner := getCanvasResizeCornerAt(boardPosition)
	if corner == CanvasResizeCornerNone:
		return false
	CanvasResizeStartBounds = GridBounds
	CanvasResizeHoveredCorner = corner
	CanvasResizeActiveCorner = corner
	CurrentInteractionMode = InteractionMode.ResizingCanvas
	refreshCanvasResizeOverlay()
	return true

func updateCanvasResizeAt(boardPosition: Vector2) -> bool:
	if CurrentInteractionMode != InteractionMode.ResizingCanvas or CanvasResizeActiveCorner == CanvasResizeCornerNone:
		return false
	var requestedBounds := getResizedGridBounds(boardPosition)
	if requestedBounds == GridBounds:
		return false
	var didResize := setGridBounds(requestedBounds)
	refreshCanvasResizeOverlay()
	return didResize

func finishCanvasResize() -> bool:
	if CurrentInteractionMode != InteractionMode.ResizingCanvas:
		return false
	CanvasResizeStartBounds = Rect2i()
	CanvasResizeActiveCorner = CanvasResizeCornerNone
	CurrentInteractionMode = InteractionMode.Idle
	updateCanvasResizeHover(get_global_mouse_position())
	return true

func cancelCanvasResize() -> void:
	if CurrentInteractionMode != InteractionMode.ResizingCanvas:
		return
	applyGridBounds(CanvasResizeStartBounds)
	CanvasResizeStartBounds = Rect2i()
	CanvasResizeActiveCorner = CanvasResizeCornerNone
	CurrentInteractionMode = InteractionMode.Idle
	updateCanvasResizeHover(get_global_mouse_position())

func getResizedGridBounds(boardPosition: Vector2) -> Rect2i:
	var snappedBoundary := Vector2i(
		roundi(boardPosition.x / float(CellSize)),
		roundi(boardPosition.y / float(CellSize))
	)
	var left := CanvasResizeStartBounds.position.x
	var top := CanvasResizeStartBounds.position.y
	var right := CanvasResizeStartBounds.end.x
	var bottom := CanvasResizeStartBounds.end.y
	match CanvasResizeActiveCorner:
		CanvasResizeCorner.TopLeft:
			left = mini(snappedBoundary.x, right - MinimumGridSize.x)
			top = mini(snappedBoundary.y, bottom - MinimumGridSize.y)
		CanvasResizeCorner.TopRight:
			right = maxi(snappedBoundary.x, left + MinimumGridSize.x)
			top = mini(snappedBoundary.y, bottom - MinimumGridSize.y)
		CanvasResizeCorner.BottomLeft:
			left = mini(snappedBoundary.x, right - MinimumGridSize.x)
			bottom = maxi(snappedBoundary.y, top + MinimumGridSize.y)
		CanvasResizeCorner.BottomRight:
			right = maxi(snappedBoundary.x, left + MinimumGridSize.x)
			bottom = maxi(snappedBoundary.y, top + MinimumGridSize.y)
		_:
			return GridBounds
	return constrainGridBoundsToTiles(Rect2i(Vector2i(left, top), Vector2i(right - left, bottom - top)))

func constrainGridBoundsToTiles(bounds: Rect2i) -> Rect2i:
	var left := bounds.position.x
	var top := bounds.position.y
	var right := bounds.end.x
	var bottom := bounds.end.y
	for coordinatesVariant in TileValues:
		var coordinates := coordinatesVariant as Vector2i
		left = mini(left, coordinates.x)
		top = mini(top, coordinates.y)
		right = maxi(right, coordinates.x + 1)
		bottom = maxi(bottom, coordinates.y + 1)
	return Rect2i(Vector2i(left, top), Vector2i(right - left, bottom - top))

func updateCanvasResizeHover(boardPosition: Vector2) -> void:
	var nextHoveredCorner := CanvasResizeActiveCorner if CurrentInteractionMode == InteractionMode.ResizingCanvas else getCanvasResizeCornerAt(boardPosition)
	if CanvasResizeHoveredCorner == nextHoveredCorner:
		return
	CanvasResizeHoveredCorner = nextHoveredCorner
	refreshCanvasResizeOverlay()

func refreshCanvasResizeOverlay() -> void:
	if CanvasResizeOverlay == null:
		return
	CanvasResizeOverlay.call(
		"setResizeState",
		ValidRect,
		getCanvasResizeHandleRadius(),
		CanvasResizeHoveredCorner,
		CanvasResizeActiveCorner,
		EditorInputEnabled
	)

func createPreviewTiles() -> Node2D:
	var tiles := Node2D.new()
	tiles.name = "PreviewTiles"
	tiles.z_index = GridWidthCount * 3
	add_child(tiles)
	return tiles

func _process(_delta: float) -> void:
	updateSelectorPosition()
	updateCanvasResizeHover(get_global_mouse_position())

func _unhandled_input(event: InputEvent) -> void:
	if not EditorInputEnabled:
		return
	var keyEvent := event as InputEventKey
	if keyEvent:
		handleKeyInput(keyEvent)
		return
	var mouseButton := event as InputEventMouseButton
	if mouseButton:
		handleMouseButton(mouseButton)
		return
	var mouseMotion := event as InputEventMouseMotion
	if mouseMotion:
		handleMouseMotion(mouseMotion)

func handleKeyInput(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if CurrentInteractionMode == InteractionMode.Pasting:
			cancelPastePreview()
		elif CurrentInteractionMode != InteractionMode.Idle:
			cancelActiveInteraction()
		else:
			clearSelection()
		get_viewport().set_input_as_handled()
		return
	if not (event.ctrl_pressed or event.meta_pressed):
		return
	match event.keycode:
		KEY_C:
			copySelection()
		KEY_X:
			cutSelection()
		KEY_V:
			beginPastePreview()
		KEY_Z:
			undo()
		KEY_U:
			redo()
		_:
			return
	get_viewport().set_input_as_handled()

func handleMouseButton(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if CurrentInteractionMode == InteractionMode.ResizingCanvas:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			finishCanvasResize()
			get_viewport().set_input_as_handled()
		return
	if CurrentInteractionMode == InteractionMode.Pasting:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			confirmPastePreview()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			cancelPastePreview()
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			var deleteCoordinates := getGridCoordinates(get_global_mouse_position())
			if handleRightButtonPress(deleteCoordinates):
				get_viewport().set_input_as_handled()
		elif CurrentInteractionMode == InteractionMode.Deleting:
			finishStroke()
			get_viewport().set_input_as_handled()
		return
	if event.pressed:
		if beginCanvasResizeAt(get_global_mouse_position()):
			get_viewport().set_input_as_handled()
			return
		var coordinates := getGridCoordinates(get_global_mouse_position())
		if handleLeftButtonPress(coordinates, event.shift_pressed):
			get_viewport().set_input_as_handled()
		return
	if CurrentInteractionMode == InteractionMode.Painting:
		finishStroke()
	elif CurrentInteractionMode == InteractionMode.Selecting:
		finishSelection(getGridCoordinates(get_global_mouse_position()))
	elif CurrentInteractionMode == InteractionMode.Moving:
		finishMove()
	else:
		return
	get_viewport().set_input_as_handled()

func handleMouseMotion(event: InputEventMouseMotion) -> void:
	if CurrentInteractionMode == InteractionMode.ResizingCanvas:
		updateCanvasResizeAt(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return
	if CurrentInteractionMode == InteractionMode.Pasting and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		return
	var coordinates := getGridCoordinates(get_global_mouse_position())
	match CurrentInteractionMode:
		InteractionMode.Painting, InteractionMode.Deleting:
			appendStrokeTo(coordinates)
		InteractionMode.Selecting:
			updateSelectionMarquee(coordinates)
		InteractionMode.Moving:
			updateMovePreview(coordinates)
		InteractionMode.Pasting:
			updatePastePreview(coordinates)
		_:
			return
	get_viewport().set_input_as_handled()

func selectTool(toolId: String) -> void:
	if ToolRegistry.has(toolId):
		SelectedTool = toolId

func setClockHoldTicks(requestedHoldTicks: int) -> bool:
	if not EditorInputEnabled:
		return false
	var normalizedHoldTicks := normalizePositiveInteger(requestedHoldTicks, ClockHoldTicksMinimum)
	var selectedCoordinates: Variant = getSingleSelectedCoordinatesForTool("clock")
	if selectedCoordinates is Vector2i:
		var didUpdateSelectedTile := setTileClockHoldTicks(selectedCoordinates as Vector2i, normalizedHoldTicks)
		if didUpdateSelectedTile:
			clockHoldTicksChanged.emit(getClockHoldTicks())
		return didUpdateSelectedTile
	if ClockHoldTicks == normalizedHoldTicks:
		return false
	ClockHoldTicks = normalizedHoldTicks
	clockHoldTicksChanged.emit(ClockHoldTicks)
	return true

func getClockHoldTicks() -> int:
	var selectedCoordinates: Variant = getSingleSelectedCoordinatesForTool("clock")
	if selectedCoordinates is Vector2i:
		return getTileClockHoldTicks(selectedCoordinates as Vector2i)
	return ClockHoldTicks

func getTileClockHoldTicks(coordinates: Vector2i) -> int:
	var tileValue := getTileValueAt(coordinates)
	if String(tileValue.get("toolId", "")) != "clock":
		return ClockHoldTicksMinimum
	return int(tileValue.get("clockHoldTicks", ClockHoldTicksMinimum))

func setMeshId(requestedMeshId: int) -> bool:
	if not EditorInputEnabled:
		return false
	var normalizedMeshId := normalizePositiveInteger(requestedMeshId, MeshIdMinimum)
	var selectedCoordinates: Variant = getSingleSelectedCoordinatesForTool("mesh")
	if selectedCoordinates is Vector2i:
		var didUpdateSelectedTile := setTileMeshId(selectedCoordinates as Vector2i, normalizedMeshId)
		if didUpdateSelectedTile:
			meshIdChanged.emit(getMeshId())
		return didUpdateSelectedTile
	if MeshId == normalizedMeshId:
		return false
	MeshId = normalizedMeshId
	meshIdChanged.emit(MeshId)
	return true

func getMeshId() -> int:
	var selectedCoordinates: Variant = getSingleSelectedCoordinatesForTool("mesh")
	if selectedCoordinates is Vector2i:
		return getTileMeshId(selectedCoordinates as Vector2i)
	return MeshId

func getTileMeshId(coordinates: Vector2i) -> int:
	var tileValue := getTileValueAt(coordinates)
	if String(tileValue.get("toolId", "")) != "mesh":
		return MeshIdMinimum
	return int(tileValue.get("meshId", MeshIdMinimum))

func setLatchInitialState(requestedIsOn: bool) -> bool:
	if not EditorInputEnabled:
		return false
	var selectedCoordinates: Variant = getSingleSelectedCoordinatesForTool("latch")
	if selectedCoordinates is Vector2i:
		var didUpdateSelectedTile := setTileLatchInitialState(selectedCoordinates as Vector2i, requestedIsOn)
		if didUpdateSelectedTile:
			latchInitialStateChanged.emit(getLatchInitialState())
		return didUpdateSelectedTile
	if LatchInitialState == requestedIsOn:
		return false
	LatchInitialState = requestedIsOn
	latchInitialStateChanged.emit(LatchInitialState)
	return true

func getLatchInitialState() -> bool:
	var selectedCoordinates: Variant = getSingleSelectedCoordinatesForTool("latch")
	if selectedCoordinates is Vector2i:
		return getTileState(selectedCoordinates as Vector2i)
	return LatchInitialState

func setTileClockHoldTicks(coordinates: Vector2i, requestedHoldTicks: int) -> bool:
	if getToolIdAt(coordinates) != "clock":
		return false
	var tileValue := getTileValueAt(coordinates)
	var normalizedHoldTicks := normalizePositiveInteger(requestedHoldTicks, ClockHoldTicksMinimum)
	if int(tileValue.get("clockHoldTicks", ClockHoldTicksMinimum)) == normalizedHoldTicks:
		return false
	tileValue["clockHoldTicks"] = normalizedHoldTicks
	return setTileValueWithHistory(coordinates, tileValue)

func setTileMeshId(coordinates: Vector2i, requestedMeshId: int) -> bool:
	if getToolIdAt(coordinates) != "mesh":
		return false
	var tileValue := getTileValueAt(coordinates)
	var normalizedMeshId := normalizePositiveInteger(requestedMeshId, MeshIdMinimum)
	if int(tileValue.get("meshId", MeshIdMinimum)) == normalizedMeshId:
		return false
	tileValue["meshId"] = normalizedMeshId
	return setTileValueWithHistory(coordinates, tileValue)

func setTileLatchInitialState(coordinates: Vector2i, requestedIsOn: bool) -> bool:
	if getToolIdAt(coordinates) != "latch":
		return false
	var tileValue := getTileValueAt(coordinates)
	if bool(tileValue.get("isOn", false)) == requestedIsOn:
		return false
	tileValue["isOn"] = requestedIsOn
	return setTileValueWithHistory(coordinates, tileValue)

func placeTile(coordinates: Vector2i, toolId := SelectedTool) -> bool:
	if not isCoordinateValid(coordinates) or TileValues.has(coordinates):
		return false
	return setTileTool(coordinates, toolId)

func removeTile(coordinates: Vector2i) -> bool:
	if not TileValues.has(coordinates):
		return false
	var removed := setTileTool(coordinates, "")
	if removed:
		pruneSelection()
	return removed

func getInkAt(coordinates: Vector2i) -> Dictionary:
	if not isCoordinateValid(coordinates) or not TileValues.has(coordinates):
		return {}
	return InkRegistry.getInk(getToolIdAt(coordinates))

func getCursorInfoAt(coordinates: Vector2i) -> Dictionary:
	var isValid := isCoordinateValid(coordinates)
	var ink := getInkAt(coordinates) if isValid else {}
	var toolId := String(ink.get("componentId", ""))
	var meshId := getTileMeshId(coordinates) if toolId == "mesh" else MeshIdMinimum
	var hoveredInkTitle := String(ink.get("title", "None"))
	if toolId == "mesh":
		hoveredInkTitle = "%s #%d" % [hoveredInkTitle, meshId]
	return {
		"coordinates": coordinates,
		"isValid": isValid,
		"toolId": toolId,
		"hoveredInkTitle": hoveredInkTitle,
		"meshId": meshId,
	}

func getTileState(coordinates: Vector2i) -> bool:
	return bool(getTileValueAt(coordinates).get("isOn", false))

func setTileState(coordinates: Vector2i, isOn: bool) -> bool:
	var tileValue := getTileValueAt(coordinates)
	if tileValue.is_empty() or bool(tileValue.get("isOn", false)) == isOn:
		return false
	tileValue["isOn"] = isOn
	return setTileValue(coordinates, tileValue)

func applyTileStates(updates: Array) -> void:
	for updateVariant in updates:
		if not (updateVariant is Dictionary):
			continue
		var update := updateVariant as Dictionary
		var rawCoordinates: Variant = update.get("coordinates", null)
		if rawCoordinates is Vector2i and update.has("isOn"):
			setTileState(rawCoordinates as Vector2i, bool(update["isOn"]))

func applyRuntimeTileStates(updates: Array) -> void:
	for updateVariant in updates:
		if not (updateVariant is Dictionary):
			continue
		var update := updateVariant as Dictionary
		var rawCoordinates: Variant = update.get("coordinates", null)
		if rawCoordinates is Vector2i and update.has("isOn"):
			setRuntimeTileState(rawCoordinates as Vector2i, bool(update["isOn"]))

func setRuntimeTileState(coordinates: Vector2i, isOn: bool) -> bool:
	if not TileValues.has(coordinates):
		return false
	var designIsOn := getTileState(coordinates)
	var renderedIsOn := getRuntimeTileState(coordinates)
	if isOn == designIsOn:
		RuntimeTileStates.erase(coordinates)
	else:
		RuntimeTileStates[coordinates] = isOn
	if renderedIsOn == isOn:
		return false
	updateTileVisualState(coordinates, isOn)
	return true

func getRuntimeTileState(coordinates: Vector2i) -> bool:
	return bool(RuntimeTileStates.get(coordinates, getTileState(coordinates)))

func hasRuntimeTileState(coordinates: Vector2i) -> bool:
	return RuntimeTileStates.has(coordinates)

func clearRuntimeTileStates() -> void:
	for coordinatesVariant in RuntimeTileStates.keys():
		var coordinates := coordinatesVariant as Vector2i
		updateTileVisualState(coordinates, getTileState(coordinates))
	RuntimeTileStates.clear()

func getTileIcon(toolId: String, isOn: bool) -> Texture2D:
	return InkRegistry.getInkIcon(toolId, isOn)

func updateTileVisualState(coordinates: Vector2i, isOn: bool) -> void:
	var tile := Occupancy.get(coordinates) as Node2D
	if tile == null:
		return
	var toolId := getToolIdAt(coordinates)
	if toolId == "latch":
		tile.call("setIcon", getTileIcon(toolId, isOn))
	tile.call("setInkState", isOn)

func getSimulationTiles() -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(TileValues.keys()):
		var tileValue := getTileValueAt(coordinates)
		var simulationTile := {
			"coordinates": coordinates,
			"toolId": String(tileValue.get("toolId", "")),
			"isOn": bool(tileValue.get("isOn", false)),
			"clockHoldTicks": int(tileValue.get("clockHoldTicks", ClockHoldTicksMinimum)),
			"meshId": int(tileValue.get("meshId", MeshIdMinimum)),
		}
		tiles.append(simulationTile)
	return tiles

func getSimulationGrid() -> Dictionary:
	return {
		"width": GridWidthCount,
		"height": GridHeightCount,
		"origin": getSimulationGridOrigin(),
		"tiles": getSimulationTiles(),
	}

func getSimulationGridOrigin() -> Vector2i:
	return GridBounds.position

func exportProjectData() -> Dictionary:
	var tiles: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(TileValues.keys()):
		var tileValue := getTileValueAt(coordinates)
		var projectTile := {
			"x": coordinates.x,
			"y": coordinates.y,
			"toolId": String(tileValue.get("toolId", "")),
			"isOn": bool(tileValue.get("isOn", false)),
		}
		if String(tileValue.get("toolId", "")) == "clock":
			projectTile["clockHoldTicks"] = int(tileValue.get("clockHoldTicks", ClockHoldTicksMinimum))
		if String(tileValue.get("toolId", "")) == "mesh":
			projectTile["meshId"] = int(tileValue.get("meshId", MeshIdMinimum))
		tiles.append(projectTile)
	return {
		"selectedTool": SelectedTool,
		"clockHoldTicks": ClockHoldTicks,
		"meshId": MeshId,
		"latchInitialState": LatchInitialState,
		"grid": makeProjectGridData(GridBounds),
		"tiles": tiles,
	}

func makeProjectGridData(bounds: Rect2i) -> Dictionary:
	return {
		"originX": bounds.position.x,
		"originY": bounds.position.y,
		"width": bounds.size.x,
		"height": bounds.size.y,
	}

func parseProjectGridBounds(projectData: Dictionary) -> Variant:
	if not projectData.has("grid"):
		return InitialGridBounds
	var rawGrid: Variant = projectData.get("grid", null)
	if not (rawGrid is Dictionary):
		return null
	var grid := rawGrid as Dictionary
	for key in ["originX", "originY", "width", "height"]:
		if not grid.has(key) or not isGridInteger(grid[key]):
			return null
	var bounds := Rect2i(
		Vector2i(int(grid["originX"]), int(grid["originY"])),
		Vector2i(int(grid["width"]), int(grid["height"]))
	)
	return bounds if isGridBoundsValid(bounds) else null

func isGridInteger(rawValue: Variant) -> bool:
	if rawValue is int:
		return true
	if rawValue is float:
		return float(rawValue) == floorf(float(rawValue))
	return false

func isCoordinateValidInBounds(coordinates: Vector2i, bounds: Rect2i) -> bool:
	return bounds.has_point(coordinates)

func importProjectData(projectData: Dictionary) -> bool:
	var rawTiles: Variant = projectData.get("tiles", [])
	if not (rawTiles is Array):
		return false
	var requestedGridBoundsVariant: Variant = parseProjectGridBounds(projectData)
	if not (requestedGridBoundsVariant is Rect2i):
		return false
	var requestedGridBounds := requestedGridBoundsVariant as Rect2i
	if not isOptionalPositiveInteger(projectData.get("clockHoldTicks", null)):
		return false
	if not isOptionalPositiveInteger(projectData.get("meshId", null)):
		return false
	var requestedClockHoldTicks := normalizePositiveInteger(projectData.get("clockHoldTicks", null), ClockHoldTicksMinimum)
	var requestedMeshId := normalizePositiveInteger(projectData.get("meshId", null), MeshIdMinimum)
	var requestedLatchInitialState := bool(projectData.get("latchInitialState", InkRegistry.getDefaultIsOn("latch")))
	var nextTiles: Dictionary[Vector2i, Dictionary] = {}
	for rawTileVariant in rawTiles:
		if not (rawTileVariant is Dictionary):
			return false
		var rawTile := rawTileVariant as Dictionary
		if not rawTile.has("x") or not rawTile.has("y") or not rawTile.has("toolId"):
			return false
		var coordinates := Vector2i(int(rawTile["x"]), int(rawTile["y"]))
		var toolId := String(rawTile["toolId"])
		if nextTiles.has(coordinates) or not isCoordinateValidInBounds(coordinates, requestedGridBounds) or not ToolRegistry.has(toolId):
			return false
		if toolId == "clock" and not isOptionalPositiveInteger(rawTile.get("clockHoldTicks", null)):
			return false
		if toolId == "mesh" and not isOptionalPositiveInteger(rawTile.get("meshId", null)):
			return false
		var tileIsOn: Variant = rawTile.get("isOn", requestedLatchInitialState if toolId == "latch" else null)
		var tileClockHoldTicks: Variant = rawTile.get("clockHoldTicks", requestedClockHoldTicks)
		var tileMeshId: Variant = rawTile.get("meshId", requestedMeshId)
		nextTiles[coordinates] = makeTileValue(toolId, tileIsOn, tileClockHoldTicks, tileMeshId)
	var requestedTool := String(projectData.get("selectedTool", "or"))
	if not ToolRegistry.has(requestedTool):
		return false
	cancelActiveInteraction()
	clearPreviewTiles()
	clearRuntimeTileStates()
	for tile in PlacedTiles.get_children():
		tile.free()
	Occupancy.clear()
	TileValues.clear()
	applyGridBounds(requestedGridBounds)
	for coordinates in getSortedCoordinates(nextTiles.keys()):
		if not setTileValue(coordinates, nextTiles[coordinates]):
			return false
	SelectedTool = requestedTool
	ClockHoldTicks = requestedClockHoldTicks
	MeshId = requestedMeshId
	LatchInitialState = requestedLatchInitialState
	UndoStack.clear()
	RedoStack.clear()
	SelectedCells.clear()
	SelectionBounds = Rect2i()
	ClipboardHistory.clear()
	SelectedClipboardIndex = -1
	refreshSelectionOverlay()
	selectionChanged.emit(getSelectionSnapshot())
	emitClipboardChanged()
	clockHoldTicksChanged.emit(ClockHoldTicks)
	meshIdChanged.emit(MeshId)
	latchInitialStateChanged.emit(LatchInitialState)
	return true

func clearProjectData() -> void:
	importProjectData({
		"selectedTool": "or",
		"grid": makeProjectGridData(InitialGridBounds),
		"tiles": [],
	})

func setEditorInputEnabled(isEnabled: bool) -> void:
	if EditorInputEnabled == isEnabled:
		return
	EditorInputEnabled = isEnabled
	if not EditorInputEnabled:
		cancelActiveInteraction()
	refreshCanvasResizeOverlay()

func getClipboardItem() -> Dictionary:
	return getSelectedClipboardItem().duplicate(true)

func getSelectedClipboardItem() -> Dictionary:
	if SelectedClipboardIndex < 0 or SelectedClipboardIndex >= ClipboardHistory.size():
		return {}
	return ClipboardHistory[SelectedClipboardIndex]

func getClipboardHistory() -> Array[Dictionary]:
	var history: Array[Dictionary] = []
	for item in ClipboardHistory:
		history.append(item.duplicate(true))
	return history

func getSelectedClipboardIndex() -> int:
	return SelectedClipboardIndex

func selectClipboardItem(index: int) -> bool:
	if index < 0 or index >= ClipboardHistory.size():
		return false
	SelectedClipboardIndex = index
	if CurrentInteractionMode == InteractionMode.Pasting:
		updatePastePreview(PasteAnchorCoordinates, true)
	emitClipboardChanged()
	return true

func emitClipboardChanged() -> void:
	clipboardChanged.emit(getClipboardHistory(), SelectedClipboardIndex)

func getSelectionItem() -> Dictionary:
	return getSelectionSnapshot()

func canStartMoveAt(coordinates: Vector2i) -> bool:
	return not SelectedCells.is_empty() and SelectionBounds.has_point(coordinates)

func handleLeftButtonPress(coordinates: Vector2i, isSelectionModifierPressed: bool) -> bool:
	if isSelectionModifierPressed:
		if not isCoordinateValid(coordinates):
			return false
		beginSelection(coordinates)
	elif not SelectedCells.is_empty():
		if canStartMoveAt(coordinates):
			beginMove(coordinates)
		else:
			clearSelection()
	else:
		if not isCoordinateValid(coordinates):
			return false
		beginStroke(coordinates, true)
	return true

func handleRightButtonPress(coordinates: Vector2i) -> bool:
	if not SelectedCells.is_empty():
		if canStartMoveAt(coordinates):
			deleteSelection()
		else:
			clearSelection()
	else:
		if not isCoordinateValid(coordinates):
			return false
		beginStroke(coordinates, false)
	return true

func beginStroke(coordinates: Vector2i, shouldPlace: bool) -> void:
	CurrentInteractionMode = InteractionMode.Painting if shouldPlace else InteractionMode.Deleting
	ActiveChanges.clear()
	ActiveSelectionBefore = getSelectionSnapshot()
	HasLastStrokeCoordinates = false
	appendStrokeTo(coordinates)

func appendStrokeTo(coordinates: Vector2i) -> void:
	if not isCoordinateValid(coordinates):
		HasLastStrokeCoordinates = false
		return
	var path: Array[Vector2i] = [coordinates]
	if HasLastStrokeCoordinates:
		path = getGridLine(LastStrokeCoordinates, coordinates)
	for point in path:
		applyStrokeAt(point, CurrentInteractionMode == InteractionMode.Painting)
	LastStrokeCoordinates = coordinates
	HasLastStrokeCoordinates = true

func applyStrokeAt(coordinates: Vector2i, shouldPlace: bool) -> void:
	if not isCoordinateValid(coordinates):
		return
	var afterToolId := SelectedTool if shouldPlace else ""
	if ActiveChanges.has(coordinates):
		return
	var beforeToolId := getToolIdAt(coordinates)
	if beforeToolId == afterToolId:
		return
	var change := makeChange(coordinates, getTileValueAt(coordinates), makeTileValue(afterToolId))
	ActiveChanges[coordinates] = change
	setTileValue(coordinates, change["afterTile"])

func finishStroke() -> void:
	var changes := getActiveChanges()
	if not changes.is_empty():
		var selectionAfter := pruneSelection()
		pushHistory(changes, ActiveSelectionBefore, selectionAfter)
	ActiveChanges.clear()
	ActiveSelectionBefore.clear()
	HasLastStrokeCoordinates = false
	CurrentInteractionMode = InteractionMode.Idle

func beginSelection(coordinates: Vector2i) -> void:
	CurrentInteractionMode = InteractionMode.Selecting
	SelectionStartCoordinates = coordinates
	updateSelectionMarquee(coordinates)

func updateSelectionMarquee(coordinates: Vector2i) -> void:
	var bounds := makeGridRect(SelectionStartCoordinates, coordinates)
	SelectionOverlay.call("showGridRect", bounds, float(CellSize), false, true)

func finishSelection(coordinates: Vector2i) -> void:
	setSelection(makeGridRect(SelectionStartCoordinates, coordinates))
	CurrentInteractionMode = InteractionMode.Idle

func beginMove(coordinates: Vector2i) -> bool:
	if not canStartMoveAt(coordinates):
		return false
	CurrentInteractionMode = InteractionMode.Moving
	MoveStartCoordinates = coordinates
	MoveOffset = Vector2i.ZERO
	MovePreviewValid = false
	clearPreviewTiles()
	return true

func updateMovePreview(coordinates: Vector2i) -> void:
	MoveOffset = coordinates - MoveStartCoordinates
	var preview := getMovedTileMap(MoveOffset)
	MovePreviewValid = isMoveValid(preview)
	showPreviewTiles(preview, MovePreviewValid)
	SelectionOverlay.call("showGridRect", translateGridRect(SelectionBounds, MoveOffset), float(CellSize), true, MovePreviewValid)

func finishMove() -> void:
	if MoveOffset != Vector2i.ZERO and MovePreviewValid:
		var selectionBefore := getSelectionSnapshot()
		var targetValues := getMoveTargetValues(MoveOffset)
		var changes := makeChangesForTargetValues(targetValues)
		var selectionAfter := getMovedSelectionSnapshot(MoveOffset)
		if not changes.is_empty():
			applyChanges(changes, true)
			restoreSelection(selectionAfter)
			pushHistory(changes, selectionBefore, selectionAfter)
	clearPreviewTiles()
	if CurrentInteractionMode == InteractionMode.Moving:
		CurrentInteractionMode = InteractionMode.Idle
		refreshSelectionOverlay()

func getMovedTileMap(offset: Vector2i) -> Dictionary[Vector2i, Dictionary]:
	var tiles: Dictionary[Vector2i, Dictionary] = {}
	for coordinates in SelectedCells:
		var source := coordinates as Vector2i
		if TileValues.has(source):
			tiles[source + offset] = getTileValueAt(source)
	return tiles

func getMoveTargetValues(offset: Vector2i) -> Dictionary[Vector2i, Dictionary]:
	var targetValues: Dictionary[Vector2i, Dictionary] = {}
	for coordinates in SelectedCells:
		targetValues[coordinates as Vector2i] = {}
	for coordinates in SelectedCells:
		var source := coordinates as Vector2i
		if TileValues.has(source):
			targetValues[source + offset] = getTileValueAt(source)
	return targetValues

func isMoveValid(targetTiles: Dictionary[Vector2i, Dictionary]) -> bool:
	if targetTiles.is_empty():
		return false
	for coordinates in targetTiles:
		var target := coordinates as Vector2i
		if not isCoordinateValid(target):
			return false
		if TileValues.has(target) and not SelectedCells.has(target):
			return false
	return true

func getMovedSelectionSnapshot(offset: Vector2i) -> Dictionary:
	var cells: Array[Vector2i] = []
	for coordinates in SelectedCells:
		cells.append((coordinates as Vector2i) + offset)
	return {
		"bounds": translateGridRect(SelectionBounds, offset),
		"cells": cells,
	}

func copySelection() -> bool:
	if SelectedCells.is_empty():
		return false
	var tiles: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(SelectedCells.keys()):
		if TileValues.has(coordinates):
			var tileValue := getTileValueAt(coordinates)
			var clipboardTile := {
			"offset": coordinates - SelectionBounds.position,
			"toolId": tileValue["toolId"],
			"isOn": tileValue["isOn"],
			}
			if String(tileValue.get("toolId", "")) == "clock":
				clipboardTile["clockHoldTicks"] = int(tileValue.get("clockHoldTicks", ClockHoldTicksMinimum))
			if String(tileValue.get("toolId", "")) == "mesh":
				clipboardTile["meshId"] = int(tileValue.get("meshId", MeshIdMinimum))
			tiles.append(clipboardTile)
	var clipboardItem := {
		"bounds": Rect2i(Vector2i.ZERO, SelectionBounds.size),
		"boundsSize": SelectionBounds.size,
		"tiles": tiles,
	}
	ClipboardHistory.push_front(clipboardItem)
	while ClipboardHistory.size() > ClipboardHistoryLimit:
		ClipboardHistory.pop_back()
	SelectedClipboardIndex = 0
	emitClipboardChanged()
	clipboardCopied.emit(getClipboardHistory(), SelectedClipboardIndex)
	return true

func cutSelection() -> void:
	if SelectedCells.is_empty():
		return
	var selectionBefore := getSelectionSnapshot()
	if not copySelection():
		return
	var targetValues: Dictionary[Vector2i, Dictionary] = {}
	for coordinates in SelectedCells:
		targetValues[coordinates as Vector2i] = {}
	var changes := makeChangesForTargetValues(targetValues)
	if changes.is_empty():
		return
	applyChanges(changes, true)
	clearSelection()
	pushHistory(changes, selectionBefore, getSelectionSnapshot())

func deleteSelection() -> void:
	if SelectedCells.is_empty():
		return
	var selectionBefore := getSelectionSnapshot()
	var targetValues: Dictionary[Vector2i, Dictionary] = {}
	for coordinates in SelectedCells:
		targetValues[coordinates as Vector2i] = {}
	var changes := makeChangesForTargetValues(targetValues)
	if changes.is_empty():
		clearSelection()
		return
	applyChanges(changes, true)
	clearSelection()
	pushHistory(changes, selectionBefore, getSelectionSnapshot())

func beginPastePreview() -> void:
	if getSelectedClipboardItem().is_empty():
		return
	CurrentInteractionMode = InteractionMode.Pasting
	updatePastePreview(getGridCoordinates(get_global_mouse_position()), true)

func updatePastePreview(anchor: Vector2i, force := false) -> void:
	var clipboardItem := getSelectedClipboardItem()
	if clipboardItem.is_empty():
		return
	if not force and anchor == PasteAnchorCoordinates and not PreviewTileByCoordinates.is_empty():
		return
	PasteAnchorCoordinates = anchor
	var preview := getPasteTileMap(anchor, clipboardItem)
	PastePreviewValues = preview
	PastePreviewValid = isPasteValid(preview)
	showPreviewTiles(preview, PastePreviewValid)
	var boundsSize: Vector2i = clipboardItem.get("boundsSize", Vector2i.ONE)
	SelectionOverlay.call("showGridRect", Rect2i(anchor, boundsSize), float(CellSize), true, PastePreviewValid)

func updatePastePreviewAtPointer() -> void:
	if CurrentInteractionMode == InteractionMode.Pasting:
		updatePastePreview(getGridCoordinates(get_global_mouse_position()))

func confirmPastePreview() -> void:
	if CurrentInteractionMode != InteractionMode.Pasting or not PastePreviewValid or IsPastePreviewBuilding:
		return
	var clipboardItem := getSelectedClipboardItem()
	if clipboardItem.is_empty():
		return
	var targetValues := PastePreviewValues
	if targetValues.is_empty():
		targetValues = getPasteTileMap(PasteAnchorCoordinates, clipboardItem)
	var changes := makeChangesForTargetValues(targetValues)
	var selectionBefore := getSelectionSnapshot()
	var pastedCells: Array[Vector2i] = []
	for changeVariant in changes:
		var change := changeVariant as Dictionary
		pastedCells.append(change["coordinates"] as Vector2i)
	var selectionAfter := {
		"bounds": Rect2i(PasteAnchorCoordinates, clipboardItem.get("boundsSize", Vector2i.ONE)),
		"cells": pastedCells,
	}
	if not changes.is_empty():
		applyPasteChanges(changes)
		restoreSelection(selectionAfter)
		pushHistory(changes, selectionBefore, selectionAfter)
	cancelPastePreview(false)

func cancelPastePreview(clearSelectionOverlay := true) -> void:
	clearPreviewTiles()
	PastePreviewValid = false
	PastePreviewValues.clear()
	CurrentInteractionMode = InteractionMode.Idle
	if clearSelectionOverlay:
		refreshSelectionOverlay()

func getPasteTileMap(anchor: Vector2i, clipboardItem: Dictionary = {}) -> Dictionary[Vector2i, Dictionary]:
	var tiles: Dictionary[Vector2i, Dictionary] = {}
	for entryVariant in clipboardItem.get("tiles", []):
		var entry := entryVariant as Dictionary
		var offset: Vector2i = entry.get("offset", entry.get("position", Vector2i.ZERO))
		tiles[anchor + offset] = makeTileValue(
			String(entry.get("toolId", "")),
			entry.get("isOn", null),
			entry.get("clockHoldTicks", null),
			entry.get("meshId", null)
		)
	return tiles

func isPasteValid(targetTiles: Dictionary[Vector2i, Dictionary]) -> bool:
	if targetTiles.is_empty():
		return false
	for coordinates in targetTiles:
		var target := coordinates as Vector2i
		if not isCoordinateValid(target) or TileValues.has(target):
			return false
	return true

func undo() -> void:
	if UndoStack.is_empty():
		return
	cancelActiveInteraction()
	var command: Dictionary = UndoStack.pop_back()
	applyChanges(command["changes"], false)
	restoreSelection(command["selectionBefore"])
	RedoStack.append(command)

func redo() -> void:
	if RedoStack.is_empty():
		return
	cancelActiveInteraction()
	var command: Dictionary = RedoStack.pop_back()
	applyChanges(command["changes"], true)
	restoreSelection(command["selectionAfter"])
	UndoStack.append(command)

func cancelActiveInteraction() -> void:
	match CurrentInteractionMode:
		InteractionMode.Painting, InteractionMode.Deleting:
			rollbackActiveChanges()
		InteractionMode.Pasting:
			cancelPastePreview()
		InteractionMode.Moving:
			clearPreviewTiles()
		InteractionMode.ResizingCanvas:
			cancelCanvasResize()
		_:
			pass
	ActiveChanges.clear()
	ActiveSelectionBefore.clear()
	HasLastStrokeCoordinates = false
	CurrentInteractionMode = InteractionMode.Idle
	refreshSelectionOverlay()
	refreshCanvasResizeOverlay()

func rollbackActiveChanges() -> void:
	for change in getActiveChanges():
		setTileValue(change["coordinates"], change["beforeTile"])

func setSelection(bounds: Rect2i) -> void:
	SelectedCells.clear()
	SelectionBounds = bounds
	for x in range(bounds.position.x, bounds.end.x):
		for y in range(bounds.position.y, bounds.end.y):
			var coordinates := Vector2i(x, y)
			if TileValues.has(coordinates):
				SelectedCells[coordinates] = true
	if SelectedCells.is_empty():
		SelectionBounds = Rect2i()
	refreshSelectionOverlay()
	selectionChanged.emit(getSelectionSnapshot())

func clearSelection() -> void:
	if SelectedCells.is_empty():
		return
	SelectedCells.clear()
	SelectionBounds = Rect2i()
	refreshSelectionOverlay()
	selectionChanged.emit(getSelectionSnapshot())

func pruneSelection() -> Dictionary:
	var changed := false
	for coordinatesVariant in SelectedCells.keys():
		var coordinates := coordinatesVariant as Vector2i
		if not TileValues.has(coordinates):
			SelectedCells.erase(coordinates)
			changed = true
	if SelectedCells.is_empty() and SelectionBounds.size != Vector2i.ZERO:
		SelectionBounds = Rect2i()
		changed = true
	if changed:
		refreshSelectionOverlay()
		selectionChanged.emit(getSelectionSnapshot())
	return getSelectionSnapshot()

func restoreSelection(snapshot: Dictionary) -> void:
	SelectedCells.clear()
	SelectionBounds = snapshot.get("bounds", Rect2i())
	for coordinatesVariant in snapshot.get("cells", []):
		var coordinates := coordinatesVariant as Vector2i
		if TileValues.has(coordinates):
			SelectedCells[coordinates] = true
	if SelectedCells.is_empty():
		SelectionBounds = Rect2i()
	refreshSelectionOverlay()
	selectionChanged.emit(getSelectionSnapshot())

func getSelectionSnapshot() -> Dictionary:
	return {
		"bounds": SelectionBounds,
		"cells": getSortedCoordinates(SelectedCells.keys()),
	}

func refreshSelectionOverlay() -> void:
	if SelectedCells.is_empty():
		SelectionOverlay.call("clearOverlay")
		return
	SelectionOverlay.call("showGridRect", SelectionBounds, float(CellSize), true, true)

func showPreviewTiles(tiles: Dictionary[Vector2i, Dictionary], isValid: bool) -> void:
	if TileScene == null:
		clearPreviewTiles()
		return
	PreviewBuildGeneration += 1
	PreviewBuildState.clear()
	IsPastePreviewBuilding = false
	var previewColor := Color(1.0, 1.0, 1.0, 0.5) if isValid else Color(1.0, 0.44, 0.52, 0.58)
	var previewCoordinates: Array[Vector2i] = []
	var previewValues: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(tiles.keys()):
		var tileValue := normalizeTileValue(tiles[coordinates])
		var toolId := String(tileValue.get("toolId", ""))
		if ToolRegistry.has(toolId):
			previewCoordinates.append(coordinates)
			previewValues.append(tileValue)
	var existingTiles := PreviewTiles.get_children()
	PreviewTileByCoordinates.clear()
	var reusedCount := mini(existingTiles.size(), previewCoordinates.size())
	for index in reusedCount:
		configurePreviewTile(existingTiles[index] as Node2D, previewCoordinates[index], previewValues[index], previewColor, false)
	var createdCount := previewCoordinates.size()
	if CurrentInteractionMode == InteractionMode.Pasting and previewCoordinates.size() > PreviewBuildThreshold and reusedCount < previewCoordinates.size():
		createdCount = mini(reusedCount + PreviewBuildBatchSize, previewCoordinates.size())
	for index in range(reusedCount, createdCount):
		var tile := TileScene.instantiate() as Node2D
		PreviewTiles.add_child(tile)
		configurePreviewTile(tile, previewCoordinates[index], previewValues[index], previewColor, true)
	for index in range(createdCount, existingTiles.size()):
		(existingTiles[index] as Node2D).hide()
	if createdCount < previewCoordinates.size():
		PreviewBuildState = {
			"coordinates": previewCoordinates,
			"values": previewValues,
			"previewColor": previewColor,
			"nextIndex": createdCount,
		}
		IsPastePreviewBuilding = true
		schedulePastePreviewBatch(PreviewBuildGeneration)

func configurePreviewTile(tile: Node2D, coordinates: Vector2i, tileValue: Dictionary, previewColor: Color, isNew: bool) -> void:
	if isNew:
		tile.call("setup", self, coordinates, float(CellSize))
	else:
		tile.show()
		tile.call("updateGridCoordinates", self, coordinates)
	tile.position = Vector2(coordinates * CellSize) + Vector2.ONE * CellSize / 2.0
	var toolId := String(tileValue.get("toolId", ""))
	var isOn := bool(tileValue.get("isOn", false))
	if String(tile.get_meta("previewToolId", "")) != toolId or bool(tile.get_meta("previewIsOn", false)) != isOn:
		var attributes: Dictionary = ToolRegistry[toolId]
		tile.call("setAttributes", getTileIcon(toolId, isOn), attributes["color"], isOn)
		tile.set_meta("previewToolId", toolId)
		tile.set_meta("previewIsOn", isOn)
	tile.modulate = previewColor
	PreviewTileByCoordinates[coordinates] = tile

func schedulePastePreviewBatch(generation: int) -> void:
	get_tree().create_timer(0.0).timeout.connect(buildPastePreviewBatch.bind(generation), CONNECT_ONE_SHOT)

func buildPastePreviewBatch(generation: int) -> void:
	if generation != PreviewBuildGeneration or PreviewBuildState.is_empty() or TileScene == null:
		return
	var previewCoordinates: Array = PreviewBuildState["coordinates"]
	var previewValues: Array = PreviewBuildState["values"]
	var previewColor: Color = PreviewBuildState["previewColor"]
	var startIndex := int(PreviewBuildState["nextIndex"])
	var endIndex := mini(startIndex + PreviewBuildBatchSize, previewCoordinates.size())
	for index in range(startIndex, endIndex):
		var tile := TileScene.instantiate() as Node2D
		PreviewTiles.add_child(tile)
		configurePreviewTile(tile, previewCoordinates[index] as Vector2i, previewValues[index] as Dictionary, previewColor, true)
	PreviewBuildState["nextIndex"] = endIndex
	if endIndex >= previewCoordinates.size():
		PreviewBuildState.clear()
		IsPastePreviewBuilding = false
		return
	schedulePastePreviewBatch(generation)

func clearPreviewTiles() -> void:
	PreviewBuildGeneration += 1
	PreviewBuildState.clear()
	IsPastePreviewBuilding = false
	if PreviewTiles == null:
		return
	for tile in PreviewTiles.get_children():
		tile.free()
	PreviewTileByCoordinates.clear()

func makeChangesForTargetValues(targetValues: Dictionary) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(targetValues.keys()):
		var afterTile := normalizeTileValue(targetValues[coordinates])
		var beforeTile := getTileValueAt(coordinates)
		if beforeTile != afterTile:
			changes.append(makeChange(coordinates, beforeTile, afterTile))
	return changes

func makeChange(coordinates: Vector2i, beforeTile: Dictionary, afterTile: Dictionary) -> Dictionary:
	return {
		"coordinates": coordinates,
		"beforeTile": beforeTile.duplicate(true),
		"afterTile": afterTile.duplicate(true),
	}

func applyChanges(changes: Array, applyAfter: bool) -> void:
	for changeVariant in changes:
		var change := changeVariant as Dictionary
		var tileValue: Dictionary = (change["afterTile"] if applyAfter else change["beforeTile"]) as Dictionary
		setTileValue(change["coordinates"], tileValue)

func applyPasteChanges(changes: Array) -> void:
	if canPromotePastePreview(changes):
		promotePreviewTiles(changes)
		return
	for changeVariant in changes:
		var change := changeVariant as Dictionary
		var coordinates: Vector2i = change["coordinates"]
		var tileValue := change["afterTile"] as Dictionary
		var toolId := String(tileValue.get("toolId", ""))
		var previewTile := PreviewTileByCoordinates.get(coordinates) as Node2D
		if previewTile and previewTile.get_parent() == PreviewTiles and not toolId.is_empty() and not Occupancy.has(coordinates):
			previewTile.reparent(PlacedTiles)
			previewTile.modulate = Color.WHITE
			Occupancy[coordinates] = previewTile
			TileValues[coordinates] = tileValue.duplicate(true)
		else:
			setTileValue(coordinates, tileValue)
	PreviewTileByCoordinates.clear()

func canPromotePastePreview(changes: Array) -> bool:
	if IsPastePreviewBuilding or PreviewTiles == null or PreviewTileByCoordinates.size() != changes.size():
		return false
	for changeVariant in changes:
		var change := changeVariant as Dictionary
		var coordinates: Vector2i = change["coordinates"]
		var tileValue := change["afterTile"] as Dictionary
		var toolId := String(tileValue.get("toolId", ""))
		var previewTile := PreviewTileByCoordinates.get(coordinates) as Node2D
		if previewTile == null or previewTile.get_parent() != PreviewTiles or toolId.is_empty() or Occupancy.has(coordinates):
			return false
	return true

func promotePreviewTiles(changes: Array) -> void:
	for tile in PreviewTiles.get_children():
		if not tile.visible:
			tile.free()
	for changeVariant in changes:
		var change := changeVariant as Dictionary
		var coordinates: Vector2i = change["coordinates"]
		var previewTile := PreviewTileByCoordinates[coordinates]
		# Keep every committed tile in one Y-sorted tree so later placements interleave correctly.
		previewTile.reparent(PlacedTiles)
		previewTile.modulate = Color.WHITE
		Occupancy[coordinates] = previewTile
		TileValues[coordinates] = (change["afterTile"] as Dictionary).duplicate(true)
	PreviewTileByCoordinates.clear()

func pushHistory(changes: Array[Dictionary], selectionBefore: Dictionary, selectionAfter: Dictionary) -> void:
	if changes.is_empty():
		return
	UndoStack.append({
		"changes": changes,
		"selectionBefore": selectionBefore,
		"selectionAfter": selectionAfter,
	})
	RedoStack.clear()

func getActiveChanges() -> Array[Dictionary]:
	return makeChangesForActiveMap(ActiveChanges)

func makeChangesForActiveMap(changeMap: Dictionary) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(changeMap.keys()):
		changes.append(changeMap[coordinates])
	return changes

func makeTileValue(toolId: String, isOn: Variant = null, clockHoldTicks: Variant = null, meshId: Variant = null) -> Dictionary:
	if toolId.is_empty():
		return {}
	var defaultIsOn := LatchInitialState if toolId == "latch" else InkRegistry.getDefaultIsOn(toolId)
	var resolvedIsOn := defaultIsOn if isOn == null else bool(isOn)
	var tileValue := {
		"toolId": toolId,
		"isOn": resolvedIsOn,
	}
	if toolId == "clock":
		var resolvedClockHoldTicks := ClockHoldTicks if clockHoldTicks == null else normalizePositiveInteger(clockHoldTicks, ClockHoldTicksMinimum)
		tileValue["clockHoldTicks"] = resolvedClockHoldTicks
	if toolId == "mesh":
		var resolvedMeshId := MeshId if meshId == null else normalizePositiveInteger(meshId, MeshIdMinimum)
		tileValue["meshId"] = resolvedMeshId
	return tileValue

func normalizeTileValue(rawValue: Variant) -> Dictionary:
	if rawValue is Dictionary:
		var tileValue := rawValue as Dictionary
		return makeTileValue(
			String(tileValue.get("toolId", "")),
			tileValue.get("isOn", null),
			tileValue.get("clockHoldTicks", null),
			tileValue.get("meshId", null)
		)
	if rawValue is String:
		return makeTileValue(String(rawValue))
	return {}

func getTileValueAt(coordinates: Vector2i) -> Dictionary:
	return normalizeTileValue(TileValues.get(coordinates, {}))

func setTileTool(coordinates: Vector2i, toolId: String) -> bool:
	return setTileValue(coordinates, makeTileValue(toolId))

func setTileValue(coordinates: Vector2i, rawValue: Variant) -> bool:
	var tileValue := normalizeTileValue(rawValue)
	var toolId := String(tileValue.get("toolId", ""))
	if toolId.is_empty():
		if not TileValues.has(coordinates) and not Occupancy.has(coordinates):
			return false
		if Occupancy.has(coordinates):
			Occupancy[coordinates].queue_free()
			Occupancy.erase(coordinates)
		TileValues.erase(coordinates)
		RuntimeTileStates.erase(coordinates)
		return true
	if not isCoordinateValid(coordinates) or TileScene == null or not ToolRegistry.has(toolId):
		return false
	if Occupancy.has(coordinates) and getToolIdAt(coordinates) == toolId:
		TileValues[coordinates] = tileValue.duplicate(true)
		if RuntimeTileStates.has(coordinates) and bool(RuntimeTileStates[coordinates]) == getTileState(coordinates):
			RuntimeTileStates.erase(coordinates)
		updateTileVisualState(coordinates, getRuntimeTileState(coordinates))
		return true
	if Occupancy.has(coordinates):
		Occupancy[coordinates].queue_free()
		Occupancy.erase(coordinates)
	RuntimeTileStates.erase(coordinates)
	var isOn := bool(tileValue.get("isOn", false))
	var tile := TileScene.instantiate() as Node2D
	PlacedTiles.add_child(tile)
	tile.position = Vector2(coordinates * CellSize) + Vector2.ONE * CellSize / 2.0
	tile.call("setup", self, coordinates, float(CellSize))
	var attributes: Dictionary = ToolRegistry[toolId]
	tile.call("setAttributes", getTileIcon(toolId, isOn), attributes["color"], isOn)
	Occupancy[coordinates] = tile
	TileValues[coordinates] = tileValue.duplicate(true)
	return true

func setTileValueWithHistory(coordinates: Vector2i, rawValue: Variant) -> bool:
	var beforeTile := getTileValueAt(coordinates)
	var afterTile := normalizeTileValue(rawValue)
	if beforeTile == afterTile:
		return false
	var selectionSnapshot := getSelectionSnapshot()
	if not setTileValue(coordinates, afterTile):
		return false
	pushHistory([makeChange(coordinates, beforeTile, afterTile)], selectionSnapshot, selectionSnapshot)
	return true

func getSingleSelectedCoordinatesForTool(toolId: String) -> Variant:
	if SelectedCells.size() != 1:
		return null
	for coordinatesVariant in SelectedCells:
		var coordinates := coordinatesVariant as Vector2i
		if getToolIdAt(coordinates) == toolId:
			return coordinates
	return null

func normalizePositiveInteger(requestedValue: Variant, fallbackValue: int) -> int:
	if requestedValue == null:
		return fallbackValue
	return clampi(int(requestedValue), ClockHoldTicksMinimum, PositiveIntegerMaximum)

func isOptionalPositiveInteger(rawValue: Variant) -> bool:
	if rawValue == null:
		return true
	if rawValue is int:
		return int(rawValue) >= ClockHoldTicksMinimum and int(rawValue) <= PositiveIntegerMaximum
	if rawValue is float:
		var floatValue := float(rawValue)
		return floatValue >= float(ClockHoldTicksMinimum) and floatValue <= float(PositiveIntegerMaximum) and floatValue == floorf(floatValue)
	return false

func getToolIdAt(coordinates: Vector2i) -> String:
	return String(getTileValueAt(coordinates).get("toolId", ""))

func isCoordinateValid(coordinates: Vector2i) -> bool:
	return GridBounds.has_point(coordinates)

func makeGridRect(first: Vector2i, second: Vector2i) -> Rect2i:
	var origin := Vector2i(mini(first.x, second.x), mini(first.y, second.y))
	var end := Vector2i(maxi(first.x, second.x), maxi(first.y, second.y)) + Vector2i.ONE
	return Rect2i(origin, end - origin)

func translateGridRect(bounds: Rect2i, offset: Vector2i) -> Rect2i:
	return Rect2i(bounds.position + offset, bounds.size)

func getGridLine(first: Vector2i, second: Vector2i) -> Array[Vector2i]:
	var coordinates: Array[Vector2i] = []
	var x := first.x
	var y := first.y
	var deltaX := absi(second.x - first.x)
	var deltaY := -absi(second.y - first.y)
	var stepX := 1 if first.x < second.x else -1
	var stepY := 1 if first.y < second.y else -1
	var error := deltaX + deltaY
	while true:
		coordinates.append(Vector2i(x, y))
		if x == second.x and y == second.y:
			break
		var doubleError := error * 2
		if doubleError >= deltaY:
			error += deltaY
			x += stepX
		if doubleError <= deltaX:
			error += deltaX
			y += stepY
	return coordinates

func getSortedCoordinates(coordinates: Array) -> Array[Vector2i]:
	var sorted: Array[Vector2i] = []
	for coordinateVariant in coordinates:
		sorted.append(coordinateVariant as Vector2i)
	sorted.sort_custom(func(first: Vector2i, second: Vector2i) -> bool:
		if first.y == second.y:
			return first.x < second.x
		return first.y < second.y
	)
	return sorted

func updateSelectorPosition() -> void:
	var mousePosition := get_global_mouse_position()
	Selector.visible = CurrentInteractionMode == InteractionMode.Idle and ValidRect.has_point(mousePosition)
	if Selector.visible:
		Selector.position = Vector2(getGridCoordinates(mousePosition) * CellSize)

func getGridCoordinates(boardPosition: Vector2) -> Vector2i:
	return Vector2i(floori(boardPosition.x / CellSize), floori(boardPosition.y / CellSize))
