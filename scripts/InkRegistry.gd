extends RefCounted

const IconByComponentId := {
	"cross": preload("res://assets/inks/Cross.svg"),
	"mesh": preload("res://assets/inks/Mesh.svg"),
	"bus": preload("res://assets/inks/Bus.svg"),
	"busRed": preload("res://assets/inks/BusRed.svg"),
	"busGreen": preload("res://assets/inks/BusGreen.svg"),
	"busYellow": preload("res://assets/inks/BusYellow.svg"),
	"busCyan": preload("res://assets/inks/BusCyan.svg"),
	"busMagenta": preload("res://assets/inks/BusMagenta.svg"),
	"read": preload("res://assets/inks/Read.svg"),
	"write": preload("res://assets/inks/Write.svg"),
	"trace": preload("res://assets/inks/Trace.svg"),
	"traceRed": preload("res://assets/inks/TraceRed.svg"),
	"traceGreen": preload("res://assets/inks/TraceGreen.svg"),
	"traceBlue": preload("res://assets/inks/TraceBlue.svg"),
	"traceCyan": preload("res://assets/inks/TraceCyan.svg"),
	"traceMagenta": preload("res://assets/inks/TraceMagenta.svg"),
	"buffer": preload("res://assets/inks/Buffer.svg"),
	"and": preload("res://assets/inks/And.svg"),
	"or": preload("res://assets/inks/Or.svg"),
	"xor": preload("res://assets/inks/Xor.svg"),
	"not": preload("res://assets/inks/Not.svg"),
	"nand": preload("res://assets/inks/Nand.svg"),
	"nor": preload("res://assets/inks/Nor.svg"),
	"xnor": preload("res://assets/inks/Xnor.svg"),
	"latch": preload("res://assets/inks/LatchOn.svg"),
	"clock": preload("res://assets/inks/Clock.svg"),
	"led": preload("res://assets/inks/Led.svg"),
}

const LatchOffIcon := preload("res://assets/inks/LatchOff.svg")

static var CacheInitialized := false
static var PaletteInkCache: Array[Dictionary] = []
static var ComponentInkCache: Array[Dictionary] = []
static var InkByComponentId: Dictionary = {}
static var InkVariantsByPaletteToolId: Dictionary = {}
static var BoardToolRegistryCache: Dictionary = {}
static var DefaultIsOnByComponentId: Dictionary = {}

static func getInks() -> Array[Dictionary]:
	return getPaletteInks()

static func getPaletteInks() -> Array[Dictionary]:
	ensureCache()
	return copyInks(PaletteInkCache)

static func getComponentInks() -> Array[Dictionary]:
	ensureCache()
	return copyInks(ComponentInkCache)

static func getInkVariants(paletteToolId: String) -> Array[Dictionary]:
	ensureCache()
	var variantsVariant: Variant = InkVariantsByPaletteToolId.get(paletteToolId, null)
	if not (variantsVariant is Array):
		return []
	var variants: Array[Dictionary] = []
	for inkVariant in variantsVariant as Array:
		if inkVariant is Dictionary:
			variants.append((inkVariant as Dictionary).duplicate(true))
	return variants

static func getBoardToolRegistry() -> Dictionary:
	ensureCache()
	return BoardToolRegistryCache.duplicate(true)

static func getInk(toolId: String) -> Dictionary:
	ensureCache()
	var inkVariant: Variant = InkByComponentId.get(toolId, null)
	if inkVariant is Dictionary:
		return (inkVariant as Dictionary).duplicate(true)
	return {}

static func getComponentId(ink: Dictionary) -> String:
	return String(ink.get("componentId", ink.get("toolId", "")))

static func getPaletteToolId(ink: Dictionary) -> String:
	return String(ink.get("paletteToolId", getComponentId(ink)))

static func getInkIcon(componentId: String, isOn := true) -> Texture2D:
	if componentId == "latch" and not isOn:
		return LatchOffIcon
	return IconByComponentId[componentId] as Texture2D

static func getDefaultIsOn(componentId: String) -> bool:
	ensureCache()
	return bool(DefaultIsOnByComponentId.get(componentId, true))

static func ensureCache() -> void:
	if CacheInitialized:
		return
	PaletteInkCache = [
		makeInk("cross", "Cross", "Space Optimization", Color("8da8cf")),
		makeInk("mesh", "Mesh", "Space Optimization", Color("91a66c"), "", false, true, true),
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
		makeInk("latch", "Latch", "General Components", Color("43ec90"), "", false, true, true),
		makeInk("clock", "Clock", "General Components", Color("f05b70"), "", false, true, true),
		makeInk("led", "Led", "General Components", Color("e6edf8")),
	]
	ComponentInkCache = copyInks(PaletteInkCache)
	ComponentInkCache.append_array([
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
	InkByComponentId.clear()
	InkVariantsByPaletteToolId.clear()
	BoardToolRegistryCache.clear()
	DefaultIsOnByComponentId.clear()
	for ink in ComponentInkCache:
		var componentId := getComponentId(ink)
		var paletteToolId := getPaletteToolId(ink)
		InkByComponentId[componentId] = ink
		DefaultIsOnByComponentId[componentId] = bool(ink.get("defaultIsOn", true))
		if not InkVariantsByPaletteToolId.has(paletteToolId):
			InkVariantsByPaletteToolId[paletteToolId] = []
		(InkVariantsByPaletteToolId[paletteToolId] as Array).append(ink)
		BoardToolRegistryCache[componentId] = {
			"componentId": componentId,
			"paletteToolId": paletteToolId,
			"color": ink.get("color", Color.WHITE),
			"icon": ink.get("icon"),
			"defaultIsOn": bool(ink.get("defaultIsOn", true)),
		}
	CacheInitialized = true

static func copyInks(inks: Array[Dictionary]) -> Array[Dictionary]:
	var copiedInks: Array[Dictionary] = []
	for ink in inks:
		copiedInks.append(ink.duplicate(true))
	return copiedInks

static func makeInk(
	toolId: String,
	title: String,
	category: String,
	color: Color,
	paletteToolId := "",
	isExpandable := false,
	defaultIsOn := true,
	isConfigurable := false
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
		"isConfigurable": isConfigurable,
		"defaultIsOn": defaultIsOn,
	}
