extends Control

const DockRegistry := preload("res://scripts/DockRegistry.gd")
const InkRegistry := preload("res://scripts/InkRegistry.gd")
const InkButton := preload("res://scripts/InkButton.gd")
const ProjectManager := preload("res://scripts/ProjectManager.gd")
const SimulationBridge := preload("res://scripts/SimulationBridge.gd")
const FilePlusIcon := preload("res://assets/FilePlus.svg")
const FolderOpenIcon := preload("res://assets/FolderOpen.svg")
const SaveIcon := preload("res://assets/Save.svg")
const FilePenLineIcon := preload("res://assets/FilePenLine.svg")
const HistoryIcon := preload("res://assets/History.svg")
const PanelLeftCloseIcon := preload("res://assets/PanelLeftClose.svg")
const PanelLeftOpenIcon := preload("res://assets/PanelLeftOpen.svg")
const PanelRightCloseIcon := preload("res://assets/PanelRightClose.svg")
const PanelRightOpenIcon := preload("res://assets/PanelRightOpen.svg")
const SkipBackIcon := preload("res://assets/SkipBack.svg")
const SkipForwardIcon := preload("res://assets/SkipForward.svg")
const PauseIcon := preload("res://assets/Pause.svg")
const SidebarAnimationDuration := 0.18
const TopBarButtonActiveIconColor := Color("f2c94c")
const TopBarFontSize := 16
const TopBarSeparatorColor := Color("263346")
const ApplicationTitle := "Open Circuit Board"
const NewProjectTitle := "New Project"
const DialogBackgroundColor := Color("17212f")
const DialogSurfaceColor := Color("202a38")
const DialogInputColor := Color("111a26")
const DialogBorderColor := Color("33445b")
const DialogHoverColor := Color("35435a")
const DialogSelectionColor := Color("354b66")
const DialogTextColor := Color("d8e1ef")
const DialogMutedTextColor := Color("8d9db5")
const DialogActionColor := Color("00a967")
const SimulationStartColor := Color("00c875")
const SimulationStartHoverColor := Color("18dd8a")
const SimulationEditColor := Color("ed3157")
const SimulationEditHoverColor := Color("fa4268")
const SimulationStepColor := Color("f3b941")
const SimulationStepLengthMinimum := 1
const SimulationStepLengthMaximum := 16
const SimulationFrequencyMinimumTps := 1.0
const SimulationCapacityRiseSmoothing := 0.12
const SimulationFrameWorkShare := 0.75
const SimulationFastLoopCursorRefreshIntervalUsec := 100_000
const SimulationAsyncPublishIntervalUsec := 100_000
const SimulationAsyncBatchBudgetUsec := 2_000
const SimulationBatchTickCountMaximum := 4_096
const SimulationBatchTargetDurationUsec := 250
const SimulationFrequencyProbeBatchTickCount := 64
const SimulationFrequencyProbeDurationUsec := 4_000
const SimulationThroughputSampleIntervalUsec := 250_000
const SimulationAccumulatorMaximumSeconds := 0.25
const SimulationDragPixelsPerStep := 8.0
const DockMenuButtonSize := 28
const DockMenuSeparation := 5
const DockMenuPadding := 14
const InkVariantMenuColumns := 3
const InkVariantMenuButtonSize := Vector2i(28, 28)
const InkVariantMenuSeparation := 4
const InkVariantMenuPadding := 14
const ClockSettingsMenuSize := Vector2i(168, 38)
const MeshSettingsMenuSize := Vector2i(136, 38)
const LatchSettingsMenuSize := Vector2i(144, 38)
const MeshIdMinimum := 1
const MeshIdMaximum := 2147483647
const ClockHoldTicksMinimum := 1
const ClockHoldTicksMaximum := 2147483647
const LeftDockSide := "left"
const RightDockSide := "right"

@onready var Board: Node2D = $BoardViewport/SubViewport/CircuitBoard
@onready var BoardViewport: SubViewportContainer = $BoardViewport
@onready var TopBar: Panel = $Interface/TopBar
@onready var ProjectContent: HBoxContainer = $Interface/TopBar/ProjectContent
@onready var NewProjectButton: Button = $Interface/TopBar/ProjectContent/NewProjectButton
@onready var OpenProjectButton: Button = $Interface/TopBar/ProjectContent/OpenProjectButton
@onready var SaveProjectButton: Button = $Interface/TopBar/ProjectContent/SaveProjectButton
@onready var SaveAsProjectButton: Button = $Interface/TopBar/ProjectContent/SaveAsProjectButton
@onready var RecentProjectsButton: Button = $Interface/TopBar/ProjectContent/RecentProjectsButton
@onready var ProjectTitle: Label = $Interface/TopBar/ProjectTitle
@onready var LeftSidebarToggle: Button = $Interface/TopBar/Content/LeftSidebarToggle
@onready var RightSidebarToggle: Button = $Interface/TopBar/Content/RightSidebarToggle
@onready var SimulationModeButton: Button = $Interface/TopBar/Content/SimulationModeButton
@onready var PreviousTickButton: Button = $Interface/TopBar/Content/PreviousTickButton
@onready var LoopStepButton: Button = $Interface/TopBar/Content/LoopStepButton
@onready var NextTickButton: Button = $Interface/TopBar/Content/NextTickButton
@onready var StepLengthControl: Button = $Interface/TopBar/Content/StepLengthControl
@onready var LoopFrequencySlider: HSlider = $Interface/TopBar/Content/LoopFrequencySlider
@onready var LoopFrequencyInput: LineEdit = $Interface/TopBar/Content/LoopFrequencyInput
@onready var SimulationStatus: Label = $Interface/TopBar/Content/SimulationStatus
@onready var DockHost: Control = $Interface/DockHost
@onready var DockResizeHandle: ColorRect = $Interface/DockResizeHandle
@onready var RightDockHost: Control = $Interface/RightDockHost
@onready var RightDockResizeHandle: ColorRect = $Interface/RightDockResizeHandle

var DockDefinitions: Array[Dictionary] = []
var CurrentDock: Control
var RightCurrentDock: Control
var DockMenu: PopupPanel
var DockMenuColumns := 1
var DockMenuTargetSide := LeftDockSide
var InkVariantMenu: PopupPanel
var InkVariantMenuGrid: GridContainer
var InkVariantMenuDock: Control
var InkVariantMenuPaletteToolId := ""
var InkVariantButtons: Dictionary[String, Button] = {}
var ClockSettingsMenu: PopupPanel
var ClockHoldTicksControl: SpinBox
var ClockHoldTicksSuffix: Label
var ClockSettingsMenuDock: Control
var MeshSettingsMenu: PopupPanel
var MeshIdControl: SpinBox
var MeshSettingsMenuDock: Control
var LatchSettingsMenu: PopupPanel
var LatchEnabledStateButton: Button
var LatchDisabledStateButton: Button
var LatchSettingsMenuDock: Control
var LastSelectedInkIdByPaletteToolId: Dictionary[String, String] = {}
var DockWidth := 272.0
var RightDockWidth := 272.0
var EventHistory: Array[String] = []
var LeftSidebarOpen := true
var RightSidebarOpen := true
var IsResizingDock := false
var IsResizingRightDock := false
var LeftSidebarTween: Tween
var RightSidebarTween: Tween
var ProjectManagerInstance := ProjectManager.new()
var ProjectFileDialog: FileDialog
var ProjectNoticeDialog: AcceptDialog
var RecentProjectsMenu: PopupPanel
var PendingProjectFileAction := ""
var IsSimulating := false
var IsLooping := true
var SimulationTick := 0
var SimulationTimeline: Array = []
var SimulationTimelineStartTick := 0
var SimulationTimelineBytes := 0
@export_group("Simulation Timeline")
@export var SimulationTimelineEntryMaximum := 256
@export var SimulationTimelineMaximumBytes := 32 * 1024 * 1024
var SimulationAccumulator := 0.0
var SimulationStepLength := SimulationStepLengthMinimum
var LoopFrequency := SimulationFrequencyMinimumTps
var LoopFrequencyMaximumTps := SimulationFrequencyMinimumTps
var IsLoopFrequencyFullSpeed := false
var IsEditingLoopFrequency := false
var SimulationTicksPerSecond := 0.0
var SimulationThroughputSampleStartUsec := 0
var SimulationThroughputSampleTicks := 0
var LastFastLoopCursorUpdateUsec := 0
var IsAsyncSimulationRunning := false
var IsDraggingStepLength := false
var StepLengthDragRemainder := 0.0
var SimulationBridgeInstance := SimulationBridge.new()

func _ready() -> void:
	Input.set_use_accumulated_input(false)
	configureTopBar()
	configureProjectDialogs()
	Board.connect("clipboardChanged", updateClipboardHistory)
	Board.connect("clipboardCopied", showClipboardDock)
	Board.connect("clockHoldTicksChanged", refreshClockHoldTicksControl)
	if Board.has_signal("meshIdChanged"):
		Board.connect("meshIdChanged", refreshMeshIdControl)
	if Board.has_signal("latchInitialStateChanged"):
		Board.connect("latchInitialStateChanged", refreshLatchInitialStateControls)
	NewProjectButton.pressed.connect(createNewProject)
	OpenProjectButton.pressed.connect(showOpenProjectDialog)
	SaveProjectButton.pressed.connect(saveProject)
	SaveAsProjectButton.pressed.connect(showSaveProjectDialog)
	RecentProjectsButton.pressed.connect(showRecentProjectsMenu)
	LeftSidebarToggle.toggled.connect(setLeftSidebarOpen)
	RightSidebarToggle.toggled.connect(setRightSidebarOpen)
	SimulationModeButton.pressed.connect(toggleSimulationMode)
	PreviousTickButton.pressed.connect(showPreviousSimulationTick)
	LoopStepButton.pressed.connect(toggleLoopStepMode)
	NextTickButton.pressed.connect(showNextSimulationTick)
	StepLengthControl.gui_input.connect(handleStepLengthInput)
	LoopFrequencySlider.value_changed.connect(setLoopFrequencyFromSlider)
	LoopFrequencySlider.gui_input.connect(handleLoopFrequencySliderInput)
	LoopFrequencyInput.gui_input.connect(handleLoopFrequencyInput)
	LoopFrequencyInput.text_submitted.connect(submitLoopFrequencyInput)
	LoopFrequencyInput.focus_exited.connect(commitLoopFrequencyInput)
	BoardViewport.gui_input.connect(handleSimulationCanvasInput)
	DockResizeHandle.gui_input.connect(handleDockResizeInput)
	RightDockResizeHandle.gui_input.connect(handleRightDockResizeInput)
	DockResizeHandle.mouse_entered.connect(func() -> void: DockResizeHandle.color = Color("5d7090"))
	DockResizeHandle.mouse_exited.connect(func() -> void:
		if not IsResizingDock:
			DockResizeHandle.color = Color("263346")
	)
	RightDockResizeHandle.mouse_entered.connect(func() -> void: RightDockResizeHandle.color = Color("5d7090"))
	RightDockResizeHandle.mouse_exited.connect(func() -> void:
		if not IsResizingRightDock:
			RightDockResizeHandle.color = Color("263346")
	)
	resized.connect(syncDockLayout)
	DockDefinitions = DockRegistry.discoverDocks()
	if DockDefinitions.is_empty():
		push_error("NoDockRegistered")
		return
	buildDockMenu()
	buildInkVariantMenu()
	buildClockSettingsMenu()
	buildMeshSettingsMenu()
	buildLatchSettingsMenu()
	var initialLeftDockId := String(DockDefinitions[0].dockId)
	activateDock(initialLeftDockId, LeftDockSide)
	var initialRightDockId := getInitialRightDockId(initialLeftDockId)
	if not initialRightDockId.is_empty():
		activateDock(initialRightDockId, RightDockSide)
	setLeftSidebarOpen(LeftSidebarToggle.button_pressed, false)
	setRightSidebarOpen(RightSidebarToggle.button_pressed, false)

func _process(_delta: float) -> void:
	updateSimulation(_delta)
	if IsSimulating and IsLooping and IsLoopFrequencyFullSpeed:
		var nowUsec := Time.get_ticks_usec()
		if nowUsec - LastFastLoopCursorUpdateUsec < SimulationFastLoopCursorRefreshIntervalUsec:
			return
		LastFastLoopCursorUpdateUsec = nowUsec
	if not isPointerOverCanvas():
		return
	var mousePosition := Board.get_global_mouse_position()
	var isValid: bool = Board.ValidRect.has_point(mousePosition)
	var coordinates: Vector2i = Board.call("getGridCoordinates", mousePosition)
	var cursorInfo: Dictionary = Board.call("getCursorInfoAt", coordinates) if isValid and Board.has_method("getCursorInfoAt") else {}
	if not cursorInfo.is_empty():
		isValid = bool(cursorInfo.get("isValid", isValid))
	var hoveredInkTitle := "None"
	if not cursorInfo.is_empty():
		hoveredInkTitle = String(cursorInfo.get("hoveredInkTitle", "None"))
	elif isValid:
		var hoveredInk: Dictionary = Board.call("getInkAt", coordinates)
		hoveredInkTitle = String(hoveredInk.get("title", "None"))
	for dock in getActiveDocks():
		if dock.has_method("updateCursorInfo"):
			dock.call("updateCursorInfo", coordinates, isValid, hoveredInkTitle)

func isPointerOverCanvas() -> bool:
	var pointerPosition := get_viewport().get_mouse_position()
	if not BoardViewport.get_global_rect().has_point(pointerPosition):
		return false
	return not DockHost.get_global_rect().has_point(pointerPosition) and not RightDockHost.get_global_rect().has_point(pointerPosition)

func buildDockMenu() -> void:
	DockMenu = PopupPanel.new()
	DockMenu.transparent_bg = true
	DockMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(DockMenu)
	var grid := GridContainer.new()
	DockMenuColumns = clampi(DockDefinitions.size(), 1, 3)
	grid.columns = DockMenuColumns
	grid.add_theme_constant_override("h_separation", DockMenuSeparation)
	grid.add_theme_constant_override("v_separation", DockMenuSeparation)
	DockMenu.add_child(grid)
	for definition in DockDefinitions:
		var button := Button.new()
		button.custom_minimum_size = Vector2(DockMenuButtonSize, DockMenuButtonSize)
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
	activateDock(dockId, DockMenuTargetSide)
	DockMenu.hide()

func activateDock(dockId: String, dockSide := LeftDockSide) -> void:
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
	for definition in DockDefinitions:
		var dockId := String(definition.dockId)
		if dockId != initialLeftDockId:
			return dockId
	return ""

func getDockDefinition(dockId: String) -> Dictionary:
	for candidate in DockDefinitions:
		if String(candidate.dockId) == dockId:
			return candidate
	return {}

func getActiveDocks() -> Array[Control]:
	var docks: Array[Control] = []
	if CurrentDock:
		docks.append(CurrentDock)
	if RightCurrentDock:
		docks.append(RightCurrentDock)
	return docks

func getActiveDockById(dockId: String) -> Control:
	for dock in getActiveDocks():
		if String(dock.get("DockId")) == dockId:
			return dock
	return null

func getActiveDockId(dockSide: String) -> String:
	var dock := getActiveDock(dockSide)
	return String(dock.get("DockId")) if dock else ""

func getActiveDock(dockSide: String) -> Control:
	if not isDockSideValid(dockSide):
		return null
	return getDockForSide(dockSide)

func getDockForSide(dockSide: String) -> Control:
	if dockSide == LeftDockSide:
		return CurrentDock
	if dockSide == RightDockSide:
		return RightCurrentDock
	return null

func getDockHostForSide(dockSide: String) -> Control:
	if dockSide == LeftDockSide:
		return DockHost
	if dockSide == RightDockSide:
		return RightDockHost
	return null

func getOtherDockSide(dockSide: String) -> String:
	return RightDockSide if dockSide == LeftDockSide else LeftDockSide

func isDockSideValid(dockSide: String) -> bool:
	return dockSide == LeftDockSide or dockSide == RightDockSide

func setDockForSide(definition: Dictionary, dockSide: String) -> void:
	if definition.is_empty():
		return
	var previousDock := getDockForSide(dockSide)
	if previousDock:
		if InkVariantMenuDock == previousDock:
			hideInkVariantMenu()
		if ClockSettingsMenuDock == previousDock:
			hideClockSettingsMenu()
		if MeshSettingsMenuDock == previousDock:
			hideMeshSettingsMenu()
		if LatchSettingsMenuDock == previousDock:
			hideLatchSettingsMenu()
		previousDock.free()
	var dockScene := definition.scene as PackedScene
	var nextDock := dockScene.instantiate() as Control
	var host := getDockHostForSide(dockSide)
	host.add_child(nextDock)
	nextDock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if dockSide == LeftDockSide:
		CurrentDock = nextDock
		setDockWidth(float(definition.dockWidth))
	else:
		RightCurrentDock = nextDock
		setRightDockWidth(float(definition.dockWidth))
	connectDockSignals(nextDock, dockSide)
	if nextDock.has_method("setEventHistory"):
		nextDock.call("setEventHistory", EventHistory)
	if nextDock.has_method("setClipboardHistory"):
		nextDock.call("setClipboardHistory", Board.call("getClipboardHistory"), Board.call("getSelectedClipboardIndex"))

func connectDockSignals(dock: Control, dockSide: String) -> void:
	if dock.has_signal("dockMenuRequested"):
		dock.connect("dockMenuRequested", showDockMenu.bind(dockSide))
	if dock.has_signal("inkSelected"):
		dock.connect("inkSelected", selectInk)
	if dock.has_signal("inkVariantMenuRequested"):
		dock.connect("inkVariantMenuRequested", showInkVariantMenu.bind(dock))
	if dock.has_signal("componentSettingsMenuRequested"):
		dock.connect("componentSettingsMenuRequested", showComponentSettingsMenu.bind(dock))
	elif dock.has_signal("clockSettingsMenuRequested"):
		dock.connect("clockSettingsMenuRequested", showClockSettingsMenu.bind(dock))
	if dock.has_signal("eventRecorded"):
		dock.connect("eventRecorded", recordEvent)
	if dock.has_signal("clipboardItemSelected"):
		dock.connect("clipboardItemSelected", selectClipboardItem)
	if dock.has_method("syncLastSelectedInkIds"):
		dock.call("syncLastSelectedInkIds", LastSelectedInkIdByPaletteToolId)
	if dock.has_method("syncSelectedInk"):
		dock.call("syncSelectedInk", String(Board.get("SelectedTool")))
	if dock.has_method("setInkInputEnabled"):
		dock.call("setInkInputEnabled", not IsSimulating)

func recordEvent(eventText: String) -> void:
	EventHistory.append(eventText)
	for dock in getActiveDocks():
		if dock.has_method("appendEvent"):
			dock.call("appendEvent", eventText)

func showDockMenu(menuButton: Button, dockSide: String) -> void:
	DockMenuTargetSide = dockSide
	var buttonPosition := menuButton.get_global_rect().position
	var menuRows := ceili(float(DockDefinitions.size()) / float(DockMenuColumns))
	var menuSize := Vector2i(
		DockMenuPadding + DockMenuColumns * DockMenuButtonSize + (DockMenuColumns - 1) * DockMenuSeparation,
		DockMenuPadding + menuRows * DockMenuButtonSize + (menuRows - 1) * DockMenuSeparation
	)
	var popupPosition := Vector2i(buttonPosition + Vector2(4.0, menuButton.size.y))
	var viewportSize := get_viewport_rect().size
	popupPosition.x = clampi(popupPosition.x, 0, maxi(0, int(viewportSize.x) - menuSize.x))
	popupPosition.y = clampi(popupPosition.y, 0, maxi(0, int(viewportSize.y) - menuSize.y))
	DockMenu.popup(Rect2i(popupPosition, menuSize))

func buildInkVariantMenu() -> void:
	InkVariantMenu = PopupPanel.new()
	InkVariantMenu.transparent_bg = true
	InkVariantMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(InkVariantMenu)
	InkVariantMenuGrid = GridContainer.new()
	InkVariantMenuGrid.name = "InkVariantMenuGrid"
	InkVariantMenuGrid.columns = InkVariantMenuColumns
	InkVariantMenuGrid.add_theme_constant_override("h_separation", InkVariantMenuSeparation)
	InkVariantMenuGrid.add_theme_constant_override("v_separation", InkVariantMenuSeparation)
	InkVariantMenu.add_child(InkVariantMenuGrid)
	InkVariantMenu.popup_hide.connect(func() -> void:
		InkVariantMenuDock = null
		InkVariantMenuPaletteToolId = ""
	)

func showInkVariantMenu(anchorButton: Button, paletteToolId: String, dock: Control) -> void:
	if IsSimulating:
		return
	var variants := InkRegistry.getInkVariants(paletteToolId)
	if variants.size() < 2:
		return
	InkVariantMenuDock = dock
	InkVariantMenuPaletteToolId = paletteToolId
	populateInkVariantMenu(variants)
	var menuRows := ceili(float(variants.size()) / float(InkVariantMenuColumns))
	var menuSize := Vector2i(
		InkVariantMenuPadding + InkVariantMenuColumns * InkVariantMenuButtonSize.x + (InkVariantMenuColumns - 1) * InkVariantMenuSeparation,
		InkVariantMenuPadding + menuRows * InkVariantMenuButtonSize.y + (menuRows - 1) * InkVariantMenuSeparation
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
	InkVariantMenu.popup(Rect2i(popupPosition, menuSize))

func populateInkVariantMenu(variants: Array[Dictionary]) -> void:
	for child in InkVariantMenuGrid.get_children():
		child.free()
	InkVariantButtons.clear()
	for ink in variants:
		var button := InkButton.new() as Button
		button.call("configure", ink)
		button.pressed.connect(selectInkVariant.bind(ink))
		InkVariantMenuGrid.add_child(button)
		InkVariantButtons[InkRegistry.getComponentId(ink)] = button
	refreshInkVariantButtons()

func selectInkVariant(ink: Dictionary) -> void:
	if IsSimulating:
		hideInkVariantMenu()
		return
	if InkVariantMenuDock and InkVariantMenuDock.has_method("selectInk"):
		InkVariantMenuDock.call("selectInk", ink)
	hideInkVariantMenu()

func hideInkVariantMenu() -> void:
	if InkVariantMenu:
		InkVariantMenu.hide()
	InkVariantMenuDock = null
	InkVariantMenuPaletteToolId = ""

func showComponentSettingsMenu(anchorButton: Button, componentId: String, dock: Control) -> void:
	if IsSimulating:
		return
	match componentId:
		"clock":
			showClockSettingsMenu(anchorButton, dock)
		"mesh":
			showMeshSettingsMenu(anchorButton, dock)
		"latch":
			showLatchSettingsMenu(anchorButton, dock)
		_:
			return

func buildMeshSettingsMenu() -> void:
	MeshSettingsMenu = PopupPanel.new()
	MeshSettingsMenu.transparent_bg = true
	MeshSettingsMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(MeshSettingsMenu)
	var content := HBoxContainer.new()
	content.name = "MeshSettingsMenuContent"
	content.add_theme_constant_override("separation", 4)
	MeshSettingsMenu.add_child(content)
	var idLabel := Label.new()
	idLabel.name = "MeshIdLabel"
	idLabel.text = "ID"
	idLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	idLabel.add_theme_color_override("font_color", Color("b4c1d3"))
	content.add_child(idLabel)
	MeshIdControl = SpinBox.new()
	MeshIdControl.name = "MeshIdControl"
	MeshIdControl.custom_minimum_size = Vector2(76, 24)
	MeshIdControl.min_value = MeshIdMinimum
	MeshIdControl.max_value = MeshIdMaximum
	MeshIdControl.step = 1.0
	MeshIdControl.allow_greater = false
	MeshIdControl.allow_lesser = false
	MeshIdControl.rounded = true
	MeshIdControl.value_changed.connect(setMeshId)
	configureMeshIdControl()
	content.add_child(MeshIdControl)
	MeshSettingsMenu.popup_hide.connect(func() -> void:
		MeshSettingsMenuDock = null
	)
	refreshMeshIdControl()

func showMeshSettingsMenu(anchorButton: Button, dock: Control) -> void:
	if IsSimulating or MeshSettingsMenu == null:
		return
	hideInkVariantMenu()
	hideClockSettingsMenu()
	hideLatchSettingsMenu()
	MeshSettingsMenuDock = dock
	refreshMeshIdControl()
	MeshSettingsMenu.popup(Rect2i(getSettingsMenuPosition(anchorButton, MeshSettingsMenuSize), MeshSettingsMenuSize))

func hideMeshSettingsMenu() -> void:
	if MeshSettingsMenu:
		MeshSettingsMenu.hide()
	MeshSettingsMenuDock = null

func setMeshId(requestedMeshId: float) -> void:
	if IsSimulating:
		refreshMeshIdControl()
		return
	Board.call("setMeshId", int(requestedMeshId))
	refreshMeshIdControl()

func refreshMeshIdControl(_meshId := 0) -> void:
	if MeshIdControl == null:
		return
	MeshIdControl.set_value_no_signal(maxi(MeshIdMinimum, int(Board.call("getMeshId"))))

func configureMeshIdControl() -> void:
	if MeshIdControl == null:
		return
	MeshIdControl.add_theme_icon_override("updown", makeSolidTexture(Vector2i(1, 1), Color.TRANSPARENT))
	var lineEdit := MeshIdControl.get_line_edit()
	lineEdit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	lineEdit.add_theme_font_size_override("font_size", TopBarFontSize)
	lineEdit.add_theme_color_override("font_color", Color("9aa8bf"))
	lineEdit.add_theme_color_override("font_selected_color", Color.WHITE)
	lineEdit.add_theme_stylebox_override("normal", makeStepLengthBox(Color("2a3548")))
	lineEdit.add_theme_stylebox_override("focus", makeStepLengthBox(Color("35435a")))
	lineEdit.add_theme_stylebox_override("read_only", makeStepLengthBox(Color("202a38")))

func buildLatchSettingsMenu() -> void:
	LatchSettingsMenu = PopupPanel.new()
	LatchSettingsMenu.transparent_bg = true
	LatchSettingsMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(LatchSettingsMenu)
	var content := HBoxContainer.new()
	content.name = "LatchSettingsMenuContent"
	content.add_theme_constant_override("separation", 4)
	LatchSettingsMenu.add_child(content)
	var stateLabel := Label.new()
	stateLabel.name = "LatchStateLabel"
	stateLabel.text = "State"
	stateLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stateLabel.add_theme_color_override("font_color", Color("b4c1d3"))
	content.add_child(stateLabel)
	var stateGroup := ButtonGroup.new()
	LatchEnabledStateButton = makeLatchStateButton("On")
	LatchEnabledStateButton.name = "LatchEnabledStateButton"
	LatchEnabledStateButton.button_group = stateGroup
	LatchEnabledStateButton.pressed.connect(setLatchInitialState.bind(true))
	content.add_child(LatchEnabledStateButton)
	LatchDisabledStateButton = makeLatchStateButton("Off")
	LatchDisabledStateButton.name = "LatchDisabledStateButton"
	LatchDisabledStateButton.button_group = stateGroup
	LatchDisabledStateButton.pressed.connect(setLatchInitialState.bind(false))
	content.add_child(LatchDisabledStateButton)
	LatchSettingsMenu.popup_hide.connect(func() -> void:
		LatchSettingsMenuDock = null
	)
	refreshLatchInitialStateControls()

func showLatchSettingsMenu(anchorButton: Button, dock: Control) -> void:
	if IsSimulating or LatchSettingsMenu == null:
		return
	hideInkVariantMenu()
	hideClockSettingsMenu()
	hideMeshSettingsMenu()
	LatchSettingsMenuDock = dock
	refreshLatchInitialStateControls()
	LatchSettingsMenu.popup(Rect2i(getSettingsMenuPosition(anchorButton, LatchSettingsMenuSize), LatchSettingsMenuSize))

func hideLatchSettingsMenu() -> void:
	if LatchSettingsMenu:
		LatchSettingsMenu.hide()
	LatchSettingsMenuDock = null

func makeLatchStateButton(buttonText: String) -> Button:
	var button := Button.new()
	button.text = buttonText
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(36, 24)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("9aa8bf"))
	button.add_theme_color_override("font_hover_color", Color("e1e9f6"))
	button.add_theme_color_override("font_pressed_color", Color("111a26"))
	button.add_theme_stylebox_override("normal", makeStepLengthBox(Color("2a3548")))
	button.add_theme_stylebox_override("hover", makeStepLengthBox(Color("35435a")))
	button.add_theme_stylebox_override("pressed", makeStepLengthBox(Color("43ec90")))
	button.add_theme_stylebox_override("hover_pressed", makeStepLengthBox(Color("5af0a0")))
	return button

func setLatchInitialState(isOn: bool) -> void:
	if IsSimulating:
		refreshLatchInitialStateControls()
		return
	Board.call("setLatchInitialState", isOn)
	refreshLatchInitialStateControls()

func refreshLatchInitialStateControls(_isOn := false) -> void:
	if LatchEnabledStateButton == null or LatchDisabledStateButton == null:
		return
	var isOn := bool(Board.call("getLatchInitialState"))
	LatchEnabledStateButton.set_pressed_no_signal(isOn)
	LatchDisabledStateButton.set_pressed_no_signal(not isOn)

func getSettingsMenuPosition(anchorButton: Button, menuSize: Vector2i) -> Vector2i:
	var anchorRect := anchorButton.get_global_rect()
	var popupPosition := Vector2i(anchorRect.position + Vector2(anchorRect.size.x + 4.0, 0.0))
	var viewportSize := get_viewport_rect().size
	if popupPosition.x + menuSize.x > int(viewportSize.x):
		popupPosition.x = int(anchorRect.position.x) - menuSize.x - 4
	if popupPosition.y + menuSize.y > int(viewportSize.y):
		popupPosition.y = int(anchorRect.end.y) - menuSize.y
	popupPosition.x = clampi(popupPosition.x, 0, maxi(0, int(viewportSize.x) - menuSize.x))
	popupPosition.y = clampi(popupPosition.y, 0, maxi(0, int(viewportSize.y) - menuSize.y))
	return popupPosition

func buildClockSettingsMenu() -> void:
	ClockSettingsMenu = PopupPanel.new()
	ClockSettingsMenu.transparent_bg = true
	ClockSettingsMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(ClockSettingsMenu)
	var content := HBoxContainer.new()
	content.name = "ClockSettingsMenuContent"
	content.add_theme_constant_override("separation", 4)
	ClockSettingsMenu.add_child(content)
	var holdLabel := Label.new()
	holdLabel.name = "ClockHoldTicksLabel"
	holdLabel.text = "Hold"
	holdLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holdLabel.add_theme_color_override("font_color", Color("b4c1d3"))
	content.add_child(holdLabel)
	ClockHoldTicksControl = SpinBox.new()
	ClockHoldTicksControl.name = "ClockHoldTicksControl"
	ClockHoldTicksControl.custom_minimum_size = Vector2(76, 24)
	ClockHoldTicksControl.min_value = ClockHoldTicksMinimum
	ClockHoldTicksControl.max_value = ClockHoldTicksMaximum
	ClockHoldTicksControl.step = 1.0
	ClockHoldTicksControl.allow_greater = false
	ClockHoldTicksControl.allow_lesser = false
	ClockHoldTicksControl.rounded = true
	ClockHoldTicksControl.value_changed.connect(setClockHoldTicks)
	configureClockHoldTicksControl()
	content.add_child(ClockHoldTicksControl)
	var ticksLabel := Label.new()
	ticksLabel.name = "ClockHoldTicksSuffix"
	ticksLabel.text = "ticks"
	ticksLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ticksLabel.add_theme_color_override("font_color", Color("8d9db5"))
	content.add_child(ticksLabel)
	ClockHoldTicksSuffix = ticksLabel
	ClockSettingsMenu.popup_hide.connect(func() -> void:
		ClockSettingsMenuDock = null
	)
	refreshClockHoldTicksControl()

func showClockSettingsMenu(anchorButton: Button, dock: Control) -> void:
	if IsSimulating or ClockSettingsMenu == null:
		return
	hideInkVariantMenu()
	hideMeshSettingsMenu()
	hideLatchSettingsMenu()
	ClockSettingsMenuDock = dock
	refreshClockHoldTicksControl()
	ClockSettingsMenu.popup(Rect2i(getSettingsMenuPosition(anchorButton, ClockSettingsMenuSize), ClockSettingsMenuSize))

func hideClockSettingsMenu() -> void:
	if ClockSettingsMenu:
		ClockSettingsMenu.hide()
	ClockSettingsMenuDock = null

func setClockHoldTicks(requestedHoldTicks: float) -> void:
	if IsSimulating:
		refreshClockHoldTicksControl()
		return
	Board.call("setClockHoldTicks", int(requestedHoldTicks))
	refreshClockHoldTicksControl()

func refreshClockHoldTicksControl(_holdTicks := 0) -> void:
	var holdTicks := int(Board.call("getClockHoldTicks"))
	if ClockHoldTicksControl:
		ClockHoldTicksControl.set_value_no_signal(maxi(ClockHoldTicksMinimum, holdTicks))
	if ClockHoldTicksSuffix:
		ClockHoldTicksSuffix.text = "tick" if holdTicks == 1 else "ticks"

func refreshInkVariantButtons() -> void:
	if InkVariantMenuDock == null:
		return
	var selectedInkId := ""
	if InkVariantMenuDock.has_method("getLastSelectedInkId"):
		selectedInkId = String(InkVariantMenuDock.call("getLastSelectedInkId", InkVariantMenuPaletteToolId))
	elif InkVariantMenuDock.has_method("getSelectedInkId"):
		selectedInkId = String(InkVariantMenuDock.call("getSelectedInkId"))
	for componentId in InkVariantButtons:
		var button := InkVariantButtons[componentId]
		var ink := InkRegistry.getInk(String(componentId))
		var isSelected := componentId == selectedInkId
		button.set_pressed_no_signal(isSelected)
		button.call("setInkAppearance", ink.get("color", Color.WHITE), isSelected)

func selectInk(ink: Dictionary) -> void:
	if IsSimulating:
		return
	LastSelectedInkIdByPaletteToolId[InkRegistry.getPaletteToolId(ink)] = InkRegistry.getComponentId(ink)
	Board.call("selectTool", InkRegistry.getComponentId(ink))
	refreshInkVariantButtons()

func updateClipboardHistory(history: Array[Dictionary], selectedIndex: int) -> void:
	for dock in getActiveDocks():
		if dock.has_method("setClipboardHistory"):
			dock.call("setClipboardHistory", history, selectedIndex)

func showClipboardDock(history: Array[Dictionary], selectedIndex: int) -> void:
	var clipboardDock := getActiveDockById("clipboard")
	if clipboardDock == null:
		activateDock("clipboard", LeftDockSide)
		clipboardDock = getActiveDockById("clipboard")
	if clipboardDock and clipboardDock.has_method("setClipboardHistory"):
		clipboardDock.call("setClipboardHistory", history, selectedIndex)

func selectClipboardItem(index: int) -> void:
	Board.call("selectClipboardItem", index)

func configureProjectDialogs() -> void:
	var projectDialogTheme := makeProjectDialogTheme()
	ProjectFileDialog = FileDialog.new()
	ProjectFileDialog.access = FileDialog.ACCESS_FILESYSTEM
	ProjectFileDialog.filters = PackedStringArray(["*.ocb ; OpenCircuitBoard Project"])
	ProjectFileDialog.transparent_bg = true
	ProjectFileDialog.min_size = Vector2i(760, 480)
	ProjectFileDialog.theme = projectDialogTheme
	ProjectFileDialog.file_selected.connect(handleProjectFileSelected)
	$Interface.add_child(ProjectFileDialog)
	configureProjectFileDialogButtons()
	ProjectNoticeDialog = AcceptDialog.new()
	ProjectNoticeDialog.title = ApplicationTitle
	ProjectNoticeDialog.transparent_bg = true
	ProjectNoticeDialog.theme = projectDialogTheme
	$Interface.add_child(ProjectNoticeDialog)
	configureDialogActionButton(ProjectNoticeDialog.get_ok_button())

func configureProjectFileDialogButtons() -> void:
	configureDialogActionButton(ProjectFileDialog.get_ok_button())
	configureDialogSecondaryButton(ProjectFileDialog.get_cancel_button())

func configureDialogActionButton(button: Button) -> void:
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", makeDialogBox(DialogActionColor, DialogActionColor, 3, 6))
	button.add_theme_stylebox_override("hover", makeDialogBox(DialogActionColor.lightened(0.1), DialogActionColor.lightened(0.1), 3, 6))
	button.add_theme_stylebox_override("pressed", makeDialogBox(DialogActionColor.darkened(0.12), DialogActionColor.darkened(0.12), 3, 6))

func configureDialogSecondaryButton(button: Button) -> void:
	button.add_theme_stylebox_override("normal", makeDialogBox(DialogSurfaceColor, DialogBorderColor, 3, 6))
	button.add_theme_stylebox_override("hover", makeDialogBox(DialogHoverColor, DialogBorderColor, 3, 6))
	button.add_theme_stylebox_override("pressed", makeDialogBox(DialogInputColor, DialogBorderColor, 3, 6))

func createNewProject() -> void:
	leaveSimulation()
	Board.call("clearProjectData")
	ProjectManagerInstance.clearCurrentProject()
	refreshProjectTitle()
	recordEvent("Created new project")

func showOpenProjectDialog() -> void:
	PendingProjectFileAction = "open"
	ProjectFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	ProjectFileDialog.current_file = ""
	ProjectFileDialog.title = "Open .ocb Project"
	ProjectFileDialog.popup_centered_ratio(0.72)

func saveProject() -> void:
	if not ProjectManagerInstance.hasCurrentProject():
		showSaveProjectDialog()
		return
	handleProjectResult(ProjectManagerInstance.saveProject(Board), "Saved project")

func showSaveProjectDialog() -> void:
	PendingProjectFileAction = "save"
	ProjectFileDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	ProjectFileDialog.current_file = ProjectManagerInstance.CurrentProjectPath.get_file() if ProjectManagerInstance.hasCurrentProject() else "Untitled.ocb"
	ProjectFileDialog.title = "Save .ocb Project"
	ProjectFileDialog.popup_centered_ratio(0.72)

func handleProjectFileSelected(projectPath: String) -> void:
	var result := {}
	if PendingProjectFileAction == "open":
		leaveSimulation()
		result = ProjectManagerInstance.loadProject(Board, projectPath)
		if bool(result.get("ok", false)):
			recordEvent("Opened project")
	elif PendingProjectFileAction == "save":
		result = ProjectManagerInstance.saveProjectAs(Board, projectPath)
		if bool(result.get("ok", false)):
			recordEvent("Saved project")
	PendingProjectFileAction = ""
	if bool(result.get("ok", false)):
		refreshProjectTitle()
	else:
		showProjectNotice(getProjectErrorText(String(result.get("message", "ProjectOperationFailed"))))

func showRecentProjectsMenu() -> void:
	if RecentProjectsMenu:
		RecentProjectsMenu.queue_free()
	RecentProjectsMenu = PopupPanel.new()
	RecentProjectsMenu.transparent_bg = true
	RecentProjectsMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(RecentProjectsMenu)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	RecentProjectsMenu.add_child(content)
	var recentProjectPaths := ProjectManagerInstance.getRecentProjectPaths()
	if recentProjectPaths.is_empty():
		var emptyLabel := Label.new()
		emptyLabel.custom_minimum_size = Vector2(238, 28)
		emptyLabel.text = "No recent projects"
		emptyLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		emptyLabel.add_theme_color_override("font_color", Color("8d9db5"))
		content.add_child(emptyLabel)
	else:
		for projectPath in recentProjectPaths:
			var projectButton := Button.new()
			projectButton.custom_minimum_size = Vector2(238, 28)
			projectButton.text = projectPath.get_file()
			projectButton.tooltip_text = projectPath
			projectButton.alignment = HORIZONTAL_ALIGNMENT_LEFT
			projectButton.clip_text = true
			projectButton.add_theme_stylebox_override("normal", makeMenuItemBox(Color.TRANSPARENT))
			projectButton.add_theme_stylebox_override("hover", makeMenuItemBox(Color("2b374a")))
			projectButton.add_theme_color_override("font_color", Color("d8e1ef"))
			projectButton.pressed.connect(openRecentProject.bind(projectPath))
			content.add_child(projectButton)
	var menuRows := maxi(1, recentProjectPaths.size())
	var menuSize := Vector2i(252, 14 + menuRows * 28 + (menuRows - 1) * 4)
	var anchorRect := RecentProjectsButton.get_global_rect()
	var popupPosition := Vector2i(anchorRect.position + Vector2(0.0, anchorRect.size.y + 3.0))
	var viewportSize := get_viewport_rect().size
	popupPosition.x = clampi(popupPosition.x, 0, maxi(0, int(viewportSize.x) - menuSize.x))
	popupPosition.y = clampi(popupPosition.y, 0, maxi(0, int(viewportSize.y) - menuSize.y))
	RecentProjectsMenu.popup(Rect2i(popupPosition, menuSize))

func openRecentProject(projectPath: String) -> void:
	leaveSimulation()
	var result := ProjectManagerInstance.loadProject(Board, projectPath)
	if RecentProjectsMenu:
		RecentProjectsMenu.hide()
	if bool(result.get("ok", false)):
		refreshProjectTitle()
		recordEvent("Opened project")
		return
	showProjectNotice(getProjectErrorText(String(result.get("message", "ProjectOperationFailed"))))

func handleProjectResult(result: Dictionary, successText: String) -> void:
	if bool(result.get("ok", false)):
		refreshProjectTitle()
		recordEvent(successText)
		return
	showProjectNotice(getProjectErrorText(String(result.get("message", "ProjectOperationFailed"))))

func refreshProjectTitle() -> void:
	var projectFilename := ProjectManagerInstance.CurrentProjectPath.get_file() if ProjectManagerInstance.hasCurrentProject() else NewProjectTitle
	ProjectTitle.text = "%s - %s" % [projectFilename, ApplicationTitle]
	ProjectTitle.tooltip_text = ProjectTitle.text

func showProjectNotice(message: String) -> void:
	ProjectNoticeDialog.dialog_text = message
	ProjectNoticeDialog.popup_centered(Vector2i(360, 128))

func getProjectErrorText(errorId: String) -> String:
	match errorId:
		"ProjectFileMissing":
			return "The selected .ocb project was not found."
		"ProjectOpenFailed", "ProjectEntryMissing", "ProjectFormatInvalid", "ProjectVersionUnsupported", "ProjectBoardInvalid":
			return "The selected file is not a compatible .ocb project."
		"ProjectSaveOpenFailed", "ProjectSaveStartFailed", "ProjectSaveWriteFailed":
			return "The .ocb project could not be saved."
		_:
			return "The project operation could not be completed."

func toggleSimulationMode() -> void:
	if IsSimulating:
		leaveSimulation()
	else:
		enterSimulation()

func handleSimulationCanvasInput(event: InputEvent) -> void:
	if not IsSimulating:
		return
	var mouseButton := event as InputEventMouseButton
	if mouseButton == null or mouseButton.button_index != MOUSE_BUTTON_LEFT or not mouseButton.pressed:
		return
	var boardPosition: Vector2 = Board.get_viewport().get_canvas_transform().affine_inverse() * mouseButton.position
	var coordinatesVariant: Variant = Board.call("getGridCoordinates", boardPosition)
	if not (coordinatesVariant is Vector2i):
		return
	if toggleSimulationLatchAt(coordinatesVariant as Vector2i):
		get_viewport().set_input_as_handled()

func toggleSimulationLatchAt(coordinates: Vector2i) -> bool:
	if not IsSimulating or String(Board.call("getToolIdAt", coordinates)) != "latch":
		return false
	var toggleResult := SimulationBridgeInstance.toggleLatchAt(coordinates)
	if not bool(toggleResult.get("ok", false)):
		failActiveSimulation(toggleResult)
		return false
	if IsLooping:
		applySimulationStateChanges(toggleResult.get("changes", PackedInt32Array()) as PackedInt32Array)
		refreshSimulationControls()
		return true
	if not truncateSimulationTimelineAfter(SimulationTick):
		failActiveSimulation({"ok": false, "errorReason": "SimulationTimelineInvalid"})
		return false
	var snapshotResult := SimulationBridgeInstance.captureState()
	if not bool(snapshotResult.get("ok", false)):
		failActiveSimulation(snapshotResult)
		return false
	if not replaceSimulationSnapshot(SimulationTick, snapshotResult.get("snapshot", PackedByteArray()) as PackedByteArray):
		failActiveSimulation({"ok": false, "errorReason": "SimulationTimelineInvalid"})
		return false
	applySimulationStateChanges(toggleResult.get("changes", PackedInt32Array()) as PackedInt32Array)
	SimulationAccumulator = 0.0
	refreshSimulationControls()
	return true

func enterSimulation() -> void:
	if IsSimulating:
		return
	Board.call("cancelActiveInteraction")
	clearSimulationRuntimeStates()
	var compileResult := SimulationBridgeInstance.compile(Board)
	if not bool(compileResult.get("ok", false)):
		abortSimulationStart(compileResult)
		return
	var capacityProbeResult := probeLoopFrequencyMaximum()
	if not bool(capacityProbeResult.get("ok", false)):
		abortSimulationStart(capacityProbeResult)
		return
	updateLoopFrequencyMaximum(float(capacityProbeResult.get("ticksPerSecond", SimulationFrequencyMinimumTps)))
	var statesResult := SimulationBridgeInstance.getCurrentStates()
	if not bool(statesResult.get("ok", false)):
		abortSimulationStart(statesResult)
		return
	applySimulationStates(statesResult.get("states", PackedByteArray()))
	hideInkVariantMenu()
	hideClockSettingsMenu()
	hideMeshSettingsMenu()
	hideLatchSettingsMenu()
	Board.call("setEditorInputEnabled", false)
	IsSimulating = true
	setCircuitEditorInputEnabled(false)
	IsLooping = true
	SimulationTick = 0
	clearSimulationTimeline()
	SimulationAccumulator = 0.0
	LastFastLoopCursorUpdateUsec = 0
	IsAsyncSimulationRunning = false
	resetSimulationThroughput()
	refreshSimulationControls()

func probeLoopFrequencyMaximum() -> Dictionary:
	var snapshotResult := SimulationBridgeInstance.captureState()
	if not bool(snapshotResult.get("ok", false)):
		return snapshotResult
	var advanceResult := SimulationBridgeInstance.advanceTicksForDuration(
		SimulationFrequencyProbeDurationUsec,
		2147483647,
		SimulationFrequencyProbeBatchTickCount
	)
	if not bool(advanceResult.get("ok", false)):
		return advanceResult
	var advancedTickCount := int(advanceResult.get("advancedTickCount", 0))
	var elapsedUsec := maxi(1, int(advanceResult.get("elapsedUsec", 0)))
	var snapshot := snapshotResult.get("snapshot", PackedByteArray()) as PackedByteArray
	var restoreResult: Dictionary
	if SimulationBridgeInstance.has_method("restoreStateSilent"):
		restoreResult = SimulationBridgeInstance.restoreStateSilent(snapshot)
	else:
		restoreResult = SimulationBridgeInstance.restoreState(snapshot)
	if not bool(restoreResult.get("ok", false)):
		return restoreResult
	return {
		"ok": true,
		"ticksPerSecond": float(advancedTickCount) * 1_000_000.0 / float(elapsedUsec),
	}

func leaveSimulation() -> void:
	if not IsSimulating:
		return
	var stopResult := stopAsyncLoopingSimulation(false)
	if not bool(stopResult.get("ok", false)):
		recordEvent(getSimulationFailureText(stopResult))
	IsSimulating = false
	IsLooping = true
	SimulationTick = 0
	clearSimulationTimeline()
	SimulationAccumulator = 0.0
	LastFastLoopCursorUpdateUsec = 0
	IsAsyncSimulationRunning = false
	resetSimulationThroughput()
	clearSimulationRuntimeStates()
	SimulationBridgeInstance.release()
	Board.call("setEditorInputEnabled", true)
	setCircuitEditorInputEnabled(true)
	refreshSimulationControls()

func toggleLoopStepMode() -> void:
	if not IsSimulating:
		return
	if IsLooping:
		var stopResult := stopAsyncLoopingSimulation(true)
		if not bool(stopResult.get("ok", false)):
			failActiveSimulation(stopResult)
			return
		if not initializeStepSimulationTimeline():
			return
		IsLooping = false
	else:
		IsLooping = true
		SimulationTick = 0
		clearSimulationTimeline()
		resetSimulationThroughput()
	SimulationAccumulator = 0.0
	refreshSimulationControls()

func initializeStepSimulationTimeline() -> bool:
	var snapshotResult := SimulationBridgeInstance.captureState()
	if not bool(snapshotResult.get("ok", false)):
		failActiveSimulation(snapshotResult)
		return false
	clearSimulationTimeline()
	SimulationTick = 0
	appendSimulationSnapshot(snapshotResult.get("snapshot", PackedByteArray()) as PackedByteArray)
	return true

func showPreviousSimulationTick() -> void:
	if not IsSimulating or IsLooping or SimulationTick <= getSimulationTimelineFirstTick():
		return
	if showSimulationTick(maxi(getSimulationTimelineFirstTick(), SimulationTick - SimulationStepLength)):
		refreshSimulationControls()

func showNextSimulationTick() -> void:
	if not IsSimulating or IsLooping:
		return
	if showSimulationTick(SimulationTick + SimulationStepLength):
		refreshSimulationControls()

func updateSimulation(delta: float) -> void:
	if not IsSimulating or not IsLooping:
		return
	if IsLoopFrequencyFullSpeed:
		if not startAsyncLoopingSimulation():
			return
		SimulationAccumulator = 0.0
		var fullSpeedResult := SimulationBridgeInstance.pollAsync()
		if not bool(fullSpeedResult.get("ok", false)):
			failActiveSimulation(fullSpeedResult)
			return
		if not bool(fullSpeedResult.get("running", false)):
			IsAsyncSimulationRunning = false
			failActiveSimulation({"ok": false, "errorReason": "SimulationAsyncStopped"})
			return
		applySimulationStateChanges(fullSpeedResult.get("changes", PackedInt32Array()) as PackedInt32Array)
		var fullSpeedAdvancedTickCount := int(fullSpeedResult.get("advancedTickCount", 0))
		if fullSpeedAdvancedTickCount > 0 and recordSimulationThroughput(fullSpeedAdvancedTickCount):
			updateLoopFrequencyMaximum(SimulationTicksPerSecond)
			refreshSimulationStatus()
		return
	if IsAsyncSimulationRunning:
		var stopResult := stopAsyncLoopingSimulation(true)
		if not bool(stopResult.get("ok", false)):
			failActiveSimulation(stopResult)
			return
	SimulationAccumulator += delta
	var requestedTickCount := floori(SimulationAccumulator * LoopFrequency)
	if requestedTickCount <= 0:
		return
	var advanceResult := advanceLoopingSimulation(requestedTickCount, delta)
	if not bool(advanceResult.get("ok", false)):
		return
	var advancedTickCount := int(advanceResult.get("advancedTickCount", 0))
	if advancedTickCount > 0:
		SimulationAccumulator = maxf(0.0, SimulationAccumulator - float(advancedTickCount) / LoopFrequency)
		SimulationAccumulator = minf(SimulationAccumulator, SimulationAccumulatorMaximumSeconds)
		if recordSimulationThroughput(advancedTickCount):
			if LoopFrequency >= LoopFrequencyMaximumTps * 0.8:
				updateLoopFrequencyMaximum(SimulationTicksPerSecond)
			refreshSimulationStatus()

func startAsyncLoopingSimulation() -> bool:
	if IsAsyncSimulationRunning:
		return true
	var startResult := SimulationBridgeInstance.startAsync(
		getSimulationBatchTickCount(),
		SimulationAsyncPublishIntervalUsec,
		SimulationAsyncBatchBudgetUsec
	)
	if not bool(startResult.get("ok", false)):
		failActiveSimulation(startResult)
		return false
	IsAsyncSimulationRunning = true
	return true

func stopAsyncLoopingSimulation(applyCurrentStates: bool) -> Dictionary:
	if not IsAsyncSimulationRunning:
		return {"ok": true}
	var stopResult := SimulationBridgeInstance.stopAsync()
	IsAsyncSimulationRunning = false
	if not bool(stopResult.get("ok", false)):
		return stopResult
	if not applyCurrentStates:
		return {"ok": true}
	var statesResult := SimulationBridgeInstance.getCurrentStates()
	if not bool(statesResult.get("ok", false)):
		return statesResult
	applySimulationStates(statesResult.get("states", PackedByteArray()))
	return {"ok": true}

func advanceLoopingSimulation(requestedTickCount: int, delta: float) -> Dictionary:
	var startedUsec := Time.get_ticks_usec()
	var advanceResult := SimulationBridgeInstance.advanceTicksForDurationAndDrainStateChanges(
		getSimulationWorkBudgetUsec(delta),
		requestedTickCount,
		getSimulationBatchTickCount()
	)
	if not bool(advanceResult.get("ok", false)):
		failActiveSimulation(advanceResult)
		return {"ok": false}
	var advancedTickCount := int(advanceResult.get("advancedTickCount", 0))
	applySimulationStateChanges(advanceResult.get("changes", PackedInt32Array()) as PackedInt32Array)
	if advancedTickCount <= 0:
		return {"ok": true, "advancedTickCount": 0, "ticksPerSecond": 0.0}
	var elapsedUsec := maxi(1, Time.get_ticks_usec() - startedUsec)
	return {
		"ok": true,
		"advancedTickCount": advancedTickCount,
		"ticksPerSecond": float(advancedTickCount) * 1_000_000.0 / float(elapsedUsec),
	}

func getSimulationWorkBudgetUsec(delta: float) -> int:
	var frameDuration := maxf(delta, 0.001)
	return maxi(1, floori(frameDuration * 1_000_000.0 * SimulationFrameWorkShare))

func getSimulationBatchTickCount() -> int:
	var capacityTickCount := floori(LoopFrequencyMaximumTps * float(SimulationBatchTargetDurationUsec) / 1_000_000.0)
	return clampi(capacityTickCount, 1, SimulationBatchTickCountMaximum)

func showSimulationTick(targetTick: int) -> bool:
	if IsLooping or targetTick < getSimulationTimelineFirstTick() or SimulationTimeline.is_empty():
		return false
	if targetTick <= getSimulationTimelineLastTick():
		return applySimulationSnapshot(targetTick)
	return buildSimulationTimelineTo(targetTick)

func buildSimulationTimelineTo(targetTick: int) -> bool:
	if IsLooping:
		return false
	var lastTick := getSimulationTimelineLastTick()
	if lastTick < 0:
		return false
	if not applySimulationSnapshot(lastTick):
		return false
	while lastTick < targetTick:
		var advanceResult := SimulationBridgeInstance.advanceTick()
		if not bool(advanceResult.get("ok", false)):
			failActiveSimulation(advanceResult)
			return false
		applySimulationStateChanges(advanceResult.get("changes", PackedInt32Array()) as PackedInt32Array)
		var snapshotResult := SimulationBridgeInstance.captureState()
		if not bool(snapshotResult.get("ok", false)):
			failActiveSimulation(snapshotResult)
			return false
		lastTick += 1
		appendSimulationSnapshot(snapshotResult.get("snapshot", PackedByteArray()) as PackedByteArray)
	SimulationTick = targetTick
	return true

func captureSimulationSnapshot() -> Dictionary:
	return SimulationBridgeInstance.captureState()

func applySimulationSnapshot(snapshotTick: int) -> bool:
	var snapshotIndex := getSimulationTimelineIndex(snapshotTick)
	if snapshotIndex < 0:
		return false
	var snapshotVariant: Variant = SimulationTimeline[snapshotIndex]
	if not (snapshotVariant is PackedByteArray):
		failActiveSimulation({"ok": false, "errorReason": "SimulationSnapshotInvalid"})
		return false
	var restoreResult := SimulationBridgeInstance.restoreState(snapshotVariant as PackedByteArray)
	if not bool(restoreResult.get("ok", false)):
		failActiveSimulation(restoreResult)
		return false
	applySimulationStateChanges(restoreResult.get("changes", PackedInt32Array()) as PackedInt32Array)
	SimulationTick = snapshotTick
	return true

func clearSimulationTimeline() -> void:
	SimulationTimeline.clear()
	SimulationTimelineStartTick = 0
	SimulationTimelineBytes = 0

func appendSimulationSnapshot(snapshot: PackedByteArray) -> void:
	SimulationTimeline.append(snapshot)
	SimulationTimelineBytes += snapshot.size()
	enforceSimulationTimelineBudget()

func replaceSimulationSnapshot(snapshotTick: int, snapshot: PackedByteArray) -> bool:
	var snapshotIndex := getSimulationTimelineIndex(snapshotTick)
	if snapshotIndex < 0:
		return false
	SimulationTimelineBytes = maxi(0, SimulationTimelineBytes - getSimulationSnapshotByteCount(SimulationTimeline[snapshotIndex]))
	SimulationTimeline[snapshotIndex] = snapshot
	SimulationTimelineBytes += snapshot.size()
	enforceSimulationTimelineBudget()
	return true

func truncateSimulationTimelineAfter(snapshotTick: int) -> bool:
	var snapshotIndex := getSimulationTimelineIndex(snapshotTick)
	if snapshotIndex < 0:
		return false
	while SimulationTimeline.size() > snapshotIndex + 1:
		SimulationTimelineBytes = maxi(0, SimulationTimelineBytes - getSimulationSnapshotByteCount(SimulationTimeline.pop_back()))
	return true

func enforceSimulationTimelineBudget() -> void:
	var entryMaximum := maxi(1, SimulationTimelineEntryMaximum)
	var byteMaximum := maxi(0, SimulationTimelineMaximumBytes)
	while SimulationTimeline.size() > entryMaximum or (SimulationTimelineBytes > byteMaximum and SimulationTimeline.size() > 1):
		SimulationTimelineBytes = maxi(0, SimulationTimelineBytes - getSimulationSnapshotByteCount(SimulationTimeline.pop_front()))
		SimulationTimelineStartTick += 1

func getSimulationTimelineFirstTick() -> int:
	return SimulationTimelineStartTick

func getSimulationTimelineLastTick() -> int:
	if SimulationTimeline.is_empty():
		return -1
	return SimulationTimelineStartTick + SimulationTimeline.size() - 1

func getSimulationTimelineIndex(snapshotTick: int) -> int:
	if snapshotTick < SimulationTimelineStartTick or snapshotTick > getSimulationTimelineLastTick():
		return -1
	return snapshotTick - SimulationTimelineStartTick

func getSimulationSnapshotByteCount(snapshotVariant: Variant) -> int:
	return (snapshotVariant as PackedByteArray).size() if snapshotVariant is PackedByteArray else 0

func applySimulationStates(states: Variant) -> void:
	if not (states is PackedInt32Array or states is PackedByteArray) or states.is_empty() or not Board.has_method("applyRuntimeTileStatesFromGrid"):
		return
	Board.call("applyRuntimeTileStatesFromGrid", states, SimulationBridgeInstance.GridWidth, SimulationBridgeInstance.GridOrigin)

func applySimulationStateChanges(changes: PackedInt32Array) -> void:
	if changes.is_empty() or not Board.has_method("applyRuntimeTileStateChanges"):
		return
	Board.call("applyRuntimeTileStateChanges", changes, SimulationBridgeInstance.GridWidth, SimulationBridgeInstance.GridOrigin)

func clearSimulationRuntimeStates() -> void:
	if Board.has_method("clearRuntimeTileStates"):
		Board.call("clearRuntimeTileStates")

func setCircuitEditorInputEnabled(isEnabled: bool) -> void:
	for dock in getActiveDocks():
		if dock.has_method("setInkInputEnabled"):
			dock.call("setInkInputEnabled", isEnabled)

func abortSimulationStart(result: Dictionary) -> void:
	clearSimulationRuntimeStates()
	SimulationBridgeInstance.release()
	Board.call("setEditorInputEnabled", true)
	setCircuitEditorInputEnabled(true)
	recordEvent(getSimulationFailureText(result))
	refreshSimulationControls()

func failActiveSimulation(result: Dictionary) -> void:
	recordEvent(getSimulationFailureText(result))
	leaveSimulation()

func getSimulationFailureText(result: Dictionary) -> String:
	var reason := String(result.get("errorReason", "SimulationFailed"))
	var errorX := int(result.get("errorX", -1))
	var errorY := int(result.get("errorY", -1))
	if bool(result.get("hasCoordinates", false)):
		return "Simulation error at (%d, %d): %s" % [errorX, errorY, reason]
	return "Simulation error: %s" % reason

func setLoopFrequency(requestedFrequency: float) -> void:
	LoopFrequency = clampf(requestedFrequency, SimulationFrequencyMinimumTps, LoopFrequencyMaximumTps)
	IsLoopFrequencyFullSpeed = is_equal_approx(LoopFrequency, LoopFrequencyMaximumTps)
	LoopFrequencySlider.set_value_no_signal(getLoopFrequencySliderValue())
	LoopFrequencyInput.text = getLoopFrequencyText()
	resetSimulationThroughput()
	if IsSimulating:
		refreshSimulationControls()

func setLoopFrequencyFromSlider(requestedValue: float) -> void:
	var sliderValue := clampf(requestedValue, 0.0, LoopFrequencyMaximumTps)
	var normalizedSliderValue := sliderValue / LoopFrequencyMaximumTps
	var maximumLogarithm := getBase10Logarithm(LoopFrequencyMaximumTps)
	LoopFrequency = pow(10.0, maximumLogarithm * normalizedSliderValue)
	IsLoopFrequencyFullSpeed = is_equal_approx(sliderValue, LoopFrequencyMaximumTps)
	LoopFrequencySlider.set_value_no_signal(sliderValue)
	LoopFrequencyInput.text = getLoopFrequencyText()
	resetSimulationThroughput()
	if IsSimulating:
		refreshSimulationControls()

func getLoopFrequencySliderValue() -> float:
	if LoopFrequencyMaximumTps <= SimulationFrequencyMinimumTps:
		return 0.0
	var maximumLogarithm := getBase10Logarithm(LoopFrequencyMaximumTps)
	if maximumLogarithm <= 0.0:
		return 0.0
	var normalizedSliderValue := getBase10Logarithm(LoopFrequency) / maximumLogarithm
	return clampf(normalizedSliderValue, 0.0, 1.0) * LoopFrequencyMaximumTps

func getBase10Logarithm(value: float) -> float:
	return log(maxf(SimulationFrequencyMinimumTps, value)) / log(10.0)

func updateLoopFrequencyMaximum(measuredTicksPerSecond: float) -> void:
	if measuredTicksPerSecond <= 0.0:
		return
	var measuredMaximum := maxf(SimulationFrequencyMinimumTps, measuredTicksPerSecond)
	var nextMaximum := measuredMaximum
	if LoopFrequencyMaximumTps > SimulationFrequencyMinimumTps and measuredMaximum > LoopFrequencyMaximumTps:
		nextMaximum = lerpf(LoopFrequencyMaximumTps, measuredMaximum, SimulationCapacityRiseSmoothing)
	setLoopFrequencyMaximumTps(nextMaximum)

func setLoopFrequencyMaximumTps(requestedMaximum: float) -> void:
	var nextMaximum := maxf(SimulationFrequencyMinimumTps, requestedMaximum)
	if is_equal_approx(nextMaximum, LoopFrequencyMaximumTps):
		return
	LoopFrequencyMaximumTps = nextMaximum
	LoopFrequencySlider.set_block_signals(true)
	LoopFrequencySlider.max_value = LoopFrequencyMaximumTps
	var didClampFrequency := false
	if IsLoopFrequencyFullSpeed:
		LoopFrequency = LoopFrequencyMaximumTps
	elif LoopFrequency > LoopFrequencyMaximumTps:
		LoopFrequency = LoopFrequencyMaximumTps
		IsLoopFrequencyFullSpeed = true
		didClampFrequency = true
	LoopFrequencySlider.set_value_no_signal(getLoopFrequencySliderValue())
	LoopFrequencySlider.set_block_signals(false)
	if not IsEditingLoopFrequency:
		LoopFrequencyInput.text = getLoopFrequencyText()
	if didClampFrequency:
		resetSimulationThroughput()

func getLoopFrequencyMaximumTps() -> float:
	return LoopFrequencyMaximumTps

func getLoopFrequencyText() -> String:
	return "%.3f" % LoopFrequency

func handleLoopFrequencySliderInput(event: InputEvent) -> void:
	if not IsSimulating or not IsLooping:
		return
	var mouseButton := event as InputEventMouseButton
	if mouseButton == null or mouseButton.button_index != MOUSE_BUTTON_RIGHT or not mouseButton.pressed:
		return
	IsEditingLoopFrequency = true
	LoopFrequencyInput.text = getLoopFrequencyText()
	refreshSimulationControls()
	LoopFrequencyInput.grab_focus()
	LoopFrequencyInput.select_all()
	get_viewport().set_input_as_handled()

func handleLoopFrequencyInput(event: InputEvent) -> void:
	if not IsEditingLoopFrequency:
		return
	var mouseButton := event as InputEventMouseButton
	if mouseButton == null or mouseButton.button_index != MOUSE_BUTTON_RIGHT or not mouseButton.pressed:
		return
	commitLoopFrequencyInput()
	IsEditingLoopFrequency = false
	refreshSimulationControls()
	get_viewport().set_input_as_handled()

func submitLoopFrequencyInput(_submittedText: String) -> void:
	commitLoopFrequencyInput()

func commitLoopFrequencyInput() -> void:
	var frequencyText := LoopFrequencyInput.text.strip_edges()
	if frequencyText.is_empty() or not frequencyText.is_valid_float():
		LoopFrequencyInput.text = getLoopFrequencyText()
		return
	setLoopFrequency(frequencyText.to_float())

func resetSimulationThroughput() -> void:
	SimulationTicksPerSecond = LoopFrequency
	SimulationThroughputSampleStartUsec = Time.get_ticks_usec()
	SimulationThroughputSampleTicks = 0

func recordSimulationThroughput(advancedTickCount: int) -> bool:
	if advancedTickCount <= 0:
		return false
	var nowUsec := Time.get_ticks_usec()
	if SimulationThroughputSampleStartUsec <= 0:
		SimulationThroughputSampleStartUsec = nowUsec
	SimulationThroughputSampleTicks += advancedTickCount
	var elapsedUsec := nowUsec - SimulationThroughputSampleStartUsec
	if elapsedUsec <= 0:
		return false
	if elapsedUsec < SimulationThroughputSampleIntervalUsec:
		return false
	SimulationTicksPerSecond = float(SimulationThroughputSampleTicks) * 1_000_000.0 / float(elapsedUsec)
	SimulationThroughputSampleStartUsec = nowUsec
	SimulationThroughputSampleTicks = 0
	return true

func getSimulationThroughputText() -> String:
	var ticksPerSecond := maxf(0.0, SimulationTicksPerSecond)
	if ticksPerSecond >= 999_950.0:
		return "%.1fM TPS" % (ticksPerSecond / 1_000_000.0)
	if ticksPerSecond >= 999.95:
		return "%.1fK TPS" % (ticksPerSecond / 1_000.0)
	return "%.1f TPS" % ticksPerSecond

func handleStepLengthInput(event: InputEvent) -> void:
	if StepLengthControl.disabled:
		return
	var mouseButton := event as InputEventMouseButton
	if mouseButton and mouseButton.button_index == MOUSE_BUTTON_LEFT:
		IsDraggingStepLength = mouseButton.pressed
		StepLengthDragRemainder = 0.0
		get_viewport().set_input_as_handled()
		return
	var mouseMotion := event as InputEventMouseMotion
	if mouseMotion and IsDraggingStepLength:
		StepLengthDragRemainder += mouseMotion.relative.x
		var adjustment := 0
		if StepLengthDragRemainder >= SimulationDragPixelsPerStep:
			adjustment = floori(StepLengthDragRemainder / SimulationDragPixelsPerStep)
		elif StepLengthDragRemainder <= -SimulationDragPixelsPerStep:
			adjustment = ceili(StepLengthDragRemainder / SimulationDragPixelsPerStep)
		if adjustment != 0:
			setSimulationStepLength(SimulationStepLength + adjustment)
			StepLengthDragRemainder -= float(adjustment) * SimulationDragPixelsPerStep
		get_viewport().set_input_as_handled()

func setSimulationStepLength(requestedStepLength: int) -> void:
	SimulationStepLength = clampi(requestedStepLength, SimulationStepLengthMinimum, SimulationStepLengthMaximum)
	StepLengthControl.text = str(SimulationStepLength)

func refreshSimulationControls() -> void:
	var canEditStepLength := IsSimulating and not IsLooping
	var canEditLoopFrequency := IsSimulating and IsLooping
	if not canEditLoopFrequency:
		IsEditingLoopFrequency = false
	SimulationModeButton.text = "Edit" if IsSimulating else "Simulate"
	SimulationModeButton.tooltip_text = "Exit simulation" if IsSimulating else "Enter simulation"
	configureSimulationModeButton()
	PreviousTickButton.disabled = not IsSimulating or IsLooping or SimulationTick <= getSimulationTimelineFirstTick()
	LoopStepButton.disabled = not IsSimulating
	NextTickButton.disabled = not IsSimulating or IsLooping
	StepLengthControl.disabled = not canEditStepLength
	LoopFrequencySlider.visible = not IsEditingLoopFrequency
	LoopFrequencyInput.visible = IsEditingLoopFrequency
	LoopFrequencySlider.mouse_filter = Control.MOUSE_FILTER_STOP if canEditLoopFrequency else Control.MOUSE_FILTER_IGNORE
	LoopFrequencySlider.focus_mode = Control.FOCUS_ALL if canEditLoopFrequency else Control.FOCUS_NONE
	LoopFrequencySlider.modulate = Color.WHITE if canEditLoopFrequency else Color(1.0, 1.0, 1.0, 0.38)
	LoopFrequencyInput.mouse_filter = Control.MOUSE_FILTER_STOP if canEditLoopFrequency else Control.MOUSE_FILTER_IGNORE
	LoopFrequencyInput.focus_mode = Control.FOCUS_ALL if canEditLoopFrequency else Control.FOCUS_NONE
	LoopFrequencyInput.editable = canEditLoopFrequency
	LoopFrequencyInput.modulate = Color.WHITE if canEditLoopFrequency else Color(1.0, 1.0, 1.0, 0.38)
	LoopStepButton.tooltip_text = "Switch to step mode" if IsLooping else "Switch to loop mode"
	LoopStepButton.add_theme_color_override("icon_normal_color", Color("e2eaf7") if IsLooping else SimulationStepColor)
	LoopStepButton.add_theme_color_override("icon_hover_color", Color.WHITE if IsLooping else Color("ffd878"))
	refreshSimulationStatus()
	setSimulationStepLength(SimulationStepLength)

func refreshSimulationStatus() -> void:
	SimulationStatus.visible = IsSimulating
	if not IsSimulating:
		return
	SimulationStatus.text = getSimulationThroughputText() if IsLooping else "Step Mode"

func setLeftSidebarOpen(isOpen: bool, animate := true) -> void:
	LeftSidebarOpen = isOpen
	LeftSidebarToggle.set_pressed_no_signal(isOpen)
	updateSidebarLayout(animate)

func setRightSidebarOpen(isOpen: bool, animate := true) -> void:
	RightSidebarOpen = isOpen
	RightSidebarToggle.set_pressed_no_signal(isOpen)
	updateSidebarLayout(animate)

func setDockWidth(requestedWidth: float) -> void:
	DockWidth = clampDockWidth(requestedWidth)
	updateSidebarLayout(false)

func setRightDockWidth(requestedWidth: float) -> void:
	RightDockWidth = clampDockWidth(requestedWidth)
	updateSidebarLayout(false)

func clampDockWidth(requestedWidth: float) -> float:
	var maximumWidth := maxf(208.0, minf(480.0, size.x * 0.5))
	return clampf(requestedWidth, 208.0, maximumWidth)

func updateSidebarLayout(animate: bool) -> void:
	LeftSidebarToggle.icon = PanelLeftCloseIcon if LeftSidebarOpen else PanelLeftOpenIcon
	RightSidebarToggle.icon = PanelRightCloseIcon if RightSidebarOpen else PanelRightOpenIcon
	LeftSidebarToggle.tooltip_text = "CloseLeftSidebar" if LeftSidebarOpen else "OpenLeftSidebar"
	RightSidebarToggle.tooltip_text = "CloseRightSidebar" if RightSidebarOpen else "OpenRightSidebar"
	var leftStart := 0.0 if LeftSidebarOpen else -DockWidth
	var leftEnd := DockWidth if LeftSidebarOpen else 0.0
	var rightStart := -RightDockWidth if RightSidebarOpen else 0.0
	var rightEnd := 0.0 if RightSidebarOpen else RightDockWidth
	var resizeStart := DockWidth if LeftSidebarOpen else -6.0
	var resizeEnd := DockWidth + 6.0 if LeftSidebarOpen else 0.0
	var rightResizeStart := -RightDockWidth - 6.0 if RightSidebarOpen else 0.0
	var rightResizeEnd := -RightDockWidth if RightSidebarOpen else 6.0
	if LeftSidebarTween:
		LeftSidebarTween.kill()
	if RightSidebarTween:
		RightSidebarTween.kill()
	if not animate:
		DockHost.offset_left = leftStart
		DockHost.offset_right = leftEnd
		RightDockHost.offset_left = rightStart
		RightDockHost.offset_right = rightEnd
		DockResizeHandle.offset_left = resizeStart
		DockResizeHandle.offset_right = resizeEnd
		DockResizeHandle.visible = LeftSidebarOpen
		RightDockResizeHandle.offset_left = rightResizeStart
		RightDockResizeHandle.offset_right = rightResizeEnd
		RightDockResizeHandle.visible = RightSidebarOpen
		return
	DockHost.visible = true
	RightDockHost.visible = true
	DockResizeHandle.visible = true
	RightDockResizeHandle.visible = true
	LeftSidebarTween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	LeftSidebarTween.tween_property(DockHost, "offset_left", leftStart, SidebarAnimationDuration)
	LeftSidebarTween.parallel().tween_property(DockHost, "offset_right", leftEnd, SidebarAnimationDuration)
	LeftSidebarTween.parallel().tween_property(DockResizeHandle, "offset_left", resizeStart, SidebarAnimationDuration)
	LeftSidebarTween.parallel().tween_property(DockResizeHandle, "offset_right", resizeEnd, SidebarAnimationDuration)
	LeftSidebarTween.chain().tween_callback(finishLeftSidebarTransition.bind(LeftSidebarOpen))
	RightSidebarTween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	RightSidebarTween.tween_property(RightDockHost, "offset_left", rightStart, SidebarAnimationDuration)
	RightSidebarTween.parallel().tween_property(RightDockHost, "offset_right", rightEnd, SidebarAnimationDuration)
	RightSidebarTween.parallel().tween_property(RightDockResizeHandle, "offset_left", rightResizeStart, SidebarAnimationDuration)
	RightSidebarTween.parallel().tween_property(RightDockResizeHandle, "offset_right", rightResizeEnd, SidebarAnimationDuration)
	RightSidebarTween.chain().tween_callback(finishRightSidebarTransition.bind(RightSidebarOpen))

func finishLeftSidebarTransition(isOpen: bool) -> void:
	if LeftSidebarOpen == isOpen:
		DockResizeHandle.visible = isOpen

func finishRightSidebarTransition(isOpen: bool) -> void:
	if RightSidebarOpen == isOpen:
		RightDockResizeHandle.visible = isOpen

func handleDockResizeInput(event: InputEvent) -> void:
	var mouseButton := event as InputEventMouseButton
	if mouseButton and mouseButton.button_index == MOUSE_BUTTON_LEFT:
		IsResizingDock = mouseButton.pressed
		DockResizeHandle.color = Color("7589aa") if IsResizingDock else Color("5d7090")
		get_viewport().set_input_as_handled()
		return
	var mouseMotion := event as InputEventMouseMotion
	if mouseMotion and IsResizingDock:
		setDockWidth(get_global_mouse_position().x)
		get_viewport().set_input_as_handled()

func handleRightDockResizeInput(event: InputEvent) -> void:
	var mouseButton := event as InputEventMouseButton
	if mouseButton and mouseButton.button_index == MOUSE_BUTTON_LEFT:
		IsResizingRightDock = mouseButton.pressed
		RightDockResizeHandle.color = Color("7589aa") if IsResizingRightDock else Color("5d7090")
		get_viewport().set_input_as_handled()
		return
	var mouseMotion := event as InputEventMouseMotion
	if mouseMotion and IsResizingRightDock:
		setRightDockWidth(size.x - get_global_mouse_position().x)
		get_viewport().set_input_as_handled()

func syncDockLayout() -> void:
	DockWidth = clampDockWidth(DockWidth)
	RightDockWidth = clampDockWidth(RightDockWidth)
	updateSidebarLayout(false)

func configureTopBar() -> void:
	var topBarBox := StyleBoxFlat.new()
	topBarBox.bg_color = Color("121924")
	topBarBox.border_width_bottom = 1
	topBarBox.border_color = TopBarSeparatorColor
	TopBar.add_theme_stylebox_override("panel", topBarBox)
	NewProjectButton.icon = FilePlusIcon
	OpenProjectButton.icon = FolderOpenIcon
	SaveProjectButton.icon = SaveIcon
	SaveAsProjectButton.icon = FilePenLineIcon
	RecentProjectsButton.icon = HistoryIcon
	PreviousTickButton.icon = SkipBackIcon
	LoopStepButton.icon = PauseIcon
	NextTickButton.icon = SkipForwardIcon
	NewProjectButton.tooltip_text = "New .ocb project"
	OpenProjectButton.tooltip_text = "Open .ocb project"
	SaveProjectButton.tooltip_text = "Save .ocb project"
	SaveAsProjectButton.tooltip_text = "Save .ocb project as"
	RecentProjectsButton.tooltip_text = "Recent projects"
	PreviousTickButton.tooltip_text = "Previous tick"
	NextTickButton.tooltip_text = "Next tick"
	StepLengthControl.tooltip_text = "Drag to change step length"
	LoopFrequencySlider.tooltip_text = "Drag to change loop frequency"
	LoopFrequencyInput.tooltip_text = "Enter loop frequency in TPS"
	for child in ProjectContent.get_children():
		var projectButton := child as Button
		if projectButton:
			configureTopBarButton(projectButton)
	for child in $Interface/TopBar/Content.get_children():
		var topBarButton := child as Button
		if topBarButton and topBarButton != SimulationModeButton and topBarButton != StepLengthControl:
			configureTopBarButton(topBarButton)
	($Interface/TopBar/RowSeparator as ColorRect).color = TopBarSeparatorColor
	($Interface/TopBar/Content/SidebarSeparator as ColorRect).color = TopBarSeparatorColor
	($Interface/TopBar/Content/RightSidebarSeparator as ColorRect).color = TopBarSeparatorColor
	ProjectTitle.add_theme_font_size_override("font_size", 14)
	ProjectTitle.add_theme_color_override("font_color", Color("b4c1d3"))
	refreshProjectTitle()
	configureStepLengthControl()
	configureLoopFrequencySlider()
	configureLoopFrequencyInput()
	SimulationStatus.add_theme_font_size_override("font_size", TopBarFontSize)
	SimulationStatus.add_theme_color_override("font_color", Color("7f8ca2"))
	refreshSimulationControls()
	DockResizeHandle.color = TopBarSeparatorColor
	DockResizeHandle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	RightDockResizeHandle.color = TopBarSeparatorColor
	RightDockResizeHandle.mouse_default_cursor_shape = Control.CURSOR_HSIZE

func configureTopBarButton(topBarButton: Button) -> void:
	topBarButton.expand_icon = false
	topBarButton.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topBarButton.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	topBarButton.add_theme_color_override("icon_normal_color", Color("8d9db5"))
	topBarButton.add_theme_color_override("icon_hover_color", Color("e1e9f6"))
	topBarButton.add_theme_color_override("icon_pressed_color", TopBarButtonActiveIconColor)
	topBarButton.add_theme_color_override("icon_hover_pressed_color", TopBarButtonActiveIconColor)
	topBarButton.add_theme_color_override("icon_disabled_color", Color("334155"))
	topBarButton.add_theme_stylebox_override("normal", makeMenuItemBox(Color.TRANSPARENT))
	topBarButton.add_theme_stylebox_override("hover", makeMenuItemBox(Color("2b374a")))
	topBarButton.add_theme_stylebox_override("pressed", makeMenuItemBox(Color.TRANSPARENT))
	topBarButton.add_theme_stylebox_override("hover_pressed", makeMenuItemBox(Color("2b374a")))

func configureSimulationModeButton() -> void:
	var normalColor := SimulationEditColor if IsSimulating else SimulationStartColor
	var hoverColor := SimulationEditHoverColor if IsSimulating else SimulationStartHoverColor
	SimulationModeButton.add_theme_font_size_override("font_size", TopBarFontSize)
	SimulationModeButton.add_theme_color_override("font_color", Color.WHITE)
	SimulationModeButton.add_theme_color_override("font_hover_color", Color.WHITE)
	SimulationModeButton.add_theme_color_override("font_pressed_color", Color.WHITE)
	SimulationModeButton.add_theme_stylebox_override("normal", makeCommandBox(normalColor))
	SimulationModeButton.add_theme_stylebox_override("hover", makeCommandBox(hoverColor))
	SimulationModeButton.add_theme_stylebox_override("pressed", makeCommandBox(normalColor.darkened(0.1)))
	SimulationModeButton.add_theme_stylebox_override("hover_pressed", makeCommandBox(hoverColor.darkened(0.08)))

func configureStepLengthControl() -> void:
	configureTickCountControl(StepLengthControl)

func configureClockHoldTicksControl() -> void:
	if ClockHoldTicksControl:
		ClockHoldTicksControl.add_theme_icon_override("updown", makeSolidTexture(Vector2i(1, 1), Color.TRANSPARENT))
		var lineEdit := ClockHoldTicksControl.get_line_edit()
		lineEdit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		lineEdit.add_theme_font_size_override("font_size", TopBarFontSize)
		lineEdit.add_theme_color_override("font_color", Color("9aa8bf"))
		lineEdit.add_theme_color_override("font_selected_color", Color.WHITE)
		lineEdit.add_theme_stylebox_override("normal", makeStepLengthBox(Color("2a3548")))
		lineEdit.add_theme_stylebox_override("focus", makeStepLengthBox(Color("35435a")))
		lineEdit.add_theme_stylebox_override("read_only", makeStepLengthBox(Color("202a38")))

func configureTickCountControl(control: Button) -> void:
	control.alignment = HORIZONTAL_ALIGNMENT_CENTER
	control.add_theme_font_size_override("font_size", TopBarFontSize)
	control.add_theme_color_override("font_color", Color("9aa8bf"))
	control.add_theme_color_override("font_hover_color", Color("e1e9f6"))
	control.add_theme_color_override("font_pressed_color", Color("f2c94c"))
	control.add_theme_color_override("font_disabled_color", Color("46546b"))
	control.add_theme_stylebox_override("normal", makeStepLengthBox(Color("2a3548")))
	control.add_theme_stylebox_override("hover", makeStepLengthBox(Color("35435a")))
	control.add_theme_stylebox_override("pressed", makeStepLengthBox(Color("202b3b")))
	control.add_theme_stylebox_override("disabled", makeStepLengthBox(Color("202a38")))
	control.mouse_default_cursor_shape = Control.CURSOR_HSIZE

func configureLoopFrequencySlider() -> void:
	var sliderBox := StyleBoxFlat.new()
	sliderBox.bg_color = Color("2b3749")
	sliderBox.corner_radius_top_left = 1
	sliderBox.corner_radius_top_right = 1
	sliderBox.corner_radius_bottom_left = 1
	sliderBox.corner_radius_bottom_right = 1
	sliderBox.content_margin_top = 10
	sliderBox.content_margin_bottom = 10
	LoopFrequencySlider.add_theme_stylebox_override("slider", sliderBox)
	LoopFrequencySlider.add_theme_icon_override("grabber", makeSolidTexture(Vector2i(6, 16), Color("f4f6fa")))
	LoopFrequencySlider.add_theme_icon_override("grabber_highlight", makeSolidTexture(Vector2i(6, 16), Color.WHITE))
	LoopFrequencySlider.add_theme_icon_override("grabber_disabled", makeSolidTexture(Vector2i(6, 16), Color("7d899e")))

func configureLoopFrequencyInput() -> void:
	LoopFrequencyInput.alignment = HORIZONTAL_ALIGNMENT_CENTER
	LoopFrequencyInput.context_menu_enabled = false
	LoopFrequencyInput.select_all_on_focus = true
	LoopFrequencyInput.add_theme_font_size_override("font_size", TopBarFontSize)
	LoopFrequencyInput.add_theme_color_override("font_color", Color("d8e1ef"))
	LoopFrequencyInput.add_theme_color_override("font_selected_color", Color.WHITE)
	LoopFrequencyInput.add_theme_color_override("caret_color", Color("f4f6fa"))
	LoopFrequencyInput.add_theme_stylebox_override("normal", makeStepLengthBox(Color("2a3548")))
	LoopFrequencyInput.add_theme_stylebox_override("focus", makeStepLengthBox(Color("35435a")))
	LoopFrequencyInput.add_theme_stylebox_override("read_only", makeStepLengthBox(Color("202a38")))

func makeCommandBox(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_left = 4
	box.corner_radius_bottom_right = 4
	return box

func makeStepLengthBox(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 3
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 3
	return box

func makeSolidTexture(textureSize: Vector2i, color: Color) -> ImageTexture:
	var image := Image.create(textureSize.x, textureSize.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func makeProjectDialogTheme() -> Theme:
	var dialogTheme := Theme.new()
	dialogTheme.set_stylebox("panel", "FileDialog", makeDialogBox(DialogBackgroundColor, DialogBorderColor, 6, 10))
	dialogTheme.set_stylebox("panel", "AcceptDialog", makeDialogBox(DialogBackgroundColor, DialogBorderColor, 6, 10))
	dialogTheme.set_stylebox("panel", "Panel", makeDialogBox(DialogBackgroundColor, DialogBorderColor, 4, 6))
	dialogTheme.set_stylebox("normal", "Button", makeDialogBox(DialogSurfaceColor, DialogBorderColor, 3, 6))
	dialogTheme.set_stylebox("hover", "Button", makeDialogBox(DialogHoverColor, DialogBorderColor, 3, 6))
	dialogTheme.set_stylebox("pressed", "Button", makeDialogBox(DialogInputColor, DialogBorderColor, 3, 6))
	dialogTheme.set_stylebox("hover_pressed", "Button", makeDialogBox(DialogHoverColor, DialogBorderColor, 3, 6))
	dialogTheme.set_stylebox("disabled", "Button", makeDialogBox(DialogInputColor, DialogBorderColor.darkened(0.25), 3, 6))
	dialogTheme.set_color("font_color", "Button", DialogTextColor)
	dialogTheme.set_color("font_hover_color", "Button", Color.WHITE)
	dialogTheme.set_color("font_pressed_color", "Button", DialogTextColor)
	dialogTheme.set_color("font_disabled_color", "Button", DialogMutedTextColor.darkened(0.25))
	dialogTheme.set_stylebox("normal", "LineEdit", makeDialogBox(DialogInputColor, DialogBorderColor, 3, 6))
	dialogTheme.set_stylebox("read_only", "LineEdit", makeDialogBox(DialogInputColor, DialogBorderColor, 3, 6))
	dialogTheme.set_stylebox("focus", "LineEdit", makeDialogBox(DialogInputColor, DialogActionColor, 3, 6))
	dialogTheme.set_color("font_color", "LineEdit", DialogTextColor)
	dialogTheme.set_color("font_uneditable_color", "LineEdit", DialogMutedTextColor)
	dialogTheme.set_stylebox("panel", "Tree", makeDialogBox(DialogInputColor, DialogBorderColor, 3, 4))
	dialogTheme.set_stylebox("selected", "Tree", makeDialogBox(DialogSelectionColor, DialogActionColor, 2, 2))
	dialogTheme.set_stylebox("selected_focus", "Tree", makeDialogBox(DialogSelectionColor, DialogActionColor, 2, 2))
	dialogTheme.set_color("font_color", "Tree", DialogTextColor)
	dialogTheme.set_color("font_selected_color", "Tree", Color.WHITE)
	dialogTheme.set_color("guide_color", "Tree", DialogBorderColor)
	dialogTheme.set_stylebox("panel", "ItemList", makeDialogBox(DialogInputColor, DialogBorderColor, 3, 4))
	dialogTheme.set_stylebox("selected", "ItemList", makeDialogBox(DialogSelectionColor, DialogActionColor, 2, 2))
	dialogTheme.set_color("font_color", "ItemList", DialogTextColor)
	dialogTheme.set_color("font_selected_color", "ItemList", Color.WHITE)
	dialogTheme.set_stylebox("normal", "OptionButton", makeDialogBox(DialogSurfaceColor, DialogBorderColor, 3, 6))
	dialogTheme.set_stylebox("hover", "OptionButton", makeDialogBox(DialogHoverColor, DialogBorderColor, 3, 6))
	dialogTheme.set_stylebox("pressed", "OptionButton", makeDialogBox(DialogInputColor, DialogBorderColor, 3, 6))
	dialogTheme.set_color("font_color", "OptionButton", DialogTextColor)
	dialogTheme.set_stylebox("panel", "PopupMenu", makeDialogBox(DialogSurfaceColor, DialogBorderColor, 4, 4))
	dialogTheme.set_color("font_color", "PopupMenu", DialogTextColor)
	dialogTheme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	dialogTheme.set_color("font_color", "Label", DialogTextColor)
	dialogTheme.set_color("default_color", "RichTextLabel", DialogTextColor)
	dialogTheme.set_color("title_color", "Window", DialogTextColor)
	dialogTheme.set_font_size("title_font_size", "Window", 15)
	dialogTheme.set_constant("title_height", "Window", 34)
	dialogTheme.set_stylebox("embedded_border", "Window", makeEmbeddedDialogWindowBox(DialogBorderColor))
	dialogTheme.set_stylebox("embedded_unfocused_border", "Window", makeEmbeddedDialogWindowBox(DialogBorderColor.darkened(0.25)))
	dialogTheme.set_color("folder_icon_color", "FileDialog", Color("8fb4e8"))
	dialogTheme.set_color("file_icon_color", "FileDialog", DialogMutedTextColor)
	dialogTheme.set_color("file_disabled_color", "FileDialog", DialogMutedTextColor.darkened(0.35))
	return dialogTheme

func makeDialogBox(backgroundColor: Color, borderColor: Color, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = backgroundColor
	box.border_width_left = 1
	box.border_width_top = 1
	box.border_width_right = 1
	box.border_width_bottom = 1
	box.border_color = borderColor
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = margin
	box.content_margin_top = margin
	box.content_margin_right = margin
	box.content_margin_bottom = margin
	return box

func makeEmbeddedDialogWindowBox(borderColor: Color) -> StyleBoxFlat:
	var box := makeDialogBox(DialogBackgroundColor, borderColor, 6, 0)
	box.expand_margin_left = 2
	box.expand_margin_top = 34
	box.expand_margin_right = 2
	box.expand_margin_bottom = 2
	return box

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
