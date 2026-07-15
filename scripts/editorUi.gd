extends Control

const DockRegistry := preload("res://scripts/dockRegistry.gd")
const InkRegistry := preload("res://scripts/inkRegistry.gd")
const InkButton := preload("res://scripts/inkButton.gd")
const ProjectManager := preload("res://scripts/projectManager.gd")
const filePlusIcon := preload("res://assets/filePlus.svg")
const folderOpenIcon := preload("res://assets/folderOpen.svg")
const saveIcon := preload("res://assets/save.svg")
const filePenLineIcon := preload("res://assets/filePenLine.svg")
const historyIcon := preload("res://assets/history.svg")
const panelLeftCloseIcon := preload("res://assets/panelLeftClose.svg")
const panelLeftOpenIcon := preload("res://assets/panelLeftOpen.svg")
const panelRightCloseIcon := preload("res://assets/panelRightClose.svg")
const panelRightOpenIcon := preload("res://assets/panelRightOpen.svg")
const skipBackIcon := preload("res://assets/skipBack.svg")
const skipForwardIcon := preload("res://assets/skipForward.svg")
const pauseIcon := preload("res://assets/pause.svg")
const sidebarAnimationDuration := 0.18
const topBarButtonActiveIconColor := Color("f2c94c")
const topBarFontSize := 16
const topBarSeparatorColor := Color("263346")
const simulationStartColor := Color("00c875")
const simulationStartHoverColor := Color("18dd8a")
const simulationEditColor := Color("ed3157")
const simulationEditHoverColor := Color("fa4268")
const simulationStepColor := Color("f3b941")
const simulationStepLengthMinimum := 1
const simulationStepLengthMaximum := 16
const simulationFrequencyMinimum := 1.0
const simulationFrequencyMaximum := 20.0
const simulationDragPixelsPerStep := 8.0
const simulationMaxCatchUpTicks := 8
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
@onready var projectContent: HBoxContainer = $Interface/TopBar/ProjectContent
@onready var newProjectButton: Button = $Interface/TopBar/ProjectContent/newProjectButton
@onready var openProjectButton: Button = $Interface/TopBar/ProjectContent/openProjectButton
@onready var saveProjectButton: Button = $Interface/TopBar/ProjectContent/saveProjectButton
@onready var saveAsProjectButton: Button = $Interface/TopBar/ProjectContent/saveAsProjectButton
@onready var recentProjectsButton: Button = $Interface/TopBar/ProjectContent/recentProjectsButton
@onready var leftSidebarToggle: Button = $Interface/TopBar/Content/leftSidebarToggle
@onready var rightSidebarToggle: Button = $Interface/TopBar/Content/rightSidebarToggle
@onready var simulationModeButton: Button = $Interface/TopBar/Content/simulationModeButton
@onready var previousTickButton: Button = $Interface/TopBar/Content/previousTickButton
@onready var loopStepButton: Button = $Interface/TopBar/Content/loopStepButton
@onready var nextTickButton: Button = $Interface/TopBar/Content/nextTickButton
@onready var stepLengthControl: Button = $Interface/TopBar/Content/stepLengthControl
@onready var loopFrequencySlider: HSlider = $Interface/TopBar/Content/loopFrequencySlider
@onready var simulationStatus: Label = $Interface/TopBar/Content/simulationStatus
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
var projectManager := ProjectManager.new()
var projectFileDialog: FileDialog
var projectNoticeDialog: AcceptDialog
var recentProjectsMenu: PopupPanel
var pendingProjectFileAction := ""
var isSimulating := false
var isLooping := true
var simulationTick := 0
var simulationTimeline: Array = []
var simulationAccumulator := 0.0
var simulationStepLength := simulationStepLengthMinimum
var loopFrequency := 5.0
var isDraggingStepLength := false
var stepLengthDragRemainder := 0.0

func _ready() -> void:
	Input.set_use_accumulated_input(false)
	configureTopBar()
	configureProjectDialogs()
	board.connect("clipboardChanged", updateClipboardHistory)
	board.connect("clipboardCopied", showClipboardDock)
	newProjectButton.pressed.connect(createNewProject)
	openProjectButton.pressed.connect(showOpenProjectDialog)
	saveProjectButton.pressed.connect(saveProject)
	saveAsProjectButton.pressed.connect(showSaveProjectDialog)
	recentProjectsButton.pressed.connect(showRecentProjectsMenu)
	leftSidebarToggle.toggled.connect(setLeftSidebarOpen)
	rightSidebarToggle.toggled.connect(setRightSidebarOpen)
	simulationModeButton.pressed.connect(toggleSimulationMode)
	previousTickButton.pressed.connect(showPreviousSimulationTick)
	loopStepButton.pressed.connect(toggleLoopStepMode)
	nextTickButton.pressed.connect(showNextSimulationTick)
	stepLengthControl.gui_input.connect(handleStepLengthInput)
	loopFrequencySlider.value_changed.connect(setLoopFrequency)
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
	updateSimulation(_delta)
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

func configureProjectDialogs() -> void:
	projectFileDialog = FileDialog.new()
	projectFileDialog.access = FileDialog.ACCESS_FILESYSTEM
	projectFileDialog.filters = PackedStringArray(["*.ocb ; OpenCircuitBoard Project"])
	projectFileDialog.file_selected.connect(handleProjectFileSelected)
	$Interface.add_child(projectFileDialog)
	projectNoticeDialog = AcceptDialog.new()
	projectNoticeDialog.title = "OpenCircuitBoard"
	$Interface.add_child(projectNoticeDialog)

func createNewProject() -> void:
	leaveSimulation()
	board.call("clearProjectData")
	projectManager.clearCurrentProject()
	recordEvent("Created new project")

func showOpenProjectDialog() -> void:
	pendingProjectFileAction = "open"
	projectFileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	projectFileDialog.current_file = ""
	projectFileDialog.popup_centered_ratio(0.72)

func saveProject() -> void:
	if not projectManager.hasCurrentProject():
		showSaveProjectDialog()
		return
	handleProjectResult(projectManager.saveProject(board), "Saved project")

func showSaveProjectDialog() -> void:
	pendingProjectFileAction = "save"
	projectFileDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	projectFileDialog.current_file = projectManager.currentProjectPath.get_file() if projectManager.hasCurrentProject() else "Untitled.ocb"
	projectFileDialog.popup_centered_ratio(0.72)

func handleProjectFileSelected(projectPath: String) -> void:
	var result := {}
	if pendingProjectFileAction == "open":
		leaveSimulation()
		result = projectManager.loadProject(board, projectPath)
		if bool(result.get("ok", false)):
			recordEvent("Opened project")
	elif pendingProjectFileAction == "save":
		result = projectManager.saveProjectAs(board, projectPath)
		if bool(result.get("ok", false)):
			recordEvent("Saved project")
	pendingProjectFileAction = ""
	if not bool(result.get("ok", false)):
		showProjectNotice(getProjectErrorText(String(result.get("message", "ProjectOperationFailed"))))

func showRecentProjectsMenu() -> void:
	if recentProjectsMenu:
		recentProjectsMenu.queue_free()
	recentProjectsMenu = PopupPanel.new()
	recentProjectsMenu.transparent_bg = true
	recentProjectsMenu.add_theme_stylebox_override("panel", makeMenuBox())
	$Interface.add_child(recentProjectsMenu)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	recentProjectsMenu.add_child(content)
	var recentProjectPaths := projectManager.getRecentProjectPaths()
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
	var anchorRect := recentProjectsButton.get_global_rect()
	var popupPosition := Vector2i(anchorRect.position + Vector2(0.0, anchorRect.size.y + 3.0))
	var viewportSize := get_viewport_rect().size
	popupPosition.x = clampi(popupPosition.x, 0, maxi(0, int(viewportSize.x) - menuSize.x))
	popupPosition.y = clampi(popupPosition.y, 0, maxi(0, int(viewportSize.y) - menuSize.y))
	recentProjectsMenu.popup(Rect2i(popupPosition, menuSize))

func openRecentProject(projectPath: String) -> void:
	leaveSimulation()
	var result := projectManager.loadProject(board, projectPath)
	if recentProjectsMenu:
		recentProjectsMenu.hide()
	if bool(result.get("ok", false)):
		recordEvent("Opened project")
		return
	showProjectNotice(getProjectErrorText(String(result.get("message", "ProjectOperationFailed"))))

func handleProjectResult(result: Dictionary, successText: String) -> void:
	if bool(result.get("ok", false)):
		recordEvent(successText)
		return
	showProjectNotice(getProjectErrorText(String(result.get("message", "ProjectOperationFailed"))))

func showProjectNotice(message: String) -> void:
	projectNoticeDialog.dialog_text = message
	projectNoticeDialog.popup_centered(Vector2i(360, 128))

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
	if isSimulating:
		leaveSimulation()
	else:
		enterSimulation()

func enterSimulation() -> void:
	if isSimulating:
		return
	board.call("cancelActiveInteraction")
	board.call("setEditorInputEnabled", false)
	isSimulating = true
	isLooping = true
	simulationTick = 0
	simulationTimeline = [captureSimulationSnapshot()]
	simulationAccumulator = 0.0
	refreshSimulationControls()

func leaveSimulation() -> void:
	if not isSimulating:
		return
	isSimulating = false
	isLooping = true
	simulationTick = 0
	simulationTimeline.clear()
	simulationAccumulator = 0.0
	board.call("setEditorInputEnabled", true)
	refreshSimulationControls()

func toggleLoopStepMode() -> void:
	if not isSimulating:
		return
	isLooping = not isLooping
	simulationAccumulator = 0.0
	refreshSimulationControls()

func showPreviousSimulationTick() -> void:
	if not isSimulating or isLooping or simulationTick <= 0:
		return
	simulationTick = maxi(0, simulationTick - simulationStepLength)
	applySimulationSnapshot(simulationTick)
	refreshSimulationControls()

func showNextSimulationTick() -> void:
	if not isSimulating or isLooping:
		return
	var targetTick := simulationTick + simulationStepLength
	while simulationTimeline.size() <= targetTick:
		advanceSimulationTimeline()
	simulationTick = targetTick
	applySimulationSnapshot(simulationTick)
	refreshSimulationControls()

func updateSimulation(delta: float) -> void:
	if not isSimulating or not isLooping:
		return
	simulationAccumulator += delta
	var tickPeriod := 1.0 / maxf(loopFrequency, simulationFrequencyMinimum)
	var advancedTickCount := 0
	while simulationAccumulator >= tickPeriod and advancedTickCount < simulationMaxCatchUpTicks:
		simulationAccumulator -= tickPeriod
		advanceSimulationTimeline()
		advancedTickCount += 1
	if advancedTickCount > 0:
		refreshSimulationControls()

func advanceSimulationTimeline() -> void:
	if simulationTick < simulationTimeline.size() - 1:
		simulationTick += 1
		applySimulationSnapshot(simulationTick)
		return
	simulationTimeline.append(captureSimulationSnapshot())
	simulationTick += 1

func captureSimulationSnapshot() -> Array:
	return (board.call("getSimulationTiles") as Array).duplicate(true)

func applySimulationSnapshot(snapshotIndex: int) -> void:
	if snapshotIndex < 0 or snapshotIndex >= simulationTimeline.size():
		return
	board.call("applyTileStates", simulationTimeline[snapshotIndex] as Array)

func setLoopFrequency(requestedFrequency: float) -> void:
	loopFrequency = clampf(roundf(requestedFrequency), simulationFrequencyMinimum, simulationFrequencyMaximum)
	loopFrequencySlider.set_value_no_signal(loopFrequency)
	if isSimulating:
		refreshSimulationControls()

func handleStepLengthInput(event: InputEvent) -> void:
	if stepLengthControl.disabled:
		return
	var mouseButton := event as InputEventMouseButton
	if mouseButton and mouseButton.button_index == MOUSE_BUTTON_LEFT:
		isDraggingStepLength = mouseButton.pressed
		stepLengthDragRemainder = 0.0
		get_viewport().set_input_as_handled()
		return
	var mouseMotion := event as InputEventMouseMotion
	if mouseMotion and isDraggingStepLength:
		stepLengthDragRemainder += mouseMotion.relative.x
		var adjustment := 0
		if stepLengthDragRemainder >= simulationDragPixelsPerStep:
			adjustment = floori(stepLengthDragRemainder / simulationDragPixelsPerStep)
		elif stepLengthDragRemainder <= -simulationDragPixelsPerStep:
			adjustment = ceili(stepLengthDragRemainder / simulationDragPixelsPerStep)
		if adjustment != 0:
			setSimulationStepLength(simulationStepLength + adjustment)
			stepLengthDragRemainder -= float(adjustment) * simulationDragPixelsPerStep
		get_viewport().set_input_as_handled()

func setSimulationStepLength(requestedStepLength: int) -> void:
	simulationStepLength = clampi(requestedStepLength, simulationStepLengthMinimum, simulationStepLengthMaximum)
	stepLengthControl.text = str(simulationStepLength)

func refreshSimulationControls() -> void:
	simulationModeButton.text = "Edit" if isSimulating else "Simulate"
	simulationModeButton.tooltip_text = "Exit simulation" if isSimulating else "Enter simulation"
	configureSimulationModeButton()
	previousTickButton.disabled = not isSimulating or isLooping or simulationTick <= 0
	loopStepButton.disabled = not isSimulating
	nextTickButton.disabled = not isSimulating or isLooping
	stepLengthControl.disabled = not isSimulating
	loopFrequencySlider.mouse_filter = Control.MOUSE_FILTER_STOP if isSimulating else Control.MOUSE_FILTER_IGNORE
	loopFrequencySlider.modulate = Color.WHITE if isSimulating else Color(1.0, 1.0, 1.0, 0.38)
	loopStepButton.tooltip_text = "Switch to step mode" if isLooping else "Switch to loop mode"
	loopStepButton.add_theme_color_override("icon_normal_color", Color("e2eaf7") if isLooping else simulationStepColor)
	loopStepButton.add_theme_color_override("icon_hover_color", Color.WHITE if isLooping else Color("ffd878"))
	simulationStatus.visible = isSimulating
	if isSimulating:
		simulationStatus.text = "~%d TPS" % roundi(loopFrequency) if isLooping else "Step Mode"
	setSimulationStepLength(simulationStepLength)

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
	topBarBox.border_color = topBarSeparatorColor
	topBar.add_theme_stylebox_override("panel", topBarBox)
	newProjectButton.icon = filePlusIcon
	openProjectButton.icon = folderOpenIcon
	saveProjectButton.icon = saveIcon
	saveAsProjectButton.icon = filePenLineIcon
	recentProjectsButton.icon = historyIcon
	previousTickButton.icon = skipBackIcon
	loopStepButton.icon = pauseIcon
	nextTickButton.icon = skipForwardIcon
	newProjectButton.tooltip_text = "New .ocb project"
	openProjectButton.tooltip_text = "Open .ocb project"
	saveProjectButton.tooltip_text = "Save .ocb project"
	saveAsProjectButton.tooltip_text = "Save .ocb project as"
	recentProjectsButton.tooltip_text = "Recent projects"
	previousTickButton.tooltip_text = "Previous tick"
	nextTickButton.tooltip_text = "Next tick"
	stepLengthControl.tooltip_text = "Drag to change step length"
	loopFrequencySlider.tooltip_text = "Drag to change loop frequency"
	for child in projectContent.get_children():
		var projectButton := child as Button
		if projectButton:
			configureTopBarButton(projectButton)
	for child in $Interface/TopBar/Content.get_children():
		var topBarButton := child as Button
		if topBarButton and topBarButton != simulationModeButton and topBarButton != stepLengthControl:
			configureTopBarButton(topBarButton)
	($Interface/TopBar/rowSeparator as ColorRect).color = topBarSeparatorColor
	($Interface/TopBar/Content/sidebarSeparator as ColorRect).color = topBarSeparatorColor
	configureStepLengthControl()
	configureLoopFrequencySlider()
	simulationStatus.add_theme_font_size_override("font_size", topBarFontSize)
	simulationStatus.add_theme_color_override("font_color", Color("7f8ca2"))
	refreshSimulationControls()
	dockResizeHandle.color = topBarSeparatorColor
	dockResizeHandle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	rightDockResizeHandle.color = topBarSeparatorColor
	rightDockResizeHandle.mouse_default_cursor_shape = Control.CURSOR_HSIZE

func configureTopBarButton(topBarButton: Button) -> void:
	topBarButton.expand_icon = false
	topBarButton.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topBarButton.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	topBarButton.add_theme_color_override("icon_normal_color", Color("8d9db5"))
	topBarButton.add_theme_color_override("icon_hover_color", Color("e1e9f6"))
	topBarButton.add_theme_color_override("icon_pressed_color", topBarButtonActiveIconColor)
	topBarButton.add_theme_color_override("icon_hover_pressed_color", topBarButtonActiveIconColor)
	topBarButton.add_theme_color_override("icon_disabled_color", Color("334155"))
	topBarButton.add_theme_stylebox_override("normal", makeMenuItemBox(Color.TRANSPARENT))
	topBarButton.add_theme_stylebox_override("hover", makeMenuItemBox(Color("2b374a")))
	topBarButton.add_theme_stylebox_override("pressed", makeMenuItemBox(Color.TRANSPARENT))
	topBarButton.add_theme_stylebox_override("hover_pressed", makeMenuItemBox(Color("2b374a")))

func configureSimulationModeButton() -> void:
	var normalColor := simulationEditColor if isSimulating else simulationStartColor
	var hoverColor := simulationEditHoverColor if isSimulating else simulationStartHoverColor
	simulationModeButton.add_theme_font_size_override("font_size", topBarFontSize)
	simulationModeButton.add_theme_color_override("font_color", Color.WHITE)
	simulationModeButton.add_theme_color_override("font_hover_color", Color.WHITE)
	simulationModeButton.add_theme_color_override("font_pressed_color", Color.WHITE)
	simulationModeButton.add_theme_stylebox_override("normal", makeCommandBox(normalColor))
	simulationModeButton.add_theme_stylebox_override("hover", makeCommandBox(hoverColor))
	simulationModeButton.add_theme_stylebox_override("pressed", makeCommandBox(normalColor.darkened(0.1)))
	simulationModeButton.add_theme_stylebox_override("hover_pressed", makeCommandBox(hoverColor.darkened(0.08)))

func configureStepLengthControl() -> void:
	stepLengthControl.alignment = HORIZONTAL_ALIGNMENT_CENTER
	stepLengthControl.add_theme_font_size_override("font_size", topBarFontSize)
	stepLengthControl.add_theme_color_override("font_color", Color("9aa8bf"))
	stepLengthControl.add_theme_color_override("font_hover_color", Color("e1e9f6"))
	stepLengthControl.add_theme_color_override("font_pressed_color", Color("f2c94c"))
	stepLengthControl.add_theme_color_override("font_disabled_color", Color("46546b"))
	stepLengthControl.add_theme_stylebox_override("normal", makeStepLengthBox(Color("2a3548")))
	stepLengthControl.add_theme_stylebox_override("hover", makeStepLengthBox(Color("35435a")))
	stepLengthControl.add_theme_stylebox_override("pressed", makeStepLengthBox(Color("202b3b")))
	stepLengthControl.add_theme_stylebox_override("disabled", makeStepLengthBox(Color("202a38")))
	stepLengthControl.mouse_default_cursor_shape = Control.CURSOR_HSIZE

func configureLoopFrequencySlider() -> void:
	var sliderBox := StyleBoxFlat.new()
	sliderBox.bg_color = Color("2b3749")
	sliderBox.corner_radius_top_left = 1
	sliderBox.corner_radius_top_right = 1
	sliderBox.corner_radius_bottom_left = 1
	sliderBox.corner_radius_bottom_right = 1
	sliderBox.content_margin_top = 10
	sliderBox.content_margin_bottom = 10
	loopFrequencySlider.add_theme_stylebox_override("slider", sliderBox)
	loopFrequencySlider.add_theme_icon_override("grabber", makeSolidTexture(Vector2i(6, 16), Color("f4f6fa")))
	loopFrequencySlider.add_theme_icon_override("grabber_highlight", makeSolidTexture(Vector2i(6, 16), Color.WHITE))
	loopFrequencySlider.add_theme_icon_override("grabber_disabled", makeSolidTexture(Vector2i(6, 16), Color("7d899e")))

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
