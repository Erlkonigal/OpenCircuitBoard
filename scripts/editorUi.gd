extends Control

const panelLeftCloseIcon := preload("res://assets/panelLeftClose.svg")
const panelLeftOpenIcon := preload("res://assets/panelLeftOpen.svg")
const panelRightCloseIcon := preload("res://assets/panelRightClose.svg")
const panelRightOpenIcon := preload("res://assets/panelRightOpen.svg")
const sidebarAnimationDuration := 0.18
const sidebarOpenIconColor := Color("f2c94c")
const sidebarClosedIconNormalColor := Color(0.68, 0.75, 0.86, 1)
const sidebarClosedIconHoverColor := Color(0.84, 0.91, 0.98, 1)
const sidebarClosedIconPressedColor := Color(0.76, 0.94, 0.96, 1)

@onready var board: Node2D = $BoardViewport/SubViewport/CircuitBoard
@onready var boardCamera: Camera2D = $BoardViewport/SubViewport/BoardCamera
@onready var boardViewport: SubViewportContainer = $BoardViewport
@onready var topBar: Panel = $Interface/TopBar
@onready var leftBar: PanelContainer = $Interface/LeftBar
@onready var rightBar: PanelContainer = $Interface/RightBar
@onready var wireButton: Button = $Interface/LeftBar/Content/WireButton
@onready var orGateButton: Button = $Interface/LeftBar/Content/OrGateButton
@onready var processorButton: Button = $Interface/LeftBar/Content/ProcessorButton
@onready var selectionLabel: Label = $Interface/RightBar/Content/Selection
@onready var toolDescription: Label = $Interface/RightBar/Content/ToolDescription
@onready var boardSizeLabel: Label = $Interface/LeftBar/Content/BoardSize
@onready var pointerLabel: Label = $Interface/LeftBar/Content/Pointer
@onready var zoomLabel: Label = $Interface/TopBar/Margin/Rows/CommandRow/ZoomLabel
@onready var leftSidebarToggle: Button = $Interface/TopBar/Margin/Rows/CommandRow/leftSidebarToggle
@onready var rightSidebarToggle: Button = $Interface/TopBar/Margin/Rows/CommandRow/rightSidebarToggle

var fullscreenExitMode := Window.MODE_WINDOWED
var leftSidebarWidth := 0.0
var rightSidebarWidth := 0.0
var topBarHeight := 0.0
var leftSidebarOpen := true
var rightSidebarOpen := true
var leftSidebarTween: Tween
var rightSidebarTween: Tween

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
	leftSidebarToggle.toggled.connect(setLeftSidebarOpen)
	rightSidebarToggle.toggled.connect(setRightSidebarOpen)
	leftSidebarWidth = leftBar.offset_right - leftBar.offset_left
	rightSidebarWidth = rightBar.offset_right - rightBar.offset_left
	topBarHeight = topBar.offset_bottom - topBar.offset_top
	resized.connect(syncSidebarLayout)
	boardSizeLabel.text = "%d x %d cells" % [board.gridWidthCount, board.gridHeightCount]
	selectTool("orGate")
	setLeftSidebarOpen(leftSidebarToggle.button_pressed, false)
	setRightSidebarOpen(rightSidebarToggle.button_pressed, false)

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

func setLeftSidebarOpen(isOpen: bool, animate := true) -> void:
	leftSidebarOpen = isOpen
	leftSidebarToggle.set_pressed_no_signal(isOpen)
	updateSidebarLayout(animate)

func setRightSidebarOpen(isOpen: bool, animate := true) -> void:
	rightSidebarOpen = isOpen
	rightSidebarToggle.set_pressed_no_signal(isOpen)
	updateSidebarLayout(animate)

func syncSidebarLayout() -> void:
	leftSidebarWidth = leftBar.size.x
	rightSidebarWidth = rightBar.size.x
	topBarHeight = topBar.size.y
	updateSidebarLayout(false)

func updateSidebarLayout(animate := true) -> void:
	boardViewport.offset_left = 0.0
	boardViewport.offset_top = topBarHeight
	boardViewport.offset_right = 0.0
	leftSidebarToggle.icon = panelLeftCloseIcon if leftSidebarOpen else panelLeftOpenIcon
	rightSidebarToggle.icon = panelRightCloseIcon if rightSidebarOpen else panelRightOpenIcon
	leftSidebarToggle.tooltip_text = "Collapse component library" if leftSidebarOpen else "Expand component library"
	rightSidebarToggle.tooltip_text = "Collapse inspector" if rightSidebarOpen else "Expand inspector"
	updateSidebarToggleColor(leftSidebarToggle, leftSidebarOpen)
	updateSidebarToggleColor(rightSidebarToggle, rightSidebarOpen)
	updateLeftSidebarPosition(animate)
	updateRightSidebarPosition(animate)

func updateSidebarToggleColor(sidebarToggle: Button, isOpen: bool) -> void:
	if isOpen:
		sidebarToggle.add_theme_color_override("icon_normal_color", sidebarOpenIconColor)
		sidebarToggle.add_theme_color_override("icon_hover_color", sidebarOpenIconColor)
		sidebarToggle.add_theme_color_override("icon_pressed_color", sidebarOpenIconColor)
		return
	sidebarToggle.add_theme_color_override("icon_normal_color", sidebarClosedIconNormalColor)
	sidebarToggle.add_theme_color_override("icon_hover_color", sidebarClosedIconHoverColor)
	sidebarToggle.add_theme_color_override("icon_pressed_color", sidebarClosedIconPressedColor)

func updateLeftSidebarPosition(animate: bool) -> void:
	var targetLeft := 0.0 if leftSidebarOpen else -leftSidebarWidth
	var targetRight := leftSidebarWidth if leftSidebarOpen else 0.0
	if leftSidebarTween:
		leftSidebarTween.kill()
	if not animate:
		leftBar.offset_left = targetLeft
		leftBar.offset_right = targetRight
		leftBar.visible = leftSidebarOpen
		return
	leftBar.visible = true
	leftSidebarTween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	leftSidebarTween.tween_property(leftBar, "offset_left", targetLeft, sidebarAnimationDuration)
	leftSidebarTween.parallel().tween_property(leftBar, "offset_right", targetRight, sidebarAnimationDuration)
	leftSidebarTween.chain().tween_callback(finishLeftSidebarTransition.bind(leftSidebarOpen))

func updateRightSidebarPosition(animate: bool) -> void:
	var targetLeft := -rightSidebarWidth if rightSidebarOpen else 0.0
	var targetRight := 0.0 if rightSidebarOpen else rightSidebarWidth
	if rightSidebarTween:
		rightSidebarTween.kill()
	if not animate:
		rightBar.offset_left = targetLeft
		rightBar.offset_right = targetRight
		rightBar.visible = rightSidebarOpen
		return
	rightBar.visible = true
	rightSidebarTween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rightSidebarTween.tween_property(rightBar, "offset_left", targetLeft, sidebarAnimationDuration)
	rightSidebarTween.parallel().tween_property(rightBar, "offset_right", targetRight, sidebarAnimationDuration)
	rightSidebarTween.chain().tween_callback(finishRightSidebarTransition.bind(rightSidebarOpen))

func finishLeftSidebarTransition(isOpen: bool) -> void:
	if leftSidebarOpen == isOpen:
		leftBar.visible = isOpen

func finishRightSidebarTransition(isOpen: bool) -> void:
	if rightSidebarOpen == isOpen:
		rightBar.visible = isOpen

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
