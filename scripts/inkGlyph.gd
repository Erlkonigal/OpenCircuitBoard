extends Control

const glyphPadding := 4.0

var glyphId := ""
var glyphColor := Color.WHITE

func setGlyphId(nextGlyphId: String) -> void:
	glyphId = nextGlyphId
	queue_redraw()

func setGlyphColor(nextGlyphColor: Color) -> void:
	glyphColor = nextGlyphColor
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var glyphSize := Vector2(
		maxf(1.0, size.x - glyphPadding * 2.0),
		maxf(1.0, size.y - glyphPadding * 2.0)
	)
	var bounds := Rect2(Vector2.ONE * glyphPadding, glyphSize)
	var lineWidth := clampf(minf(glyphSize.x, glyphSize.y) * 0.13, 1.25, 2.0)
	match getGlyphFamily():
		"cross":
			draw_line(point(bounds, 0.5, 0.12), point(bounds, 0.5, 0.88), glyphColor, lineWidth, true)
			draw_line(point(bounds, 0.12, 0.5), point(bounds, 0.88, 0.5), glyphColor, lineWidth, true)
		"tunnel":
			drawPath([point(bounds, 0.31, 0.13), point(bounds, 0.18, 0.3), point(bounds, 0.18, 0.7), point(bounds, 0.31, 0.87)], lineWidth)
			drawPath([point(bounds, 0.69, 0.13), point(bounds, 0.82, 0.3), point(bounds, 0.82, 0.7), point(bounds, 0.69, 0.87)], lineWidth)
		"mesh":
			draw_line(point(bounds, 0.12, 0.5), point(bounds, 0.88, 0.5), glyphColor, lineWidth, true)
			draw_line(point(bounds, 0.5, 0.12), point(bounds, 0.5, 0.88), glyphColor, lineWidth, true)
			draw_circle(point(bounds, 0.5, 0.5), lineWidth * 0.72, glyphColor)
		"bus":
			drawPath([point(bounds, 0.62, 0.08), point(bounds, 0.35, 0.47), point(bounds, 0.57, 0.47), point(bounds, 0.38, 0.92), point(bounds, 0.76, 0.36), point(bounds, 0.54, 0.36)], lineWidth)
		"read":
			drawPath([point(bounds, 0.1, 0.18), point(bounds, 0.28, 0.82), point(bounds, 0.5, 0.42), point(bounds, 0.72, 0.82), point(bounds, 0.9, 0.18)], lineWidth)
		"write":
			drawPath([point(bounds, 0.18, 0.88), point(bounds, 0.18, 0.12), point(bounds, 0.57, 0.12), point(bounds, 0.72, 0.27), point(bounds, 0.57, 0.47), point(bounds, 0.18, 0.47)], lineWidth)
			draw_line(point(bounds, 0.5, 0.47), point(bounds, 0.82, 0.88), glyphColor, lineWidth, true)
		"trace":
			drawPath([point(bounds, 0.18, 0.85), point(bounds, 0.18, 0.18), point(bounds, 0.82, 0.18)], lineWidth)
			drawPath([point(bounds, 0.4, 0.85), point(bounds, 0.4, 0.4), point(bounds, 0.82, 0.4)], lineWidth)
		"buffer":
			drawPath([point(bounds, 0.16, 0.14), point(bounds, 0.16, 0.86), point(bounds, 0.84, 0.5), point(bounds, 0.16, 0.14)], lineWidth, true)
		"and", "nand":
			drawPath([point(bounds, 0.18, 0.12), point(bounds, 0.18, 0.88)], lineWidth)
			drawPath([point(bounds, 0.18, 0.12), point(bounds, 0.58, 0.12), point(bounds, 0.84, 0.5), point(bounds, 0.58, 0.88), point(bounds, 0.18, 0.88)], lineWidth)
			if getGlyphFamily() == "nand":
				draw_circle(point(bounds, 0.9, 0.5), lineWidth * 0.72, glyphColor, false, lineWidth, true)
		"or", "nor":
			drawPath([point(bounds, 0.14, 0.1), point(bounds, 0.42, 0.5), point(bounds, 0.14, 0.9)], lineWidth)
			drawPath([point(bounds, 0.35, 0.1), point(bounds, 0.83, 0.5), point(bounds, 0.35, 0.9)], lineWidth)
			if getGlyphFamily() == "nor":
				draw_circle(point(bounds, 0.9, 0.5), lineWidth * 0.72, glyphColor, false, lineWidth, true)
		"xor", "xnor":
			drawPath([point(bounds, 0.05, 0.1), point(bounds, 0.33, 0.5), point(bounds, 0.05, 0.9)], lineWidth)
			drawPath([point(bounds, 0.23, 0.1), point(bounds, 0.5, 0.5), point(bounds, 0.23, 0.9)], lineWidth)
			drawPath([point(bounds, 0.43, 0.1), point(bounds, 0.88, 0.5), point(bounds, 0.43, 0.9)], lineWidth)
			if getGlyphFamily() == "xnor":
				draw_circle(point(bounds, 0.93, 0.5), lineWidth * 0.62, glyphColor, false, lineWidth, true)
		"not":
			drawPath([point(bounds, 0.14, 0.14), point(bounds, 0.14, 0.86), point(bounds, 0.72, 0.5), point(bounds, 0.14, 0.14)], lineWidth, true)
			draw_circle(point(bounds, 0.84, 0.5), lineWidth * 0.72, glyphColor, false, lineWidth, true)
		"latchOn":
			draw_arc(point(bounds, 0.5, 0.56), bounds.size.x * 0.32, 0.0, TAU, 16, glyphColor, lineWidth, true)
			draw_line(point(bounds, 0.5, 0.04), point(bounds, 0.5, 0.47), glyphColor, lineWidth, true)
		"latchOff":
			draw_circle(point(bounds, 0.5, 0.5), bounds.size.x * 0.29, glyphColor, false, lineWidth, true)
			draw_line(point(bounds, 0.5, 0.14), point(bounds, 0.5, 0.48), glyphColor, lineWidth, true)
		"clock":
			draw_arc(point(bounds, 0.5, 0.5), bounds.size.x * 0.32, 0.0, TAU, 16, glyphColor, lineWidth, true)
			draw_line(point(bounds, 0.5, 0.5), point(bounds, 0.5, 0.23), glyphColor, lineWidth, true)
			draw_line(point(bounds, 0.5, 0.5), point(bounds, 0.72, 0.62), glyphColor, lineWidth, true)
		"led":
			draw_circle(point(bounds, 0.5, 0.5), bounds.size.x * 0.2, glyphColor)
			for angle in [0.0, TAU * 0.25, TAU * 0.5, TAU * 0.75]:
				var direction := Vector2(cos(angle), sin(angle))
				draw_line(point(bounds, 0.5, 0.5) + direction * bounds.size.x * 0.3, point(bounds, 0.5, 0.5) + direction * bounds.size.x * 0.43, glyphColor, lineWidth, true)
		_:
			draw_rect(bounds.grow(-lineWidth), glyphColor, false, lineWidth, true)

func getGlyphFamily() -> String:
	return glyphId

func point(bounds: Rect2, x: float, y: float) -> Vector2:
	return bounds.position + bounds.size * Vector2(x, y)

func drawPath(points: Array[Vector2], lineWidth: float, closed := false) -> void:
	if points.size() < 2:
		return
	for index in range(points.size() - 1):
		draw_line(points[index], points[index + 1], glyphColor, lineWidth, true)
	if closed:
		draw_line(points[-1], points[0], glyphColor, lineWidth, true)
