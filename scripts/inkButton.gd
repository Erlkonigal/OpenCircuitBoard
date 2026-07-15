extends Button

const InkGlyph := preload("res://scripts/inkGlyph.gd")
const inactiveBackgroundColor := Color.TRANSPARENT
const hoverBackgroundColor := Color("26364a")
const inverseGlyphColor := Color("111a26")

var glyph: Control

func configure(ink: Dictionary) -> void:
	name = "%sButton" % String(ink.get("componentId", ink.get("toolId", "Ink")))
	custom_minimum_size = Vector2(28, 24)
	toggle_mode = true
	tooltip_text = String(ink.get("title", ""))
	expand_icon = false
	var glyphControl := InkGlyph.new() as Control
	glyphControl.name = "glyph"
	glyphControl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyphControl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glyphControl)
	glyph = glyphControl
	var inkColor: Color = ink.get("color", Color.WHITE)
	setGlyph(String(ink.get("toolId", "")))
	setInkAppearance(inkColor, false)

func setGlyph(glyphId: String) -> void:
	if glyph:
		glyph.call("setGlyphId", glyphId)

func setInkAppearance(accent: Color, isSelected: bool) -> void:
	add_theme_color_override("icon_normal_color", accent)
	add_theme_color_override("icon_hover_color", accent.lightened(0.15))
	add_theme_color_override("icon_pressed_color", inverseGlyphColor)
	add_theme_color_override("icon_hover_pressed_color", inverseGlyphColor)
	add_theme_stylebox_override("normal", makeBox(inactiveBackgroundColor))
	add_theme_stylebox_override("hover", makeBox(hoverBackgroundColor))
	add_theme_stylebox_override("pressed", makeBox(accent))
	add_theme_stylebox_override("hover_pressed", makeBox(accent.lightened(0.12)))
	if glyph:
		glyph.call("setGlyphColor", inverseGlyphColor if isSelected else accent)

func makeBox(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 3
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 3
	return box
