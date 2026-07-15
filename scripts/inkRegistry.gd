extends RefCounted

const iconByComponentId := {
	"cross": preload("res://assets/inks/cross.svg"),
	"tunnel": preload("res://assets/inks/tunnel.svg"),
	"mesh": preload("res://assets/inks/mesh.svg"),
	"bus": preload("res://assets/inks/bus.svg"),
	"busRed": preload("res://assets/inks/busRed.svg"),
	"busGreen": preload("res://assets/inks/busGreen.svg"),
	"busYellow": preload("res://assets/inks/busYellow.svg"),
	"busCyan": preload("res://assets/inks/busCyan.svg"),
	"busMagenta": preload("res://assets/inks/busMagenta.svg"),
	"read": preload("res://assets/inks/read.svg"),
	"write": preload("res://assets/inks/write.svg"),
	"trace": preload("res://assets/inks/trace.svg"),
	"traceRed": preload("res://assets/inks/traceRed.svg"),
	"traceGreen": preload("res://assets/inks/traceGreen.svg"),
	"traceBlue": preload("res://assets/inks/traceBlue.svg"),
	"traceCyan": preload("res://assets/inks/traceCyan.svg"),
	"traceMagenta": preload("res://assets/inks/traceMagenta.svg"),
	"buffer": preload("res://assets/inks/buffer.svg"),
	"and": preload("res://assets/inks/and.svg"),
	"or": preload("res://assets/inks/or.svg"),
	"xor": preload("res://assets/inks/xor.svg"),
	"not": preload("res://assets/inks/not.svg"),
	"nand": preload("res://assets/inks/nand.svg"),
	"nor": preload("res://assets/inks/nor.svg"),
	"xnor": preload("res://assets/inks/xnor.svg"),
	"latchOn": preload("res://assets/inks/latchOn.svg"),
	"latchOff": preload("res://assets/inks/latchOff.svg"),
	"clock": preload("res://assets/inks/clock.svg"),
	"led": preload("res://assets/inks/led.svg"),
}

static func getInks() -> Array[Dictionary]:
	return getPaletteInks()

static func getPaletteInks() -> Array[Dictionary]:
	return [
		makeInk("cross", "Cross", "Space Optimization", Color("8da8cf")),
		makeInk("tunnel", "Tunnel", "Space Optimization", Color("7483a1")),
		makeInk("mesh", "Mesh", "Space Optimization", Color("91a66c")),
		makeInk("bus", "Bus", "Space Optimization", Color("2378f4"), "bus", true),
		makeInk("read", "Read", "Trace", Color("f04f68")),
		makeInk("write", "Write", "Trace", Color("4ca8ef")),
		makeInk("trace", "Trace", "Trace", Color("f4df35"), "trace", true),
		makeInk("buffer", "Buffer", "Gates", Color("55ed91")),
		makeInk("and", "And", "Gates", Color("f3c46e")),
		makeInk("or", "Or", "Gates", Color("55dfeb")),
		makeInk("xor", "Xor", "Gates", Color("a977ed")),
		makeInk("not", "Not", "Gates", Color("ef5b78")),
		makeInk("nand", "Nand", "Gates", Color("f59d35")),
		makeInk("nor", "Nor", "Gates", Color("46d8e5")),
		makeInk("xnor", "Xnor", "Gates", Color("bf58ee")),
		makeInk("latchOn", "LatchOn", "General Components", Color("43ec90")),
		makeInk("latchOff", "LatchOff", "General Components", Color("67d9a2"), "", false, false),
		makeInk("clock", "Clock", "General Components", Color("f05b70")),
		makeInk("led", "Led", "General Components", Color("e6edf8")),
	]

static func getComponentInks() -> Array[Dictionary]:
	var componentInks := getPaletteInks()
	componentInks.append_array([
		makeInk("traceRed", "Trace Red", "Trace", Color("ff4d4d"), "trace"),
		makeInk("traceGreen", "Trace Green", "Trace", Color("71f06b"), "trace"),
		makeInk("traceBlue", "Trace Blue", "Trace", Color("2378f4"), "trace"),
		makeInk("traceCyan", "Trace Cyan", "Trace", Color("55dfeb"), "trace"),
		makeInk("traceMagenta", "Trace Magenta", "Trace", Color("c66af6"), "trace"),
		makeInk("busRed", "Bus Red", "Space Optimization", Color("ff4d4d"), "bus"),
		makeInk("busGreen", "Bus Green", "Space Optimization", Color("71f06b"), "bus"),
		makeInk("busYellow", "Bus Yellow", "Space Optimization", Color("f4df35"), "bus"),
		makeInk("busCyan", "Bus Cyan", "Space Optimization", Color("55dfeb"), "bus"),
		makeInk("busMagenta", "Bus Magenta", "Space Optimization", Color("c66af6"), "bus"),
	])
	return componentInks

static func getInkVariants(paletteToolId: String) -> Array[Dictionary]:
	var variants: Array[Dictionary] = []
	for ink in getComponentInks():
		if getPaletteToolId(ink) == paletteToolId:
			variants.append(ink)
	return variants

static func getBoardToolRegistry() -> Dictionary:
	var toolRegistry := {}
	for ink in getComponentInks():
		var componentId := getComponentId(ink)
		toolRegistry[componentId] = {
			"componentId": componentId,
			"paletteToolId": getPaletteToolId(ink),
			"color": ink.color,
			"icon": ink.icon,
			"defaultIsOn": bool(ink.get("defaultIsOn", true)),
		}
	return toolRegistry

static func getInk(toolId: String) -> Dictionary:
	for ink in getComponentInks():
		if getComponentId(ink) == toolId:
			return ink
	return {}

static func getComponentId(ink: Dictionary) -> String:
	return String(ink.get("componentId", ink.get("toolId", "")))

static func getPaletteToolId(ink: Dictionary) -> String:
	return String(ink.get("paletteToolId", getComponentId(ink)))

static func getInkIcon(componentId: String) -> Texture2D:
	return iconByComponentId[componentId] as Texture2D

static func getDefaultIsOn(componentId: String) -> bool:
	var ink := getInk(componentId)
	return bool(ink.get("defaultIsOn", true))

static func makeInk(
	toolId: String,
	title: String,
	category: String,
	color: Color,
	paletteToolId := "",
	isExpandable := false,
	defaultIsOn := true
) -> Dictionary:
	var resolvedPaletteToolId := paletteToolId if not paletteToolId.is_empty() else toolId
	return {
		"toolId": toolId,
		"componentId": toolId,
		"paletteToolId": resolvedPaletteToolId,
		"title": title,
		"category": category,
		"color": color,
		"icon": getInkIcon(toolId),
		"isExpandable": isExpandable,
		"defaultIsOn": defaultIsOn,
	}
