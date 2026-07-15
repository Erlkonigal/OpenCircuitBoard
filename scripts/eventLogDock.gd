extends "res://scripts/dockView.gd"

signal dockMenuRequested(menuButton: Button)

const eventLogIcon := preload("res://assets/eventLog.svg")
const dockIconSize := 16
const sidebarBackgroundColor := Color("131c28")
const fieldBackgroundColor := Color("111a26")
const sectionBorderColor := Color("26364a")
const primaryTextColor := Color("b4c1d3")
const mutedTextColor := Color("75859b")
const controlHoverColor := Color("26364a")
const activeAccentColor := Color("f2c94c")

var eventHistory: Array[String] = []
var eventLog: RichTextLabel
var dockMenuButton: Button

func _init() -> void:
	dockId = "eventLog"
	dockTitle = "Event Log"
	dockWidth = 272.0
	dockIcon = eventLogIcon

func _ready() -> void:
	buildDock()
	refreshEventLog()

func setEventHistory(history: Array[String]) -> void:
	eventHistory.clear()
	eventHistory.append_array(history)
	refreshEventLog()

func appendEvent(eventText: String) -> void:
	eventHistory.append(eventText)
	if eventLog:
		eventLog.append_text(eventText + "\n")

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
	root.add_theme_constant_override("separation", 4)
	contentFrame.add_child(root)
	root.add_child(buildHeader())

	eventLog = RichTextLabel.new()
	eventLog.name = "eventLog"
	eventLog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eventLog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	eventLog.bbcode_enabled = false
	eventLog.scroll_following = true
	eventLog.add_theme_color_override("default_color", primaryTextColor)
	eventLog.add_theme_font_size_override("normal_font_size", 15)
	eventLog.add_theme_constant_override("line_separation", 3)
	eventLog.add_theme_stylebox_override("normal", makeLogBox())
	root.add_child(eventLog)

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

func refreshEventLog() -> void:
	if eventLog == null:
		return
	eventLog.clear()
	for eventText in eventHistory:
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

func makeLogBox() -> StyleBoxFlat:
	var box := makeBox(fieldBackgroundColor, 4, sectionBorderColor)
	box.content_margin_left = 7
	box.content_margin_top = 6
	box.content_margin_right = 7
	box.content_margin_bottom = 6
	return box
