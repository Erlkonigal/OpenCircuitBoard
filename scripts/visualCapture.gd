extends SceneTree

func _init() -> void:
	call_deferred("captureBoard")

func getCaptureZoom() -> float:
	var captureZoom := 1.25
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--captureZoom="):
			captureZoom = maxf(argument.trim_prefix("--captureZoom=").to_float(), 0.01)
	return captureZoom

func captureBoard() -> void:
	var mainScene := load("res://main.tscn") as PackedScene
	var main := mainScene.instantiate()
	root.add_child(main)
	for frame in 5:
		await process_frame

	var board := main.get_node("BoardViewport/SubViewport/CircuitBoard") as Node2D
	var camera := main.get_node("BoardViewport/SubViewport/BoardCamera") as Camera2D
	board.set_process(false)
	# Place the right tile first so the capture verifies X-based depth ordering.
	board.call("placeTile", Vector2i(1, 0))
	board.call("selectTool", "processor")
	board.call("placeTile", Vector2i(0, 0))
	board.call("selectTool", "wire")
	board.call("placeTile", Vector2i(-1, 1))
	# Keep an isolated tile in view to inspect the full shadow silhouette.
	board.call("selectTool", "orGate")
	board.call("placeTile", Vector2i(4, -2))
	var occupancy: Dictionary = board.get("occupancy")
	var rightTile := occupancy[Vector2i(1, 0)] as Node2D
	var leftTile := occupancy[Vector2i(0, 0)] as Node2D
	assert(leftTile.z_index > rightTile.z_index)
	board.get_node("Selector").visible = false
	camera.zoom = Vector2.ONE * getCaptureZoom()
	for frame in 5:
		await process_frame

	var viewport := main.get_node("BoardViewport/SubViewport") as SubViewport
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("The subviewport image is unavailable.")
		quit(1)
		return
	var outputPath := "user://tileCapture.png"
	var error := image.save_png(outputPath)
	print("capture=", outputPath, " error=", error, " data=", OS.get_user_data_dir())
	quit(error)
