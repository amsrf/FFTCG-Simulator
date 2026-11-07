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
	match player_mode:
		GlobalVariables.Player_Mode.PAYING_COST:
			# The Hand owns the "selected for mana" marker (Card.show_mana_crystal).
			if hand.selected_cards_for_mana_conversion.has(card):
				hand.remove_card_from_mana_conversion(card)
			else:
				hand.add_card_to_mana_conversion(card)
		GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
			# Triggered "may" choice: only criteria-matching cards can be
			# selected, and selecting one unselects the previous one.
			if card.matches_criteria(hand.choose_card_criteria):
				hand.toggle_effect_card_selection(card)
		_:
			card.begin_drag()
			hand.begin_character_drag(card)

func handle_released():
	if card.controller != "player":
		return
	if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
		# Selection happens on grab; release just ends any drag state.
		card.is_dragging = false
		hand.update_card_positions()
		card.apply_zone_scale()
		return
	# RELEASING A HAND CARD FROM THE CAST STANCE STARTS PAYMENT.
	# The stance itself is the drop confirmation: the pointer has already left
	# the hand band, so there is no extra "is the pointer over the mat" check.
	if hand.character_drag_latched():
		if card.can_be_played() and hand.charge(card):
			hand.begin_character_charge(card)
			card.is_dragging = false
			return
		# Illegal or failed charge: put the card back in the hand.
		hand.end_character_drag(card)
		card.is_dragging = false
		hand.update_card_positions()
		card.apply_zone_scale()
		return
	# Below the ready boundary, release only reorders the hand.
	var new_index = hand.find_index(card)
	hand.end_character_drag(card)
	hand.move_element(hand.cards, card.index, new_index)
	card.index = new_index
	card.is_dragging = false
	hand.update_card_positions()
	card.apply_zone_scale()
