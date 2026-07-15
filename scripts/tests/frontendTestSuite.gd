extends RefCounted

const FrontendTestRegistry := preload("res://scripts/tests/frontendTestRegistry.gd")

func runDefault(context) -> Dictionary:
	for entryVariant in FrontendTestRegistry.behaviorTestEntries:
		await runEntry(context, entryVariant as Dictionary)
	return await runEntry(context, FrontendTestRegistry.getDefaultCaptureEntry())

func runEntry(context, entry: Dictionary) -> Dictionary:
	var testPath := String(entry.get("path", ""))
	var testScript := load(testPath) as Script
	assert(testScript != null, "Unable to load frontend test: %s" % testPath)
	var test: Variant = testScript.new()
	assert(test != null and test.has_method("run"), "Invalid frontend test: %s" % testPath)
	var result: Variant = await test.call("run", context)
	return result as Dictionary if result is Dictionary else {}
