extends Control

var indicatorColor := Color.WHITE

func setIndicatorColor(nextColor: Color) -> void:
	indicatorColor = nextColor
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var radius := maxf(1.0, minf(size.x, size.y) * 0.3)
	var center := size * 0.5
	draw_line(center - Vector2(radius, 0.0), center + Vector2(radius, 0.0), indicatorColor, 1.25, true)
	draw_line(center - Vector2(0.0, radius), center + Vector2(0.0, radius), indicatorColor, 1.25, true)
