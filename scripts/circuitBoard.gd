extends Node2D

const orGateIcon := preload("res://assets/orGate.svg")

@export_group("Board")
@export var cellSize := 64
@export var gridWidthCount := 40
@export var gridHeightCount := 28
@export var tileScene: PackedScene
@export var canvasBoard: ColorRect
@export var boardCamera: Camera2D

@onready var selector: ColorRect = $Selector
@onready var placedTiles: Node2D = $PlacedTiles

var validRect := Rect2()
var occupancy: Dictionary[Vector2i, Node2D] = {}
var selectedTool := "orGate"
var toolRegistry := {
	"wire": {"color": Color("bdc3c7"), "icon": null},
	"orGate": {"color": Color("2ecc71"), "icon": orGateIcon},
	"processor": {"color": Color("e74c3c"), "icon": null},
}

func _ready() -> void:
	var boardSize := Vector2(gridWidthCount * cellSize, gridHeightCount * cellSize)
	validRect = Rect2(-boardSize / 2.0, boardSize)
	canvasBoard.size = boardSize
	canvasBoard.position = validRect.position
	var material := canvasBoard.material as ShaderMaterial
	if material:
		material.set_shader_parameter("cellSize", float(cellSize))
		material.set_shader_parameter("boardSize", boardSize)
	if boardCamera and boardCamera.has_method("setDragBounds"):
		boardCamera.call("setDragBounds", validRect)
	selector.size = Vector2.ONE * cellSize
	selector.z_index = min(gridWidthCount * 2 + 100, RenderingServer.CANVAS_ITEM_Z_MAX)

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
