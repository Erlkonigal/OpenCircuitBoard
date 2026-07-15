extends "res://scripts/DockView.gd"

signal dockMenuRequested(menuButton: Button)
signal clipboardItemSelected(index: int)

const InkRegistry := preload("res://scripts/InkRegistry.gd")
const CircuitTile := preload("res://scripts/CircuitTile.gd")
const ClipboardIcon := preload("res://assets/Clipboard.svg")
const DockIconSize := 16
const MaximumHistoryItems := 4
const SidebarBackgroundColor := Color("131c28")
const SectionBackgroundColor := Color("1a2432")
const SectionBorderColor := Color("26364a")
const FieldBackgroundColor := Color("111a26")
const PrimaryTextColor := Color("b4c1d3")
const MutedTextColor := Color("75859b")
const ControlHoverColor := Color("26364a")
const ActiveAccentColor := Color("f2c94c")

class ClipboardPreview extends Control:
	var PreviewTiles: Array[Dictionary] = []
	var Dimensions := Vector2i.ONE

	func setPreview(nextTiles: Array[Dictionary], nextDimensions: Vector2i) -> void:
		PreviewTiles.clear()
		PreviewTiles.append_array(nextTiles)
		Dimensions = Vector2i(maxi(1, nextDimensions.x), maxi(1, nextDimensions.y))
		queue_redraw()

	func _draw() -> void:
		if PreviewTiles.is_empty():
			return
		var availableSize := size - Vector2(8.0, 8.0)
		var cellLength := minf(availableSize.x / float(Dimensions.x), availableSize.y / float(Dimensions.y))
		cellLength = maxf(2.0, cellLength)
		var previewSize := Vector2(Dimensions) * cellLength
		var previewOrigin := (size - previewSize) * 0.5
		for tile in PreviewTiles:
			var offset: Vector2i = tile.get("offset", Vector2i.ZERO)
			if offset.x < 0 or offset.y < 0 or offset.x >= Dimensions.x or offset.y >= Dimensions.y:
				continue
			var tileRect := Rect2(previewOrigin + Vector2(offset) * cellLength, Vector2.ONE * cellLength)
			var inset := minf(1.5, cellLength * 0.2)
			draw_rect(tileRect.grow(-inset), tile.get("color", MutedTextColor), true)
			draw_rect(tileRect.grow(-inset), Color("0b1119"), false, 1.0)
		draw_rect(Rect2(previewOrigin, previewSize), SectionBorderColor, false, 1.0)

var ClipboardHistory: Array[Dictionary] = []
var SelectedClipboardIndex := -1
var DockMenuButton: Button
var HistoryGrid: GridContainer
var EmptyLabel: Label
var HistoryButtons: Array[Button] = []

func _init() -> void:
	DockId = "clipboard"
	DockTitle = "Clipboard"
	DockWidth = 272.0
	DockIcon = ClipboardIcon

func _ready() -> void:
	buildDock()
	refreshClipboardHistory()

func setClipboardHistory(history: Array[Dictionary], selectedIndex: int) -> void:
	ClipboardHistory.clear()
	for item in history:
		if ClipboardHistory.size() >= MaximumHistoryItems:
			break
		ClipboardHistory.append(item.duplicate(true))
	SelectedClipboardIndex = selectedIndex if selectedIndex >= 0 and selectedIndex < ClipboardHistory.size() else -1
	refreshClipboardHistory()

func setClipboardItem(item: Dictionary) -> void:
	if item.is_empty():
		setClipboardHistory([], -1)
		return
	setClipboardHistory([item], 0)

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
	root.add_child(buildClipboardSection())

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

func buildClipboardSection() -> Control:
	var panel := PanelContainer.new()
	panel.name = "ClipboardSection"
	panel.add_theme_stylebox_override("panel", makeBox(SectionBackgroundColor, 5, SectionBorderColor))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	margin.add_child(content)
	var sectionTitle := Label.new()
	sectionTitle.text = "History"
	sectionTitle.add_theme_color_override("font_color", PrimaryTextColor)
	sectionTitle.add_theme_font_size_override("font_size", 16)
	content.add_child(sectionTitle)

	EmptyLabel = Label.new()
	EmptyLabel.name = "EmptyClipboardHistory"
	EmptyLabel.text = "NoClipboardItems"
	EmptyLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	EmptyLabel.add_theme_color_override("font_color", MutedTextColor)
	EmptyLabel.add_theme_font_size_override("font_size", 15)
	EmptyLabel.custom_minimum_size = Vector2(0, 48)
	EmptyLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(EmptyLabel)

	HistoryGrid = GridContainer.new()
	HistoryGrid.name = "ClipboardHistory"
	HistoryGrid.columns = 1
	HistoryGrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HistoryGrid.add_theme_constant_override("h_separation", 4)
	HistoryGrid.add_theme_constant_override("v_separation", 4)
	content.add_child(HistoryGrid)
	return panel

func refreshClipboardHistory() -> void:
	if HistoryGrid == null or EmptyLabel == null:
		return
	for child in HistoryGrid.get_children():
		child.queue_free()
	HistoryButtons.clear()
	EmptyLabel.visible = ClipboardHistory.is_empty()
	HistoryGrid.visible = not ClipboardHistory.is_empty()
	for index in ClipboardHistory.size():
		var itemButton := buildHistoryItem(index, ClipboardHistory[index])
		HistoryButtons.append(itemButton)
		HistoryGrid.add_child(itemButton)

func buildHistoryItem(index: int, item: Dictionary) -> Button:
	var itemButton := Button.new()
	itemButton.name = "ClipboardItem%d" % index
	itemButton.toggle_mode = true
	itemButton.custom_minimum_size = Vector2(0, 80)
	itemButton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	itemButton.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	itemButton.add_theme_stylebox_override("normal", makeBox(FieldBackgroundColor, 4, SectionBorderColor))
	itemButton.add_theme_stylebox_override("hover", makeBox(ControlHoverColor, 4, SectionBorderColor))
	itemButton.add_theme_stylebox_override("pressed", makeBox(FieldBackgroundColor, 4, ActiveAccentColor))
	itemButton.add_theme_stylebox_override("hover_pressed", makeBox(ControlHoverColor, 4, ActiveAccentColor))
	itemButton.set_pressed_no_signal(index == SelectedClipboardIndex)
	itemButton.pressed.connect(selectClipboardItem.bind(index))

	var itemMargin := MarginContainer.new()
	itemMargin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	itemMargin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	itemMargin.add_theme_constant_override("margin_left", 5)
	itemMargin.add_theme_constant_override("margin_top", 5)
	itemMargin.add_theme_constant_override("margin_right", 5)
	itemMargin.add_theme_constant_override("margin_bottom", 5)
	itemButton.add_child(itemMargin)
	var itemContent := HBoxContainer.new()
	itemContent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	itemContent.add_theme_constant_override("separation", 7)
	itemMargin.add_child(itemContent)
	var tiles := getPreviewTiles(item)
	var dimensions := getClipboardDimensions(item, tiles)
	var preview := ClipboardPreview.new()
	preview.name = "ClipboardPreview"
	preview.custom_minimum_size = Vector2(58, 58)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.setPreview(tiles, dimensions)
	itemContent.add_child(preview)
	var itemText := VBoxContainer.new()
	itemText.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	itemText.alignment = BoxContainer.ALIGNMENT_CENTER
	itemText.mouse_filter = Control.MOUSE_FILTER_IGNORE
	itemText.add_theme_constant_override("separation", 2)
	itemContent.add_child(itemText)
	var itemTitle := Label.new()
	itemTitle.name = "ClipboardItemTitle"
	itemTitle.text = "Selection %d" % (index + 1)
	itemTitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	itemTitle.add_theme_color_override("font_color", PrimaryTextColor)
	itemTitle.add_theme_font_size_override("font_size", 14)
	itemText.add_child(itemTitle)
	var itemDetails := Label.new()
	itemDetails.name = "ClipboardItemDetails"
	itemDetails.text = "%d x %d | %d tiles" % [dimensions.x, dimensions.y, tiles.size()]
	itemDetails.mouse_filter = Control.MOUSE_FILTER_IGNORE
	itemDetails.add_theme_color_override("font_color", MutedTextColor)
	itemDetails.add_theme_font_size_override("font_size", 13)
	itemText.add_child(itemDetails)
	return itemButton

func selectClipboardItem(index: int) -> void:
	if index < 0 or index >= ClipboardHistory.size():
		return
	SelectedClipboardIndex = index
	for buttonIndex in HistoryButtons.size():
		HistoryButtons[buttonIndex].set_pressed_no_signal(buttonIndex == SelectedClipboardIndex)
	clipboardItemSelected.emit(SelectedClipboardIndex)

func getClipboardDimensions(item: Dictionary, tiles: Array[Dictionary]) -> Vector2i:
	var bounds: Variant = item.get("bounds", null)
	if bounds is Rect2i:
		return Vector2i(maxi(1, bounds.size.x), maxi(1, bounds.size.y))
	if bounds is Dictionary:
		var boundsSize := getVector2i(bounds.get("size", Vector2i.ZERO))
		if boundsSize.x > 0 and boundsSize.y > 0:
			return boundsSize
	for key in ["boundsSize", "size", "dimensions"]:
		var value := getVector2i(item.get(key, Vector2i.ZERO))
		if value.x > 0 and value.y > 0:
			return value
	var width := int(item.get("width", 0))
	var height := int(item.get("height", 0))
	if width > 0 and height > 0:
		return Vector2i(width, height)
	var largestOffset := Vector2i.ZERO
	for tile in tiles:
		var offset: Vector2i = tile.get("offset", Vector2i.ZERO)
		largestOffset = Vector2i(maxi(largestOffset.x, offset.x), maxi(largestOffset.y, offset.y))
	return largestOffset + Vector2i.ONE

func getPreviewTiles(item: Dictionary) -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	var rawTiles: Variant = item.get("tiles", item.get("cells", []))
	if not rawTiles is Array:
		return tiles
	var boundsPosition := getBoundsPosition(item)
	for rawTile in rawTiles:
		if not rawTile is Dictionary:
			continue
		var tile: Dictionary = rawTile
		var offset := getVector2i(tile.get("offset", tile.get("position", Vector2i.ZERO)))
		if not tile.has("offset"):
			offset -= boundsPosition
		tiles.append({"offset": offset, "color": getTileColor(tile)})
	return tiles

func getBoundsPosition(item: Dictionary) -> Vector2i:
	var bounds: Variant = item.get("bounds", null)
	if bounds is Rect2i:
		return bounds.position
	if bounds is Dictionary:
		return getVector2i(bounds.get("position", Vector2i.ZERO))
	return getVector2i(item.get("origin", Vector2i.ZERO))

func getVector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO

func getTileColor(tile: Dictionary) -> Color:
	var color: Variant = tile.get("color", null)
	var toolId := String(tile.get("toolId", ""))
	var defaultIsOn := InkRegistry.getDefaultIsOn(toolId)
	if color is Color:
		return CircuitTile.getTopColor(color, bool(tile.get("isOn", defaultIsOn)))
	var ink := InkRegistry.getInk(toolId)
	if not ink.is_empty():
		return CircuitTile.getTopColor(ink.color, bool(tile.get("isOn", defaultIsOn)))
	return MutedTextColor

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
