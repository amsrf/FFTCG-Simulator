# HandCardState.gd
extends CardState
class_name HandCardState  
var card: Card
var hand: Hand

func _init(card_ref: Card):
	card = card_ref
	hand = card.get_parent()

func handle_grabbed():
	# Only the player's own hand is interactive. Opponent cards use the same
	# Hand scene but must never be draggable/selectable.
	if card.controller != "player":
		return
	var player_mode = GlobalVariables.get_player_mode()
	var instructions: Array[Instruction]
	match player_mode:
		GlobalVariables.Player_Mode.PAYING_COST:
			var selected_cards = hand.selected_cards_for_mana_conversion
			if selected_cards.has(card):
				card.crystal_instance.queue_free()
				hand.remove_card_from_mana_conversion(card)
			else:
				hand.add_card_to_mana_conversion(card)
				card.crystal_instance = card.crystal_scene.instantiate()
				card.add_child(card.crystal_instance)
				card.crystal_instance.position = Vector3(0, 0.05, -0.35)
		GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
			# Triggered "may" choice: only criteria-matching cards can be
			# selected, and selecting one unselects the previous one.
			if card.matches_criteria(hand.choose_card_criteria):
				hand.toggle_effect_card_selection(card)
		_:
			card.is_dragging = true
			card.position +=  Vector3(0, 0.1,-0.1)
			card.rotation = Vector3.ZERO
			card.scale = Vector3.ONE * 1.05
			card.offset = card.global_transform.origin - card._get_mouse_3d_position_on_card_plane()

func handle_released():
	if card.controller != "player":
		return
	if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
		# Selection happens on grab; release just ends any drag state.
		card.is_dragging = false
		hand.update_card_positions()
		card.scale = Vector3.ONE
		return
	var new_index = hand.find_index(card)
	# Define the rectangle bounds
	var x_min = -1.5
	var x_max = 1.5
	var z_min = -1.25
	var z_max = 0
	
	# Get the card's global position
	var card_position = card.global_position
	# Check if the card is inside the rectangle
	if (card_position.x >= x_min && card_position.x <= x_max &&
		card_position.z >= z_min && card_position.z <= z_max && card.can_be_played()):
		hand.charge(card)
	else:
		hand.move_element(hand.cards,card.index,new_index)
		card.index = new_index
	card.is_dragging = false
	hand.update_card_positions()
	card.scale = Vector3.ONE
