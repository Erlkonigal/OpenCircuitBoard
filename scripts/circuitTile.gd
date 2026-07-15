extends Node2D

static var geometryBySize: Dictionary[Vector2i, Dictionary] = {}

const onIconDarkening := 0.45
const onSideDarkening := 0.55
const offTopColor := Color("263a3c")
const offSideShadowColor := Color("101c25")
const offIconColor := Color("46645f")

@onready var baseBlock: TextureRect = $BaseBlock
@onready var shadowBlock: TextureRect = $ShadowBlock
@onready var iconRect: TextureRect = $Icon

var gridCoordinates := Vector2i.ZERO
var cellSize := 64.0
var extrusionDepth := 32.0
var inkColor := Color.WHITE
var isOn := true

func setup(board: Node2D, coordinates: Vector2i, size: float) -> void:
	cellSize = size
	extrusionDepth = cellSize * 0.5
	var gridWidth := updateGridCoordinates(board, coordinates)
	var faceLayerOffset := gridWidth + 1
	shadowBlock.z_index = 0
	baseBlock.z_index = faceLayerOffset
	iconRect.z_index = faceLayerOffset + 1
	buildGeometry()

func updateGridCoordinates(board: Node2D, coordinates: Vector2i) -> int:
	gridCoordinates = coordinates
	var gridWidth := 1000
	if "gridWidthCount" in board:
		gridWidth = int(board.gridWidthCount)
	z_index = gridWidth - coordinates.x
	return gridWidth

func buildGeometry() -> void:
	var geometry := getGeometry(cellSize, extrusionDepth)
	var totalSize := float(geometry["totalSize"])
	var texture := geometry["texture"] as Texture2D
	var topUvBounds := geometry["topUvBounds"] as Vector4
	for block in [baseBlock, shadowBlock]:
		block.size = Vector2.ONE * totalSize
		block.position = -block.size / 2.0
		block.texture = texture
		block.ignore_texture_size = true
		block.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var material := block.material as ShaderMaterial
		if material:
			material.set_shader_parameter("topUvBounds", topUvBounds)

	iconRect.size = Vector2.ONE * cellSize
	iconRect.position = -iconRect.size / 2.0
	iconRect.stretch_mode = TextureRect.STRETCH_SCALE
	iconRect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

static func getGeometry(size: float, depth: float) -> Dictionary:
	var key := Vector2i(roundi(size), roundi(depth))
	if geometryBySize.has(key):
		return geometryBySize[key]
	var padding := depth * 3.0
	var totalSize := size + padding
	var image := Image.create(int(totalSize), int(totalSize), false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var topUvStart := padding * 0.5 / totalSize
	var topUvEnd := topUvStart + size / totalSize
	var geometry := {
		"totalSize": totalSize,
		"texture": ImageTexture.create_from_image(image),
		"topUvBounds": Vector4(topUvStart, topUvStart, topUvEnd, topUvEnd),
	}
	geometryBySize[key] = geometry
	return geometry

static func warmGeometry(size: float) -> void:
	getGeometry(size, size * 0.5)

static func getTopColor(baseColor: Color, nextIsOn: bool) -> Color:
	return baseColor if nextIsOn else offTopColor

static func getSideShadowColor(baseColor: Color, nextIsOn: bool) -> Color:
	return baseColor.darkened(onSideDarkening) if nextIsOn else offSideShadowColor

static func getIconColor(baseColor: Color, nextIsOn: bool) -> Color:
	return baseColor.darkened(onIconDarkening) if nextIsOn else offIconColor

func setAttributes(icon: Texture2D, baseColor: Color, nextIsOn := true) -> void:
	inkColor = baseColor
	iconRect.texture = icon
	iconRect.visible = icon != null
	setInkState(nextIsOn)

func setInkState(nextIsOn: bool) -> void:
	isOn = nextIsOn
	var topColor := getTopColor(inkColor, isOn)
	var sideShadowColor := getSideShadowColor(inkColor, isOn)
	for block in [baseBlock, shadowBlock]:
		var material := block.material as ShaderMaterial
		if material:
			material.set_shader_parameter("topColor", topColor)
			material.set_shader_parameter("sideShadowColor", sideShadowColor)
			material.set_shader_parameter("extrusionDepth", extrusionDepth)
	if iconRect.texture:
		iconRect.modulate = getIconColor(inkColor, isOn)
