extends Node3D
var card_offset = Vector3(0, 0.005, 0)
var randomness_range = Vector3(0.015, 0.005, 0.015)
@export var graveyard_cards = []
	
func add_card(card):
	graveyard_cards.append(card)
	card.reparent(self,false)
	card.position = Vector3.ZERO
	
func update_card_positions():
	for i in range(graveyard_cards.size()):
		var base_offset = i * card_offset
		var random_offset = Vector3(
			randf_range(-randomness_range.x, randomness_range.x),
			0,
			randf_range(-randomness_range.z, randomness_range.z)
		)
		graveyard_cards[i].position += base_offset + random_offset
	
	#card.get_node("AnimationPlayer").play("draw")
