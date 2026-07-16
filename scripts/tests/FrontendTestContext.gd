extends RefCounted
class_name FrontendTestContext

const CircuitTile := preload("res://scripts/CircuitTile.gd")
const MainScene := preload("res://Main.tscn")

const BoardPath := NodePath("BoardViewport/SubViewport/CircuitBoard")
const BoardViewportPath := NodePath("BoardViewport")
const SubViewportPath := NodePath("BoardViewport/SubViewport")
const CameraPath := NodePath("BoardViewport/SubViewport/BoardCamera")
const InterfacePath := NodePath("Interface")
const TopBarPath := NodePath("Interface/TopBar")
const ProjectContentPath := NodePath("Interface/TopBar/ProjectContent")
const TopBarContentPath := NodePath("Interface/TopBar/Content")

var ContextTree: SceneTree
var RootWindow: Window
var MainSceneRoot: Control
var CircuitBoard: Node2D
var BoardViewport: SubViewportContainer
var BoardSubViewport: SubViewport
var BoardCamera: Camera2D
var InterfaceLayer: CanvasLayer
var TopBar: Control
var ProjectContent: Control
var TopBarContent: Control
var TestData: Dictionary = {}

func _init(sceneTree: SceneTree) -> void:
	ContextTree = sceneTree
	RootWindow = ContextTree.root

func resetMain(frameCount := 5) -> Control:
	assert(ContextTree != null)
	RootWindow = ContextTree.root
	assert(RootWindow != null)
	var previousMain := MainSceneRoot
	clearNodeRefs()
	if is_instance_valid(previousMain):
		previousMain.queue_free()
		await waitFrames(1)
	MainSceneRoot = MainScene.instantiate() as Control
	assert(MainSceneRoot != null)
	RootWindow.size = getConfiguredViewportSize()
	RootWindow.add_child(MainSceneRoot)
	await waitFrames(frameCount)
	cacheNodeRefs()
	return MainSceneRoot

func clearNodeRefs() -> void:
	MainSceneRoot = null
	CircuitBoard = null
	BoardViewport = null
	BoardSubViewport = null
	BoardCamera = null
	InterfaceLayer = null
	TopBar = null
	ProjectContent = null
	TopBarContent = null
	TestData.clear()

func cacheNodeRefs() -> void:
	CircuitBoard = getMainNode(BoardPath) as Node2D
	BoardViewport = getMainNode(BoardViewportPath) as SubViewportContainer
	BoardSubViewport = getMainNode(SubViewportPath) as SubViewport
	BoardCamera = getMainNode(CameraPath) as Camera2D
	InterfaceLayer = getMainNode(InterfacePath) as CanvasLayer
	TopBar = getMainNode(TopBarPath) as Control
	ProjectContent = getMainNode(ProjectContentPath) as Control
	TopBarContent = getMainNode(TopBarContentPath) as Control
	assert(CircuitBoard != null)
	assert(BoardViewport != null)
	assert(BoardSubViewport != null)
	assert(BoardCamera != null)
	assert(InterfaceLayer != null)
	assert(TopBar != null)
	assert(ProjectContent != null)
	assert(TopBarContent != null)
	TestData = {
		"main": MainSceneRoot,
		"board": CircuitBoard,
		"boardViewport": BoardViewport,
		"subViewport": BoardSubViewport,
		"camera": BoardCamera,
		"interfaceLayer": InterfaceLayer,
		"topBar": TopBar,
		"projectContent": ProjectContent,
		"topBarContent": TopBarContent,
	}

func getMainNode(path: NodePath) -> Node:
	assert(MainSceneRoot != null)
	var node := MainSceneRoot.get_node_or_null(path)
	assert(node != null, "Missing main-scene node: %s" % path)
	return node

func getNodeRef(path: NodePath) -> Node:
	return getMainNode(path)

func getConfiguredViewportSize() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width")),
		int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	)

func waitFrames(frameCount := 1) -> void:
	for frame in range(maxi(frameCount, 0)):
		await ContextTree.process_frame

func waitSeconds(seconds: float) -> void:
	if seconds > 0.0:
		await ContextTree.create_timer(seconds).timeout

func saveBoardCapture(outputPath := "user://capture.png") -> int:
	assert(BoardSubViewport != null)
	var image := BoardSubViewport.get_texture().get_image()
	if image == null:
		push_error("The subviewport image is unavailable.")
		return FAILED
	return image.save_png(outputPath)

func saveInterfaceCapture(outputPath: String) -> int:
	assert(MainSceneRoot != null)
	var image := MainSceneRoot.get_viewport().get_texture().get_image()
	if image == null:
		push_error("The interface image is unavailable.")
		return FAILED
	return image.save_png(outputPath)

func getUserArgs() -> PackedStringArray:
	return OS.get_cmdline_user_args()

func hasArg(argument: String) -> bool:
	return getUserArgs().has(argument)

func getArgValue(argumentName: String, defaultValue := "") -> String:
	var prefix := "%s=" % argumentName
	for argument in getUserArgs():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return defaultValue

func getFloatArg(argumentName: String, defaultValue: float) -> float:
	var value := getArgValue(argumentName)
	return value.to_float() if not value.is_empty() else defaultValue

func getDockForSide(targetMain: Control, dockSide: String) -> Control:
	assert(targetMain.has_method("getDockForSide"))
	var dock := targetMain.call("getDockForSide", dockSide) as Control
	assert(dock != null)
	return dock

func getDockHostForSide(targetMain: Control, dockSide: String) -> Control:
	assert(targetMain.has_method("getDockHostForSide"))
	var dockHost := targetMain.call("getDockHostForSide", dockSide) as Control
	assert(dockHost != null)
	return dockHost

func getActiveDockState(targetMain: Control, dockId: String) -> Dictionary:
	for dockSide in ["left", "right"]:
		var dock := getDockForSide(targetMain, dockSide)
		if String(dock.get("DockId")) == dockId:
			return {
				"dock": dock,
				"dockHost": getDockHostForSide(targetMain, dockSide),
				"dockSide": dockSide,
			}
	return {}

func assertDualDockState(targetMain: Control) -> Dictionary:
	assert(targetMain.get_node_or_null("Interface/RightDock") == null)
	assert(targetMain.get_node_or_null("Interface/RightDockHost") != null)
	var leftDock := getDockForSide(targetMain, "left")
	var rightDock := getDockForSide(targetMain, "right")
	var leftDockHost := getDockHostForSide(targetMain, "left")
	var rightDockHost := getDockHostForSide(targetMain, "right")
	assert(leftDock != rightDock)
	assert(not String(leftDock.get("DockId")).is_empty())
	assert(not String(rightDock.get("DockId")).is_empty())
	assert(String(leftDock.get("DockId")) != String(rightDock.get("DockId")))
	assert(leftDockHost.get_child_count() == 1)
	assert(rightDockHost.get_child_count() == 1)
	assert(leftDockHost.get_child(0) == leftDock)
	assert(rightDockHost.get_child(0) == rightDock)
	assertDockLayout(leftDockHost, leftDock)
	assertDockLayout(rightDockHost, rightDock)
	return {
		"leftDock": leftDock,
		"rightDock": rightDock,
		"leftDockHost": leftDockHost,
		"rightDockHost": rightDockHost,
	}

func assertDockMenuFitsViewport(dockMenu: PopupPanel) -> void:
	assert(RootWindow != null)
	assert(dockMenu.visible)
	assert(dockMenu.position.x >= 0)
	assert(dockMenu.position.y >= 0)
	assert(dockMenu.position.x + dockMenu.size.x <= RootWindow.size.x)
	assert(dockMenu.position.y + dockMenu.size.y <= RootWindow.size.y)

func assertDualDockSwap(targetMain: Control, dockMenu: PopupPanel, dockMenuGrid: GridContainer) -> void:
	targetMain.call("activateDock", "circuitEditor", "left")
	await waitFrames()
	targetMain.call("activateDock", "clipboard", "right")
	await waitFrames()
	var initialState := assertDualDockState(targetMain)
	assert(String((initialState.get("leftDock") as Control).get("DockId")) == "circuitEditor")
	assert(String((initialState.get("rightDock") as Control).get("DockId")) == "clipboard")
	var clipboardMenuButton := findDockMenuButton(dockMenuGrid, "Clipboard")
	assert(clipboardMenuButton != null)

	var leftDockMenuButton := (initialState.get("leftDock") as Control).get("DockMenuButton") as Button
	assertIconButton(leftDockMenuButton)
	leftDockMenuButton.emit_signal("pressed")
	await waitFrames()
	assertDockMenuFitsViewport(dockMenu)
	assert(String(targetMain.get("DockMenuTargetSide")) == "left")
	clipboardMenuButton.emit_signal("pressed")
	await waitFrames()
	var swappedState := assertDualDockState(targetMain)
	assert(String((swappedState.get("leftDock") as Control).get("DockId")) == "clipboard")
	assert(String((swappedState.get("rightDock") as Control).get("DockId")) == "circuitEditor")

	var rightDockMenuButton := (swappedState.get("rightDock") as Control).get("DockMenuButton") as Button
	assertIconButton(rightDockMenuButton)
	rightDockMenuButton.emit_signal("pressed")
	await waitFrames()
	assertDockMenuFitsViewport(dockMenu)
	assert(String(targetMain.get("DockMenuTargetSide")) == "right")
	clipboardMenuButton.emit_signal("pressed")
	await waitFrames()
	var restoredState := assertDualDockState(targetMain)
	assert(String((restoredState.get("leftDock") as Control).get("DockId")) == "circuitEditor")
	assert(String((restoredState.get("rightDock") as Control).get("DockId")) == "clipboard")
	dockMenu.hide()

func assertHoveredInkForCanvasTile(targetBoard: Node2D, circuitEditorDock: Control, coordinates: Vector2i) -> void:
	assert(targetBoard.has_method("getInkAt"))
	assert(circuitEditorDock.has_method("updateCursorInfo"))
	var hoveredInk := targetBoard.call("getInkAt", coordinates) as Dictionary
	assert(String(hoveredInk.get("toolId", "")) == "xor")
	assert(String(hoveredInk.get("title", "")) == "Xor")
	circuitEditorDock.call("updateCursorInfo", coordinates, true, String(hoveredInk.get("title", "")))
	var hoveredInkLabel := circuitEditorDock.get("HoveredInkLabel") as Label
	assert(hoveredInkLabel != null)
	assert(hoveredInkLabel.text == "Xor")
	circuitEditorDock.call("updateCursorInfo", coordinates, false, String(hoveredInk.get("title", "")))
	assert(hoveredInkLabel.text == "None")

func assertCanvasViewIsStable(targetBoardViewport: SubViewportContainer, targetSubViewport: SubViewport, targetCamera: Camera2D, expectedRect: Rect2, expectedSize: Vector2i, expectedCenter: Vector2, expectedZoom: Vector2) -> void:
	var actualRect := targetBoardViewport.get_global_rect()
	assert(actualRect.position.is_equal_approx(expectedRect.position))
	assert(actualRect.size.is_equal_approx(expectedRect.size))
	assert(targetSubViewport.size == expectedSize)
	assert(targetCamera.get_screen_center_position().is_equal_approx(expectedCenter))
	assert(targetCamera.zoom.is_equal_approx(expectedZoom))

func assertSidebarControlsFit(contentRoot: Control) -> void:
	var contentRect := contentRoot.get_global_rect()
	for child in contentRoot.find_children("*", "Control", true, false):
		var control := child as Control
		if control == null or not control.visible:
			continue
		var controlRect := control.get_global_rect()
		assert(controlRect.position.x >= contentRect.position.x - 0.5)
		assert(controlRect.end.x <= contentRect.end.x + 0.5)
		assert(control.get_combined_minimum_size().x <= control.size.x + 0.5)

func assertDockLayout(dockHost: Control, dock: Control) -> void:
	var contentRoot := dock.get_node("Background/ContentFrame/ContentRoot") as VBoxContainer
	assert(dock.find_children("*", "ScrollContainer", true, false).is_empty())
	assert(contentRoot.size.y >= contentRoot.get_combined_minimum_size().y)
	var dockRect := dockHost.get_global_rect()
	var contentRect := contentRoot.get_global_rect()
	assert(contentRect.position.x >= dockRect.position.x + 8.0 - 0.5)
	assert(contentRect.end.x <= dockRect.end.x - 8.0 + 0.5)
	assertSidebarControlsFit(contentRoot)

func findDockDefinition(definitions: Array[Dictionary], dockId: String) -> Dictionary:
	for definition in definitions:
		if String(definition.get("dockId", "")) == dockId:
			return definition
	return {}

func findDockMenuButton(grid: GridContainer, dockTitle: String) -> Button:
	for buttonNode in grid.get_children():
		var button := buttonNode as Button
		if button and button.tooltip_text == dockTitle:
			return button
	return null

func assertIconButton(button: Button) -> void:
	assert(button != null)
	assert(button.icon != null)
	assert(not button.expand_icon)
	assert(button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER)
	assert(button.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER)
	assert(button.icon.get_size() == Vector2(16, 16))

func assertTopBarIconButtonStyle(button: Button) -> void:
	assertIconButton(button)
	var normalStyle := button.get_theme_stylebox("normal") as StyleBoxFlat
	var hoverStyle := button.get_theme_stylebox("hover") as StyleBoxFlat
	var pressedStyle := button.get_theme_stylebox("pressed") as StyleBoxFlat
	var hoverPressedStyle := button.get_theme_stylebox("hover_pressed") as StyleBoxFlat
	assert(normalStyle != null)
	assert(hoverStyle != null)
	assert(pressedStyle != null)
	assert(hoverPressedStyle != null)
	assert(pressedStyle.bg_color.is_equal_approx(Color.TRANSPARENT))
	assert(hoverPressedStyle.bg_color.is_equal_approx(hoverStyle.bg_color))
	assert(is_equal_approx(normalStyle.content_margin_left, pressedStyle.content_margin_left))
	assert(is_equal_approx(normalStyle.content_margin_top, pressedStyle.content_margin_top))
	assert(is_equal_approx(normalStyle.content_margin_right, pressedStyle.content_margin_right))
	assert(is_equal_approx(normalStyle.content_margin_bottom, pressedStyle.content_margin_bottom))
	assert(button.get_theme_color("icon_pressed_color").is_equal_approx(Color("f2c94c")))
	assert(button.get_theme_color("icon_hover_pressed_color").is_equal_approx(Color("f2c94c")))

func assertInkButton(button: Button, ink: Dictionary, isSelected: bool) -> void:
	assert(button != null)
	assert(button.icon == null)
	assert(button.toggle_mode)
	assert(is_equal_approx(button.custom_minimum_size.x, button.custom_minimum_size.y))
	assert(button.button_pressed == isSelected)
	var inkColor: Color = ink.get("color", Color.WHITE)
	var pressedStyle := button.get_theme_stylebox("pressed") as StyleBoxFlat
	assert(pressedStyle != null)
	assert(pressedStyle.bg_color.is_equal_approx(inkColor))
	var icon := button.get_node("InkIcon") as TextureRect
	var expectedIcon := ink.get("icon") as Texture2D
	assert(icon != null)
	assert(expectedIcon != null)
	assert(icon.texture == expectedIcon)
	assert(expectedIcon.get_size() == Vector2(64, 64))
	assert(icon.expand_mode == TextureRect.EXPAND_IGNORE_SIZE)
	assert(icon.stretch_mode == TextureRect.STRETCH_SCALE)
	var expectedIconColor: Color = Color("111a26") if isSelected else inkColor
	assert(icon.modulate.is_equal_approx(expectedIconColor))
	var variantIndicator := button.get_node_or_null("VariantIndicator") as Control
	var hasContextMenu := bool(button.get("IsExpandable")) or bool(button.get("IsConfigurable"))
	assert((variantIndicator != null) == hasContextMenu)
	if variantIndicator:
		assert(variantIndicator.mouse_filter == Control.MOUSE_FILTER_IGNORE)
		var expectedIndicatorColor := Color("111a26") if isSelected else Color("b4c1d3")
		var actualIndicatorColor: Color = variantIndicator.get("IndicatorColor")
		assert(actualIndicatorColor.is_equal_approx(expectedIndicatorColor))
		var buttonRect := button.get_global_rect()
		var indicatorRect := variantIndicator.get_global_rect()
		assert(indicatorRect.position.x >= buttonRect.get_center().x)
		assert(indicatorRect.position.y >= buttonRect.get_center().y)
		assert(indicatorRect.end.x <= buttonRect.end.x + 0.5)
		assert(indicatorRect.end.y <= buttonRect.end.y + 0.5)

func assertTileIcon(tile: Node2D, ink: Dictionary, cellSize: float, isOn := true) -> void:
	var iconRect := tile.get_node("Icon") as TextureRect
	var expectedIcon := ink.get("icon") as Texture2D
	var inkColor: Color = ink.get("color", Color.WHITE)
	assert(iconRect != null)
	assert(expectedIcon != null)
	assert(iconRect.visible)
	assert(iconRect.texture == expectedIcon)
	assert(iconRect.size.is_equal_approx(Vector2.ONE * cellSize))
	assert(iconRect.position.is_equal_approx(-iconRect.size / 2.0))
	assert(iconRect.stretch_mode == TextureRect.STRETCH_SCALE)
	assert(bool(tile.get("IsOn")) == isOn)
	assert(iconRect.modulate.is_equal_approx(CircuitTile.getIconColor(inkColor, isOn)))
	var baseBlock := tile.get_node("BaseBlock") as TextureRect
	var baseMaterial := baseBlock.material as ShaderMaterial
	assert(baseMaterial != null)
	var topColor: Color = baseMaterial.get_shader_parameter("TopColor")
	var sideShadowColor: Color = baseMaterial.get_shader_parameter("SideShadowColor")
	assert(topColor.is_equal_approx(CircuitTile.getTopColor(inkColor, isOn)))
	assert(sideShadowColor.is_equal_approx(CircuitTile.getSideShadowColor(inkColor, isOn)))

func assertSharedTileGeometry(firstTile: Node2D, secondTile: Node2D) -> void:
	var firstBase := firstTile.get_node("BaseBlock") as TextureRect
	var firstShadow := firstTile.get_node("ShadowBlock") as TextureRect
	var secondBase := secondTile.get_node("BaseBlock") as TextureRect
	var secondShadow := secondTile.get_node("ShadowBlock") as TextureRect
	assert(firstBase.texture != null)
	assert(firstBase.texture == firstShadow.texture)
	assert(firstBase.texture == secondBase.texture)
	assert(firstBase.texture == secondShadow.texture)

func assertClipboardDock(dockHost: Control, clipboardDock: Control, expectedHistory: Array, expectedSelectedIndex: int) -> void:
	assert(String(clipboardDock.get("DockId")) == "clipboard")
	assertDockLayout(dockHost, clipboardDock)
	var dockIcon := clipboardDock.get("DockIcon") as Texture2D
	assert(dockIcon != null)
	assert(dockIcon.get_size() == Vector2(16, 16))
	var dockMenuButton := clipboardDock.get("DockMenuButton") as Button
	assertIconButton(dockMenuButton)
	var historyGrid := clipboardDock.find_child("ClipboardHistory", true, false) as GridContainer
	var emptyHistoryLabel := clipboardDock.find_child("EmptyClipboardHistory", true, false) as Label
	assert(historyGrid != null)
	assert(emptyHistoryLabel != null)
	assert(historyGrid.columns == 1)
	assert((clipboardDock.get("ClipboardHistory") as Array).size() == expectedHistory.size())
	assert(int(clipboardDock.get("SelectedClipboardIndex")) == expectedSelectedIndex)
	assert(historyGrid.get_child_count() == expectedHistory.size())
	assert(historyGrid.visible == not expectedHistory.is_empty())
	assert(emptyHistoryLabel.visible == expectedHistory.is_empty())
	for index in expectedHistory.size():
		var expectedItem: Dictionary = expectedHistory[index]
		var itemButton := historyGrid.get_child(index) as Button
		assert(itemButton != null)
		var itemTitle := itemButton.find_child("ClipboardItemTitle", true, false) as Label
		var itemDetails := itemButton.find_child("ClipboardItemDetails", true, false) as Label
		var preview := itemButton.find_child("ClipboardPreview", true, false) as Control
		assert(itemTitle != null)
		assert(itemDetails != null)
		assert(preview != null)
		assert(itemButton.toggle_mode)
		assert(itemButton.button_pressed == (index == expectedSelectedIndex))
		assert(itemButton.size_flags_vertical == Control.SIZE_SHRINK_BEGIN)
		assert(itemButton.custom_minimum_size.y <= 80.0)
		assert(itemButton.get_global_rect().size.x >= historyGrid.get_global_rect().size.x - 0.5)
		assert(itemTitle.text == "Selection %d" % (index + 1))
		var boundsSize: Vector2i = expectedItem.get("boundsSize", Vector2i.ZERO)
		var tileCount := (expectedItem.get("tiles", []) as Array).size()
		assert(itemDetails.text.contains("%d x %d" % [boundsSize.x, boundsSize.y]))
		assert(itemDetails.text.contains("%d tiles" % tileCount))
		assert(preview.custom_minimum_size.x <= 58.0)
		assert(preview.custom_minimum_size.y <= 58.0)

func sendCtrlShortcut(targetBoard: Node2D, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.ctrl_pressed = true
	event.keycode = keycode
	targetBoard.call("handleKeyInput", event)

func makeMouseButtonEvent(target: Control, buttonIndex: MouseButton, isPressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	var pointerPosition := target.get_global_rect().get_center()
	event.button_index = buttonIndex
	event.pressed = isPressed
	event.position = pointerPosition
	event.global_position = pointerPosition
	return event

func makeMouseMotionEvent(position: Vector2, buttonMask := 0) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = buttonMask
	return event

func assertPastePreviewAllowsCameraPan(targetBoard: Node2D, targetCamera: Camera2D) -> void:
	assert(targetBoard.has_method("updatePastePreviewAtPointer"))
	var initialCameraPosition := targetCamera.global_position
	var pressEvent := InputEventMouseButton.new()
	pressEvent.button_index = MOUSE_BUTTON_MIDDLE
	pressEvent.pressed = true
	pressEvent.position = Vector2(480, 300)
	targetCamera.call("_unhandled_input", pressEvent)
	var motionEvent := makeMouseMotionEvent(Vector2(432, 300), MOUSE_BUTTON_MASK_MIDDLE)
	var pasteAnchorBefore: Vector2i = targetBoard.get("PasteAnchorCoordinates")
	targetBoard.call("handleMouseMotion", motionEvent)
	assert((targetBoard.get("PasteAnchorCoordinates") as Vector2i) == pasteAnchorBefore)
	targetCamera.call("_unhandled_input", motionEvent)
	assert(not targetCamera.global_position.is_equal_approx(initialCameraPosition))
	var clipboardItem: Dictionary = targetBoard.call("getClipboardItem")
	assert((targetBoard.get_node("PreviewTiles") as Node2D).get_child_count() == (clipboardItem.get("tiles", []) as Array).size())
	var releaseEvent := InputEventMouseButton.new()
	releaseEvent.button_index = MOUSE_BUTTON_MIDDLE
	releaseEvent.pressed = false
	releaseEvent.position = motionEvent.position
	targetCamera.call("_unhandled_input", releaseEvent)
	targetCamera.global_position = initialCameraPosition
	targetCamera.force_update_scroll()
