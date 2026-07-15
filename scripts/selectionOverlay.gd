extends Node2D

const marqueeFillColor := Color("5fa8ff", 0.11)
const marqueeLineColor := Color("8dc4ff", 0.92)
const selectedFillColor := Color("f2c94c", 0.13)
const selectedLineColor := Color("f2c94c", 0.96)
const invalidFillColor := Color("ed697b", 0.13)
const invalidLineColor := Color("ff8e9d", 0.96)

var overlayRect := Rect2()
var hasOverlay := false
var isSelection := false
var isValid := true
var dashLength := 8.0

func showGridRect(bounds: Rect2i, cellSize: float, finalSelection: bool, nextIsValid := true) -> void:
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		clearOverlay()
		return
	overlayRect = Rect2(Vector2(bounds.position) * cellSize, Vector2(bounds.size) * cellSize)
	hasOverlay = true
	isSelection = finalSelection
	isValid = nextIsValid
	dashLength = maxf(6.0, cellSize * 0.16)
	queue_redraw()

func clearOverlay() -> void:
	if not hasOverlay:
		return
	hasOverlay = false
	queue_redraw()

func _draw() -> void:
	if not hasOverlay:
		return
	var fillColor := marqueeFillColor
	var lineColor := marqueeLineColor
	if not isValid:
		fillColor = invalidFillColor
		lineColor = invalidLineColor
	elif isSelection:
		fillColor = selectedFillColor
		lineColor = selectedLineColor
	draw_rect(overlayRect, fillColor, true)
	var topLeft := overlayRect.position
	var topRight := Vector2(overlayRect.end.x, overlayRect.position.y)
	var bottomLeft := Vector2(overlayRect.position.x, overlayRect.end.y)
	var bottomRight := overlayRect.end
	draw_dashed_line(topLeft, topRight, lineColor, 2.0, dashLength, true, true)
	draw_dashed_line(topRight, bottomRight, lineColor, 2.0, dashLength, true, true)
	draw_dashed_line(bottomRight, bottomLeft, lineColor, 2.0, dashLength, true, true)
	draw_dashed_line(bottomLeft, topLeft, lineColor, 2.0, dashLength, true, true)
