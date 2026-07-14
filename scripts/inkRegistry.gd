extends RefCounted

static func getInks() -> Array[Dictionary]:
	return [
		{"toolId": "cross", "title": "Cross", "category": "SpaceOptimization", "color": Color("8da8cf")},
		{"toolId": "tunnel", "title": "Tunnel", "category": "SpaceOptimization", "color": Color("7483a1")},
		{"toolId": "mesh", "title": "Mesh", "category": "SpaceOptimization", "color": Color("91a66c")},
		{"toolId": "bus", "title": "Bus", "category": "SpaceOptimization", "color": Color("2378f4")},
		{"toolId": "read", "title": "Read", "category": "Trace", "color": Color("f04f68")},
		{"toolId": "write", "title": "Write", "category": "Trace", "color": Color("4ca8ef")},
		{"toolId": "trace", "title": "Trace", "category": "Trace", "color": Color("f4df35")},
		{"toolId": "buffer", "title": "Buffer", "category": "Gates", "color": Color("55ed91")},
		{"toolId": "and", "title": "And", "category": "Gates", "color": Color("f3c46e")},
		{"toolId": "or", "title": "Or", "category": "Gates", "color": Color("55dfeb")},
		{"toolId": "xor", "title": "Xor", "category": "Gates", "color": Color("a977ed")},
		{"toolId": "not", "title": "Not", "category": "Gates", "color": Color("ef5b78")},
		{"toolId": "nand", "title": "Nand", "category": "Gates", "color": Color("f59d35")},
		{"toolId": "nor", "title": "Nor", "category": "Gates", "color": Color("46d8e5")},
		{"toolId": "xnor", "title": "Xnor", "category": "Gates", "color": Color("bf58ee")},
		{"toolId": "latchOn", "title": "LatchOn", "category": "GeneralComponents", "color": Color("43ec90")},
		{"toolId": "latchOff", "title": "LatchOff", "category": "GeneralComponents", "color": Color("67d9a2")},
		{"toolId": "clock", "title": "Clock", "category": "GeneralComponents", "color": Color("f05b70")},
		{"toolId": "led", "title": "Led", "category": "GeneralComponents", "color": Color("e6edf8")},
	]

static func getBoardToolRegistry() -> Dictionary:
	var toolRegistry := {}
	for ink in getInks():
		toolRegistry[ink.toolId] = {"color": ink.color, "icon": null}
	return toolRegistry

static func getInk(toolId: String) -> Dictionary:
	for ink in getInks():
		if ink.toolId == toolId:
			return ink
	return {}
