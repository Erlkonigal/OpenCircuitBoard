extends Camera2D

@export var ZoomStep := Vector2(0.05, 0.05)
@export var MinZoom := Vector2(0.15, 0.15)
@export var MaxZoom := Vector2(1.25, 1.25)
@export var Board: Node2D

var LimitRect := Rect2()
var HasLimit := false
var IsDragging := false
var LastMousePosition := Vector2.ZERO

func _process(_delta: float) -> void:
	if not HasLimit:
		return
	clampPosition()

func setDragBounds(bounds: Rect2) -> void:
	LimitRect = bounds
	HasLimit = true
	clampPosition()

func clampPosition() -> void:
	if not HasLimit:
		return
	global_position = global_position.clamp(LimitRect.position, LimitRect.end)

func zoomAtPointer(amount: Vector2) -> void:
	var oldZoom := zoom
	var newZoom := (zoom + amount).clamp(MinZoom, MaxZoom)
	if oldZoom == newZoom:
		return
	var anchorPosition := get_global_mouse_position()
	zoom = newZoom
	global_position = anchorPosition + (global_position - anchorPosition) * oldZoom.x / newZoom.x
	clampPosition()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			IsDragging = event.pressed
			LastMousePosition = event.position
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoomAtPointer(ZoomStep)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoomAtPointer(-ZoomStep)
	elif event is InputEventMouseMotion and IsDragging:
		global_position += (LastMousePosition - event.position) / zoom.x
		clampPosition()
		LastMousePosition = event.position
		force_update_scroll()
		if Board:
			if Board.has_method("updateSelectorPosition"):
				Board.call("updateSelectorPosition")
			if Board.has_method("updatePastePreviewAtPointer"):
				Board.call("updatePastePreviewAtPointer")
