extends Node2D

const PassiveHandleColor := Color("6d88aa", 0.56)
const HoverHandleColor := Color("8dc4ff", 0.96)
const ActiveHandleColor := Color("63b2ff", 1.0)
const ActiveBorderColor := Color("63b2ff", 0.94)
const HoverBorderColor := Color("8dc4ff", 0.50)
const ActiveFillColor := Color("63b2ff", 0.055)

var Bounds := Rect2()
var HandleRadius := 8.0
var HoveredCorner := -1
var ActiveCorner := -1
var IsEnabled := false

func setResizeState(bounds: Rect2, handleRadius: float, hoveredCorner: int, activeCorner: int, isEnabled: bool) -> void:
	Bounds = bounds
	HandleRadius = maxf(2.0, handleRadius)
	HoveredCorner = hoveredCorner
	ActiveCorner = activeCorner
	IsEnabled = isEnabled
	visible = IsEnabled
	queue_redraw()

func _draw() -> void:
	if not IsEnabled or Bounds.size.x <= 0.0 or Bounds.size.y <= 0.0:
		return
	if ActiveCorner >= 0:
		draw_rect(Bounds, ActiveFillColor, true)
		draw_rect(Bounds, ActiveBorderColor, false, 3.0, true)
	elif HoveredCorner >= 0:
		draw_rect(Bounds, HoverBorderColor, false, 2.0, true)
	var corners := [
		Bounds.position,
		Vector2(Bounds.end.x, Bounds.position.y),
		Vector2(Bounds.position.x, Bounds.end.y),
		Bounds.end,
	]
	for cornerIndex in range(corners.size()):
		var color := PassiveHandleColor
		if cornerIndex == ActiveCorner:
			color = ActiveHandleColor
		elif cornerIndex == HoveredCorner:
			color = HoverHandleColor
		var corner := corners[cornerIndex] as Vector2
		var handleSize := Vector2.ONE * HandleRadius * 2.0
		var handleRect := Rect2(corner - handleSize / 2.0, handleSize)
		draw_rect(handleRect, color, true)
		draw_rect(handleRect, color.lightened(0.16), false, 1.5, true)
