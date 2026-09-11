extends Agent
class_name LocalAgent
## Human playing at this machine: every decision is answered through the
## existing UI (pass button, attacker clicks, modal buttons).

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

func decide_blocker(_player_id: int, _attacker: Card) -> Card:
	# No manual blocker UI yet; the defender simply does not block.
	return null
