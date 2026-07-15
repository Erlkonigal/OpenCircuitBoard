extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("enterSimulation")
	context.MainSceneRoot.call("setLoopFrequency", 5.0)
	var status := context.getNodeRef(NodePath("Interface/TopBar/Content/SimulationStatus")) as Label
	assert(status.text == "~5 TPS")
	return {}
