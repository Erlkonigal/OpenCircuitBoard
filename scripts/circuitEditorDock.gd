extends "res://scripts/dockView.gd"

signal dockMenuRequested(menuButton: Button)
signal inkSelected(ink: Dictionary)
signal eventRecorded(eventText: String)

const InkRegistry := preload("res://scripts/inkRegistry.gd")
const circuitEditorIcon := preload("res://assets/circuitEditor.svg")
const dockIconSize := 16
const sidebarBackgroundColor := Color("131c28")
const sectionBackgroundColor := Color("1a2432")
const sectionBorderColor := Color("26364a")
const fieldBackgroundColor := Color("111a26")
const fieldFocusBorderColor := Color("536b86")
const primaryTextColor := Color("b4c1d3")
const mutedTextColor := Color("75859b")
const controlHoverColor := Color("26364a")
const activeAccentColor := Color("f2c94c")

var inkButtons: Dictionary[String, Button] = {}
var selectedInkId := "or"
var hoveredInkLabel: Label
var positionXLabel: Label
var positionYLabel: Label
var solidIcon: ImageTexture
var dockMenuButton: Button

func _init() -> void:
	dockId = "circuitEditor"
	dockTitle = "CircuitEditor"
	dockWidth = 272.0
	dockIcon = circuitEditorIcon

func _ready() -> void:
	solidIcon = makeSolidIcon()
	buildDock()
	selectInk(InkRegistry.getInk(selectedInkId), false)

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

	content.add_child(buildToolsSection())
	content.add_child(buildCursorInfoSection())
	content.add_child(buildInksSection())
	content.add_child(buildArraySection())

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

func buildToolsSection() -> Control:
	var panel := makeSection()
	panel.name = "toolsSection"
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("Tools"))
	section.add_child(makeActionRow(["Add", "Image", "Duplicate", "Undo", "Redo"]))
	section.add_child(makeActionRow(["Draw", "Edit", "Erase", "Sample", "Select", "Transform"]))
	return panel

func makeActionRow(actionNames: Array[String]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for actionName in actionNames:
		row.add_child(makeActionButton(actionName))
	return row

func buildCursorInfoSection() -> Control:
	var panel := makeSection()
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("CursorInfo"))
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
	for ink in InkRegistry.getInks():
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

func buildArraySection() -> Control:
	var panel := makeSection()
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("Array"))
	var parameterGrid := GridContainer.new()
	parameterGrid.columns = 2
	parameterGrid.add_theme_constant_override("h_separation", 4)
	parameterGrid.add_theme_constant_override("v_separation", 4)
	parameterGrid.add_child(makeArrayValueField("Repeat", 1, 1, 99))
	parameterGrid.add_child(makeArrayValueField("Angle", 0, 0, 360))
	parameterGrid.add_child(makeArrayValueField("OffsetX", 2, -999, 999))
	parameterGrid.add_child(makeArrayValueField("OffsetY", 0, -999, 999))
	section.add_child(parameterGrid)
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

func makeActionButton(actionName: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(24, 22)
	button.tooltip_text = actionName
	button.icon = solidIcon
	button.expand_icon = false
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_theme_color_override("icon_normal_color", Color("91a0b9"))
	button.add_theme_color_override("icon_hover_color", primaryTextColor)
	button.add_theme_color_override("icon_pressed_color", activeAccentColor)
	button.add_theme_color_override("icon_hover_pressed_color", activeAccentColor)
	button.add_theme_stylebox_override("normal", makeBox(Color.TRANSPARENT, 2, Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", makeBox(controlHoverColor, 2, Color.TRANSPARENT))
	button.add_theme_stylebox_override("pressed", makeBox(Color.TRANSPARENT, 2, Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover_pressed", makeBox(controlHoverColor, 2, Color.TRANSPARENT))
	button.pressed.connect(func() -> void: recordEvent("%sAction" % actionName))
	return button

func makeInkButton(ink: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(26, 22)
	button.toggle_mode = true
	button.tooltip_text = String(ink.title)
	button.icon = solidIcon
	button.expand_icon = false
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var accent: Color = ink.color
	button.add_theme_color_override("icon_normal_color", accent)
	button.add_theme_color_override("icon_hover_color", accent.lightened(0.15))
	button.add_theme_color_override("icon_pressed_color", accent)
	button.add_theme_color_override("icon_hover_pressed_color", accent.lightened(0.15))
	button.add_theme_stylebox_override("normal", makeBox(fieldBackgroundColor, 3, Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", makeBox(controlHoverColor, 3, Color.TRANSPARENT))
	button.add_theme_stylebox_override("pressed", makeBox(fieldBackgroundColor, 3, accent))
	button.add_theme_stylebox_override("hover_pressed", makeBox(controlHoverColor, 3, accent.lightened(0.15)))
	button.pressed.connect(selectInk.bind(ink, true))
	button.mouse_entered.connect(setHoveredInk.bind(String(ink.title)))
	button.mouse_exited.connect(clearHoveredInk)
	inkButtons[String(ink.toolId)] = button
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

func makeSpinBox(value: float, minimum: float, maximum: float) -> SpinBox:
	var spinBox := SpinBox.new()
	spinBox.custom_minimum_size = Vector2(0, 22)
	spinBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinBox.add_theme_constant_override("buttons_width", 10)
	spinBox.add_theme_constant_override("field_and_buttons_separation", 1)
	spinBox.min_value = minimum
	spinBox.max_value = maximum
	spinBox.value = value
	spinBox.allow_greater = false
	spinBox.allow_lesser = false
	var lineEdit := spinBox.get_line_edit()
	lineEdit.custom_minimum_size = Vector2(0, 22)
	lineEdit.add_theme_constant_override("minimum_character_width", 1)
	lineEdit.add_theme_font_size_override("font_size", 15)
	lineEdit.add_theme_color_override("font_color", primaryTextColor)
	lineEdit.add_theme_color_override("caret_color", primaryTextColor)
	lineEdit.add_theme_color_override("selection_color", Color("38506b"))
	lineEdit.add_theme_stylebox_override("normal", makeFieldBox(sectionBorderColor))
	lineEdit.add_theme_stylebox_override("read_only", makeFieldBox(sectionBorderColor))
	lineEdit.add_theme_stylebox_override("focus", makeFieldBox(fieldFocusBorderColor))
	spinBox.value_changed.connect(func(_nextValue: float) -> void: recordEvent("ArrayUpdated"))
	return spinBox

func makeInfoField(labelText: String, value: Label) -> HBoxContainer:
	var field := HBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 4)
	field.add_child(makeInfoLabel(labelText))
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(value)
	return field

func makeArrayValueField(labelText: String, value: float, minimum: float, maximum: float) -> VBoxContainer:
	var field := VBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 2)
	field.add_child(makeInfoLabel(labelText))
	field.add_child(makeSpinBox(value, minimum, maximum))
	return field

func selectInk(ink: Dictionary, shouldRecordEvent := true) -> void:
	if ink.is_empty():
		return
	selectedInkId = String(ink.toolId)
	for toolId in inkButtons:
		inkButtons[toolId].set_pressed_no_signal(toolId == selectedInkId)
	if shouldRecordEvent:
		recordEvent("Selected%s" % ink.title)
	inkSelected.emit(ink)

func setHoveredInk(titleText: String) -> void:
	if hoveredInkLabel:
		hoveredInkLabel.text = titleText

func clearHoveredInk() -> void:
	if hoveredInkLabel:
		hoveredInkLabel.text = "None"

func updateCursorInfo(position: Vector2i, isValid: bool) -> void:
	if positionXLabel == null or positionYLabel == null:
		return
	positionXLabel.text = str(position.x) if isValid else "0"
	positionYLabel.text = str(position.y) if isValid else "0"

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

func makeSolidIcon() -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
