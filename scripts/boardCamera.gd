extends Camera2D

@export var zoomStep := Vector2(0.05, 0.05)
@export var minZoom := Vector2(0.15, 0.15)
@export var maxZoom := Vector2(1.25, 1.25)
@export var dragMargin := 512.0
@export var board: Node2D

var limitRect := Rect2()
var hasLimit := false
var isDragging := false
var lastMousePosition := Vector2.ZERO

func _process(_delta: float) -> void:
	if not hasLimit:
		return
	var boundedMinZoom := getBoundedMinZoom()
	var constrainedZoom := Vector2(
		maxf(zoom.x, boundedMinZoom.x),
		maxf(zoom.y, boundedMinZoom.y)
	)
	if zoom != constrainedZoom:
		zoom = constrainedZoom
	clampPosition()

func setDragBounds(bounds: Rect2) -> void:
	limitRect = bounds
	hasLimit = true
	clampPosition()

func getBoundedMinZoom() -> Vector2:
	if not hasLimit:
		return minZoom
	var viewportSize := get_viewport().get_visible_rect().size
	var allowedSize := limitRect.size + Vector2.ONE * dragMargin * 2.0
	var requiredZoom := maxf(viewportSize.x / allowedSize.x, viewportSize.y / allowedSize.y)
	var boundedZoom := minf(maxf(minZoom.x, requiredZoom), maxZoom.x)
	return Vector2.ONE * boundedZoom

func clampPosition() -> void:
	if not hasLimit:
		return
	var allowedRect := limitRect.grow(dragMargin)
	var safeZoom := Vector2(maxf(zoom.x, 0.0001), maxf(zoom.y, 0.0001))
	var viewHalfSize := get_viewport().get_visible_rect().size / safeZoom * 0.5
	var minPosition := allowedRect.position + viewHalfSize
	var maxPosition := allowedRect.end - viewHalfSize
	var clampedPosition := global_position
	if minPosition.x > maxPosition.x:
		clampedPosition.x = allowedRect.get_center().x
	else:
		clampedPosition.x = clampf(clampedPosition.x, minPosition.x, maxPosition.x)
	if minPosition.y > maxPosition.y:
		clampedPosition.y = allowedRect.get_center().y
	else:
		clampedPosition.y = clampf(clampedPosition.y, minPosition.y, maxPosition.y)
	global_position = clampedPosition

func zoomAtPointer(amount: Vector2) -> void:
	var oldZoom := zoom
	var newZoom := (zoom + amount).clamp(getBoundedMinZoom(), maxZoom)
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
