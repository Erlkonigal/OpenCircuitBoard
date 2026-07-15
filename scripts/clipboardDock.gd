extends "res://scripts/dockView.gd"

signal dockMenuRequested(menuButton: Button)
signal clipboardItemSelected(index: int)

const InkRegistry := preload("res://scripts/inkRegistry.gd")
const clipboardIcon := preload("res://assets/clipboard.svg")
const dockIconSize := 16
const maximumHistoryItems := 4
const sidebarBackgroundColor := Color("131c28")
const sectionBackgroundColor := Color("1a2432")
const sectionBorderColor := Color("26364a")
const fieldBackgroundColor := Color("111a26")
const primaryTextColor := Color("b4c1d3")
const mutedTextColor := Color("75859b")
const controlHoverColor := Color("26364a")
const activeAccentColor := Color("f2c94c")

class ClipboardPreview extends Control:
	var previewTiles: Array[Dictionary] = []
	var dimensions := Vector2i.ONE

	func setPreview(nextTiles: Array[Dictionary], nextDimensions: Vector2i) -> void:
		previewTiles.clear()
		previewTiles.append_array(nextTiles)
		dimensions = Vector2i(maxi(1, nextDimensions.x), maxi(1, nextDimensions.y))
		queue_redraw()

	func _draw() -> void:
		if previewTiles.is_empty():
			return
		var availableSize := size - Vector2(8.0, 8.0)
		var cellLength := minf(availableSize.x / float(dimensions.x), availableSize.y / float(dimensions.y))
		cellLength = maxf(2.0, cellLength)
		var previewSize := Vector2(dimensions) * cellLength
		var previewOrigin := (size - previewSize) * 0.5
		for tile in previewTiles:
			var offset: Vector2i = tile.get("offset", Vector2i.ZERO)
			if offset.x < 0 or offset.y < 0 or offset.x >= dimensions.x or offset.y >= dimensions.y:
				continue
			var tileRect := Rect2(previewOrigin + Vector2(offset) * cellLength, Vector2.ONE * cellLength)
			var inset := minf(1.5, cellLength * 0.2)
			draw_rect(tileRect.grow(-inset), tile.get("color", mutedTextColor), true)
			draw_rect(tileRect.grow(-inset), Color("0b1119"), false, 1.0)
		draw_rect(Rect2(previewOrigin, previewSize), sectionBorderColor, false, 1.0)

var clipboardHistory: Array[Dictionary] = []
var selectedClipboardIndex := -1
var dockMenuButton: Button
var historyGrid: GridContainer
var emptyLabel: Label
var historyButtons: Array[Button] = []

func _init() -> void:
	dockId = "clipboard"
	dockTitle = "Clipboard"
	dockWidth = 272.0
	dockIcon = clipboardIcon

func _ready() -> void:
	buildDock()
	refreshClipboardHistory()

func setClipboardHistory(history: Array[Dictionary], selectedIndex: int) -> void:
	clipboardHistory.clear()
	for item in history:
		if clipboardHistory.size() >= maximumHistoryItems:
			break
		clipboardHistory.append(item.duplicate(true))
	selectedClipboardIndex = selectedIndex if selectedIndex >= 0 and selectedIndex < clipboardHistory.size() else -1
	refreshClipboardHistory()

func setClipboardItem(item: Dictionary) -> void:
	if item.is_empty():
		setClipboardHistory([], -1)
		return
	setClipboardHistory([item], 0)

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
	root.add_child(buildClipboardSection())

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

func buildClipboardSection() -> Control:
	var panel := PanelContainer.new()
	panel.name = "clipboardSection"
	panel.add_theme_stylebox_override("panel", makeBox(sectionBackgroundColor, 5, sectionBorderColor))
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
	sectionTitle.add_theme_color_override("font_color", primaryTextColor)
	sectionTitle.add_theme_font_size_override("font_size", 16)
	content.add_child(sectionTitle)

	emptyLabel = Label.new()
	emptyLabel.name = "emptyClipboardHistory"
	emptyLabel.text = "NoClipboardItems"
	emptyLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emptyLabel.add_theme_color_override("font_color", mutedTextColor)
	emptyLabel.add_theme_font_size_override("font_size", 15)
	emptyLabel.custom_minimum_size = Vector2(0, 48)
	emptyLabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(emptyLabel)

	historyGrid = GridContainer.new()
	historyGrid.name = "clipboardHistory"
	historyGrid.columns = 1
	historyGrid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	historyGrid.add_theme_constant_override("h_separation", 4)
	historyGrid.add_theme_constant_override("v_separation", 4)
	content.add_child(historyGrid)
	return panel

func refreshClipboardHistory() -> void:
	if historyGrid == null or emptyLabel == null:
		return
	for child in historyGrid.get_children():
		child.queue_free()
	historyButtons.clear()
	emptyLabel.visible = clipboardHistory.is_empty()
	historyGrid.visible = not clipboardHistory.is_empty()
	for index in clipboardHistory.size():
		var itemButton := buildHistoryItem(index, clipboardHistory[index])
		historyButtons.append(itemButton)
		historyGrid.add_child(itemButton)

func buildHistoryItem(index: int, item: Dictionary) -> Button:
	var itemButton := Button.new()
	itemButton.name = "clipboardItem%d" % index
	itemButton.toggle_mode = true
	itemButton.custom_minimum_size = Vector2(0, 80)
	itemButton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	itemButton.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	itemButton.add_theme_stylebox_override("normal", makeBox(fieldBackgroundColor, 4, sectionBorderColor))
	itemButton.add_theme_stylebox_override("hover", makeBox(controlHoverColor, 4, sectionBorderColor))
	itemButton.add_theme_stylebox_override("pressed", makeBox(fieldBackgroundColor, 4, activeAccentColor))
	itemButton.add_theme_stylebox_override("hover_pressed", makeBox(controlHoverColor, 4, activeAccentColor))
	itemButton.set_pressed_no_signal(index == selectedClipboardIndex)
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
	preview.name = "clipboardPreview"
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
	itemTitle.name = "clipboardItemTitle"
	itemTitle.text = "Selection %d" % (index + 1)
	itemTitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	itemTitle.add_theme_color_override("font_color", primaryTextColor)
	itemTitle.add_theme_font_size_override("font_size", 14)
	itemText.add_child(itemTitle)
	var itemDetails := Label.new()
	itemDetails.name = "clipboardItemDetails"
	itemDetails.text = "%d x %d | %d tiles" % [dimensions.x, dimensions.y, tiles.size()]
	itemDetails.mouse_filter = Control.MOUSE_FILTER_IGNORE
	itemDetails.add_theme_color_override("font_color", mutedTextColor)
	itemDetails.add_theme_font_size_override("font_size", 13)
	itemText.add_child(itemDetails)
	return itemButton

func selectClipboardItem(index: int) -> void:
	if index < 0 or index >= clipboardHistory.size():
		return
	selectedClipboardIndex = index
	for buttonIndex in historyButtons.size():
		historyButtons[buttonIndex].set_pressed_no_signal(buttonIndex == selectedClipboardIndex)
	clipboardItemSelected.emit(selectedClipboardIndex)

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
	if color is Color:
		return color
	var ink := InkRegistry.getInk(String(tile.get("toolId", "")))
	if not ink.is_empty():
		return ink.color
	return mutedTextColor

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
