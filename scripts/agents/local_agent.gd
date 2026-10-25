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

## The human's whole formation: they may have built a party by clicking, so the answer is the party as it stands —
## which for a single click is a list of one.
func decide_attackers(_player_id: int) -> Array:
	var assistant: Assistant = game.assistant
	assistant.set_declare_attack_button('No Attack')
	await assistant.advance_attack_declaration_step
	var field: Field = game.field
	return field.party_members().duplicate()

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

## The blocker's power divided across the party it blocked. The human chooses in the distribution window; the rules
## layer only awaits the answer, exactly as it awaits decide_blocker().
##
## Loaded by PATH, not by class name: this scene is new and the headless class cache does not know it.
const PARTY_SPLIT := preload("res://party_split.tscn")
const DECK_SEARCH := preload("res://deck_search.tscn")

func choose_party_damage_split(_player_id: int, party: Array, total: int) -> Array:
	if party.is_empty():
		return []
	var window = PARTY_SPLIT.instantiate()
	game.add_child(window)
	window.open(party, total)
	var split: Array = await window.finished
	return split

## "Your opponent discards 1 card from their hand." A DISCARD is the owner's choice, so this is the human's answer:
## the same hand-selection UI the S cost uses, with any card legal.
##
## This lives here rather than in Game on purpose. The rules layer asks the seat that owns the hand and gets a card
## back; whether that seat is a person at this keyboard, an AI, or a remote opponent is the agent's business. Once
## a RemoteAgent exists it implements this same method and the rules layer does not change at all.
## CONFIRM / REFUSE for a "you may" instruction. The confirm button carries the short prompt ("Deal 6000"), so the
## player can see what they are agreeing to; Refuse is the cancel button.
##
## The answers live on MEMBERS because GDScript lambdas capture locals by value — assigning to a local inside the
## callback would never reach this function.
var _optional_answer: bool = false
var _optional_settled: bool = false

func confirm_optional(_player_id: int, prompt: String) -> bool:
	var assistant: Assistant = game.assistant
	_optional_settled = false
	_optional_answer = false
	var text: String = prompt if prompt != "" else "Confirm"
	# A MODAL, so the pass-phase button cannot sit on top of Confirm/Refuse. The button rack and its animation are
	# unchanged; only the input mode is pushed.
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.OPTIONAL_CHOICE)
	assistant.show_modal(text, "Refuse",
		func():
			_optional_answer = true
			_optional_settled = true,
		func():
			_optional_answer = false
			_optional_settled = true,
		true, true)
	while not _optional_settled:
		await game.get_tree().process_frame
	assistant.hide_buttons()
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.OPTIONAL_CHOICE)
	return _optional_answer

## Free play from hand — the same window, over the hand instead of a zone.
func choose_hand_card_to_play(_owner_id: int, ids: Array, filter: Dictionary) -> int:
	if ids.is_empty():
		return -1
	var window = DECK_SEARCH.instantiate()
	game.add_child(window)
	window.open(ids, filter, "Choose a card in your hand to play.")
	return await window.finished

## THE BREAK ZONE SEARCH IS THE DECK SEARCH. Same fan, same hover preview, same look — only the cards and the
## subtitle differ, which is exactly what the window was built to allow.
func choose_break_zone_card(_owner_id: int, ids: Array, filter: Dictionary) -> int:
	if ids.is_empty():
		return -1
	var window = DECK_SEARCH.instantiate()
	game.add_child(window)
	window.open(ids, filter, "Choose a card in your Break Zone.")
	return await window.finished

## A generic "select one of these field cards" picker. The window is the same card browser; the ids are the actual
## candidates, so the chosen id maps back to a card.
func choose_field_card(_owner_id: int, candidates: Array, prompt: String = "Choose a card") -> Card:
	if candidates.is_empty():
		return null
	var ids: Array = []
	for card in candidates:
		ids.append(card.id)
	var window = DECK_SEARCH.instantiate()
	game.add_child(window)
	window.open(ids, {}, prompt)
	var chosen: int = await window.finished
	if chosen < 0:
		return null
	for card in candidates:
		if card.id == chosen:
			return card
	return null

## The Emperor 185: search this owner's deck. Same window, different subtitle.
func choose_deck_card(_owner_id: int, ids: Array, filter: Dictionary) -> int:
	if ids.is_empty():
		return -1
	var window = DECK_SEARCH.instantiate()
	game.add_child(window)
	window.open(ids, filter, "Choose a card in your deck.")
	return await window.finished

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

## "Place 1 card from your hand at the bottom of your deck" (Yuj 175). Same picker as a discard, different verb.
func choose_hand_card_to_bottom(player_id: int, _cards: Array) -> Card:
	var hand: Hand = game.hand_for(player_id)
	if hand == null:
		return null
	var assistant: Assistant = game.assistant
	GlobalVariables.push_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	hand.begin_choose_card({})
	assistant.show_choose_card_buttons("Put on bottom", "Cancel")
	var play: bool = await assistant.choose_card_finished
	var chosen: Card = hand.selected_card_for_effect
	hand.end_choose_card()
	assistant.hide_buttons()
	GlobalVariables.pop_modal(GlobalVariables.Player_Mode.CHOOSE_CARD_IN_HAND)
	return chosen if play else null

const SKILL_CHOICE := preload("res://skill_choice.tscn")

## Which ability? A modal listing each ability's text. The human selects a container, Confirm commits, Cancel (-1)
## abandons the activation — and nothing has been tapped or paid at that point.
func choose_skill(_player_id: int, card: Card, skills: Array, usable: Array = []) -> int:
	if card == null or skills.size() <= 1:
		return 0
	var window = SKILL_CHOICE.instantiate()
	game.add_child(window)
	window.call("open", card, skills, usable)
	var index: int = await window.finished
	return index

## The human distributes the damage. `allow_cancel` adds the Back button (and Escape): for Bloodfest, cancelling must
## return to choosing targets, which the rules layer does when it sees an empty array come back.
func choose_damage_split(_player_id: int, cards: Array, total: int) -> Array:
	if cards.is_empty():
		return []
	var window = PARTY_SPLIT.instantiate()
	game.add_child(window)
	window.allow_cancel = true
	window.open(cards, total)
	var split: Array = await window.finished
	return split

## The human picks which Backup to put into the Break Zone. Reuses the card-picker window from the deck search — a fan
## of cards with art, Confirm and Cancel — because it is already the "choose one card" UI in this project.
func choose_sacrifice(_player_id: int, candidates: Array) -> Card:
	if candidates.is_empty():
		return null
	var ids: Array = []
	for c in candidates:
		if c != null and is_instance_valid(c):
			ids.append(c.id)
	var window = DECK_SEARCH.instantiate()
	game.add_child(window)
	window.call("open", ids, {})
	var chosen: int = await window.finished
	for c in candidates:
		if c != null and is_instance_valid(c) and c.id == chosen:
			return c
	return null
