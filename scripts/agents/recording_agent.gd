extends "res://scripts/agents/agent.gd"
## ONLINE LOCKSTEP, SENDING SIDE. Wraps the agent that really decides for a seat (a human's LocalAgent, or the AI) and
## sends every COMMITTED decision as a JSON message (`message_sent`). The other machine's RemoteAgent answers the same
## decisions from those messages, in the same order, so both games stay identical.
##
## - A simple decision is {kind, result}, cards as uids.
## - A PRIORITY WINDOW is one message: each card the seat tried to play, with the decisions made during that attempt.
## - A PAYMENT is what got selected (Backups with their element, hand cards), so the element picked while paying is
##   part of it rather than a separate message. TARGETS are the accepted picks plus confirm / cancel.
const CODEC := preload("res://scripts/agents/lockstep_codec.gd")

signal message_sent(json: String)

var inner: Agent
var sent: Array[String] = []
## The open priority window (take_priority), if any.
var _window: Dictionary = {}
## Inside pay_cost / choose_target: nested decisions are part of that one result, not separate messages.
var _opaque_depth: int = 0

func _init(wrapped: Agent) -> void:
	inner = wrapped

func bind(game_root: Node) -> void:
	super(game_root)
	inner.bind(game_root)

func _send(message: Dictionary) -> void:
	var json: String = CODEC.to_wire(message)
	sent.append(json)
	message_sent.emit(json)

## Record one decision: into the open play attempt during a priority window, otherwise as its own message.
func _record(kind: String, result: Variant) -> void:
	if _opaque_depth > 0:
		return
	var entry := {"kind": kind, "result": result}
	if not _window.is_empty():
		var plays: Array = _window["plays"]
		if not plays.is_empty():
			plays.back()["nested"].append(entry)
			return
	_send(entry)

## Game.play_card_for() tells us which card this play attempt is about.
func note_play(card: Card) -> void:
	if not _window.is_empty():
		_window["plays"].append({"card": card, "nested": []})

func take_priority(player_id: int) -> bool:
	_window = {"kind": "take_priority", "plays": []}
	var acted: bool = await inner.take_priority(player_id)
	_window["result"] = acted
	var message: Dictionary = _window
	_window = {}
	_send(message)
	return acted

func pay_cost(owner_id: int, cost: Dictionary) -> bool:
	_opaque_depth += 1
	var paid: bool = await inner.pay_cost(owner_id, cost)
	_opaque_depth -= 1
	var field = game.field
	var backups: Array = []
	for card in field.selected_cards_for_mana_conversion:
		backups.append([card, str(field.selected_mana_elements.get(card, card.mana_element()))])
	var hand_cards: Array = game.hand_for(owner_id).selected_cards_for_mana_conversion.duplicate()
	_record("pay_cost", {"paid": paid, "backups": backups, "hand": hand_cards})
	return paid

func choose_target(owner_id: int, source: Card, criteria: Dictionary) -> void:
	var picks: Array = []
	var cancelled := [false]
	var on_pick := func(card: Card) -> void: picks.append(card)
	var on_cancel := func() -> void: cancelled[0] = true
	game.field.target_picked.connect(on_pick)
	game.assistant.target_cancel.connect(on_cancel)
	_opaque_depth += 1
	await inner.choose_target(owner_id, source, criteria)
	_opaque_depth -= 1
	game.field.target_picked.disconnect(on_pick)
	game.assistant.target_cancel.disconnect(on_cancel)
	_record("choose_target", {"picks": picks, "cancel": cancelled[0]})

func decide_attacker(player_id: int) -> Card:
	var r: Card = await inner.decide_attacker(player_id); _record("decide_attacker", r); return r
func decide_attackers(player_id: int) -> Array:
	var r: Array = await inner.decide_attackers(player_id); _record("decide_attackers", r); return r
func decide_blocker(player_id: int, attacker: Card) -> Card:
	var r: Card = await inner.decide_blocker(player_id, attacker); _record("decide_blocker", r); return r
func choose_party_damage_split(player_id: int, party: Array, total: int) -> Array:
	var r: Array = await inner.choose_party_damage_split(player_id, party, total); _record("choose_party_damage_split", r); return r
func choose_damage_split(player_id: int, cards: Array, total: int) -> Array:
	var r: Array = await inner.choose_damage_split(player_id, cards, total); _record("choose_damage_split", r); return r
func confirm_optional(player_id: int, prompt: String) -> bool:
	var r: bool = await inner.confirm_optional(player_id, prompt); _record("confirm_optional", r); return r
func choose_hand_card_to_play(owner_id: int, ids: Array, filter: Dictionary) -> int:
	var r: int = await inner.choose_hand_card_to_play(owner_id, ids, filter); _record("choose_hand_card_to_play", r); return r
func choose_hand_card_to_bottom(owner_id: int, cards: Array) -> Card:
	var r: Card = await inner.choose_hand_card_to_bottom(owner_id, cards); _record("choose_hand_card_to_bottom", r); return r
func choose_break_zone_card(owner_id: int, ids: Array, filter: Dictionary) -> int:
	var r: int = await inner.choose_break_zone_card(owner_id, ids, filter); _record("choose_break_zone_card", r); return r
func choose_field_card(owner_id: int, candidates: Array, prompt: String = "Choose a card") -> Card:
	var r: Card = await inner.choose_field_card(owner_id, candidates, prompt); _record("choose_field_card", r); return r
func choose_deck_card(owner_id: int, ids: Array, filter: Dictionary) -> int:
	var r: int = await inner.choose_deck_card(owner_id, ids, filter); _record("choose_deck_card", r); return r
func choose_deck_cards(owner_id: int, ids: Array, filter: Dictionary, request, prompt: String = "Choose cards") -> Array:
	var r: Array = await inner.choose_deck_cards(owner_id, ids, filter, request, prompt); _record("choose_deck_cards", r); return r
func choose_element(owner_id: int, options: Array, prompt: String = "Choose an Element") -> String:
	var r: String = await inner.choose_element(owner_id, options, prompt); _record("choose_element", r); return r
func choose_number(owner_id: int, minimum: int, maximum: int, prompt: String = "Choose a number") -> int:
	var r: int = await inner.choose_number(owner_id, minimum, maximum, prompt); _record("choose_number", r); return r
func choose_mana_color(owner_id: int, card: Card, options: Array) -> String:
	var r: String = await inner.choose_mana_color(owner_id, card, options); _record("choose_mana_color", r); return r
func choose_discard(owner_id: int, cards: Array) -> Card:
	var r: Card = await inner.choose_discard(owner_id, cards); _record("choose_discard", r); return r
func choose_skill(player_id: int, card: Card, skills: Array, usable: Array = []) -> int:
	var r: int = await inner.choose_skill(player_id, card, skills, usable); _record("choose_skill", r); return r
func choose_sacrifice(player_id: int, candidates: Array) -> Card:
	var r: Card = await inner.choose_sacrifice(player_id, candidates); _record("choose_sacrifice", r); return r
