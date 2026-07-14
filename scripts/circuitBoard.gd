extends Node2D

const InkRegistry := preload("res://scripts/inkRegistry.gd")

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
var selectedTool := "or"
var toolRegistry: Dictionary = {}

func _ready() -> void:
	toolRegistry = InkRegistry.getBoardToolRegistry()
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

func _process(_delta: float) -> void:
	updateSelectorPosition()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	var coordinates := getGridCoordinates(get_global_mouse_position())
	if not validRect.has_point(get_global_mouse_position()):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		placeTile(coordinates)
	else:
		removeTile(coordinates)

func selectTool(toolId: String) -> void:
	if toolRegistry.has(toolId):
		selectedTool = toolId

func placeTile(coordinates: Vector2i) -> void:
	if occupancy.has(coordinates) or tileScene == null:
		return
	var tile := tileScene.instantiate() as Node2D
	placedTiles.add_child(tile)
	tile.position = Vector2(coordinates * cellSize) + Vector2.ONE * cellSize / 2.0
	tile.call("setup", self, coordinates, float(cellSize))
	var attributes: Dictionary = toolRegistry[selectedTool]
	tile.call("setAttributes", attributes["icon"], attributes["color"])
	occupancy[coordinates] = tile

func removeTile(coordinates: Vector2i) -> void:
	if occupancy.has(coordinates):
		occupancy[coordinates].queue_free()
		occupancy.erase(coordinates)

func updateSelectorPosition() -> void:
	var mousePosition := get_global_mouse_position()
	selector.visible = validRect.has_point(mousePosition)
	if selector.visible:
		selector.position = Vector2(getGridCoordinates(mousePosition) * cellSize)

func getGridCoordinates(boardPosition: Vector2) -> Vector2i:
	return Vector2i(floori(boardPosition.x / cellSize), floori(boardPosition.y / cellSize))
