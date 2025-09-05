extends Node3D
var card_offset = Vector3(0, 0.0033, 0)
var randomness_range = Vector3(0.015, 0.0033, 0.015)
@export var deck_cards = []

func add_cards(cards: Array):
	for card in cards:
		deck_cards.append(card)
		add_child(card)
	update_card_positions()
	
	
func update_card_positions():
	for i in range(deck_cards.size()):
		var base_offset = i * card_offset
		var random_offset = Vector3(
			randf_range(-randomness_range.x, randomness_range.x),
			0,
			randf_range(-randomness_range.z, randomness_range.z)
		)
		deck_cards[i].position += base_offset + random_offset
	
	#card.get_node("AnimationPlayer").play("draw")
