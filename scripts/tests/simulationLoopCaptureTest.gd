extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.main.call("enterSimulation")
	context.main.call("setLoopFrequency", 5.0)
	var status := context.getNodeRef(NodePath("Interface/TopBar/Content/simulationStatus")) as Label
	assert(status.text == "~5 TPS")
	return {}
