extends Node2D

const ActiveBorderColor := Color("63b2ff", 0.94)
const HoverBorderColor := Color("8dc4ff", 0.50)

var Bounds := Rect2()
var HoveredCorner := -1
var ActiveCorner := -1
var IsEnabled := false

func setResizeState(bounds: Rect2, hoveredCorner: int, activeCorner: int, isEnabled: bool) -> void:
	Bounds = bounds
	HoveredCorner = hoveredCorner
	ActiveCorner = activeCorner
	IsEnabled = isEnabled
	visible = IsEnabled
	queue_redraw()

func _draw() -> void:
	if not IsEnabled or Bounds.size.x <= 0.0 or Bounds.size.y <= 0.0:
		return
	if ActiveCorner >= 0:
		draw_rect(Bounds, ActiveBorderColor, false, 3.0, true)
	elif HoveredCorner >= 0:
		draw_rect(Bounds, HoverBorderColor, false, 2.0, true)
