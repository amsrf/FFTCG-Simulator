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
			if card.type != "Summon":
				hand.update_character_drag(card, card.get_viewport().get_mouse_position())
				return
			card.position +=  Vector3(0, 0.1,-0.1)
			card.rotation = Vector3.ZERO
			# NO SIZE CHANGE HERE. The card keeps the size it already has, which after a hover is the STACK's size —
			# and the stack is where it is going. This used to force it to 1.05, which fought the hover and made a
			# played card shrink on the way out and then pop back up as it landed.
			card.offset = card.global_transform.origin - card._get_mouse_3d_position_on_card_plane()

func handle_released():
	if card.controller != "player":
		return
	if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND:
		# Selection happens on grab; release just ends any drag state.
		card.is_dragging = false
		hand.update_card_positions()
		card.apply_zone_scale()
		return
	var new_index = hand.find_index(card)
	# THE BOARD OWNS THE DROP AREA. This used to be a hard-coded 3 x 1.25 m
	# rectangle in the hand, inside an 8 x 4 m playmat, so most of the visible
	# board rejected the drop. Ask the Field for its real bounds instead.
	var over_board: bool = hand.field != null and hand.field.is_in_play_area(card.global_position)
	if card.type != "Summon":
		over_board = hand.character_drop_over_board(card.get_viewport().get_mouse_position())
	var charged := false
	if over_board && card.can_be_played():
		charged = hand.charge(card)
	else:
		hand.move_element(hand.cards,card.index,new_index)
		card.index = new_index
	card.is_dragging = false
	hand.update_card_positions()
	# Back to whatever size its zone wants. apply_zone_scale() rather than a hard-coded Vector3.ONE, because a card
	# that was just PLAYED has already been parked on the stack and must keep the stack's size — and because the
	# hand's own resting size lives in Card.ZONE_PRESENTATION, where a copy of it here would drift.
	if not charged:
		card.apply_zone_scale()
