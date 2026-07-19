extends RefCounted

func run(context) -> Dictionary:
	await context.resetMain()
	await context.waitFrames(1)
	var board := context.CircuitBoard as Node2D
	var first := Vector2i(-3, -2)
	var second := Vector2i(-2, -2)
	assert(board.call("placeTile", first, "busRed"))
	assert(board.call("placeTile", second, "busGreen"))
	board.call("setSelection", Rect2i(first, Vector2i(2, 1)))
	assert(board.call("handleRightButtonPress", first, true))
	await context.waitFrames(2)
	var menu := context.MainSceneRoot.get("InkVariantMenu") as PopupPanel
	assert(menu.visible)
	assert(menu.position.x >= 0)
	assert(menu.position.y >= 0)
	assert(menu.position.x + menu.size.x <= context.RootWindow.size.x)
	assert(menu.position.y + menu.size.y <= context.RootWindow.size.y)
	return {}
