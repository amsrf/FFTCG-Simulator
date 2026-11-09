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
				# PILE CARDS INSPECT WITH EITHER BUTTON. A card in the Break Zone, the removed pile or the damage
				# zone has nothing to drag or focus, so a right-click there means the same thing a left-click does:
				# open the zone. Everywhere else right-click keeps its old focus behaviour.
				if parent.current_zone == Card.Zone.DAMAGE \
						or parent.current_zone == Card.Zone.GRAVEYARD \
						or parent.current_zone == Card.Zone.REMOVED:
					emit_signal("card_grabbed", parent)
		else:
			emit_signal("card_released", parent)  # Release applies to both buttons
