extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	context.MainSceneRoot.call("enterSimulation")
	context.MainSceneRoot.call("toggleLoopStepMode")
	context.MainSceneRoot.call("setSimulationStepLength", 3)
	var status := context.getNodeRef(NodePath("Interface/TopBar/Content/SimulationStatus")) as Label
	assert(status.text == "Step Mode")
	return {}
