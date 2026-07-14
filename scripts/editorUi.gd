extends Control

@onready var board: Node2D = $BoardViewport/SubViewport/CircuitBoard
@onready var boardCamera: Camera2D = $BoardViewport/SubViewport/BoardCamera
@onready var wireButton: Button = $Interface/LeftBar/Content/WireButton
@onready var orGateButton: Button = $Interface/LeftBar/Content/OrGateButton
@onready var processorButton: Button = $Interface/LeftBar/Content/ProcessorButton
@onready var selectionLabel: Label = $Interface/RightBar/Content/Selection
@onready var toolDescription: Label = $Interface/RightBar/Content/ToolDescription
@onready var boardSizeLabel: Label = $Interface/LeftBar/Content/BoardSize
@onready var pointerLabel: Label = $Interface/LeftBar/Content/Pointer
@onready var zoomLabel: Label = $Interface/TopBar/Margin/Rows/CommandRow/ZoomLabel

var fullscreenExitMode := Window.MODE_WINDOWED

var toolDescriptions := {
	"wire": "Place a wire marker on an available cell.",
	"orGate": "Place an OR gate on an available cell.",
	"processor": "Place a processor on an available cell.",
}

var toolDisplayNames := {
	"wire": "Wire",
	"orGate": "OR Gate",
	"processor": "Processor",
}

func _ready() -> void:
	wireButton.pressed.connect(selectTool.bind("wire"))
	orGateButton.pressed.connect(selectTool.bind("orGate"))
	processorButton.pressed.connect(selectTool.bind("processor"))
	boardSizeLabel.text = "%d x %d cells" % [board.gridWidthCount, board.gridHeightCount]
	selectTool("orGate")

func _process(_delta: float) -> void:
	updatePointerStatus()
	zoomLabel.text = "Zoom %d%%" % roundi(boardCamera.zoom.x * 100.0)

func _input(event: InputEvent) -> void:
	var keyEvent := event as InputEventKey
	if keyEvent == null:
		return
	if not keyEvent.pressed or keyEvent.echo or not keyEvent.alt_pressed:
		return
	if keyEvent.keycode != KEY_ENTER and keyEvent.keycode != KEY_KP_ENTER:
		return
	toggleFullscreen()
	get_viewport().set_input_as_handled()

func toggleFullscreen() -> void:
	var window := get_window()
	if window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		window.mode = fullscreenExitMode
		return
	fullscreenExitMode = window.mode
	window.mode = Window.MODE_FULLSCREEN

func selectTool(toolId: String) -> void:
	board.call("selectTool", toolId)
	selectionLabel.text = toolDisplayNames[toolId]
	toolDescription.text = toolDescriptions[toolId]
	wireButton.button_pressed = toolId == "wire"
	orGateButton.button_pressed = toolId == "orGate"
	processorButton.button_pressed = toolId == "processor"

func updatePointerStatus() -> void:
	var mousePosition := board.get_global_mouse_position()
	if not board.validRect.has_point(mousePosition):
		pointerLabel.text = "Pointer: outside board"
		return
	var coordinates: Vector2i = board.call("getGridCoordinates", mousePosition)
	pointerLabel.text = "Pointer: %d, %d" % [coordinates.x, coordinates.y]
