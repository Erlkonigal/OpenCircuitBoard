extends Node2D

const InkRegistry := preload("res://scripts/inkRegistry.gd")
const SelectionOverlay := preload("res://scripts/selectionOverlay.gd")
const CircuitTile := preload("res://scripts/circuitTile.gd")
const clipboardHistoryLimit := 4
const previewBuildBatchSize := 64
const previewBuildThreshold := 128

enum InteractionMode {
	IDLE,
	PAINTING,
	DELETING,
	SELECTING,
	MOVING,
	PASTING,
}

signal clipboardChanged(history: Array[Dictionary], selectedIndex: int)
signal clipboardCopied(history: Array[Dictionary], selectedIndex: int)
signal selectionChanged(item: Dictionary)

@export_group("Board")
@export var cellSize := 64
@export var gridWidthCount := 40
@export var gridHeightCount := 28
@export var tileScene: PackedScene
@export var canvasBackground: ColorRect
@export var canvasShadow: ColorRect
@export var canvasBoard: ColorRect
@export var boardCamera: Camera2D
@export var canvasCornerRadius := 64.0
@export var canvasBackgroundMargin := 8192.0
@export var canvasShadowMargin := 256.0

@onready var selector: ColorRect = $Selector
@onready var placedTiles: Node2D = $PlacedTiles

var validRect := Rect2()
var occupancy: Dictionary[Vector2i, Node2D] = {}
var tileData: Dictionary[Vector2i, Dictionary] = {}
var selectedTool := "or"
var toolRegistry: Dictionary = {}
var editorInputEnabled := true
var interactionMode := InteractionMode.IDLE
var selectionStartCoordinates := Vector2i.ZERO
var moveStartCoordinates := Vector2i.ZERO
var moveOffset := Vector2i.ZERO
var movePreviewValid := false
var pasteAnchorCoordinates := Vector2i.ZERO
var pastePreviewValid := false
var pastePreviewValues: Dictionary[Vector2i, Dictionary] = {}
var lastStrokeCoordinates := Vector2i.ZERO
var hasLastStrokeCoordinates := false
var activeChanges: Dictionary[Vector2i, Dictionary] = {}
var activeSelectionBefore: Dictionary = {}
var selectedCells: Dictionary[Vector2i, bool] = {}
var selectionBounds := Rect2i()
var clipboardHistory: Array[Dictionary] = []
var selectedClipboardIndex := -1
var undoStack: Array[Dictionary] = []
var redoStack: Array[Dictionary] = []
var selectionOverlay: Node2D
var previewTiles: Node2D
var previewTileByCoordinates: Dictionary[Vector2i, Node2D] = {}
var previewBuildGeneration := 0
var previewBuildState: Dictionary = {}
var isPastePreviewBuilding := false

func _ready() -> void:
	toolRegistry = InkRegistry.getBoardToolRegistry()
	CircuitTile.warmGeometry(float(cellSize))
	var boardSize := Vector2(gridWidthCount * cellSize, gridHeightCount * cellSize)
	validRect = Rect2(-boardSize / 2.0, boardSize)
	configurePatternCanvas(
		canvasBackground,
		boardSize + Vector2.ONE * canvasBackgroundMargin * 2.0,
		validRect.position - Vector2.ONE * canvasBackgroundMargin,
		0.0
	)
	configureCanvasShadow(boardSize)
	configurePatternCanvas(canvasBoard, boardSize, validRect.position, canvasCornerRadius)
	if boardCamera and boardCamera.has_method("setDragBounds"):
		boardCamera.call("setDragBounds", validRect)
	selector.size = Vector2.ONE * cellSize
	selector.z_index = min(gridWidthCount * 2 + 100, RenderingServer.CANVAS_ITEM_Z_MAX)
	previewTiles = createPreviewTiles()
	selectionOverlay = SelectionOverlay.new()
	selectionOverlay.name = "SelectionOverlay"
	selectionOverlay.z_index = min(gridWidthCount * 4 + 100, RenderingServer.CANVAS_ITEM_Z_MAX)
	add_child(selectionOverlay)

func configurePatternCanvas(patternCanvas: ColorRect, patternCanvasSize: Vector2, patternCanvasPosition: Vector2, radius: float) -> void:
	if patternCanvas == null:
		return
	patternCanvas.size = patternCanvasSize
	patternCanvas.position = patternCanvasPosition
	var material := patternCanvas.material as ShaderMaterial
	if material:
		material.set_shader_parameter("patternSize", float(cellSize * 16))
		material.set_shader_parameter("boardSize", patternCanvasSize)
		material.set_shader_parameter("patternOrigin", patternCanvasPosition)
		material.set_shader_parameter("cornerRadius", radius)

func configureCanvasShadow(boardSize: Vector2) -> void:
	if canvasShadow == null:
		return
	var shadowMargin := Vector2.ONE * canvasShadowMargin
	canvasShadow.size = boardSize + shadowMargin * 2.0
	canvasShadow.position = validRect.position - shadowMargin
	var material := canvasShadow.material as ShaderMaterial
	if material:
		material.set_shader_parameter("boardSize", boardSize)
		material.set_shader_parameter("frameSize", canvasShadow.size)
		material.set_shader_parameter("boardOffset", shadowMargin)
		material.set_shader_parameter("cornerRadius", canvasCornerRadius)

func createPreviewTiles() -> Node2D:
	var tiles := Node2D.new()
	tiles.name = "PreviewTiles"
	tiles.z_index = gridWidthCount * 3
	add_child(tiles)
	return tiles

func _process(_delta: float) -> void:
	updateSelectorPosition()

func _unhandled_input(event: InputEvent) -> void:
	if not editorInputEnabled:
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
		if interactionMode == InteractionMode.PASTING:
			cancelPastePreview()
		elif interactionMode != InteractionMode.IDLE:
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
	if interactionMode == InteractionMode.PASTING:
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
		elif interactionMode == InteractionMode.DELETING:
			finishStroke()
			get_viewport().set_input_as_handled()
		return
	if event.pressed:
		var coordinates := getGridCoordinates(get_global_mouse_position())
		if handleLeftButtonPress(coordinates, event.shift_pressed):
			get_viewport().set_input_as_handled()
		return
	if interactionMode == InteractionMode.PAINTING:
		finishStroke()
	elif interactionMode == InteractionMode.SELECTING:
		finishSelection(getGridCoordinates(get_global_mouse_position()))
	elif interactionMode == InteractionMode.MOVING:
		finishMove()
	else:
		return
	get_viewport().set_input_as_handled()

func handleMouseMotion(event: InputEventMouseMotion) -> void:
	if interactionMode == InteractionMode.PASTING and event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		return
	var coordinates := getGridCoordinates(get_global_mouse_position())
	match interactionMode:
		InteractionMode.PAINTING, InteractionMode.DELETING:
			appendStrokeTo(coordinates)
		InteractionMode.SELECTING:
			updateSelectionMarquee(coordinates)
		InteractionMode.MOVING:
			updateMovePreview(coordinates)
		InteractionMode.PASTING:
			updatePastePreview(coordinates)
		_:
			return
	get_viewport().set_input_as_handled()

func selectTool(toolId: String) -> void:
	if toolRegistry.has(toolId):
		selectedTool = toolId

func placeTile(coordinates: Vector2i, toolId := selectedTool) -> bool:
	if not isCoordinateValid(coordinates) or tileData.has(coordinates):
		return false
	return setTileTool(coordinates, toolId)

func removeTile(coordinates: Vector2i) -> bool:
	if not tileData.has(coordinates):
		return false
	var removed := setTileTool(coordinates, "")
	if removed:
		pruneSelection()
	return removed

func getInkAt(coordinates: Vector2i) -> Dictionary:
	if not isCoordinateValid(coordinates) or not tileData.has(coordinates):
		return {}
	return InkRegistry.getInk(getToolIdAt(coordinates))

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

func getSimulationTiles() -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(tileData.keys()):
		var tileValue := getTileValueAt(coordinates)
		tiles.append({
			"coordinates": coordinates,
			"toolId": String(tileValue.get("toolId", "")),
			"isOn": bool(tileValue.get("isOn", false)),
		})
	return tiles

func exportProjectData() -> Dictionary:
	var tiles: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(tileData.keys()):
		var tileValue := getTileValueAt(coordinates)
		tiles.append({
			"x": coordinates.x,
			"y": coordinates.y,
			"toolId": String(tileValue.get("toolId", "")),
			"isOn": bool(tileValue.get("isOn", false)),
		})
	return {
		"selectedTool": selectedTool,
		"tiles": tiles,
	}

func importProjectData(projectData: Dictionary) -> bool:
	var rawTiles: Variant = projectData.get("tiles", [])
	if not (rawTiles is Array):
		return false
	var nextTiles: Dictionary[Vector2i, Dictionary] = {}
	for rawTileVariant in rawTiles:
		if not (rawTileVariant is Dictionary):
			return false
		var rawTile := rawTileVariant as Dictionary
		if not rawTile.has("x") or not rawTile.has("y") or not rawTile.has("toolId"):
			return false
		var coordinates := Vector2i(int(rawTile["x"]), int(rawTile["y"]))
		var toolId := String(rawTile["toolId"])
		if nextTiles.has(coordinates) or not isCoordinateValid(coordinates) or not toolRegistry.has(toolId):
			return false
		nextTiles[coordinates] = makeTileValue(toolId, rawTile.get("isOn", null))
	var requestedTool := String(projectData.get("selectedTool", "or"))
	if not toolRegistry.has(requestedTool):
		requestedTool = "or"
	cancelActiveInteraction()
	clearPreviewTiles()
	for tile in placedTiles.get_children():
		tile.free()
	occupancy.clear()
	tileData.clear()
	for coordinates in getSortedCoordinates(nextTiles.keys()):
		if not setTileValue(coordinates, nextTiles[coordinates]):
			return false
	selectedTool = requestedTool
	undoStack.clear()
	redoStack.clear()
	selectedCells.clear()
	selectionBounds = Rect2i()
	clipboardHistory.clear()
	selectedClipboardIndex = -1
	refreshSelectionOverlay()
	selectionChanged.emit(getSelectionSnapshot())
	emitClipboardChanged()
	return true

func clearProjectData() -> void:
	importProjectData({"selectedTool": "or", "tiles": []})

func setEditorInputEnabled(isEnabled: bool) -> void:
	if editorInputEnabled == isEnabled:
		return
	editorInputEnabled = isEnabled
	if not editorInputEnabled:
		cancelActiveInteraction()

func getClipboardItem() -> Dictionary:
	return getSelectedClipboardItem().duplicate(true)

func getSelectedClipboardItem() -> Dictionary:
	if selectedClipboardIndex < 0 or selectedClipboardIndex >= clipboardHistory.size():
		return {}
	return clipboardHistory[selectedClipboardIndex]

func getClipboardHistory() -> Array[Dictionary]:
	var history: Array[Dictionary] = []
	for item in clipboardHistory:
		history.append(item.duplicate(true))
	return history

func getSelectedClipboardIndex() -> int:
	return selectedClipboardIndex

func selectClipboardItem(index: int) -> bool:
	if index < 0 or index >= clipboardHistory.size():
		return false
	selectedClipboardIndex = index
	if interactionMode == InteractionMode.PASTING:
		updatePastePreview(pasteAnchorCoordinates, true)
	emitClipboardChanged()
	return true

func emitClipboardChanged() -> void:
	clipboardChanged.emit(getClipboardHistory(), selectedClipboardIndex)

func getSelectionItem() -> Dictionary:
	return getSelectionSnapshot()

func canStartMoveAt(coordinates: Vector2i) -> bool:
	return not selectedCells.is_empty() and selectionBounds.has_point(coordinates)

func handleLeftButtonPress(coordinates: Vector2i, isSelectionModifierPressed: bool) -> bool:
	if isSelectionModifierPressed:
		if not isCoordinateValid(coordinates):
			return false
		beginSelection(coordinates)
	elif not selectedCells.is_empty():
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
	if not selectedCells.is_empty():
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
	interactionMode = InteractionMode.PAINTING if shouldPlace else InteractionMode.DELETING
	activeChanges.clear()
	activeSelectionBefore = getSelectionSnapshot()
	hasLastStrokeCoordinates = false
	appendStrokeTo(coordinates)

func appendStrokeTo(coordinates: Vector2i) -> void:
	if not isCoordinateValid(coordinates):
		hasLastStrokeCoordinates = false
		return
	var path: Array[Vector2i] = [coordinates]
	if hasLastStrokeCoordinates:
		path = getGridLine(lastStrokeCoordinates, coordinates)
	for point in path:
		applyStrokeAt(point, interactionMode == InteractionMode.PAINTING)
	lastStrokeCoordinates = coordinates
	hasLastStrokeCoordinates = true

func applyStrokeAt(coordinates: Vector2i, shouldPlace: bool) -> void:
	if not isCoordinateValid(coordinates):
		return
	var afterToolId := selectedTool if shouldPlace else ""
	if activeChanges.has(coordinates):
		return
	var beforeToolId := getToolIdAt(coordinates)
	if beforeToolId == afterToolId:
		return
	var change := makeChange(coordinates, getTileValueAt(coordinates), makeTileValue(afterToolId))
	activeChanges[coordinates] = change
	setTileValue(coordinates, change["afterTile"])

func finishStroke() -> void:
	var changes := getActiveChanges()
	if not changes.is_empty():
		var selectionAfter := pruneSelection()
		pushHistory(changes, activeSelectionBefore, selectionAfter)
	activeChanges.clear()
	activeSelectionBefore.clear()
	hasLastStrokeCoordinates = false
	interactionMode = InteractionMode.IDLE

func beginSelection(coordinates: Vector2i) -> void:
	interactionMode = InteractionMode.SELECTING
	selectionStartCoordinates = coordinates
	updateSelectionMarquee(coordinates)

func updateSelectionMarquee(coordinates: Vector2i) -> void:
	var bounds := makeGridRect(selectionStartCoordinates, coordinates)
	selectionOverlay.call("showGridRect", bounds, float(cellSize), false, true)

func finishSelection(coordinates: Vector2i) -> void:
	setSelection(makeGridRect(selectionStartCoordinates, coordinates))
	interactionMode = InteractionMode.IDLE

func beginMove(coordinates: Vector2i) -> bool:
	if not canStartMoveAt(coordinates):
		return false
	interactionMode = InteractionMode.MOVING
	moveStartCoordinates = coordinates
	moveOffset = Vector2i.ZERO
	movePreviewValid = false
	clearPreviewTiles()
	return true

func updateMovePreview(coordinates: Vector2i) -> void:
	moveOffset = coordinates - moveStartCoordinates
	var preview := getMovedTileMap(moveOffset)
	movePreviewValid = isMoveValid(preview)
	showPreviewTiles(preview, movePreviewValid)
	selectionOverlay.call("showGridRect", translateGridRect(selectionBounds, moveOffset), float(cellSize), true, movePreviewValid)

func finishMove() -> void:
	if moveOffset != Vector2i.ZERO and movePreviewValid:
		var selectionBefore := getSelectionSnapshot()
		var targetValues := getMoveTargetValues(moveOffset)
		var changes := makeChangesForTargetValues(targetValues)
		var selectionAfter := getMovedSelectionSnapshot(moveOffset)
		if not changes.is_empty():
			applyChanges(changes, true)
			restoreSelection(selectionAfter)
			pushHistory(changes, selectionBefore, selectionAfter)
	clearPreviewTiles()
	if interactionMode == InteractionMode.MOVING:
		interactionMode = InteractionMode.IDLE
		refreshSelectionOverlay()

func getMovedTileMap(offset: Vector2i) -> Dictionary[Vector2i, Dictionary]:
	var tiles: Dictionary[Vector2i, Dictionary] = {}
	for coordinates in selectedCells:
		var source := coordinates as Vector2i
		if tileData.has(source):
			tiles[source + offset] = getTileValueAt(source)
	return tiles

func getMoveTargetValues(offset: Vector2i) -> Dictionary[Vector2i, Dictionary]:
	var targetValues: Dictionary[Vector2i, Dictionary] = {}
	for coordinates in selectedCells:
		targetValues[coordinates as Vector2i] = {}
	for coordinates in selectedCells:
		var source := coordinates as Vector2i
		if tileData.has(source):
			targetValues[source + offset] = getTileValueAt(source)
	return targetValues

func isMoveValid(targetTiles: Dictionary[Vector2i, Dictionary]) -> bool:
	if targetTiles.is_empty():
		return false
	for coordinates in targetTiles:
		var target := coordinates as Vector2i
		if not isCoordinateValid(target):
			return false
		if tileData.has(target) and not selectedCells.has(target):
			return false
	return true

func getMovedSelectionSnapshot(offset: Vector2i) -> Dictionary:
	var cells: Array[Vector2i] = []
	for coordinates in selectedCells:
		cells.append((coordinates as Vector2i) + offset)
	return {
		"bounds": translateGridRect(selectionBounds, offset),
		"cells": cells,
	}

func copySelection() -> bool:
	if selectedCells.is_empty():
		return false
	var tiles: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(selectedCells.keys()):
		if tileData.has(coordinates):
			var tileValue := getTileValueAt(coordinates)
			tiles.append({
			"offset": coordinates - selectionBounds.position,
			"toolId": tileValue["toolId"],
			"isOn": tileValue["isOn"],
		})
	var clipboardItem := {
		"bounds": Rect2i(Vector2i.ZERO, selectionBounds.size),
		"boundsSize": selectionBounds.size,
		"tiles": tiles,
	}
	clipboardHistory.push_front(clipboardItem)
	while clipboardHistory.size() > clipboardHistoryLimit:
		clipboardHistory.pop_back()
	selectedClipboardIndex = 0
	emitClipboardChanged()
	clipboardCopied.emit(getClipboardHistory(), selectedClipboardIndex)
	return true

func cutSelection() -> void:
	if selectedCells.is_empty():
		return
	var selectionBefore := getSelectionSnapshot()
	if not copySelection():
		return
	var targetValues: Dictionary[Vector2i, Dictionary] = {}
	for coordinates in selectedCells:
		targetValues[coordinates as Vector2i] = {}
	var changes := makeChangesForTargetValues(targetValues)
	if changes.is_empty():
		return
	applyChanges(changes, true)
	clearSelection()
	pushHistory(changes, selectionBefore, getSelectionSnapshot())

func deleteSelection() -> void:
	if selectedCells.is_empty():
		return
	var selectionBefore := getSelectionSnapshot()
	var targetValues: Dictionary[Vector2i, Dictionary] = {}
	for coordinates in selectedCells:
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
	interactionMode = InteractionMode.PASTING
	updatePastePreview(getGridCoordinates(get_global_mouse_position()), true)

func updatePastePreview(anchor: Vector2i, force := false) -> void:
	var clipboardItem := getSelectedClipboardItem()
	if clipboardItem.is_empty():
		return
	if not force and anchor == pasteAnchorCoordinates and not previewTileByCoordinates.is_empty():
		return
	pasteAnchorCoordinates = anchor
	var preview := getPasteTileMap(anchor, clipboardItem)
	pastePreviewValues = preview
	pastePreviewValid = isPasteValid(preview)
	showPreviewTiles(preview, pastePreviewValid)
	var boundsSize: Vector2i = clipboardItem.get("boundsSize", Vector2i.ONE)
	selectionOverlay.call("showGridRect", Rect2i(anchor, boundsSize), float(cellSize), true, pastePreviewValid)

func updatePastePreviewAtPointer() -> void:
	if interactionMode == InteractionMode.PASTING:
		updatePastePreview(getGridCoordinates(get_global_mouse_position()))

func confirmPastePreview() -> void:
	if interactionMode != InteractionMode.PASTING or not pastePreviewValid or isPastePreviewBuilding:
		return
	var clipboardItem := getSelectedClipboardItem()
	if clipboardItem.is_empty():
		return
	var targetValues := pastePreviewValues
	if targetValues.is_empty():
		targetValues = getPasteTileMap(pasteAnchorCoordinates, clipboardItem)
	var changes := makeChangesForTargetValues(targetValues)
	var selectionBefore := getSelectionSnapshot()
	var pastedCells: Array[Vector2i] = []
	for changeVariant in changes:
		var change := changeVariant as Dictionary
		pastedCells.append(change["coordinates"] as Vector2i)
	var selectionAfter := {
		"bounds": Rect2i(pasteAnchorCoordinates, clipboardItem.get("boundsSize", Vector2i.ONE)),
		"cells": pastedCells,
	}
	if not changes.is_empty():
		applyPasteChanges(changes)
		restoreSelection(selectionAfter)
		pushHistory(changes, selectionBefore, selectionAfter)
	cancelPastePreview(false)

func cancelPastePreview(clearSelectionOverlay := true) -> void:
	clearPreviewTiles()
	pastePreviewValid = false
	pastePreviewValues.clear()
	interactionMode = InteractionMode.IDLE
	if clearSelectionOverlay:
		refreshSelectionOverlay()

func getPasteTileMap(anchor: Vector2i, clipboardItem: Dictionary = {}) -> Dictionary[Vector2i, Dictionary]:
	var tiles: Dictionary[Vector2i, Dictionary] = {}
	for entryVariant in clipboardItem.get("tiles", []):
		var entry := entryVariant as Dictionary
		var offset: Vector2i = entry.get("offset", entry.get("position", Vector2i.ZERO))
		tiles[anchor + offset] = makeTileValue(String(entry.get("toolId", "")), entry.get("isOn", null))
	return tiles

func isPasteValid(targetTiles: Dictionary[Vector2i, Dictionary]) -> bool:
	if targetTiles.is_empty():
		return false
	for coordinates in targetTiles:
		var target := coordinates as Vector2i
		if not isCoordinateValid(target) or tileData.has(target):
			return false
	return true

func undo() -> void:
	if undoStack.is_empty():
		return
	cancelActiveInteraction()
	var command: Dictionary = undoStack.pop_back()
	applyChanges(command["changes"], false)
	restoreSelection(command["selectionBefore"])
	redoStack.append(command)

func redo() -> void:
	if redoStack.is_empty():
		return
	cancelActiveInteraction()
	var command: Dictionary = redoStack.pop_back()
	applyChanges(command["changes"], true)
	restoreSelection(command["selectionAfter"])
	undoStack.append(command)

func cancelActiveInteraction() -> void:
	match interactionMode:
		InteractionMode.PAINTING, InteractionMode.DELETING:
			rollbackActiveChanges()
		InteractionMode.PASTING:
			cancelPastePreview()
		InteractionMode.MOVING:
			clearPreviewTiles()
		_:
			pass
	activeChanges.clear()
	activeSelectionBefore.clear()
	hasLastStrokeCoordinates = false
	interactionMode = InteractionMode.IDLE
	refreshSelectionOverlay()

func rollbackActiveChanges() -> void:
	for change in getActiveChanges():
		setTileValue(change["coordinates"], change["beforeTile"])

func setSelection(bounds: Rect2i) -> void:
	selectedCells.clear()
	selectionBounds = bounds
	for x in range(bounds.position.x, bounds.end.x):
		for y in range(bounds.position.y, bounds.end.y):
			var coordinates := Vector2i(x, y)
			if tileData.has(coordinates):
				selectedCells[coordinates] = true
	if selectedCells.is_empty():
		selectionBounds = Rect2i()
	refreshSelectionOverlay()
	selectionChanged.emit(getSelectionSnapshot())

func clearSelection() -> void:
	if selectedCells.is_empty():
		return
	selectedCells.clear()
	selectionBounds = Rect2i()
	refreshSelectionOverlay()
	selectionChanged.emit(getSelectionSnapshot())

func pruneSelection() -> Dictionary:
	var changed := false
	for coordinatesVariant in selectedCells.keys():
		var coordinates := coordinatesVariant as Vector2i
		if not tileData.has(coordinates):
			selectedCells.erase(coordinates)
			changed = true
	if selectedCells.is_empty() and selectionBounds.size != Vector2i.ZERO:
		selectionBounds = Rect2i()
		changed = true
	if changed:
		refreshSelectionOverlay()
		selectionChanged.emit(getSelectionSnapshot())
	return getSelectionSnapshot()

func restoreSelection(snapshot: Dictionary) -> void:
	selectedCells.clear()
	selectionBounds = snapshot.get("bounds", Rect2i())
	for coordinatesVariant in snapshot.get("cells", []):
		var coordinates := coordinatesVariant as Vector2i
		if tileData.has(coordinates):
			selectedCells[coordinates] = true
	if selectedCells.is_empty():
		selectionBounds = Rect2i()
	refreshSelectionOverlay()
	selectionChanged.emit(getSelectionSnapshot())

func getSelectionSnapshot() -> Dictionary:
	return {
		"bounds": selectionBounds,
		"cells": getSortedCoordinates(selectedCells.keys()),
	}

func refreshSelectionOverlay() -> void:
	if selectedCells.is_empty():
		selectionOverlay.call("clearOverlay")
		return
	selectionOverlay.call("showGridRect", selectionBounds, float(cellSize), true, true)

func showPreviewTiles(tiles: Dictionary[Vector2i, Dictionary], isValid: bool) -> void:
	if tileScene == null:
		clearPreviewTiles()
		return
	previewBuildGeneration += 1
	previewBuildState.clear()
	isPastePreviewBuilding = false
	var previewColor := Color(1.0, 1.0, 1.0, 0.5) if isValid else Color(1.0, 0.44, 0.52, 0.58)
	var previewCoordinates: Array[Vector2i] = []
	var previewValues: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(tiles.keys()):
		var tileValue := normalizeTileValue(tiles[coordinates])
		var toolId := String(tileValue.get("toolId", ""))
		if toolRegistry.has(toolId):
			previewCoordinates.append(coordinates)
			previewValues.append(tileValue)
	var existingTiles := previewTiles.get_children()
	previewTileByCoordinates.clear()
	var reusedCount := mini(existingTiles.size(), previewCoordinates.size())
	for index in reusedCount:
		configurePreviewTile(existingTiles[index] as Node2D, previewCoordinates[index], previewValues[index], previewColor, false)
	var createdCount := previewCoordinates.size()
	if interactionMode == InteractionMode.PASTING and previewCoordinates.size() > previewBuildThreshold and reusedCount < previewCoordinates.size():
		createdCount = mini(reusedCount + previewBuildBatchSize, previewCoordinates.size())
	for index in range(reusedCount, createdCount):
		var tile := tileScene.instantiate() as Node2D
		previewTiles.add_child(tile)
		configurePreviewTile(tile, previewCoordinates[index], previewValues[index], previewColor, true)
	for index in range(createdCount, existingTiles.size()):
		(existingTiles[index] as Node2D).hide()
	if createdCount < previewCoordinates.size():
		previewBuildState = {
			"coordinates": previewCoordinates,
			"values": previewValues,
			"previewColor": previewColor,
			"nextIndex": createdCount,
		}
		isPastePreviewBuilding = true
		schedulePastePreviewBatch(previewBuildGeneration)

func configurePreviewTile(tile: Node2D, coordinates: Vector2i, tileValue: Dictionary, previewColor: Color, isNew: bool) -> void:
	if isNew:
		tile.call("setup", self, coordinates, float(cellSize))
	else:
		tile.show()
		tile.call("updateGridCoordinates", self, coordinates)
	tile.position = Vector2(coordinates * cellSize) + Vector2.ONE * cellSize / 2.0
	var toolId := String(tileValue.get("toolId", ""))
	var isOn := bool(tileValue.get("isOn", false))
	if String(tile.get_meta("previewToolId", "")) != toolId or bool(tile.get_meta("previewIsOn", false)) != isOn:
		var attributes: Dictionary = toolRegistry[toolId]
		tile.call("setAttributes", attributes["icon"], attributes["color"], isOn)
		tile.set_meta("previewToolId", toolId)
		tile.set_meta("previewIsOn", isOn)
	tile.modulate = previewColor
	previewTileByCoordinates[coordinates] = tile

func schedulePastePreviewBatch(generation: int) -> void:
	get_tree().create_timer(0.0).timeout.connect(buildPastePreviewBatch.bind(generation), CONNECT_ONE_SHOT)

func buildPastePreviewBatch(generation: int) -> void:
	if generation != previewBuildGeneration or previewBuildState.is_empty() or tileScene == null:
		return
	var previewCoordinates: Array = previewBuildState["coordinates"]
	var previewValues: Array = previewBuildState["values"]
	var previewColor: Color = previewBuildState["previewColor"]
	var startIndex := int(previewBuildState["nextIndex"])
	var endIndex := mini(startIndex + previewBuildBatchSize, previewCoordinates.size())
	for index in range(startIndex, endIndex):
		var tile := tileScene.instantiate() as Node2D
		previewTiles.add_child(tile)
		configurePreviewTile(tile, previewCoordinates[index] as Vector2i, previewValues[index] as Dictionary, previewColor, true)
	previewBuildState["nextIndex"] = endIndex
	if endIndex >= previewCoordinates.size():
		previewBuildState.clear()
		isPastePreviewBuilding = false
		return
	schedulePastePreviewBatch(generation)

func clearPreviewTiles() -> void:
	previewBuildGeneration += 1
	previewBuildState.clear()
	isPastePreviewBuilding = false
	if previewTiles == null:
		return
	for tile in previewTiles.get_children():
		tile.free()
	previewTileByCoordinates.clear()

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
		var previewTile := previewTileByCoordinates.get(coordinates) as Node2D
		if previewTile and previewTile.get_parent() == previewTiles and not toolId.is_empty() and not occupancy.has(coordinates):
			previewTile.reparent(placedTiles)
			previewTile.modulate = Color.WHITE
			occupancy[coordinates] = previewTile
			tileData[coordinates] = tileValue.duplicate(true)
		else:
			setTileValue(coordinates, tileValue)
	previewTileByCoordinates.clear()

func canPromotePastePreview(changes: Array) -> bool:
	if isPastePreviewBuilding or previewTiles == null or previewTileByCoordinates.size() != changes.size():
		return false
	for changeVariant in changes:
		var change := changeVariant as Dictionary
		var coordinates: Vector2i = change["coordinates"]
		var tileValue := change["afterTile"] as Dictionary
		var toolId := String(tileValue.get("toolId", ""))
		var previewTile := previewTileByCoordinates.get(coordinates) as Node2D
		if previewTile == null or previewTile.get_parent() != previewTiles or toolId.is_empty() or occupancy.has(coordinates):
			return false
	return true

func promotePreviewTiles(changes: Array) -> void:
	for tile in previewTiles.get_children():
		if not tile.visible:
			tile.free()
	for changeVariant in changes:
		var change := changeVariant as Dictionary
		var coordinates: Vector2i = change["coordinates"]
		var previewTile := previewTileByCoordinates[coordinates]
		# Keep every committed tile in one Y-sorted tree so later placements interleave correctly.
		previewTile.reparent(placedTiles)
		previewTile.modulate = Color.WHITE
		occupancy[coordinates] = previewTile
		tileData[coordinates] = (change["afterTile"] as Dictionary).duplicate(true)
	previewTileByCoordinates.clear()

func pushHistory(changes: Array[Dictionary], selectionBefore: Dictionary, selectionAfter: Dictionary) -> void:
	if changes.is_empty():
		return
	undoStack.append({
		"changes": changes,
		"selectionBefore": selectionBefore,
		"selectionAfter": selectionAfter,
	})
	redoStack.clear()

func getActiveChanges() -> Array[Dictionary]:
	return makeChangesForActiveMap(activeChanges)

func makeChangesForActiveMap(changeMap: Dictionary) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	for coordinates in getSortedCoordinates(changeMap.keys()):
		changes.append(changeMap[coordinates])
	return changes

func makeTileValue(toolId: String, isOn: Variant = null) -> Dictionary:
	if toolId.is_empty():
		return {}
	var resolvedIsOn := InkRegistry.getDefaultIsOn(toolId) if isOn == null else bool(isOn)
	return {
		"toolId": toolId,
		"isOn": resolvedIsOn,
	}

func normalizeTileValue(rawValue: Variant) -> Dictionary:
	if rawValue is Dictionary:
		var tileValue := rawValue as Dictionary
		return makeTileValue(String(tileValue.get("toolId", "")), tileValue.get("isOn", null))
	if rawValue is String:
		return makeTileValue(String(rawValue))
	return {}

func getTileValueAt(coordinates: Vector2i) -> Dictionary:
	return normalizeTileValue(tileData.get(coordinates, {}))

func setTileTool(coordinates: Vector2i, toolId: String) -> bool:
	return setTileValue(coordinates, makeTileValue(toolId))

func setTileValue(coordinates: Vector2i, rawValue: Variant) -> bool:
	var tileValue := normalizeTileValue(rawValue)
	var toolId := String(tileValue.get("toolId", ""))
	if toolId.is_empty():
		if not tileData.has(coordinates) and not occupancy.has(coordinates):
			return false
		if occupancy.has(coordinates):
			occupancy[coordinates].queue_free()
			occupancy.erase(coordinates)
		tileData.erase(coordinates)
		return true
	if not isCoordinateValid(coordinates) or tileScene == null or not toolRegistry.has(toolId):
		return false
	var isOn := bool(tileValue.get("isOn", false))
	if occupancy.has(coordinates) and getToolIdAt(coordinates) == toolId:
		tileData[coordinates] = tileValue.duplicate(true)
		occupancy[coordinates].call("setInkState", isOn)
		return true
	if occupancy.has(coordinates):
		occupancy[coordinates].queue_free()
		occupancy.erase(coordinates)
	var tile := tileScene.instantiate() as Node2D
	placedTiles.add_child(tile)
	tile.position = Vector2(coordinates * cellSize) + Vector2.ONE * cellSize / 2.0
	tile.call("setup", self, coordinates, float(cellSize))
	var attributes: Dictionary = toolRegistry[toolId]
	tile.call("setAttributes", attributes["icon"], attributes["color"], isOn)
	occupancy[coordinates] = tile
	tileData[coordinates] = tileValue.duplicate(true)
	return true

func getToolIdAt(coordinates: Vector2i) -> String:
	return String(getTileValueAt(coordinates).get("toolId", ""))

func isCoordinateValid(coordinates: Vector2i) -> bool:
	var cellCenter := Vector2(coordinates * cellSize) + Vector2.ONE * cellSize * 0.5
	return validRect.has_point(cellCenter)

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
	selector.visible = interactionMode == InteractionMode.IDLE and validRect.has_point(mousePosition)
	if selector.visible:
		selector.position = Vector2(getGridCoordinates(mousePosition) * cellSize)

func getGridCoordinates(boardPosition: Vector2) -> Vector2i:
	return Vector2i(floori(boardPosition.x / cellSize), floori(boardPosition.y / cellSize))
