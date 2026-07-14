extends SceneTree

func _init() -> void:
	call_deferred("captureBoard")

func getCaptureZoom() -> float:
	var captureZoom := 1.25
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captureZoom="):
			captureZoom = maxf(argument.trim_prefix("--captureZoom=").to_float(), 0.01)
	return captureZoom

func shouldCaptureSelector() -> bool:
	return OS.get_cmdline_user_args().has("--captureSelector")

func shouldCaptureBoardEdge() -> bool:
	return OS.get_cmdline_user_args().has("--captureBoardEdge")

func shouldCaptureInterface() -> bool:
	return OS.get_cmdline_user_args().has("--captureInterface")

func captureBoard() -> void:
	var mainScene := load("res://main.tscn") as PackedScene
	var main := mainScene.instantiate()
	root.add_child(main)
	for frame in 5:
		await process_frame

	var board := main.get_node("BoardViewport/SubViewport/CircuitBoard") as Node2D
	var dockHost := main.get_node("Interface/DockHost") as Control
	assert(dockHost.get_child_count() == 1)
	var circuitEditorDock := dockHost.get_child(0) as Control
	assert(circuitEditorDock.get("dockId") == "circuitEditor")
	var dockMenu := main.get("dockMenu") as PopupPanel
	assert(dockMenu.get_child_count() == 1)
	assert(dockMenu.get_child(0).get_child_count() == 1)
	var inkButtons: Dictionary = circuitEditorDock.get("inkButtons")
	assert(inkButtons.size() == 19)
	var toolRegistry: Dictionary = board.get("toolRegistry")
	assert(toolRegistry.size() == 19)
	for toolId in ["cross", "tunnel", "mesh", "bus", "read", "write", "trace", "buffer", "and", "or", "xor", "not", "nand", "nor", "xnor", "latchOn", "latchOff", "clock", "led"]:
		assert(toolRegistry.has(toolId))
	var camera := main.get_node("BoardViewport/SubViewport/BoardCamera") as Camera2D
	var boardBounds: Rect2 = board.get("validRect")
	board.set_process(false)
	# Place the right tile first so the capture verifies X-based depth ordering.
	board.call("placeTile", Vector2i(1, 0))
	board.call("selectTool", "xor")
	board.call("placeTile", Vector2i(0, 0))
	board.call("selectTool", "trace")
	board.call("placeTile", Vector2i(-1, 1))
	# Keep an isolated tile in view to inspect the full shadow silhouette.
	board.call("selectTool", "or")
	board.call("placeTile", Vector2i(4, -2))
	var occupancy: Dictionary = board.get("occupancy")
	var rightTile := occupancy[Vector2i(1, 0)] as Node2D
	var leftTile := occupancy[Vector2i(0, 0)] as Node2D
	assert(leftTile.z_index > rightTile.z_index)
	var selector := board.get_node("Selector") as ColorRect
	selector.visible = shouldCaptureSelector()
	if selector.visible:
		selector.position = Vector2(8, -8) * float(board.get("cellSize"))
	camera.zoom = Vector2.ONE * getCaptureZoom()
	if shouldCaptureBoardEdge():
		camera.global_position = boardBounds.position
	for frame in 5:
		await process_frame
	if shouldCaptureBoardEdge():
		assert(is_equal_approx(camera.global_position.x, boardBounds.position.x))
		assert(is_equal_approx(camera.global_position.y, boardBounds.position.y))

	var viewport := main.get_node("BoardViewport/SubViewport") as SubViewport
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("The subviewport image is unavailable.")
		quit(1)
		return
	var outputPath := "user://capture.png"
	var error := image.save_png(outputPath)
	print("capture=", outputPath, " error=", error, " data=", OS.get_user_data_dir())
	if shouldCaptureInterface():
		var interfaceImage := main.get_viewport().get_texture().get_image()
		var interfaceError := interfaceImage.save_png("user://interfaceCapture.png")
		print("interfaceCapture=user://interfaceCapture.png error=", interfaceError)
	quit(error)
