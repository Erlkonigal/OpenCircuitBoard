extends Control

const DockRegistry := preload("res://scripts/dockRegistry.gd")

@onready var board: Node2D = $BoardViewport/SubViewport/CircuitBoard
@onready var boardViewport: SubViewportContainer = $BoardViewport
@onready var dockHost: Control = $Interface/DockHost

var dockDefinitions: Array[Dictionary] = []
var currentDock: Control
var dockMenu: PopupPanel

func _ready() -> void:
	dockDefinitions = DockRegistry.discoverDocks()
	if dockDefinitions.is_empty():
		push_error("NoDockRegistered")
		return
	buildDockMenu()
	activateDock(String(dockDefinitions[0].dockId))

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
	var dockWidth := float(definition.dockWidth)
	dockHost.offset_right = dockWidth
	boardViewport.offset_left = dockWidth

func showDockMenu(menuButton: Button) -> void:
	var buttonPosition := menuButton.get_global_rect().position
	var menuSize := Vector2i(130, 130)
	var popupY := maxf(0.0, buttonPosition.y - float(menuSize.y) + menuButton.size.y)
	var popupPosition := Vector2i(buttonPosition.x + 4.0, popupY)
	dockMenu.popup(Rect2i(popupPosition, menuSize))

func selectInk(ink: Dictionary) -> void:
	board.call("selectTool", String(ink.toolId))

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
