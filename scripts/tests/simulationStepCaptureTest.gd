extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.main.call("enterSimulation")
	context.main.call("toggleLoopStepMode")
	context.main.call("setSimulationStepLength", 3)
	var status := context.getNodeRef(NodePath("Interface/TopBar/Content/simulationStatus")) as Label
	assert(status.text == "Step Mode")
	return {}
