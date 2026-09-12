extends Agent
class_name LocalAgent
## Human playing at this machine: every decision is answered through the
## existing UI (pass button, card clicks, modal buttons).

func take_priority(_player_id: int) -> void:
	var assistant: Assistant = game.assistant
	assistant.show_pass_priority_button()
	await assistant.pressed_pass_priority

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
