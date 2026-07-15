extends Node2D

const MarqueeFillColor := Color("5fa8ff", 0.11)
const MarqueeLineColor := Color("8dc4ff", 0.92)
const SelectedFillColor := Color("f2c94c", 0.13)
const SelectedLineColor := Color("f2c94c", 0.96)
const InvalidFillColor := Color("ed697b", 0.13)
const InvalidLineColor := Color("ff8e9d", 0.96)

var OverlayRect := Rect2()
var HasOverlay := false
var IsSelection := false
var IsValid := true
var DashLength := 8.0

func showGridRect(bounds: Rect2i, cellSize: float, finalSelection: bool, nextIsValid := true) -> void:
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		clearOverlay()
		return
	OverlayRect = Rect2(Vector2(bounds.position) * cellSize, Vector2(bounds.size) * cellSize)
	HasOverlay = true
	IsSelection = finalSelection
	IsValid = nextIsValid
	DashLength = maxf(6.0, cellSize * 0.16)
	queue_redraw()

func clearOverlay() -> void:
	if not HasOverlay:
		return
	HasOverlay = false
	queue_redraw()

func _draw() -> void:
	if not HasOverlay:
		return
	var fillColor := MarqueeFillColor
	var lineColor := MarqueeLineColor
	if not IsValid:
		fillColor = InvalidFillColor
		lineColor = InvalidLineColor
	elif IsSelection:
		fillColor = SelectedFillColor
		lineColor = SelectedLineColor
	draw_rect(OverlayRect, fillColor, true)
	var topLeft := OverlayRect.position
	var topRight := Vector2(OverlayRect.end.x, OverlayRect.position.y)
	var bottomLeft := Vector2(OverlayRect.position.x, OverlayRect.end.y)
	var bottomRight := OverlayRect.end
	draw_dashed_line(topLeft, topRight, lineColor, 2.0, DashLength, true, true)
	draw_dashed_line(topRight, bottomRight, lineColor, 2.0, DashLength, true, true)
	draw_dashed_line(bottomRight, bottomLeft, lineColor, 2.0, DashLength, true, true)
	draw_dashed_line(bottomLeft, topLeft, lineColor, 2.0, DashLength, true, true)
