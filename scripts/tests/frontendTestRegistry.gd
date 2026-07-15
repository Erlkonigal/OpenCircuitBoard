extends RefCounted

const behaviorTestEntries := [
	{"id": "initialInterface", "path": "res://scripts/tests/initialInterfaceTest.gd"},
	{"id": "dockLayout", "path": "res://scripts/tests/dockLayoutTest.gd"},
	{"id": "inkPalette", "path": "res://scripts/tests/inkPaletteTest.gd"},
	{"id": "traceVariant", "path": "res://scripts/tests/traceVariantTest.gd"},
	{"id": "busVariant", "path": "res://scripts/tests/busVariantTest.gd"},
	{"id": "strokeHistory", "path": "res://scripts/tests/strokeHistoryTest.gd"},
	{"id": "simulationState", "path": "res://scripts/tests/simulationStateTest.gd"},
	{"id": "selectionMarquee", "path": "res://scripts/tests/selectionMarqueeTest.gd"},
	{"id": "selectionDeletion", "path": "res://scripts/tests/selectionDeletionTest.gd"},
	{"id": "rightClickDelete", "path": "res://scripts/tests/rightClickDeleteTest.gd"},
	{"id": "selectionCancellation", "path": "res://scripts/tests/selectionCancellationTest.gd"},
	{"id": "cutClipboard", "path": "res://scripts/tests/cutClipboardTest.gd"},
	{"id": "pastePreview", "path": "res://scripts/tests/pastePreviewTest.gd"},
	{"id": "invalidPaste", "path": "res://scripts/tests/invalidPasteTest.gd"},
	{"id": "selectionMove", "path": "res://scripts/tests/selectionMoveTest.gd"},
	{"id": "clipboardHistory", "path": "res://scripts/tests/clipboardHistoryTest.gd"},
	{"id": "tileRendering", "path": "res://scripts/tests/tileRenderingTest.gd"},
	{"id": "eventLogDock", "path": "res://scripts/tests/eventLogDockTest.gd"},
	{"id": "clipboardDock", "path": "res://scripts/tests/clipboardDockTest.gd"},
	{"id": "simulationToolbar", "path": "res://scripts/tests/simulationToolbarTest.gd"},
	{"id": "projectRoundTrip", "path": "res://scripts/tests/projectRoundTripTest.gd"},
]

const captureTestEntries := [
	{"id": "board", "path": "res://scripts/tests/boardCaptureTest.gd", "legacyArgs": []},
	{"id": "selector", "path": "res://scripts/tests/selectorCaptureTest.gd", "legacyArgs": ["--captureSelector"]},
	{"id": "boardEdge", "path": "res://scripts/tests/boardEdgeCaptureTest.gd", "legacyArgs": ["--captureBoardEdge"]},
	{"id": "interface", "path": "res://scripts/tests/interfaceCaptureTest.gd", "legacyArgs": ["--captureInterface"], "interfaceOutputPath": "user://interfaceCapture.png"},
	{"id": "simulationLoop", "path": "res://scripts/tests/simulationLoopCaptureTest.gd", "legacyArgs": ["--captureSimulationLoop"], "interfaceOutputPath": "user://interfaceCapture.png"},
	{"id": "simulationStep", "path": "res://scripts/tests/simulationStepCaptureTest.gd", "legacyArgs": ["--captureSimulationStep"], "interfaceOutputPath": "user://interfaceCapture.png"},
	{"id": "sidebar", "path": "res://scripts/tests/sidebarCaptureTest.gd", "legacyArgs": ["--captureSidebar"], "interfaceOutputPath": "user://sidebarCapture.png"},
	{"id": "eventLogDockCapture", "path": "res://scripts/tests/eventLogDockCaptureTest.gd", "legacyArgs": ["--captureEventLogDock"], "interfaceOutputPath": "user://eventLogDockCapture.png"},
	{"id": "clipboardDockCapture", "path": "res://scripts/tests/clipboardDockCaptureTest.gd", "legacyArgs": ["--captureClipboardDock"], "interfaceOutputPath": "user://clipboardDockCapture.png"},
	{"id": "selection", "path": "res://scripts/tests/selectionCaptureTest.gd", "legacyArgs": ["--captureSelection"]},
	{"id": "pastePreviewCapture", "path": "res://scripts/tests/pastePreviewCaptureTest.gd", "legacyArgs": ["--capturePastePreview"]},
	{"id": "pastedLayering", "path": "res://scripts/tests/pastedLayeringCaptureTest.gd", "legacyArgs": ["--capturePastedLayering"]},
	{"id": "inkStates", "path": "res://scripts/tests/inkStatesCaptureTest.gd", "legacyArgs": ["--captureInkStates"]},
	{"id": "dockMenuCapture", "path": "res://scripts/tests/dockMenuCaptureTest.gd", "legacyArgs": ["--captureDockMenu"], "interfaceOutputPath": "user://dockMenuCapture.png"},
	{"id": "defaultZoom", "path": "res://scripts/tests/defaultZoomCaptureTest.gd", "legacyArgs": ["--captureDefaultZoom"]},
	{"id": "dualDockCapture", "path": "res://scripts/tests/dualDockCaptureTest.gd", "legacyArgs": ["--captureDualDock"], "interfaceOutputPath": "user://dualDockCapture.png"},
	{"id": "traceColorMenu", "path": "res://scripts/tests/traceColorMenuCaptureTest.gd", "legacyArgs": ["--captureTraceColorMenu"], "interfaceOutputPath": "user://traceColorMenuCapture.png"},
	{"id": "busColorMenu", "path": "res://scripts/tests/busColorMenuCaptureTest.gd", "legacyArgs": ["--captureBusColorMenu"], "interfaceOutputPath": "user://busColorMenuCapture.png"},
]

static func getDefaultCaptureEntry() -> Dictionary:
	return captureTestEntries[0].duplicate(true)

static func resolveRequestedEntry(arguments: PackedStringArray) -> Dictionary:
	var selectedIds: Array[String] = []
	for argument in arguments:
		if argument.begins_with("--frontendTest="):
			appendSelectedId(selectedIds, argument.trim_prefix("--frontendTest="))
	for entryVariant in captureTestEntries:
		var entry := entryVariant as Dictionary
		for legacyArgumentVariant in entry.get("legacyArgs", []):
			var legacyArgument := String(legacyArgumentVariant)
			if arguments.has(legacyArgument):
				appendSelectedId(selectedIds, String(entry.get("id", "")))
	if selectedIds.size() > 1:
		return {"error": "FrontendTestSelectionAmbiguous"}
	if selectedIds.is_empty():
		return {}
	var entry := getEntryById(selectedIds[0])
	if entry.is_empty():
		return {"error": "FrontendTestNotFound"}
	return entry

static func getEntryById(testId: String) -> Dictionary:
	for entryVariant in behaviorTestEntries:
		var entry := entryVariant as Dictionary
		if String(entry.get("id", "")) == testId:
			return entry.duplicate(true)
	for entryVariant in captureTestEntries:
		var entry := entryVariant as Dictionary
		if String(entry.get("id", "")) == testId:
			return entry.duplicate(true)
	return {}

static func appendSelectedId(selectedIds: Array[String], testId: String) -> void:
	if not testId.is_empty() and not selectedIds.has(testId):
		selectedIds.append(testId)
