extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/frontendTestFixtures.gd")
const InkRegistry := preload("res://scripts/inkRegistry.gd")

func run(context) -> void:
	await context.resetMain()
	await context.waitFrames(1)
	var main := context.main as Control
	var board := context.board as Node2D
	var circuitEditorDock: Control = context.getDockForSide(main, "left")
	board.set_process(false)
	var visualTiles := FrontendTestFixtures.setupVisualTiles(board)
	var coordinates: Dictionary = visualTiles.get("coordinates", {})
	var tiles: Dictionary = visualTiles.get("tiles", {})
	var tileData: Dictionary = board.get("tileData")
	assert(String((tileData[coordinates.get("bus")] as Dictionary).get("toolId", "")) == "busMagenta")
	assert(String((tileData[coordinates.get("traceRed")] as Dictionary).get("toolId", "")) == "traceRed")
	assert(String((tileData[coordinates.get("traceBlue")] as Dictionary).get("toolId", "")) == "traceBlue")
	context.assertHoveredInkForCanvasTile(board, circuitEditorDock, coordinates.get("left") as Vector2i)
	var cellSize := float(board.get("cellSize"))
	var rightTile := tiles.get("right") as Node2D
	var leftTile := tiles.get("left") as Node2D
	var busTile := tiles.get("bus") as Node2D
	var traceRedTile := tiles.get("traceRed") as Node2D
	var traceBlueTile := tiles.get("traceBlue") as Node2D
	context.assertTileIcon(rightTile, InkRegistry.getInk("or"), cellSize)
	context.assertTileIcon(leftTile, InkRegistry.getInk("xor"), cellSize)
	context.assertTileIcon(busTile, InkRegistry.getInk("busMagenta"), cellSize)
	context.assertTileIcon(traceRedTile, InkRegistry.getInk("traceRed"), cellSize)
	context.assertTileIcon(traceBlueTile, InkRegistry.getInk("traceBlue"), cellSize)
	context.assertSharedTileGeometry(rightTile, leftTile)
	context.assertSharedTileGeometry(leftTile, busTile)
	context.assertSharedTileGeometry(busTile, traceRedTile)
	context.assertSharedTileGeometry(traceRedTile, traceBlueTile)
	assert(leftTile.z_index > rightTile.z_index)
	assert((tiles.get("isolated") as Node2D).visible)
