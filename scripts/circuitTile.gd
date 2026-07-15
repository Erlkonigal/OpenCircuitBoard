extends Node2D

@onready var baseBlock: TextureRect = $BaseBlock
@onready var shadowBlock: TextureRect = $ShadowBlock
@onready var iconRect: TextureRect = $Icon

var gridCoordinates := Vector2i.ZERO
var cellSize := 64.0
var extrusionDepth := 32.0

func setup(board: Node2D, coordinates: Vector2i, size: float) -> void:
	gridCoordinates = coordinates
	cellSize = size
	extrusionDepth = cellSize * 0.5
	var gridWidth := 1000
	if "gridWidthCount" in board:
		gridWidth = int(board.gridWidthCount)
	z_index = gridWidth - coordinates.x
	var faceLayerOffset := gridWidth + 1
	shadowBlock.z_index = 0
	baseBlock.z_index = faceLayerOffset
	iconRect.z_index = faceLayerOffset + 1
	buildGeometry()

func buildGeometry() -> void:
	var padding := extrusionDepth * 3.0
	var totalSize := cellSize + padding
	var image := Image.create(int(totalSize), int(totalSize), false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var topUvStart := padding * 0.5 / totalSize
	var topUvEnd := topUvStart + cellSize / totalSize
	var topUvBounds := Vector4(topUvStart, topUvStart, topUvEnd, topUvEnd)
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
	iconRect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func setAttributes(icon: Texture2D, baseColor: Color) -> void:
	for block in [baseBlock, shadowBlock]:
		var material := block.material as ShaderMaterial
		if material:
			material.set_shader_parameter("topColor", baseColor)
			material.set_shader_parameter("sideShadowColor", baseColor.darkened(0.55))
			material.set_shader_parameter("extrusionDepth", extrusionDepth)
	iconRect.texture = icon
	iconRect.visible = icon != null
	if icon:
		iconRect.modulate = baseColor.darkened(0.45)
