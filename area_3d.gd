extends Area3D

var _on_press_callback: Callable
var _is_hovered := false

func _ready():
	input_event.connect(_on_input_event)

func set_on_press_callback(callback: Callable):
	_on_press_callback = callback
# Called when the Area3D receives input
func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _on_press_callback:
				_on_press_callback.call()
				
# Handle hover state
func _on_area_mouse_entered():
	_is_hovered = true# Optional: For visual feedback

func _on_area_mouse_exited():
	_is_hovered = false
