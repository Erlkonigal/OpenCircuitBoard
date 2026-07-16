extends Control

const DockRegistry := preload("res://scripts/DockRegistry.gd")
const InkRegistry := preload("res://scripts/InkRegistry.gd")
const InkButton := preload("res://scripts/InkButton.gd")
const ProjectManager := preload("res://scripts/ProjectManager.gd")
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
const SimulationStartColor := Color("00c875")
const SimulationStartHoverColor := Color("18dd8a")
const SimulationEditColor := Color("ed3157")
const SimulationEditHoverColor := Color("fa4268")
const SimulationStepColor := Color("f3b941")
const SimulationStepLengthMinimum := 1
const SimulationStepLengthMaximum := 16
const SimulationFrequencyMinimum := 1.0
const SimulationFrequencyMaximum := 20.0
const SimulationDragPixelsPerStep := 8.0
const SimulationMaxCatchUpTicks := 8
const DockMenuButtonSize := 28
const DockMenuSeparation := 5
const DockMenuPadding := 14
const InkVariantMenuColumns := 3
const InkVariantMenuButtonSize := Vector2i(28, 28)
const InkVariantMenuSeparation := 4
const InkVariantMenuPadding := 14
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
var SimulationAccumulator := 0.0
var SimulationStepLength := SimulationStepLengthMinimum
var LoopFrequency := 5.0
var IsDraggingStepLength := false
var StepLengthDragRemainder := 0.0

func _ready() -> void:
	Input.set_use_accumulated_input(false)
	configureTopBar()
	configureProjectDialogs()
	Board.connect("clipboardChanged", updateClipboardHistory)
	Board.connect("clipboardCopied", showClipboardDock)
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
	LoopFrequencySlider.value_changed.connect(setLoopFrequency)
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
	var initialLeftDockId := String(DockDefinitions[0].dockId)
	activateDock(initialLeftDockId, LeftDockSide)
	var initialRightDockId := getInitialRightDockId(initialLeftDockId)
	if not initialRightDockId.is_empty():
		activateDock(initialRightDockId, RightDockSide)
	setLeftSidebarOpen(LeftSidebarToggle.button_pressed, false)
	setRightSidebarOpen(RightSidebarToggle.button_pressed, false)

func _process(_delta: float) -> void:
	updateSimulation(_delta)
	if not isPointerOverCanvas():
		return
	var mousePosition := Board.get_global_mouse_position()
	var isValid: bool = Board.ValidRect.has_point(mousePosition)
	var coordinates: Vector2i = Board.call("getGridCoordinates", mousePosition)
	var hoveredInk: Dictionary = Board.call("getInkAt", coordinates) if isValid else {}
	var hoveredInkTitle := String(hoveredInk.get("title", "None"))
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
	if dock.has_signal("eventRecorded"):
		dock.connect("eventRecorded", recordEvent)
	if dock.has_signal("clipboardItemSelected"):
		dock.connect("clipboardItemSelected", selectClipboardItem)
	if dock.has_method("syncLastSelectedInkIds"):
		dock.call("syncLastSelectedInkIds", LastSelectedInkIdByPaletteToolId)
	if dock.has_method("syncSelectedInk"):
		dock.call("syncSelectedInk", String(Board.get("SelectedTool")))

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
	if InkVariantMenuDock and InkVariantMenuDock.has_method("selectInk"):
		InkVariantMenuDock.call("selectInk", ink)
	hideInkVariantMenu()

func hideInkVariantMenu() -> void:
	if InkVariantMenu:
		InkVariantMenu.hide()
	InkVariantMenuDock = null
	InkVariantMenuPaletteToolId = ""

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
	ProjectFileDialog = FileDialog.new()
	ProjectFileDialog.access = FileDialog.ACCESS_FILESYSTEM
	ProjectFileDialog.filters = PackedStringArray(["*.ocb ; OpenCircuitBoard Project"])
	ProjectFileDialog.file_selected.connect(handleProjectFileSelected)
	$Interface.add_child(ProjectFileDialog)
	ProjectNoticeDialog = AcceptDialog.new()
	ProjectNoticeDialog.title = "OpenCircuitBoard"
	$Interface.add_child(ProjectNoticeDialog)

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

func enterSimulation() -> void:
	if IsSimulating:
		return
	Board.call("cancelActiveInteraction")
	Board.call("setEditorInputEnabled", false)
	IsSimulating = true
	IsLooping = true
	SimulationTick = 0
	SimulationTimeline = [captureSimulationSnapshot()]
	SimulationAccumulator = 0.0
	refreshSimulationControls()

func leaveSimulation() -> void:
	if not IsSimulating:
		return
	IsSimulating = false
	IsLooping = true
	SimulationTick = 0
	SimulationTimeline.clear()
	SimulationAccumulator = 0.0
	Board.call("setEditorInputEnabled", true)
	refreshSimulationControls()

func toggleLoopStepMode() -> void:
	if not IsSimulating:
		return
	IsLooping = not IsLooping
	SimulationAccumulator = 0.0
	refreshSimulationControls()

func showPreviousSimulationTick() -> void:
	if not IsSimulating or IsLooping or SimulationTick <= 0:
		return
	SimulationTick = maxi(0, SimulationTick - SimulationStepLength)
	applySimulationSnapshot(SimulationTick)
	refreshSimulationControls()

func showNextSimulationTick() -> void:
	if not IsSimulating or IsLooping:
		return
	var targetTick := SimulationTick + SimulationStepLength
	while SimulationTimeline.size() <= targetTick:
		advanceSimulationTimeline()
	SimulationTick = targetTick
	applySimulationSnapshot(SimulationTick)
	refreshSimulationControls()

func updateSimulation(delta: float) -> void:
	if not IsSimulating or not IsLooping:
		return
	SimulationAccumulator += delta
	var tickPeriod := 1.0 / maxf(LoopFrequency, SimulationFrequencyMinimum)
	var advancedTickCount := 0
	while SimulationAccumulator >= tickPeriod and advancedTickCount < SimulationMaxCatchUpTicks:
		SimulationAccumulator -= tickPeriod
		advanceSimulationTimeline()
		advancedTickCount += 1
	if advancedTickCount > 0:
		refreshSimulationControls()

func advanceSimulationTimeline() -> void:
	if SimulationTick < SimulationTimeline.size() - 1:
		SimulationTick += 1
		applySimulationSnapshot(SimulationTick)
		return
	SimulationTimeline.append(captureSimulationSnapshot())
	SimulationTick += 1

func captureSimulationSnapshot() -> Array:
	return (Board.call("getSimulationTiles") as Array).duplicate(true)

func applySimulationSnapshot(snapshotIndex: int) -> void:
	if snapshotIndex < 0 or snapshotIndex >= SimulationTimeline.size():
		return
	Board.call("applyTileStates", SimulationTimeline[snapshotIndex] as Array)

func setLoopFrequency(requestedFrequency: float) -> void:
	LoopFrequency = clampf(roundf(requestedFrequency), SimulationFrequencyMinimum, SimulationFrequencyMaximum)
	LoopFrequencySlider.set_value_no_signal(LoopFrequency)
	if IsSimulating:
		refreshSimulationControls()

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
	SimulationModeButton.text = "Edit" if IsSimulating else "Simulate"
	SimulationModeButton.tooltip_text = "Exit simulation" if IsSimulating else "Enter simulation"
	configureSimulationModeButton()
	PreviousTickButton.disabled = not IsSimulating or IsLooping or SimulationTick <= 0
	LoopStepButton.disabled = not IsSimulating
	NextTickButton.disabled = not IsSimulating or IsLooping
	StepLengthControl.disabled = not canEditStepLength
	LoopFrequencySlider.mouse_filter = Control.MOUSE_FILTER_STOP if canEditLoopFrequency else Control.MOUSE_FILTER_IGNORE
	LoopFrequencySlider.focus_mode = Control.FOCUS_ALL if canEditLoopFrequency else Control.FOCUS_NONE
	LoopFrequencySlider.modulate = Color.WHITE if canEditLoopFrequency else Color(1.0, 1.0, 1.0, 0.38)
	LoopStepButton.tooltip_text = "Switch to step mode" if IsLooping else "Switch to loop mode"
	LoopStepButton.add_theme_color_override("icon_normal_color", Color("e2eaf7") if IsLooping else SimulationStepColor)
	LoopStepButton.add_theme_color_override("icon_hover_color", Color.WHITE if IsLooping else Color("ffd878"))
	SimulationStatus.visible = IsSimulating
	if IsSimulating:
		SimulationStatus.text = "~%d TPS" % roundi(LoopFrequency) if IsLooping else "Step Mode"
	setSimulationStepLength(SimulationStepLength)

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
	StepLengthControl.alignment = HORIZONTAL_ALIGNMENT_CENTER
	StepLengthControl.add_theme_font_size_override("font_size", TopBarFontSize)
	StepLengthControl.add_theme_color_override("font_color", Color("9aa8bf"))
	StepLengthControl.add_theme_color_override("font_hover_color", Color("e1e9f6"))
	StepLengthControl.add_theme_color_override("font_pressed_color", Color("f2c94c"))
	StepLengthControl.add_theme_color_override("font_disabled_color", Color("46546b"))
	StepLengthControl.add_theme_stylebox_override("normal", makeStepLengthBox(Color("2a3548")))
	StepLengthControl.add_theme_stylebox_override("hover", makeStepLengthBox(Color("35435a")))
	StepLengthControl.add_theme_stylebox_override("pressed", makeStepLengthBox(Color("202b3b")))
	StepLengthControl.add_theme_stylebox_override("disabled", makeStepLengthBox(Color("202a38")))
	StepLengthControl.mouse_default_cursor_shape = Control.CURSOR_HSIZE

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
