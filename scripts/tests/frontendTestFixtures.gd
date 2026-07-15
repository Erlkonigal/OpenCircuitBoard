extends RefCounted
class_name FrontendTestFixtures

const visualTileDefinitions := [
	{"name": "right", "coordinates": Vector2i(1, 0), "toolId": "or"},
	{"name": "left", "coordinates": Vector2i(0, 0), "toolId": "xor"},
	{"name": "bus", "coordinates": Vector2i(-3, 1), "toolId": "busMagenta"},
	{"name": "traceRed", "coordinates": Vector2i(-2, 1), "toolId": "traceRed"},
	{"name": "traceBlue", "coordinates": Vector2i(-1, 1), "toolId": "traceBlue"},
	{"name": "isolated", "coordinates": Vector2i(4, -2), "toolId": "or"},
]

const visualClipboardSelections := [
	Rect2i(Vector2i(1, 0), Vector2i(1, 1)),
	Rect2i(Vector2i(0, 0), Vector2i(2, 1)),
	Rect2i(Vector2i(-2, 1), Vector2i(2, 1)),
	Rect2i(Vector2i(4, -2), Vector2i(1, 1)),
]

static func clearBoardTiles(board: Node2D) -> void:
	assert(board != null)
	assert(board.has_method("removeTile"))
	var tileData := board.get("tileData") as Dictionary
	for coordinatesVariant in tileData.keys():
		assert(board.call("removeTile", coordinatesVariant as Vector2i))
	if board.has_method("clearSelection"):
		board.call("clearSelection")

static func setupVisualTiles(board: Node2D, clearExisting := false) -> Dictionary:
	assert(board != null)
	assert(board.has_method("placeTile"))
	if clearExisting:
		clearBoardTiles(board)
	var occupancy := board.get("occupancy") as Dictionary
	var tiles := {}
	var coordinates := {}
	for definitionVariant in visualTileDefinitions:
		var definition := definitionVariant as Dictionary
		var name := String(definition.get("name", ""))
		var tileCoordinates: Vector2i = definition.get("coordinates", Vector2i.ZERO)
		var toolId := String(definition.get("toolId", ""))
		assert(not name.is_empty())
		assert(board.call("placeTile", tileCoordinates, toolId))
		coordinates[name] = tileCoordinates
		tiles[name] = occupancy.get(tileCoordinates) as Node2D
		assert(tiles[name] != null)
	return {
		"coordinates": coordinates,
		"tiles": tiles,
	}

static func setupClipboardHistory(board: Node2D, selections: Array = visualClipboardSelections) -> Dictionary:
	assert(board != null)
	assert(board.has_method("setSelection"))
	assert(board.has_method("copySelection"))
	for selectionVariant in selections:
		assert(selectionVariant is Rect2i)
		board.call("setSelection", selectionVariant as Rect2i)
		assert(board.call("copySelection"))
	return {
		"history": board.call("getClipboardHistory") as Array,
		"selectedIndex": int(board.call("getSelectedClipboardIndex")),
	}

static func setupVisualBoardWithClipboard(board: Node2D, clearExisting := false) -> Dictionary:
	var visualTiles := setupVisualTiles(board, clearExisting)
	var clipboard := setupClipboardHistory(board)
	return {
		"coordinates": visualTiles.get("coordinates", {}),
		"tiles": visualTiles.get("tiles", {}),
		"history": clipboard.get("history", []),
		"selectedIndex": clipboard.get("selectedIndex", -1),
	}
