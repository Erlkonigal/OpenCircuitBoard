extends Control

@onready var topBar: Panel = $Interface/TopBar
@onready var leftBar: PanelContainer = $Interface/LeftBar
@onready var rightBar: PanelContainer = $Interface/RightBar
@onready var board: Node2D = $BoardViewport/SubViewport/CircuitBoard
@onready var selectionLabel: Label = $Interface/RightBar/Content/Selection

var leftBarOpen := false
var rightBarOpen := false

func _ready() -> void:
	$Interface/TopBar/Margin/Row/LeftToggle.pressed.connect(toggleLeftBar)
	$Interface/TopBar/Margin/Row/RightToggle.pressed.connect(toggleRightBar)
	$Interface/RightBar/Content/WireButton.pressed.connect(selectTool.bind("wire", "Wire"))
	$Interface/RightBar/Content/OrGateButton.pressed.connect(selectTool.bind("orGate", "OR Gate"))
	$Interface/RightBar/Content/ProcessorButton.pressed.connect(selectTool.bind("processor", "Processor"))
	get_tree().root.size_changed.connect(updateLayout)
	updateLayout()

func toggleLeftBar() -> void:
	leftBarOpen = not leftBarOpen
	leftBar.visible = leftBarOpen

func toggleRightBar() -> void:
	rightBarOpen = not rightBarOpen
	rightBar.visible = rightBarOpen

func selectTool(toolId: String, displayName: String) -> void:
	board.call("selectTool", toolId)
	selectionLabel.text = "Selected: %s" % displayName

func updateLayout() -> void:
	var viewportSize := get_viewport_rect().size
	topBar.size = Vector2(viewportSize.x, 58.0)
	leftBar.position = Vector2(0, 58)
	leftBar.size = Vector2(244, viewportSize.y - 58)
	rightBar.position = Vector2(viewportSize.x - 262, 58)
	rightBar.size = Vector2(262, viewportSize.y - 58)
