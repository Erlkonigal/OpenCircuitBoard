extends Node2D

static var GeometryBySize: Dictionary[Vector2i, Dictionary] = {}

const OnIconDarkening := 0.45
const OnSideDarkening := 0.55
const OffTopColor := Color("263a3c")
const OffSideShadowColor := Color("101c25")
const OffIconColor := Color("46645f")

@onready var BaseBlock: TextureRect = $BaseBlock
@onready var ShadowBlock: TextureRect = $ShadowBlock
@onready var IconRect: TextureRect = $Icon

var GridCoordinates := Vector2i.ZERO
var CellSize := 64.0
var ExtrusionDepth := 32.0
var InkColor := Color.WHITE
var IsOn := true

func setup(board: Node2D, coordinates: Vector2i, size: float) -> void:
	CellSize = size
	ExtrusionDepth = CellSize * 0.5
	var gridWidth := updateGridCoordinates(board, coordinates)
	var faceLayerOffset := gridWidth + 1
	ShadowBlock.z_index = 0
	BaseBlock.z_index = faceLayerOffset
	IconRect.z_index = faceLayerOffset + 1
	buildGeometry()

func updateGridCoordinates(board: Node2D, coordinates: Vector2i) -> int:
	GridCoordinates = coordinates
	var gridWidth := 1000
	if "GridWidthCount" in board:
		gridWidth = int(board.GridWidthCount)
	z_index = gridWidth - coordinates.x
	return gridWidth

func buildGeometry() -> void:
	var geometry := getGeometry(CellSize, ExtrusionDepth)
	var totalSize := float(geometry["totalSize"])
	var texture := geometry["texture"] as Texture2D
	var topUvBounds := geometry["topUvBounds"] as Vector4
	for block in [BaseBlock, ShadowBlock]:
		block.size = Vector2.ONE * totalSize
		block.position = -block.size / 2.0
		block.texture = texture
		block.ignore_texture_size = true
		block.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var material := block.material as ShaderMaterial
		if material:
			material.set_shader_parameter("TopUvBounds", topUvBounds)

	IconRect.size = Vector2.ONE * CellSize
	IconRect.position = -IconRect.size / 2.0
	IconRect.stretch_mode = TextureRect.STRETCH_SCALE
	IconRect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

static func getGeometry(size: float, depth: float) -> Dictionary:
	var key := Vector2i(roundi(size), roundi(depth))
	if GeometryBySize.has(key):
		return GeometryBySize[key]
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
	GeometryBySize[key] = geometry
	return geometry

static func warmGeometry(size: float) -> void:
	getGeometry(size, size * 0.5)

static func getTopColor(baseColor: Color, nextIsOn: bool) -> Color:
	return baseColor if nextIsOn else OffTopColor

static func getSideShadowColor(baseColor: Color, nextIsOn: bool) -> Color:
	return baseColor.darkened(OnSideDarkening) if nextIsOn else OffSideShadowColor

static func getIconColor(baseColor: Color, nextIsOn: bool) -> Color:
	return baseColor.darkened(OnIconDarkening) if nextIsOn else OffIconColor

func setAttributes(icon: Texture2D, baseColor: Color, nextIsOn := true) -> void:
	InkColor = baseColor
	IconRect.texture = icon
	IconRect.visible = icon != null
	setInkState(nextIsOn)

func setInkState(nextIsOn: bool) -> void:
	IsOn = nextIsOn
	var topColor := getTopColor(InkColor, IsOn)
	var sideShadowColor := getSideShadowColor(InkColor, IsOn)
	for block in [BaseBlock, ShadowBlock]:
		var material := block.material as ShaderMaterial
		if material:
			material.set_shader_parameter("TopColor", topColor)
			material.set_shader_parameter("SideShadowColor", sideShadowColor)
			material.set_shader_parameter("ExtrusionDepth", ExtrusionDepth)
	if IconRect.texture:
		IconRect.modulate = getIconColor(InkColor, IsOn)
