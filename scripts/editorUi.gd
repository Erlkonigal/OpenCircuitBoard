extends Control

const DockRegistry := preload("res://scripts/dockRegistry.gd")
const InkRegistry := preload("res://scripts/inkRegistry.gd")
const InkButton := preload("res://scripts/inkButton.gd")
const panelLeftCloseIcon := preload("res://assets/panelLeftClose.svg")
const panelLeftOpenIcon := preload("res://assets/panelLeftOpen.svg")
const panelRightCloseIcon := preload("res://assets/panelRightClose.svg")
const panelRightOpenIcon := preload("res://assets/panelRightOpen.svg")
const sidebarAnimationDuration := 0.18
const topBarButtonActiveIconColor := Color("f2c94c")
const topBarFontSize := 16
const dockMenuButtonSize := 28
const dockMenuSeparation := 5
const dockMenuPadding := 14
const inkVariantMenuColumns := 3
const inkVariantMenuButtonSize := Vector2i(28, 28)
const inkVariantMenuSeparation := 4
const inkVariantMenuPadding := 14
const leftDockSide := "left"
const rightDockSide := "right"

@onready var board: Node2D = $BoardViewport/SubViewport/CircuitBoard
@onready var boardViewport: SubViewportContainer = $BoardViewport
@onready var topBar: Panel = $Interface/TopBar
@onready var leftSidebarToggle: Button = $Interface/TopBar/Content/leftSidebarToggle
@onready var rightSidebarToggle: Button = $Interface/TopBar/Content/rightSidebarToggle
@onready var dockHost: Control = $Interface/DockHost
@onready var dockResizeHandle: ColorRect = $Interface/DockResizeHandle
@onready var rightDockHost: Control = $Interface/RightDockHost
@onready var rightDockResizeHandle: ColorRect = $Interface/RightDockResizeHandle

var dockDefinitions: Array[Dictionary] = []
var currentDock: Control
var rightCurrentDock: Control
var dockMenu: PopupPanel
var dockMenuColumns := 1
var dockMenuTargetSide := leftDockSide
var inkVariantMenu: PopupPanel
var inkVariantMenuGrid: GridContainer
var inkVariantMenuDock: Control
var inkVariantMenuPaletteToolId := ""
var inkVariantButtons: Dictionary[String, Button] = {}
var lastSelectedInkIdByPaletteToolId: Dictionary[String, String] = {}
var dockWidth := 272.0
var rightDockWidth := 272.0
var eventHistory: Array[String] = []
var leftSidebarOpen := true
var rightSidebarOpen := true
var isResizingDock := false
var isResizingRightDock := false
var leftSidebarTween: Tween
var rightSidebarTween: Tween

func _ready() -> void:
	Input.set_use_accumulated_input(false)
	configureTopBar()
	board.connect("clipboardChanged", updateClipboardHistory)
	board.connect("clipboardCopied", showClipboardDock)
	leftSidebarToggle.toggled.connect(setLeftSidebarOpen)
	rightSidebarToggle.toggled.connect(setRightSidebarOpen)
	dockResizeHandle.gui_input.connect(handleDockResizeInput)
	rightDockResizeHandle.gui_input.connect(handleRightDockResizeInput)
	dockResizeHandle.mouse_entered.connect(func() -> void: dockResizeHandle.color = Color("5d7090"))
	dockResizeHandle.mouse_exited.connect(func() -> void:
		if not isResizingDock:
			dockResizeHandle.color = Color("263346")
	)
	rightDockResizeHandle.mouse_entered.connect(func() -> void: rightDockResizeHandle.color = Color("5d7090"))
	rightDockResizeHandle.mouse_exited.connect(func() -> void:
		if not isResizingRightDock:
			rightDockResizeHandle.color = Color("263346")
	)
	resized.connect(syncDockLayout)
	dockDefinitions = DockRegistry.discoverDocks()
	if dockDefinitions.is_empty():
		push_error("NoDockRegistered")
		return
	buildDockMenu()
	buildInkVariantMenu()
	var initialLeftDockId := String(dockDefinitions[0].dockId)
	activateDock(initialLeftDockId, leftDockSide)
	var initialRightDockId := getInitialRightDockId(initialLeftDockId)
	if not initialRightDockId.is_empty():
		activateDock(initialRightDockId, rightDockSide)
	setLeftSidebarOpen(leftSidebarToggle.button_pressed, false)
	setRightSidebarOpen(rightSidebarToggle.button_pressed, false)

func _process(_delta: float) -> void:
	if not isPointerOverCanvas():
		return
	var mousePosition := board.get_global_mouse_position()
	var isValid: bool = board.validRect.has_point(mousePosition)
	var coordinates: Vector2i = board.call("getGridCoordinates", mousePosition)
	var hoveredInk: Dictionary = board.call("getInkAt", coordinates) if isValid else {}
	var hoveredInkTitle := String(hoveredInk.get("title", "None"))
	for dock in getActiveDocks():
		if dock.has_method("updateCursorInfo"):
			dock.call("updateCursorInfo", coordinates, isValid, hoveredInkTitle)

func isPointerOverCanvas() -> bool:
	var pointerPosition := get_viewport().get_mouse_position()
	if not boardViewport.get_global_rect().has_point(pointerPosition):
		return false
	return not dockHost.get_global_rect().has_point(pointerPosition) and not rightDockHost.get_global_rect().has_point(pointerPosition)

func buildDockMenu() -> void:
	dockMenu = PopupPanel.new()
	dockMenu.transparent_bg = true
	dockMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(dockMenu)
	var grid := GridContainer.new()
	dockMenuColumns = clampi(dockDefinitions.size(), 1, 3)
	grid.columns = dockMenuColumns
	grid.add_theme_constant_override("h_separation", dockMenuSeparation)
	grid.add_theme_constant_override("v_separation", dockMenuSeparation)
	dockMenu.add_child(grid)
	for definition in dockDefinitions:
		var button := Button.new()
		button.custom_minimum_size = Vector2(dockMenuButtonSize, dockMenuButtonSize)
		button.tooltip_text = String(definition.dockTitle)
		button.icon = definition.dockIcon
		button.expand_icon = false
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_theme_color_override("icon_normal_color", Color("9aa8bf"))
		button.add_theme_color_override("icon_hover_color", Color("e2eaf7"))
		button.add_theme_stylebox_override("normal", makeMenuItemBox(Color.TRANSPARENT))
		button.add_theme_stylebox_override("hover", makeMenuItemBox(Color("2b374a")))
		button.pressed.connect(activateDockFromMenu.bind(String(definition.dockId)))
		grid.add_child(button)

func activateDockFromMenu(dockId: String) -> void:
	activateDock(dockId, dockMenuTargetSide)
	dockMenu.hide()

func activateDock(dockId: String, dockSide := leftDockSide) -> void:
	if not isDockSideValid(dockSide):
		push_error("DockSideInvalid")
		return
	var definition := getDockDefinition(dockId)
	if definition.is_empty():
		push_error("DockNotFound")
		return
	var currentDockId := getActiveDockId(dockSide)
	if currentDockId == dockId:
		return
	var otherDockSide := getOtherDockSide(dockSide)
	var otherDockId := getActiveDockId(otherDockSide)
	if dockId == otherDockId:
		if currentDockId.is_empty():
			return
		var currentDefinition := getDockDefinition(currentDockId)
		setDockForSide(currentDefinition, otherDockSide)
	setDockForSide(definition, dockSide)

func getInitialRightDockId(initialLeftDockId: String) -> String:
	var eventLogDefinition := getDockDefinition("eventLog")
	if not eventLogDefinition.is_empty() and String(eventLogDefinition.dockId) != initialLeftDockId:
		return String(eventLogDefinition.dockId)
	for definition in dockDefinitions:
		var dockId := String(definition.dockId)
		if dockId != initialLeftDockId:
			return dockId
	return ""

func getDockDefinition(dockId: String) -> Dictionary:
	for candidate in dockDefinitions:
		if String(candidate.dockId) == dockId:
			return candidate
	return {}

func getActiveDocks() -> Array[Control]:
	var docks: Array[Control] = []
	if currentDock:
		docks.append(currentDock)
	if rightCurrentDock:
		docks.append(rightCurrentDock)
	return docks

func getActiveDockById(dockId: String) -> Control:
	for dock in getActiveDocks():
		if String(dock.get("dockId")) == dockId:
			return dock
	return null

func getActiveDockId(dockSide: String) -> String:
	var dock := getActiveDock(dockSide)
	return String(dock.get("dockId")) if dock else ""

func getActiveDock(dockSide: String) -> Control:
	if not isDockSideValid(dockSide):
		return null
	return getDockForSide(dockSide)

func getDockForSide(dockSide: String) -> Control:
	if dockSide == leftDockSide:
		return currentDock
	if dockSide == rightDockSide:
		return rightCurrentDock
	return null

func getDockHostForSide(dockSide: String) -> Control:
	if dockSide == leftDockSide:
		return dockHost
	if dockSide == rightDockSide:
		return rightDockHost
	return null

func getOtherDockSide(dockSide: String) -> String:
	return rightDockSide if dockSide == leftDockSide else leftDockSide

func isDockSideValid(dockSide: String) -> bool:
	return dockSide == leftDockSide or dockSide == rightDockSide

func setDockForSide(definition: Dictionary, dockSide: String) -> void:
	if definition.is_empty():
		return
	var previousDock := getDockForSide(dockSide)
	if previousDock:
		if inkVariantMenuDock == previousDock:
			hideInkVariantMenu()
		previousDock.free()
	var dockScene := definition.scene as PackedScene
	var nextDock := dockScene.instantiate() as Control
	var host := getDockHostForSide(dockSide)
	host.add_child(nextDock)
	nextDock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if dockSide == leftDockSide:
		currentDock = nextDock
		setDockWidth(float(definition.dockWidth))
	else:
		rightCurrentDock = nextDock
		setRightDockWidth(float(definition.dockWidth))
	connectDockSignals(nextDock, dockSide)
	if nextDock.has_method("setEventHistory"):
		nextDock.call("setEventHistory", eventHistory)
	if nextDock.has_method("setClipboardHistory"):
		nextDock.call("setClipboardHistory", board.call("getClipboardHistory"), board.call("getSelectedClipboardIndex"))

func connectDockSignals(dock: Control, dockSide: String) -> void:
	if dock.has_signal("dockMenuRequested"):
		dock.connect("dockMenuRequested", showDockMenu.bind(dockSide))
	if dock.has_signal("inkSelected"):
		dock.connect("inkSelected", selectInk)
	if dock.has_signal("inkVariantMenuRequested"):
		dock.connect("inkVariantMenuRequested", showInkVariantMenu.bind(dock))
	if dock.has_signal("eventRecorded"):
		dock.connect("eventRecorded", recordEvent)
	if dock.has_signal("clipboardItemSelected"):
		dock.connect("clipboardItemSelected", selectClipboardItem)
	if dock.has_method("syncLastSelectedInkIds"):
		dock.call("syncLastSelectedInkIds", lastSelectedInkIdByPaletteToolId)
	if dock.has_method("syncSelectedInk"):
		dock.call("syncSelectedInk", String(board.get("selectedTool")))

func recordEvent(eventText: String) -> void:
	eventHistory.append(eventText)
	for dock in getActiveDocks():
		if dock.has_method("appendEvent"):
			dock.call("appendEvent", eventText)

func showDockMenu(menuButton: Button, dockSide: String) -> void:
	dockMenuTargetSide = dockSide
	var buttonPosition := menuButton.get_global_rect().position
	var menuRows := ceili(float(dockDefinitions.size()) / float(dockMenuColumns))
	var menuSize := Vector2i(
		dockMenuPadding + dockMenuColumns * dockMenuButtonSize + (dockMenuColumns - 1) * dockMenuSeparation,
		dockMenuPadding + menuRows * dockMenuButtonSize + (menuRows - 1) * dockMenuSeparation
	)
	var popupPosition := Vector2i(buttonPosition + Vector2(4.0, menuButton.size.y))
	var viewportSize := get_viewport_rect().size
	popupPosition.x = clampi(popupPosition.x, 0, maxi(0, int(viewportSize.x) - menuSize.x))
	popupPosition.y = clampi(popupPosition.y, 0, maxi(0, int(viewportSize.y) - menuSize.y))
	dockMenu.popup(Rect2i(popupPosition, menuSize))

func buildInkVariantMenu() -> void:
	inkVariantMenu = PopupPanel.new()
	inkVariantMenu.transparent_bg = true
	inkVariantMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(inkVariantMenu)
	inkVariantMenuGrid = GridContainer.new()
	inkVariantMenuGrid.name = "inkVariantMenuGrid"
	inkVariantMenuGrid.columns = inkVariantMenuColumns
	inkVariantMenuGrid.add_theme_constant_override("h_separation", inkVariantMenuSeparation)
	inkVariantMenuGrid.add_theme_constant_override("v_separation", inkVariantMenuSeparation)
	inkVariantMenu.add_child(inkVariantMenuGrid)
	inkVariantMenu.popup_hide.connect(func() -> void:
		inkVariantMenuDock = null
		inkVariantMenuPaletteToolId = ""
	)

func showInkVariantMenu(anchorButton: Button, paletteToolId: String, dock: Control) -> void:
	var variants := InkRegistry.getInkVariants(paletteToolId)
	if variants.size() < 2:
		return
	inkVariantMenuDock = dock
	inkVariantMenuPaletteToolId = paletteToolId
	populateInkVariantMenu(variants)
	var menuRows := ceili(float(variants.size()) / float(inkVariantMenuColumns))
	var menuSize := Vector2i(
		inkVariantMenuPadding + inkVariantMenuColumns * inkVariantMenuButtonSize.x + (inkVariantMenuColumns - 1) * inkVariantMenuSeparation,
		inkVariantMenuPadding + menuRows * inkVariantMenuButtonSize.y + (menuRows - 1) * inkVariantMenuSeparation
	)
	var anchorRect := anchorButton.get_global_rect()
	var popupPosition := Vector2i(anchorRect.position + Vector2(anchorRect.size.x + 4.0, 0.0))
	var viewportSize := get_viewport_rect().size
	if popupPosition.x + menuSize.x > int(viewportSize.x):
		popupPosition.x = int(anchorRect.position.x) - menuSize.x - 4
	if popupPosition.y + menuSize.y > int(viewportSize.y):
		popupPosition.y = int(anchorRect.end.y) - menuSize.y
	popupPosition.x = clampi(popupPosition.x, 0, maxi(0, int(viewportSize.x) - menuSize.x))
	popupPosition.y = clampi(popupPosition.y, 0, maxi(0, int(viewportSize.y) - menuSize.y))
	inkVariantMenu.popup(Rect2i(popupPosition, menuSize))

func populateInkVariantMenu(variants: Array[Dictionary]) -> void:
	for child in inkVariantMenuGrid.get_children():
		child.free()
	inkVariantButtons.clear()
	for ink in variants:
		var button := InkButton.new() as Button
		button.call("configure", ink)
		button.pressed.connect(selectInkVariant.bind(ink))
		inkVariantMenuGrid.add_child(button)
		inkVariantButtons[InkRegistry.getComponentId(ink)] = button
	refreshInkVariantButtons()

func selectInkVariant(ink: Dictionary) -> void:
	if inkVariantMenuDock and inkVariantMenuDock.has_method("selectInk"):
		inkVariantMenuDock.call("selectInk", ink)
	hideInkVariantMenu()

func hideInkVariantMenu() -> void:
	if inkVariantMenu:
		inkVariantMenu.hide()
	inkVariantMenuDock = null
	inkVariantMenuPaletteToolId = ""

func refreshInkVariantButtons() -> void:
	if inkVariantMenuDock == null:
		return
	var selectedInkId := ""
	if inkVariantMenuDock.has_method("getLastSelectedInkId"):
		selectedInkId = String(inkVariantMenuDock.call("getLastSelectedInkId", inkVariantMenuPaletteToolId))
	elif inkVariantMenuDock.has_method("getSelectedInkId"):
		selectedInkId = String(inkVariantMenuDock.call("getSelectedInkId"))
	for componentId in inkVariantButtons:
		var button := inkVariantButtons[componentId]
		var ink := InkRegistry.getInk(String(componentId))
		var isSelected := componentId == selectedInkId
		button.set_pressed_no_signal(isSelected)
		button.call("setInkAppearance", ink.get("color", Color.WHITE), isSelected)

func selectInk(ink: Dictionary) -> void:
	lastSelectedInkIdByPaletteToolId[InkRegistry.getPaletteToolId(ink)] = InkRegistry.getComponentId(ink)
	board.call("selectTool", InkRegistry.getComponentId(ink))
	refreshInkVariantButtons()

func updateClipboardHistory(history: Array[Dictionary], selectedIndex: int) -> void:
	for dock in getActiveDocks():
		if dock.has_method("setClipboardHistory"):
			dock.call("setClipboardHistory", history, selectedIndex)

func showClipboardDock(history: Array[Dictionary], selectedIndex: int) -> void:
	var clipboardDock := getActiveDockById("clipboard")
	if clipboardDock == null:
		activateDock("clipboard", leftDockSide)
		clipboardDock = getActiveDockById("clipboard")
	if clipboardDock and clipboardDock.has_method("setClipboardHistory"):
		clipboardDock.call("setClipboardHistory", history, selectedIndex)

func selectClipboardItem(index: int) -> void:
	board.call("selectClipboardItem", index)

func setLeftSidebarOpen(isOpen: bool, animate := true) -> void:
	leftSidebarOpen = isOpen
	leftSidebarToggle.set_pressed_no_signal(isOpen)
	updateSidebarLayout(animate)

func setRightSidebarOpen(isOpen: bool, animate := true) -> void:
	rightSidebarOpen = isOpen
	rightSidebarToggle.set_pressed_no_signal(isOpen)
	updateSidebarLayout(animate)

func setDockWidth(requestedWidth: float) -> void:
	dockWidth = clampDockWidth(requestedWidth)
	updateSidebarLayout(false)

func setRightDockWidth(requestedWidth: float) -> void:
	rightDockWidth = clampDockWidth(requestedWidth)
	updateSidebarLayout(false)

func clampDockWidth(requestedWidth: float) -> float:
	var maximumWidth := maxf(208.0, minf(480.0, size.x * 0.5))
	return clampf(requestedWidth, 208.0, maximumWidth)

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
	var rightResizeStart := -rightDockWidth - 6.0 if rightSidebarOpen else 0.0
	var rightResizeEnd := -rightDockWidth if rightSidebarOpen else 6.0
	if leftSidebarTween:
		leftSidebarTween.kill()
	if rightSidebarTween:
		rightSidebarTween.kill()
	if not animate:
		dockHost.offset_left = leftStart
		dockHost.offset_right = leftEnd
		rightDockHost.offset_left = rightStart
		rightDockHost.offset_right = rightEnd
		dockResizeHandle.offset_left = resizeStart
		dockResizeHandle.offset_right = resizeEnd
		dockResizeHandle.visible = leftSidebarOpen
		rightDockResizeHandle.offset_left = rightResizeStart
		rightDockResizeHandle.offset_right = rightResizeEnd
		rightDockResizeHandle.visible = rightSidebarOpen
		return
	dockHost.visible = true
	rightDockHost.visible = true
	dockResizeHandle.visible = true
	rightDockResizeHandle.visible = true
	leftSidebarTween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	leftSidebarTween.tween_property(dockHost, "offset_left", leftStart, sidebarAnimationDuration)
	leftSidebarTween.parallel().tween_property(dockHost, "offset_right", leftEnd, sidebarAnimationDuration)
	leftSidebarTween.parallel().tween_property(dockResizeHandle, "offset_left", resizeStart, sidebarAnimationDuration)
	leftSidebarTween.parallel().tween_property(dockResizeHandle, "offset_right", resizeEnd, sidebarAnimationDuration)
	leftSidebarTween.chain().tween_callback(finishLeftSidebarTransition.bind(leftSidebarOpen))
	rightSidebarTween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rightSidebarTween.tween_property(rightDockHost, "offset_left", rightStart, sidebarAnimationDuration)
	rightSidebarTween.parallel().tween_property(rightDockHost, "offset_right", rightEnd, sidebarAnimationDuration)
	rightSidebarTween.parallel().tween_property(rightDockResizeHandle, "offset_left", rightResizeStart, sidebarAnimationDuration)
	rightSidebarTween.parallel().tween_property(rightDockResizeHandle, "offset_right", rightResizeEnd, sidebarAnimationDuration)
	rightSidebarTween.chain().tween_callback(finishRightSidebarTransition.bind(rightSidebarOpen))

func finishLeftSidebarTransition(isOpen: bool) -> void:
	if leftSidebarOpen == isOpen:
		dockResizeHandle.visible = isOpen

func finishRightSidebarTransition(isOpen: bool) -> void:
	if rightSidebarOpen == isOpen:
		rightDockResizeHandle.visible = isOpen

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

func handleRightDockResizeInput(event: InputEvent) -> void:
	var mouseButton := event as InputEventMouseButton
	if mouseButton and mouseButton.button_index == MOUSE_BUTTON_LEFT:
		isResizingRightDock = mouseButton.pressed
		rightDockResizeHandle.color = Color("7589aa") if isResizingRightDock else Color("5d7090")
		get_viewport().set_input_as_handled()
		return
	var mouseMotion := event as InputEventMouseMotion
	if mouseMotion and isResizingRightDock:
		setRightDockWidth(size.x - get_global_mouse_position().x)
		get_viewport().set_input_as_handled()

func syncDockLayout() -> void:
	dockWidth = clampDockWidth(dockWidth)
	rightDockWidth = clampDockWidth(rightDockWidth)
	updateSidebarLayout(false)

func configureTopBar() -> void:
	var topBarBox := StyleBoxFlat.new()
	topBarBox.bg_color = Color("121924")
	topBarBox.border_width_bottom = 1
	topBarBox.border_color = Color("263346")
	topBar.add_theme_stylebox_override("panel", topBarBox)
	var title := $Interface/TopBar/Content/Title as Label
	title.add_theme_font_size_override("font_size", topBarFontSize)
	for child in $Interface/TopBar/Content.get_children():
		var topBarButton := child as Button
		if topBarButton:
			configureTopBarButton(topBarButton)
	dockResizeHandle.color = Color("263346")
	dockResizeHandle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	rightDockResizeHandle.color = Color("263346")
	rightDockResizeHandle.mouse_default_cursor_shape = Control.CURSOR_HSIZE

func configureTopBarButton(topBarButton: Button) -> void:
	topBarButton.expand_icon = false
	topBarButton.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topBarButton.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	topBarButton.add_theme_color_override("icon_normal_color", Color("8d9db5"))
	topBarButton.add_theme_color_override("icon_hover_color", Color("e1e9f6"))
	topBarButton.add_theme_color_override("icon_pressed_color", topBarButtonActiveIconColor)
	topBarButton.add_theme_color_override("icon_hover_pressed_color", topBarButtonActiveIconColor)
	topBarButton.add_theme_stylebox_override("normal", makeMenuItemBox(Color.TRANSPARENT))
	topBarButton.add_theme_stylebox_override("hover", makeMenuItemBox(Color("2b374a")))
	topBarButton.add_theme_stylebox_override("pressed", makeMenuItemBox(Color.TRANSPARENT))
	topBarButton.add_theme_stylebox_override("hover_pressed", makeMenuItemBox(Color("2b374a")))

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
