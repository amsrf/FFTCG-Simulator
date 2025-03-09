extends Node3D
var card_offset = Vector3(0, 0.005, 0)
var randomness_range = Vector3(0.002, 0.002, 0.002)

func add_cards(cards: Array):
	for card in cards:
		add_child(card)
	update_card_positions()
	
	
func update_card_positions():
	var cards = get_children()
	for i in range(cards.size()):
		var base_offset = i * card_offset
		var random_offset = Vector3(
			randf_range(-randomness_range.x, randomness_range.x),
			randf_range(-randomness_range.y, randomness_range.y),
			randf_range(-randomness_range.z, randomness_range.z)
		)
		cards[i].position += base_offset + random_offset

func arc_motion(t: float, start: Vector3, mid: Vector3, end: Vector3) -> Vector3:
	return start.lerp(mid, t).lerp(mid.lerp(end, t), t)
	
func draw_card(target_position: Vector3, on_finished: Callable):
	var tween = create_tween()
	var card = get_children()[0]
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# Arc motion
	var midpoint = (card.position + target_position) / 2
	midpoint.y += 0.2
	tween.tween_method(arc_motion.bind(card.position, midpoint, target_position), 0.0, 1.0, 0.5)
	
	# Flip animation
	var target_rotation = card.rotation + Vector3(0, 0, deg_to_rad(180))
	tween.parallel().tween_property(card, "rotation", target_rotation, 0.5)
	
	# Scale animation
	tween.parallel().tween_property(card, "scale", Vector3(1.2, 1.2, 1.2), 0.25)
	tween.parallel().tween_property(card, "scale", Vector3(1, 1, 1), 0.25).set_delay(0.25)
	
	# Connect the tween's finished signal to the callback
	tween.finished.connect(on_finished.bind(card))
