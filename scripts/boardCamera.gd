extends Camera2D

@export var zoomStep := Vector2(0.05, 0.05)
@export var minZoom := Vector2(0.15, 0.15)
@export var maxZoom := Vector2(1.25, 1.25)
@export var board: Node2D

var limitRect := Rect2()
var hasLimit := false
var isDragging := false
var lastMousePosition := Vector2.ZERO

func _process(_delta: float) -> void:
	if not hasLimit:
		return
	clampPosition()

func setDragBounds(bounds: Rect2) -> void:
	limitRect = bounds
	hasLimit = true
	clampPosition()

func clampPosition() -> void:
	if not hasLimit:
		return
	global_position = global_position.clamp(limitRect.position, limitRect.end)

func zoomAtPointer(amount: Vector2) -> void:
	var oldZoom := zoom
	var newZoom := (zoom + amount).clamp(minZoom, maxZoom)
	if oldZoom == newZoom:
		return
	var anchorPosition := get_global_mouse_position()
	zoom = newZoom
	global_position = anchorPosition + (global_position - anchorPosition) * oldZoom.x / newZoom.x
	clampPosition()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			isDragging = event.pressed
			lastMousePosition = event.position
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoomAtPointer(zoomStep)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoomAtPointer(-zoomStep)
	elif event is InputEventMouseMotion and isDragging:
		global_position += (lastMousePosition - event.position) / zoom.x
		clampPosition()
		lastMousePosition = event.position
		force_update_scroll()
		if board and board.has_method("updateSelectorPosition"):
			board.call("updateSelectorPosition")
