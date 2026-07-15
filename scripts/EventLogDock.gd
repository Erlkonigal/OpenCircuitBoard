extends "res://scripts/DockView.gd"

signal dockMenuRequested(menuButton: Button)

const EventLogIcon := preload("res://assets/EventLog.svg")
const DockIconSize := 16
const SidebarBackgroundColor := Color("131c28")
const FieldBackgroundColor := Color("111a26")
const SectionBorderColor := Color("26364a")
const PrimaryTextColor := Color("b4c1d3")
const MutedTextColor := Color("75859b")
const ControlHoverColor := Color("26364a")
const ActiveAccentColor := Color("f2c94c")

var EventHistory: Array[String] = []
var EventLog: RichTextLabel
var DockMenuButton: Button

func _init() -> void:
	DockId = "eventLog"
	DockTitle = "Event Log"
	DockWidth = 272.0
	DockIcon = EventLogIcon

func _ready() -> void:
	buildDock()
	refreshEventLog()

func setEventHistory(history: Array[String]) -> void:
	EventHistory.clear()
	EventHistory.append_array(history)
	refreshEventLog()

func appendEvent(eventText: String) -> void:
	EventHistory.append(eventText)
	if EventLog:
		EventLog.append_text(eventText + "\n")

func buildDock() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := Panel.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", makeBox(SidebarBackgroundColor, 0, Color.TRANSPARENT))
	add_child(background)

	var contentFrame := MarginContainer.new()
	contentFrame.name = "ContentFrame"
	contentFrame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contentFrame.add_theme_constant_override("margin_left", 8)
	contentFrame.add_theme_constant_override("margin_right", 8)
	background.add_child(contentFrame)

	var root := VBoxContainer.new()
	root.name = "ContentRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	contentFrame.add_child(root)
	root.add_child(buildHeader())

	EventLog = RichTextLabel.new()
	EventLog.name = "EventLog"
	EventLog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	EventLog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EventLog.bbcode_enabled = false
	EventLog.scroll_following = true
	EventLog.add_theme_color_override("default_color", PrimaryTextColor)
	EventLog.add_theme_font_size_override("normal_font_size", 15)
	EventLog.add_theme_constant_override("line_separation", 3)
	EventLog.add_theme_stylebox_override("normal", makeLogBox())
	root.add_child(EventLog)

func buildHeader() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 28)
	header.add_theme_constant_override("separation", 6)
	DockMenuButton = Button.new()
	DockMenuButton.custom_minimum_size = Vector2(DockIconSize + 8, DockIconSize + 8)
	DockMenuButton.tooltip_text = "SwitchDock"
	DockMenuButton.icon = DockIcon
	DockMenuButton.expand_icon = false
	DockMenuButton.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	DockMenuButton.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	DockMenuButton.add_theme_color_override("icon_normal_color", MutedTextColor)
	DockMenuButton.add_theme_color_override("icon_hover_color", PrimaryTextColor)
	DockMenuButton.add_theme_color_override("icon_pressed_color", ActiveAccentColor)
	DockMenuButton.add_theme_color_override("icon_hover_pressed_color", ActiveAccentColor)
	DockMenuButton.add_theme_stylebox_override("normal", makeBox(Color.TRANSPARENT, 2, Color.TRANSPARENT))
	DockMenuButton.add_theme_stylebox_override("hover", makeBox(ControlHoverColor, 2, Color.TRANSPARENT))
	DockMenuButton.add_theme_stylebox_override("pressed", makeBox(Color.TRANSPARENT, 2, Color.TRANSPARENT))
	DockMenuButton.add_theme_stylebox_override("hover_pressed", makeBox(ControlHoverColor, 2, Color.TRANSPARENT))
	DockMenuButton.pressed.connect(func() -> void: dockMenuRequested.emit(DockMenuButton))
	header.add_child(DockMenuButton)
	var title := Label.new()
	title.text = DockTitle
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("8e9db2"))
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(DockIconSize + 8, DockIconSize + 8)
	header.add_child(spacer)
	return header

func refreshEventLog() -> void:
	if EventLog == null:
		return
	EventLog.clear()
	for eventText in EventHistory:
		EventLog.append_text(eventText + "\n")

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
	var box := makeBox(FieldBackgroundColor, 4, SectionBorderColor)
	box.content_margin_left = 7
	box.content_margin_top = 6
	box.content_margin_right = 7
	box.content_margin_bottom = 6
	return box
