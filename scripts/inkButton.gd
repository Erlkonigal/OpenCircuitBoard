extends Button

const InkVariantIndicator := preload("res://scripts/inkVariantIndicator.gd")
const inactiveBackgroundColor := Color.TRANSPARENT
const hoverBackgroundColor := Color("26364a")
const inverseGlyphColor := Color("111a26")
const variantIndicatorColor := Color("b4c1d3")

var inkIcon: TextureRect
var isExpandable := false
var variantIndicator: Control

func configure(ink: Dictionary) -> void:
	name = "%sButton" % String(ink.get("componentId", ink.get("toolId", "Ink")))
	custom_minimum_size = Vector2(28, 28)
	toggle_mode = true
	tooltip_text = String(ink.get("title", ""))
	expand_icon = false
	isExpandable = bool(ink.get("isExpandable", false))
	var iconRect := TextureRect.new()
	iconRect.name = "inkIcon"
	iconRect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iconRect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	iconRect.stretch_mode = TextureRect.STRETCH_SCALE
	iconRect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	iconRect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	iconRect.texture = ink.get("icon") as Texture2D
	add_child(iconRect)
	inkIcon = iconRect
	if isExpandable:
		variantIndicator = makeVariantIndicator()
		add_child(variantIndicator)
	var inkColor: Color = ink.get("color", Color.WHITE)
	setInkAppearance(inkColor, false)

func setInkAppearance(accent: Color, isSelected: bool) -> void:
	add_theme_color_override("icon_normal_color", accent)
	add_theme_color_override("icon_hover_color", accent.lightened(0.15))
	add_theme_color_override("icon_pressed_color", inverseGlyphColor)
	add_theme_color_override("icon_hover_pressed_color", inverseGlyphColor)
	add_theme_stylebox_override("normal", makeBox(inactiveBackgroundColor))
	add_theme_stylebox_override("hover", makeBox(hoverBackgroundColor))
	add_theme_stylebox_override("pressed", makeBox(accent))
	add_theme_stylebox_override("hover_pressed", makeBox(accent.lightened(0.12)))
	if inkIcon:
		inkIcon.modulate = inverseGlyphColor if isSelected else accent
	if variantIndicator:
		variantIndicator.call("setIndicatorColor", inverseGlyphColor if isSelected else variantIndicatorColor)

func setInkIcon(nextIcon: Texture2D) -> void:
	if inkIcon:
		inkIcon.texture = nextIcon

func makeVariantIndicator() -> Control:
	var indicator := InkVariantIndicator.new() as Control
	indicator.name = "variantIndicator"
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	indicator.offset_left = -9.0
	indicator.offset_top = -9.0
	indicator.offset_right = -1.0
	indicator.offset_bottom = -1.0
	return indicator

func makeBox(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = 3
	box.corner_radius_top_right = 3
	box.corner_radius_bottom_left = 3
	box.corner_radius_bottom_right = 3
	return box
