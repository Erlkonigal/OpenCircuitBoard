extends RefCounted

const FrontendTestFixtures := preload("res://scripts/tests/FrontendTestFixtures.gd")
const CircuitTile := preload("res://scripts/CircuitTile.gd")
const InkRegistry := preload("res://scripts/InkRegistry.gd")

func run(context) -> Dictionary:
	await context.resetMain()
	FrontendTestFixtures.clearBoardTiles(context.CircuitBoard)
	var onLatchLeft := Vector2i(-2, -2)
	var onLatchRight := Vector2i(1, -2)
	var offTraceRed := Vector2i(-2, 1)
	var offTraceBlue := Vector2i(1, 1)
	assert(context.CircuitBoard.call("placeTile", onLatchLeft, "latch"))
	assert(context.CircuitBoard.call("placeTile", onLatchRight, "latch"))
	assert(context.CircuitBoard.call("placeTile", offTraceRed, "traceRed"))
	assert(context.CircuitBoard.call("placeTile", offTraceBlue, "traceBlue"))
	assert(context.CircuitBoard.call("setTileState", offTraceRed, false))
	assert(context.CircuitBoard.call("setTileState", offTraceBlue, false))
	var occupancy: Dictionary = context.CircuitBoard.get("Occupancy")
	context.assertTileIcon(occupancy[onLatchLeft] as Node2D, InkRegistry.getInk("latch"), float(context.CircuitBoard.get("CellSize")), true)
	context.assertTileIcon(occupancy[onLatchRight] as Node2D, InkRegistry.getInk("latch"), float(context.CircuitBoard.get("CellSize")), true)
	assertOffTileUsesOwnInkColor(occupancy[offTraceRed] as Node2D, InkRegistry.getInk("traceRed"), float(context.CircuitBoard.get("CellSize")), context)
	assertOffTileUsesOwnInkColor(occupancy[offTraceBlue] as Node2D, InkRegistry.getInk("traceBlue"), float(context.CircuitBoard.get("CellSize")), context)
	context.CircuitBoard.set_process(false)
	context.BoardCamera.zoom = Vector2.ONE * maxf(context.getFloatArg("--captureZoom", 1.25), 0.01)
	return {}

func assertOffTileUsesOwnInkColor(tile: Node2D, ink: Dictionary, cellSize: float, context) -> void:
	context.assertTileIcon(tile, ink, cellSize, false)
	var inkColor: Color = ink.get("color", Color.WHITE)
	var baseBlock := tile.get_node("BaseBlock") as TextureRect
	var baseMaterial := baseBlock.material as ShaderMaterial
	var iconRect := tile.get_node("Icon") as TextureRect
	var topColor: Color = baseMaterial.get_shader_parameter("TopColor")
	var sideShadowColor: Color = baseMaterial.get_shader_parameter("SideShadowColor")
	assert(topColor.is_equal_approx(CircuitTile.getTopColor(inkColor, false)))
	assert(sideShadowColor.is_equal_approx(CircuitTile.getSideShadowColor(inkColor, false)))
	assert(iconRect.modulate.is_equal_approx(CircuitTile.getIconColor(inkColor, false)))
	assert(getSaturation(topColor) < getSaturation(inkColor))
	assert(iconRect.modulate.get_luminance() < topColor.get_luminance())

func getSaturation(color: Color) -> float:
	var maximum := maxf(color.r, maxf(color.g, color.b))
	if is_zero_approx(maximum):
		return 0.0
	var minimum := minf(color.r, minf(color.g, color.b))
	return (maximum - minimum) / maximum
