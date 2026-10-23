extends Agent
class_name LocalAgent
## Human playing at this machine: every decision is answered through the
## existing UI (pass button, card clicks, modal buttons).

func take_priority(_player_id: int) -> bool:
	# The human's priority window ends two ways: they press pass, or they
	# perform an action — the rules hand priority to the opponent the moment an
	# action is performed. Both routes end at Game.priority_window_ended, which
	# carries which of the two happened.
	var assistant: Assistant = game.assistant
	assistant.show_pass_priority_button()
	var acted: bool = await game.priority_window_ended
	return acted

func decide_attacker(_player_id: int) -> Card:
	# The human selects an attacker by clicking cards; the (Attack / No Attack)
	# button ends the declaration step. Whatever is selected at that point is
	# the declared attacker, or null for no attack.
	var assistant: Assistant = game.assistant
	assistant.set_declare_attack_button('No Attack')
	await assistant.advance_attack_declaration_step
	var field: Field = game.field
	return field.attacker_card

func decide_blocker(_player_id: int, attacker: Card) -> Card:
	# The human selects a blocker by clicking their own untapped Forwards (the
	# button label flips to "Block" once something is selected) and the button
	# ends the declaration. Game pushes the BLOCKING mode and resets the
	# selection before calling this, so there is nothing to set up here.
	if attacker == null:
		return null
	var assistant: Assistant = game.assistant
	await assistant.advance_blocker_declaration_step
	var field: Field = game.field
	return field.blocker_card

## "Your opponent discards 1 card from their hand." A DISCARD is the owner's choice, so this is the human's answer:
## the same hand-selection UI the S cost uses, with any card legal.
##
## This lives here rather than in Game on purpose. The rules layer asks the seat that owns the hand and gets a card
## back; whether that seat is a person at this keyboard, an AI, or a remote opponent is the agent's business. Once
## a RemoteAgent exists it implements this same method and the rules layer does not change at all.
func choose_discard(player_id: int, _cards: Array) -> Card:
	var hand: Hand = game.hand_for(player_id)
	if hand == null:
		return null
	var assistant: Assistant = game.assistant
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	hand.begin_choose_card({})
	assistant.show_choose_card_buttons("Discard", "Cancel")
	var play: bool = await assistant.choose_card_finished
	var chosen: Card = hand.selected_card_for_effect
	hand.end_choose_card()
	assistant.hide_buttons()
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	return chosen if play else null
