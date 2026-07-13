extends Node2D

@onready var baseBlock: TextureRect = $BaseBlock
@onready var iconRect: TextureRect = $Icon

var gridCoordinates := Vector2i.ZERO
var cellSize := 64.0
var extrusionDepth := 32.0

func setup(board: Node2D, coordinates: Vector2i, size: float) -> void:
	gridCoordinates = coordinates
	cellSize = size
	extrusionDepth = cellSize * 0.5
	var gridWidth: int = 1000
	if "gridWidthCount" in board:
		gridWidth = int(board.gridWidthCount)
	z_index = gridWidth - coordinates.x
	buildGeometry()

func buildGeometry() -> void:
	var padding := extrusionDepth * 3.0
	var totalSize := cellSize + padding
	baseBlock.size = Vector2.ONE * totalSize
	baseBlock.position = -baseBlock.size / 2.0

	var image := Image.create(int(totalSize), int(totalSize), true, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var offset := int(padding / 2.0)
	image.fill_rect(Rect2i(offset, offset, int(cellSize), int(cellSize)), Color.WHITE)
	image.generate_mipmaps()
	baseBlock.texture = ImageTexture.create_from_image(image)
	baseBlock.ignore_texture_size = true
	baseBlock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	iconRect.size = Vector2.ONE * cellSize
	iconRect.position = -iconRect.size / 2.0

func setAttributes(icon: Texture2D, baseColor: Color) -> void:
	var material := baseBlock.material as ShaderMaterial
	if material:
		material.set_shader_parameter("topColor", baseColor)
		material.set_shader_parameter("sideShadowColor", baseColor.darkened(0.55))
		material.set_shader_parameter("extrusionDepth", extrusionDepth)
	iconRect.texture = icon
	iconRect.visible = icon != null
	if icon:
		iconRect.modulate = baseColor.darkened(0.45)
