extends Area3D

signal button_pressed
signal button_hovered
signal button_unhovered

var _on_press_callback: Callable
var _is_hovered := false
var _input_enabled := true

func _ready():
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func set_on_press_callback(callback: Callable):
	_on_press_callback = callback

## Toggles whether this area can receive mouse input (ray picking). Invisible
## buttons must be disabled so they cannot swallow clicks meant for the table.
func set_input_enabled(enabled: bool):
	_input_enabled = enabled
	input_ray_pickable = enabled

func _on_mouse_entered():
	_is_hovered = true
	button_hovered.emit()

func _on_mouse_exited():
	_is_hovered = false
	button_unhovered.emit()

# Called when the Area3D receives input
func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int):
	if not _input_enabled:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			button_pressed.emit()
			if _on_press_callback:
				_on_press_callback.call()
