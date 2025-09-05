extends Area3D

var parent
signal card_released(card)
signal card_grabbed(card)

func _ready():
	input_event.connect(_on_input_event)
	parent = get_parent()

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:  # Left-click
				emit_signal("card_grabbed", parent)
			elif event.button_index == MOUSE_BUTTON_RIGHT:  # Right-click
				GlobalVariables.emit_signal("focus_card", parent.id)  # Emit new signal
		else:
			emit_signal("card_released", parent)  # Release applies to both buttons
