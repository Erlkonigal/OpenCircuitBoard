extends RefCounted

const BehaviorTestEntries := [
	{"id": "initialInterface", "path": "res://scripts/tests/InitialInterfaceTest.gd"},
	{"id": "dockLayout", "path": "res://scripts/tests/DockLayoutTest.gd"},
	{"id": "inkPalette", "path": "res://scripts/tests/InkPaletteTest.gd"},
	{"id": "traceVariant", "path": "res://scripts/tests/TraceVariantTest.gd"},
	{"id": "busVariant", "path": "res://scripts/tests/BusVariantTest.gd"},
	{"id": "clockSettings", "path": "res://scripts/tests/ClockSettingsTest.gd"},
	{"id": "componentSettings", "path": "res://scripts/tests/ComponentSettingsTest.gd"},
	{"id": "strokeHistory", "path": "res://scripts/tests/StrokeHistoryTest.gd"},
	{"id": "simulationState", "path": "res://scripts/tests/SimulationStateTest.gd"},
	{"id": "simulationCompileFailure", "path": "res://scripts/tests/SimulationCompileFailureTest.gd"},
	{"id": "selectionMarquee", "path": "res://scripts/tests/SelectionMarqueeTest.gd"},
	{"id": "selectionDeletion", "path": "res://scripts/tests/SelectionDeletionTest.gd"},
	{"id": "rightClickDelete", "path": "res://scripts/tests/RightClickDeleteTest.gd"},
	{"id": "selectionCancellation", "path": "res://scripts/tests/SelectionCancellationTest.gd"},
	{"id": "cutClipboard", "path": "res://scripts/tests/CutClipboardTest.gd"},
	{"id": "pastePreview", "path": "res://scripts/tests/PastePreviewTest.gd"},
	{"id": "invalidPaste", "path": "res://scripts/tests/InvalidPasteTest.gd"},
	{"id": "selectionMove", "path": "res://scripts/tests/SelectionMoveTest.gd"},
	{"id": "clipboardHistory", "path": "res://scripts/tests/ClipboardHistoryTest.gd"},
	{"id": "tileRendering", "path": "res://scripts/tests/TileRenderingTest.gd"},
	{"id": "eventLogDock", "path": "res://scripts/tests/EventLogDockTest.gd"},
	{"id": "clipboardDock", "path": "res://scripts/tests/ClipboardDockTest.gd"},
	{"id": "simulationToolbar", "path": "res://scripts/tests/SimulationToolbarTest.gd"},
	{"id": "projectDialogs", "path": "res://scripts/tests/ProjectDialogsTest.gd"},
	{"id": "projectRoundTrip", "path": "res://scripts/tests/ProjectRoundTripTest.gd"},
]

const CaptureTestEntries := [
	{"id": "board", "path": "res://scripts/tests/BoardCaptureTest.gd", "legacyArgs": []},
	{"id": "selector", "path": "res://scripts/tests/SelectorCaptureTest.gd", "legacyArgs": ["--captureSelector"]},
	{"id": "boardEdge", "path": "res://scripts/tests/BoardEdgeCaptureTest.gd", "legacyArgs": ["--captureBoardEdge"]},
	{"id": "interface", "path": "res://scripts/tests/InterfaceCaptureTest.gd", "legacyArgs": ["--captureInterface"], "interfaceOutputPath": "user://interfaceCapture.png"},
	{"id": "projectOpenDialog", "path": "res://scripts/tests/ProjectOpenDialogCaptureTest.gd", "legacyArgs": [], "interfaceOutputPath": "user://projectOpenDialogCapture.png"},
	{"id": "projectSaveDialog", "path": "res://scripts/tests/ProjectSaveDialogCaptureTest.gd", "legacyArgs": [], "interfaceOutputPath": "user://projectSaveDialogCapture.png"},
	{"id": "simulationLoop", "path": "res://scripts/tests/SimulationLoopCaptureTest.gd", "legacyArgs": ["--captureSimulationLoop"], "interfaceOutputPath": "user://interfaceCapture.png"},
	{"id": "simulationStep", "path": "res://scripts/tests/SimulationStepCaptureTest.gd", "legacyArgs": ["--captureSimulationStep"], "interfaceOutputPath": "user://interfaceCapture.png"},
	{"id": "sidebar", "path": "res://scripts/tests/SidebarCaptureTest.gd", "legacyArgs": ["--captureSidebar"], "interfaceOutputPath": "user://sidebarCapture.png"},
	{"id": "eventLogDockCapture", "path": "res://scripts/tests/EventLogDockCaptureTest.gd", "legacyArgs": ["--captureEventLogDock"], "interfaceOutputPath": "user://eventLogDockCapture.png"},
	{"id": "clipboardDockCapture", "path": "res://scripts/tests/ClipboardDockCaptureTest.gd", "legacyArgs": ["--captureClipboardDock"], "interfaceOutputPath": "user://clipboardDockCapture.png"},
	{"id": "selection", "path": "res://scripts/tests/SelectionCaptureTest.gd", "legacyArgs": ["--captureSelection"]},
	{"id": "pastePreviewCapture", "path": "res://scripts/tests/PastePreviewCaptureTest.gd", "legacyArgs": ["--capturePastePreview"]},
	{"id": "pastedLayering", "path": "res://scripts/tests/PastedLayeringCaptureTest.gd", "legacyArgs": ["--capturePastedLayering"]},
	{"id": "inkStates", "path": "res://scripts/tests/InkStatesCaptureTest.gd", "legacyArgs": ["--captureInkStates"]},
	{"id": "dockMenuCapture", "path": "res://scripts/tests/DockMenuCaptureTest.gd", "legacyArgs": ["--captureDockMenu"], "interfaceOutputPath": "user://dockMenuCapture.png"},
	{"id": "defaultZoom", "path": "res://scripts/tests/DefaultZoomCaptureTest.gd", "legacyArgs": ["--captureDefaultZoom"]},
	{"id": "dualDockCapture", "path": "res://scripts/tests/DualDockCaptureTest.gd", "legacyArgs": ["--captureDualDock"], "interfaceOutputPath": "user://dualDockCapture.png"},
	{"id": "traceColorMenu", "path": "res://scripts/tests/TraceColorMenuCaptureTest.gd", "legacyArgs": ["--captureTraceColorMenu"], "interfaceOutputPath": "user://traceColorMenuCapture.png"},
	{"id": "busColorMenu", "path": "res://scripts/tests/BusColorMenuCaptureTest.gd", "legacyArgs": ["--captureBusColorMenu"], "interfaceOutputPath": "user://busColorMenuCapture.png"},
	{"id": "clockSettingsMenu", "path": "res://scripts/tests/ClockSettingsMenuCaptureTest.gd", "legacyArgs": [], "interfaceOutputPath": "user://clockSettingsMenuCapture.png"},
]

static func getDefaultCaptureEntry() -> Dictionary:
	return CaptureTestEntries[0].duplicate(true)

static func resolveRequestedEntry(arguments: PackedStringArray) -> Dictionary:
	var selectedIds: Array[String] = []
	for argument in arguments:
		if argument.begins_with("--frontendTest="):
			appendSelectedId(selectedIds, argument.trim_prefix("--frontendTest="))
	for entryVariant in CaptureTestEntries:
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
	for entryVariant in BehaviorTestEntries:
		var entry := entryVariant as Dictionary
		if String(entry.get("id", "")) == testId:
			return entry.duplicate(true)
	for entryVariant in CaptureTestEntries:
		var entry := entryVariant as Dictionary
		if String(entry.get("id", "")) == testId:
			return entry.duplicate(true)
	return {}

static func appendSelectedId(selectedIds: Array[String], testId: String) -> void:
	if not testId.is_empty() and not selectedIds.has(testId):
		selectedIds.append(testId)
