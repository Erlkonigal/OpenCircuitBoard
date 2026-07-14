extends Control

const DockRegistry := preload("res://scripts/dockRegistry.gd")
const panelLeftCloseIcon := preload("res://assets/panelLeftClose.svg")
const panelLeftOpenIcon := preload("res://assets/panelLeftOpen.svg")
const panelRightCloseIcon := preload("res://assets/panelRightClose.svg")
const panelRightOpenIcon := preload("res://assets/panelRightOpen.svg")
const sidebarAnimationDuration := 0.18

@onready var board: Node2D = $BoardViewport/SubViewport/CircuitBoard
@onready var boardViewport: SubViewportContainer = $BoardViewport
@onready var topBar: Panel = $Interface/TopBar
@onready var leftSidebarToggle: Button = $Interface/TopBar/Content/leftSidebarToggle
@onready var rightSidebarToggle: Button = $Interface/TopBar/Content/rightSidebarToggle
@onready var dockHost: Control = $Interface/DockHost
@onready var dockResizeHandle: ColorRect = $Interface/DockResizeHandle
@onready var rightDock: Panel = $Interface/RightDock
@onready var selectionLabel: Label = $Interface/RightDock/Margin/Content/Selection

var dockDefinitions: Array[Dictionary] = []
var currentDock: Control
var dockMenu: PopupPanel
var dockWidth := 272.0
var rightDockWidth := 300.0
var leftSidebarOpen := true
var rightSidebarOpen := true
var isResizingDock := false
var leftSidebarTween: Tween
var rightSidebarTween: Tween
var boardLayoutTween: Tween

func _ready() -> void:
	configureTopBar()
	configureRightDock()
	leftSidebarToggle.toggled.connect(setLeftSidebarOpen)
	rightSidebarToggle.toggled.connect(setRightSidebarOpen)
	dockResizeHandle.gui_input.connect(handleDockResizeInput)
	dockResizeHandle.mouse_entered.connect(func() -> void: dockResizeHandle.color = Color("5d7090"))
	dockResizeHandle.mouse_exited.connect(func() -> void:
		if not isResizingDock:
			dockResizeHandle.color = Color("263346")
	)
	resized.connect(syncDockLayout)
	dockDefinitions = DockRegistry.discoverDocks()
	if dockDefinitions.is_empty():
		push_error("NoDockRegistered")
		return
	buildDockMenu()
	activateDock(String(dockDefinitions[0].dockId))
	setLeftSidebarOpen(leftSidebarToggle.button_pressed, false)
	setRightSidebarOpen(rightSidebarToggle.button_pressed, false)

func _process(_delta: float) -> void:
	if currentDock == null or not currentDock.has_method("updateCursorInfo"):
		return
	var mousePosition := board.get_global_mouse_position()
	var isValid: bool = board.validRect.has_point(mousePosition)
	var coordinates: Vector2i = board.call("getGridCoordinates", mousePosition)
	currentDock.call("updateCursorInfo", coordinates, isValid)

func buildDockMenu() -> void:
	dockMenu = PopupPanel.new()
	dockMenu.transparent_bg = true
	dockMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(dockMenu)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	dockMenu.add_child(grid)
	for definition in dockDefinitions:
		var button := Button.new()
		button.custom_minimum_size = Vector2(38, 38)
		button.tooltip_text = String(definition.dockTitle)
		button.icon = definition.dockIcon
		button.expand_icon = true
		button.add_theme_color_override("icon_normal_color", Color("9aa8bf"))
		button.add_theme_color_override("icon_hover_color", Color("e2eaf7"))
		button.add_theme_stylebox_override("normal", makeMenuItemBox(Color.TRANSPARENT))
		button.add_theme_stylebox_override("hover", makeMenuItemBox(Color("2b374a")))
		button.pressed.connect(func() -> void:
			activateDock(String(definition.dockId))
			dockMenu.hide()
		)
		grid.add_child(button)

func activateDock(dockId: String) -> void:
	var definition: Dictionary = {}
	for candidate in dockDefinitions:
		if String(candidate.dockId) == dockId:
			definition = candidate
			break
	if definition.is_empty():
		push_error("DockNotFound")
		return
	if currentDock:
		currentDock.queue_free()
	var dockScene := definition.scene as PackedScene
	currentDock = dockScene.instantiate() as Control
	dockHost.add_child(currentDock)
	currentDock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if currentDock.has_signal("dockMenuRequested"):
		currentDock.connect("dockMenuRequested", showDockMenu)
	if currentDock.has_signal("inkSelected"):
		currentDock.connect("inkSelected", selectInk)
	setDockWidth(float(definition.dockWidth))

func showDockMenu(menuButton: Button) -> void:
	var buttonPosition := menuButton.get_global_rect().position
	var menuSize := Vector2i(130, 130)
	var popupPosition := Vector2i(buttonPosition + Vector2(4.0, menuButton.size.y))
	dockMenu.popup(Rect2i(popupPosition, menuSize))

func selectInk(ink: Dictionary) -> void:
	board.call("selectTool", String(ink.toolId))
	selectionLabel.text = String(ink.title)

func setLeftSidebarOpen(isOpen: bool, animate := true) -> void:
	leftSidebarOpen = isOpen
	leftSidebarToggle.set_pressed_no_signal(isOpen)
	updateSidebarLayout(animate)

func setRightSidebarOpen(isOpen: bool, animate := true) -> void:
	rightSidebarOpen = isOpen
	rightSidebarToggle.set_pressed_no_signal(isOpen)
	updateSidebarLayout(animate)

func setDockWidth(requestedWidth: float) -> void:
	var maximumWidth := maxf(208.0, minf(480.0, size.x * 0.5))
	dockWidth = clampf(requestedWidth, 208.0, maximumWidth)
	updateSidebarLayout(false)

func updateSidebarLayout(animate: bool) -> void:
	leftSidebarToggle.icon = panelLeftCloseIcon if leftSidebarOpen else panelLeftOpenIcon
	rightSidebarToggle.icon = panelRightCloseIcon if rightSidebarOpen else panelRightOpenIcon
	leftSidebarToggle.tooltip_text = "CloseLeftSidebar" if leftSidebarOpen else "OpenLeftSidebar"
	rightSidebarToggle.tooltip_text = "CloseRightSidebar" if rightSidebarOpen else "OpenRightSidebar"
	var leftStart := 0.0 if leftSidebarOpen else -dockWidth
	var leftEnd := dockWidth if leftSidebarOpen else 0.0
	var rightStart := -rightDockWidth if rightSidebarOpen else 0.0
	var rightEnd := 0.0 if rightSidebarOpen else rightDockWidth
	var resizeStart := dockWidth if leftSidebarOpen else -6.0
	var resizeEnd := dockWidth + 6.0 if leftSidebarOpen else 0.0
	var boardLeft := dockWidth if leftSidebarOpen else 0.0
	var boardRight := rightDockWidth if rightSidebarOpen else 0.0
	if leftSidebarTween:
		leftSidebarTween.kill()
	if rightSidebarTween:
		rightSidebarTween.kill()
	if boardLayoutTween:
		boardLayoutTween.kill()
	if not animate:
		dockHost.offset_left = leftStart
		dockHost.offset_right = leftEnd
		rightDock.offset_left = rightStart
		rightDock.offset_right = rightEnd
		dockResizeHandle.offset_left = resizeStart
		dockResizeHandle.offset_right = resizeEnd
		dockResizeHandle.visible = leftSidebarOpen
		boardViewport.offset_left = boardLeft
		boardViewport.offset_right = -boardRight
		return
	dockHost.visible = true
	rightDock.visible = true
	dockResizeHandle.visible = true
	leftSidebarTween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	leftSidebarTween.tween_property(dockHost, "offset_left", leftStart, sidebarAnimationDuration)
	leftSidebarTween.parallel().tween_property(dockHost, "offset_right", leftEnd, sidebarAnimationDuration)
	leftSidebarTween.parallel().tween_property(dockResizeHandle, "offset_left", resizeStart, sidebarAnimationDuration)
	leftSidebarTween.parallel().tween_property(dockResizeHandle, "offset_right", resizeEnd, sidebarAnimationDuration)
	leftSidebarTween.chain().tween_callback(finishLeftSidebarTransition.bind(leftSidebarOpen))
	rightSidebarTween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rightSidebarTween.tween_property(rightDock, "offset_left", rightStart, sidebarAnimationDuration)
	rightSidebarTween.parallel().tween_property(rightDock, "offset_right", rightEnd, sidebarAnimationDuration)
	rightSidebarTween.chain().tween_callback(finishRightSidebarTransition.bind(rightSidebarOpen))
	boardLayoutTween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	boardLayoutTween.tween_property(boardViewport, "offset_left", boardLeft, sidebarAnimationDuration)
	boardLayoutTween.parallel().tween_property(boardViewport, "offset_right", -boardRight, sidebarAnimationDuration)

func finishLeftSidebarTransition(isOpen: bool) -> void:
	if leftSidebarOpen == isOpen:
		dockResizeHandle.visible = isOpen

func finishRightSidebarTransition(_isOpen: bool) -> void:
	pass

func handleDockResizeInput(event: InputEvent) -> void:
	var mouseButton := event as InputEventMouseButton
	if mouseButton and mouseButton.button_index == MOUSE_BUTTON_LEFT:
		isResizingDock = mouseButton.pressed
		dockResizeHandle.color = Color("7589aa") if isResizingDock else Color("5d7090")
		get_viewport().set_input_as_handled()
		return
	var mouseMotion := event as InputEventMouseMotion
	if mouseMotion and isResizingDock:
		setDockWidth(get_global_mouse_position().x)
		get_viewport().set_input_as_handled()

func syncDockLayout() -> void:
	setDockWidth(dockWidth)

func configureTopBar() -> void:
	var topBarBox := StyleBoxFlat.new()
	topBarBox.bg_color = Color("121924")
	topBarBox.border_width_bottom = 1
	topBarBox.border_color = Color("263346")
	topBar.add_theme_stylebox_override("panel", topBarBox)
	for sidebarToggle in [leftSidebarToggle, rightSidebarToggle]:
		sidebarToggle.expand_icon = true
		sidebarToggle.add_theme_color_override("icon_normal_color", Color("8d9db5"))
		sidebarToggle.add_theme_color_override("icon_hover_color", Color("e1e9f6"))
		sidebarToggle.add_theme_stylebox_override("normal", makeMenuItemBox(Color.TRANSPARENT))
		sidebarToggle.add_theme_stylebox_override("hover", makeMenuItemBox(Color("2b374a")))
	dockResizeHandle.color = Color("263346")
	dockResizeHandle.mouse_default_cursor_shape = Control.CURSOR_HSIZE

func configureRightDock() -> void:
	var rightDockBox := StyleBoxFlat.new()
	rightDockBox.bg_color = Color("151c27")
	rightDockBox.border_width_left = 1
	rightDockBox.border_color = Color("263346")
	rightDock.add_theme_stylebox_override("panel", rightDockBox)
	var title := $Interface/RightDock/Margin/Content/Title as Label
	var selectedLabel := $Interface/RightDock/Margin/Content/SelectedLabel as Label
	title.add_theme_color_override("font_color", Color("a4b0c5"))
	title.add_theme_font_size_override("font_size", 16)
	selectedLabel.add_theme_color_override("font_color", Color("68758a"))
	selectionLabel.add_theme_color_override("font_color", Color("55dfeb"))
	selectionLabel.add_theme_font_size_override("font_size", 20)

func makeMenuBox() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("202a38")
	box.corner_radius_top_left = 5
	box.corner_radius_top_right = 5
	box.corner_radius_bottom_left = 5
	box.corner_radius_bottom_right = 5
	box.content_margin_left = 7
	box.content_margin_top = 7
	box.content_margin_right = 7
	box.content_margin_bottom = 7
	return box

func makeMenuItemBox(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 3
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 3
	return box
