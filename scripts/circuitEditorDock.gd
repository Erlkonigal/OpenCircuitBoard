extends "res://scripts/dockView.gd"

signal dockMenuRequested(menuButton: Button)
signal inkSelected(ink: Dictionary)

const InkRegistry := preload("res://scripts/inkRegistry.gd")

var inkButtons: Dictionary[String, Button] = {}
var selectedInkId := "or"
var hoveredInkLabel: Label
var positionXLabel: Label
var positionYLabel: Label
var eventLog: RichTextLabel
var solidIcon: ImageTexture

func _init() -> void:
	dockId = "circuitEditor"
	dockTitle = "CircuitEditor"
	dockWidth = 272.0
	dockIcon = makeSwitchIcon()

func _ready() -> void:
	solidIcon = makeSolidIcon()
	buildDock()
	selectInk(InkRegistry.getInk(selectedInkId), false)

func buildDock() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", makeBox(Color("151c27"), 0, Color.TRANSPARENT))
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	background.add_child(root)
	root.add_child(buildHeader())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 7)
	scroll.add_child(content)

	content.add_child(buildLayersSection())
	content.add_child(buildToolsSection())
	content.add_child(buildCursorInfoSection())
	content.add_child(buildInksSection())
	content.add_child(buildArraySection())
	content.add_child(buildEventLogSection())

func buildHeader() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 31)
	header.add_theme_constant_override("separation", 6)
	header.add_theme_constant_override("margin_left", 8)
	header.add_theme_constant_override("margin_right", 8)
	var menuButton := Button.new()
	menuButton.custom_minimum_size = Vector2(24, 24)
	menuButton.tooltip_text = "SwitchDock"
	menuButton.icon = dockIcon
	menuButton.expand_icon = true
	menuButton.add_theme_color_override("icon_normal_color", Color("8493aa"))
	menuButton.add_theme_color_override("icon_hover_color", Color("d5deed"))
	menuButton.add_theme_stylebox_override("normal", makeBox(Color.TRANSPARENT, 2, Color.TRANSPARENT))
	menuButton.add_theme_stylebox_override("hover", makeBox(Color("273243"), 2, Color.TRANSPARENT))
	menuButton.pressed.connect(func() -> void: dockMenuRequested.emit(menuButton))
	header.add_child(menuButton)
	var title := Label.new()
	title.text = dockTitle
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("728098"))
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 24)
	header.add_child(spacer)
	return header

func buildLayersSection() -> Control:
	var panel := makeSection()
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("Layers"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for actionName in ["Add", "Image", "Duplicate", "Undo", "Redo"]:
		row.add_child(makeActionButton(actionName))
	section.add_child(row)
	return panel

func buildToolsSection() -> Control:
	var panel := makeSection()
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("Tools"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for actionName in ["Draw", "Edit", "Erase", "Sample", "Select", "Transform"]:
		row.add_child(makeActionButton(actionName))
	section.add_child(row)
	return panel

func buildCursorInfoSection() -> Control:
	var panel := makeSection()
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("CursorInfo"))
	var hoveredRow := HBoxContainer.new()
	hoveredRow.add_child(makeInfoLabel("HoveredInk"))
	hoveredInkLabel = makeInfoValue("None")
	hoveredRow.add_child(hoveredInkLabel)
	section.add_child(hoveredRow)
	var positionRow := HBoxContainer.new()
	positionRow.add_theme_constant_override("separation", 8)
	positionRow.add_child(makeInfoLabel("PositionX"))
	positionXLabel = makeSmallInfoValue("0")
	positionRow.add_child(positionXLabel)
	positionRow.add_child(makeInfoLabel("PositionY"))
	positionYLabel = makeSmallInfoValue("0")
	positionRow.add_child(positionYLabel)
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
			categoryLabel.add_theme_color_override("font_color", Color("66748a"))
			categoryLabel.add_theme_font_size_override("font_size", 14)
			section.add_child(categoryLabel)
			lastCategory = category
		var grid: GridContainer
		if section.get_child_count() == 0 or not (section.get_child(-1) is GridContainer):
			grid = GridContainer.new()
			grid.columns = 4
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 5)
			section.add_child(grid)
		else:
			grid = section.get_child(-1) as GridContainer
		grid.add_child(makeInkButton(ink))
	return panel

func buildArraySection() -> Control:
	var panel := makeSection()
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("Array"))
	var repeatRow := HBoxContainer.new()
	repeatRow.add_theme_constant_override("separation", 6)
	repeatRow.add_child(makeInfoLabel("Repeat"))
	repeatRow.add_child(makeSpinBox(1, 1, 99))
	repeatRow.add_child(makeInfoLabel("Angle"))
	repeatRow.add_child(makeSpinBox(0, 0, 360))
	section.add_child(repeatRow)
	var offsetRow := HBoxContainer.new()
	offsetRow.add_theme_constant_override("separation", 6)
	offsetRow.add_child(makeInfoLabel("OffsetX"))
	offsetRow.add_child(makeSpinBox(2, -999, 999))
	offsetRow.add_child(makeInfoLabel("OffsetY"))
	offsetRow.add_child(makeSpinBox(0, -999, 999))
	section.add_child(offsetRow)
	var toggleRow := HBoxContainer.new()
	toggleRow.add_theme_constant_override("separation", 6)
	toggleRow.add_child(makeArrayToggle("AutoCross"))
	toggleRow.add_child(makeArrayToggle("Filter"))
	section.add_child(toggleRow)
	section.add_child(makeArrayToggle("MulticoloredTraces"))
	return panel

func buildEventLogSection() -> Control:
	var panel := makeSection()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 150)
	var section := getSectionContent(panel)
	section.add_child(makeSectionTitle("EventLog"))
	eventLog = RichTextLabel.new()
	eventLog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	eventLog.bbcode_enabled = false
	eventLog.scroll_following = true
	eventLog.add_theme_color_override("default_color", Color("8f9bb0"))
	eventLog.add_theme_font_size_override("normal_font_size", 13)
	eventLog.add_theme_stylebox_override("normal", makeBox(Color("121923"), 4, Color.TRANSPARENT))
	section.add_child(eventLog)
	return panel

func makeSection() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", makeBox(Color("1c2532"), 6, Color.TRANSPARENT))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	margin.add_child(content)
	panel.set_meta("sectionContent", content)
	return panel

func getSectionContent(panel: PanelContainer) -> VBoxContainer:
	return panel.get_meta("sectionContent") as VBoxContainer

func makeSectionTitle(titleText: String) -> Label:
	var title := Label.new()
	title.text = titleText
	title.add_theme_color_override("font_color", Color("a4b0c5"))
	title.add_theme_font_size_override("font_size", 15)
	return title

func makeActionButton(actionName: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(20, 20)
	button.tooltip_text = actionName
	button.icon = solidIcon
	button.expand_icon = true
	button.add_theme_color_override("icon_normal_color", Color("91a0b9"))
	button.add_theme_color_override("icon_hover_color", Color("dbe5f4"))
	button.add_theme_stylebox_override("normal", makeBox(Color.TRANSPARENT, 2, Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", makeBox(Color("303e52"), 2, Color.TRANSPARENT))
	button.pressed.connect(func() -> void: appendEvent("%sAction" % actionName))
	return button

func makeInkButton(ink: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(36, 28)
	button.toggle_mode = true
	button.tooltip_text = String(ink.title)
	button.icon = solidIcon
	button.expand_icon = true
	var accent: Color = ink.color
	button.add_theme_color_override("icon_normal_color", accent)
	button.add_theme_color_override("icon_hover_color", accent.lightened(0.15))
	button.add_theme_color_override("icon_pressed_color", Color("17202c"))
	button.add_theme_color_override("icon_hover_pressed_color", Color("17202c"))
	button.add_theme_stylebox_override("normal", makeBox(Color("19212d"), 3, Color.TRANSPARENT))
	button.add_theme_stylebox_override("hover", makeBox(Color("273446"), 3, Color.TRANSPARENT))
	button.add_theme_stylebox_override("pressed", makeBox(accent, 3, accent))
	button.add_theme_stylebox_override("hover_pressed", makeBox(accent.lightened(0.06), 3, accent))
	button.pressed.connect(selectInk.bind(ink, true))
	button.mouse_entered.connect(setHoveredInk.bind(String(ink.title)))
	button.mouse_exited.connect(clearHoveredInk)
	inkButtons[String(ink.toolId)] = button
	return button

func makeInfoLabel(labelText: String) -> Label:
	var label := Label.new()
	label.text = labelText
	label.add_theme_color_override("font_color", Color("68758a"))
	label.add_theme_font_size_override("font_size", 13)
	return label

func makeInfoValue(valueText: String) -> Label:
	var value := Label.new()
	value.text = valueText
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_color_override("font_color", Color("aab7c9"))
	value.add_theme_stylebox_override("normal", makeBox(Color("3a4757"), 5, Color.TRANSPARENT))
	return value

func makeSmallInfoValue(valueText: String) -> Label:
	var value := makeInfoValue(valueText)
	value.custom_minimum_size = Vector2(38, 0)
	value.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return value

func makeSpinBox(value: float, minimum: float, maximum: float) -> SpinBox:
	var spinBox := SpinBox.new()
	spinBox.custom_minimum_size = Vector2(42, 24)
	spinBox.min_value = minimum
	spinBox.max_value = maximum
	spinBox.value = value
	spinBox.allow_greater = false
	spinBox.allow_lesser = false
	spinBox.value_changed.connect(func(_nextValue: float) -> void: appendEvent("ArrayUpdated"))
	return spinBox

func makeArrayToggle(labelText: String) -> CheckBox:
	var toggle := CheckBox.new()
	toggle.text = labelText
	toggle.add_theme_color_override("font_color", Color("7f8ca1"))
	toggle.toggled.connect(func(_enabled: bool) -> void: appendEvent("ArrayUpdated"))
	return toggle

func selectInk(ink: Dictionary, recordEvent := true) -> void:
	if ink.is_empty():
		return
	selectedInkId = String(ink.toolId)
	for toolId in inkButtons:
		inkButtons[toolId].set_pressed_no_signal(toolId == selectedInkId)
	if recordEvent:
		appendEvent("Selected%s" % ink.title)
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

func appendEvent(eventText: String) -> void:
	if eventLog:
		eventLog.append_text(eventText + "\n")

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

func makeSolidIcon() -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)

func makeSwitchIcon() -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(3, 13):
		for x in range(2, 6):
			image.set_pixel(x, y, Color.WHITE)
		for x in range(10, 14):
			image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)
