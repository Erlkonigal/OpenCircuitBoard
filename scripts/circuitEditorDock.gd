extends "res://scripts/dockView.gd"

signal dockMenuRequested(menuButton: Button)
signal inkSelected(ink: Dictionary)
signal inkVariantMenuRequested(anchorButton: Button, paletteToolId: String)
signal eventRecorded(eventText: String)

const InkRegistry := preload("res://scripts/inkRegistry.gd")
const InkButton := preload("res://scripts/inkButton.gd")
const circuitEditorIcon := preload("res://assets/circuitEditor.svg")
const dockIconSize := 16
const sidebarBackgroundColor := Color("131c28")
const sectionBackgroundColor := Color("1a2432")
const sectionBorderColor := Color("26364a")
const fieldBackgroundColor := Color("111a26")
const primaryTextColor := Color("b4c1d3")
const mutedTextColor := Color("75859b")
const controlHoverColor := Color("26364a")
const activeAccentColor := Color("f2c94c")

var inkButtons: Dictionary[String, Button] = {}
var selectedInkId := "or"
var lastSelectedInkIdByPaletteToolId: Dictionary[String, String] = {}
var hoveredInkLabel: Label
var positionXLabel: Label
var positionYLabel: Label
var dockMenuButton: Button

func _init() -> void:
	dockId = "circuitEditor"
	dockTitle = "Circuit Editor"
	dockWidth = 272.0
	dockIcon = circuitEditorIcon

func _ready() -> void:
	buildDock()
	selectInk(InkRegistry.getInk(selectedInkId), false, false)

func buildDock() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := Panel.new()
	background.name = "background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", makeBox(sidebarBackgroundColor, 0, Color.TRANSPARENT))
	add_child(background)

	var contentFrame := MarginContainer.new()
	contentFrame.name = "contentFrame"
	contentFrame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contentFrame.add_theme_constant_override("margin_left", 8)
	contentFrame.add_theme_constant_override("margin_right", 8)
	background.add_child(contentFrame)

	var root := VBoxContainer.new()
	root.name = "contentRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 3)
	contentFrame.add_child(root)
	root.add_child(buildHeader())
	var content := VBoxContainer.new()
	content.name = "content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 3)
	root.add_child(content)

	content.add_child(buildCursorInfoSection())
	content.add_child(buildInksSection())

func buildHeader() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 28)
	header.add_theme_constant_override("separation", 6)
	dockMenuButton = Button.new()
	dockMenuButton.custom_minimum_size = Vector2(dockIconSize + 8, dockIconSize + 8)
	dockMenuButton.tooltip_text = "SwitchDock"
	dockMenuButton.icon = dockIcon
	dockMenuButton.expand_icon = false
	dockMenuButton.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dockMenuButton.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	dockMenuButton.add_theme_color_override("icon_normal_color", mutedTextColor)
	dockMenuButton.add_theme_color_override("icon_hover_color", primaryTextColor)
	dockMenuButton.add_theme_color_override("icon_pressed_color", activeAccentColor)
	dockMenuButton.add_theme_color_override("icon_hover_pressed_color", activeAccentColor)
	dockMenuButton.add_theme_stylebox_override("normal", makeBox(Color.TRANSPARENT, 2, Color.TRANSPARENT))
	dockMenuButton.add_theme_stylebox_override("hover", makeBox(controlHoverColor, 2, Color.TRANSPARENT))
	dockMenuButton.add_theme_stylebox_override("pressed", makeBox(Color.TRANSPARENT, 2, Color.TRANSPARENT))
	dockMenuButton.add_theme_stylebox_override("hover_pressed", makeBox(controlHoverColor, 2, Color.TRANSPARENT))
	dockMenuButton.pressed.connect(func() -> void: dockMenuRequested.emit(dockMenuButton))
	header.add_child(dockMenuButton)
	var title := Label.new()
	title.text = dockTitle
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("8e9db2"))
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(dockIconSize + 8, dockIconSize + 8)
	header.add_child(spacer)
	return header

func buildCursorInfoSection() -> Control:
	var panel := makeSection()
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("Cursor Info"))
	hoveredInkLabel = makeInfoValue("None")
	section.add_child(makeInfoField("HoveredInk", hoveredInkLabel))
	var positionRow := HBoxContainer.new()
	positionRow.add_theme_constant_override("separation", 6)
	positionXLabel = makeSmallInfoValue("0")
	positionRow.add_child(makeInfoField("X", positionXLabel))
	positionYLabel = makeSmallInfoValue("0")
	positionRow.add_child(makeInfoField("Y", positionYLabel))
	section.add_child(positionRow)
	return panel

func buildInksSection() -> Control:
	var panel := makeSection()
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("Inks"))
	var lastCategory := ""
	for ink in InkRegistry.getPaletteInks():
		var category: String = ink.category
		if category != lastCategory:
			var categoryLabel := Label.new()
			categoryLabel.text = category
			categoryLabel.add_theme_color_override("font_color", mutedTextColor)
			categoryLabel.add_theme_font_size_override("font_size", 15)
			section.add_child(categoryLabel)
			lastCategory = category
		var grid: GridContainer
		if section.get_child_count() == 0 or not (section.get_child(-1) is GridContainer):
			grid = GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 3)
			section.add_child(grid)
		else:
			grid = section.get_child(-1) as GridContainer
		grid.add_child(makeInkButton(ink))
	return panel

func makeSection() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", makeBox(sectionBackgroundColor, 5, sectionBorderColor))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	margin.add_child(content)
	panel.set_meta("sectionContent", content)
	return panel

func getSectionContent(panel: PanelContainer) -> VBoxContainer:
	return panel.get_meta("sectionContent") as VBoxContainer

func makeSectionTitle(titleText: String) -> Label:
	var title := Label.new()
	title.text = titleText
	title.add_theme_color_override("font_color", primaryTextColor)
	title.add_theme_font_size_override("font_size", 16)
	return title

func makeInkButton(ink: Dictionary) -> Button:
	var button := InkButton.new() as Button
	button.call("configure", ink)
	var paletteToolId := InkRegistry.getPaletteToolId(ink)
	button.pressed.connect(selectPaletteInk.bind(paletteToolId))
	button.mouse_entered.connect(setHoveredPaletteInk.bind(paletteToolId))
	button.mouse_exited.connect(clearHoveredInk)
	if bool(ink.get("isExpandable", false)):
		button.gui_input.connect(handleInkButtonInput.bind(button, paletteToolId))
	inkButtons[paletteToolId] = button
	return button

func makeInfoLabel(labelText: String) -> Label:
	var label := Label.new()
	label.text = labelText
	label.add_theme_color_override("font_color", mutedTextColor)
	label.add_theme_font_size_override("font_size", 15)
	return label

func makeInfoValue(valueText: String) -> Label:
	var value := Label.new()
	value.text = valueText
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_color_override("font_color", primaryTextColor)
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_stylebox_override("normal", makeFieldBox(sectionBorderColor))
	return value

func makeSmallInfoValue(valueText: String) -> Label:
	var value := makeInfoValue(valueText)
	value.custom_minimum_size = Vector2(34, 0)
	value.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return value

func makeInfoField(labelText: String, value: Label) -> HBoxContainer:
	var field := HBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 4)
	field.add_child(makeInfoLabel(labelText))
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(value)
	return field

func selectInk(ink: Dictionary, shouldRecordEvent := true, shouldEmit := true) -> void:
	if ink.is_empty():
		return
	selectedInkId = InkRegistry.getComponentId(ink)
	lastSelectedInkIdByPaletteToolId[InkRegistry.getPaletteToolId(ink)] = selectedInkId
	updateInkButtonStates()
	if shouldRecordEvent:
		recordEvent("Selected%s" % ink.title)
	if shouldEmit:
		inkSelected.emit(ink)

func syncSelectedInk(toolId: String) -> void:
	selectInk(InkRegistry.getInk(toolId), false, false)

func syncLastSelectedInkIds(lastSelectedInkIds: Dictionary) -> void:
	for paletteToolId in lastSelectedInkIds:
		var normalizedPaletteToolId := String(paletteToolId)
		var componentId := String(lastSelectedInkIds[paletteToolId])
		var ink := InkRegistry.getInk(componentId)
		if not ink.is_empty() and InkRegistry.getPaletteToolId(ink) == normalizedPaletteToolId:
			lastSelectedInkIdByPaletteToolId[normalizedPaletteToolId] = componentId
	updateInkButtonStates()

func getSelectedInkId() -> String:
	return selectedInkId

func getLastSelectedInkId(paletteToolId: String) -> String:
	return InkRegistry.getComponentId(getLastSelectedInk(paletteToolId))

func updateInkButtonStates() -> void:
	var selectedInk := InkRegistry.getInk(selectedInkId)
	for paletteToolId in inkButtons:
		var button := inkButtons[paletteToolId]
		var displayedInk := getLastSelectedInk(String(paletteToolId))
		var isSelected := InkRegistry.getPaletteToolId(selectedInk) == paletteToolId
		button.set_pressed_no_signal(isSelected)
		button.tooltip_text = String(displayedInk.get("title", ""))
		button.call("setInkIcon", displayedInk.get("icon") as Texture2D)
		button.call("setInkAppearance", displayedInk.get("color", Color.WHITE), isSelected)

func selectPaletteInk(paletteToolId: String) -> void:
	selectInk(getLastSelectedInk(paletteToolId))

func getLastSelectedInk(paletteToolId: String) -> Dictionary:
	var componentId := String(lastSelectedInkIdByPaletteToolId.get(paletteToolId, paletteToolId))
	var ink := InkRegistry.getInk(componentId)
	if not ink.is_empty() and InkRegistry.getPaletteToolId(ink) == paletteToolId:
		return ink
	return InkRegistry.getInk(paletteToolId)

func handleInkButtonInput(event: InputEvent, anchorButton: Button, paletteToolId: String) -> void:
	var mouseButton := event as InputEventMouseButton
	if mouseButton == null or mouseButton.button_index != MOUSE_BUTTON_RIGHT:
		return
	if mouseButton.pressed:
		inkVariantMenuRequested.emit(anchorButton, paletteToolId)
	accept_event()

func setHoveredInk(titleText: String) -> void:
	if hoveredInkLabel:
		hoveredInkLabel.text = titleText

func setHoveredPaletteInk(paletteToolId: String) -> void:
	setHoveredInk(String(getLastSelectedInk(paletteToolId).get("title", "None")))

func clearHoveredInk() -> void:
	if hoveredInkLabel:
		hoveredInkLabel.text = "None"

func updateCursorInfo(position: Vector2i, isValid: bool, hoveredInkTitle := "None") -> void:
	if positionXLabel == null or positionYLabel == null:
		return
	positionXLabel.text = str(position.x) if isValid else "0"
	positionYLabel.text = str(position.y) if isValid else "0"
	setHoveredInk(hoveredInkTitle if isValid else "None")

func recordEvent(eventText: String) -> void:
	eventRecorded.emit(eventText)

func makeBox(color: Color, radius: int, borderColor: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	if borderColor.a > 0.0:
		box.border_width_left = 1
		box.border_width_top = 1
		box.border_width_right = 1
		box.border_width_bottom = 1
		box.border_color = borderColor
	return box

func makeFieldBox(borderColor: Color) -> StyleBoxFlat:
	var box := makeBox(fieldBackgroundColor, 4, borderColor)
	box.content_margin_left = 5
	box.content_margin_top = 1
	box.content_margin_right = 5
	box.content_margin_bottom = 1
	return box
