extends "res://scripts/agents/agent.gd"
## ONLINE LOCKSTEP, SENDING SIDE. Wraps the agent that really decides for a seat (a human's LocalAgent, or the AI) and
## sends every COMMITTED decision as a JSON message (`message_sent`). The other machine's RemoteAgent answers the same
## decisions from those messages, in the same order, so both games stay identical.
##
## - A simple decision is {kind, result}, cards as uids.
## - Each PLAY is sent the moment it commits, so the other player sees it at once: {kind: "play", card, nested}, the
##   nested decisions being the ones made during that attempt (payment, targets...). An ABILITY activated from the
##   field is a play too, with "ability": true and its "skill"; its nested decisions come in the order the activation
##   asks them (X, sacrifice, discards, S card, payment, targets).
## - The end of a PRIORITY WINDOW is its own message, {kind: "take_priority", result}: passed, or acted on the stack.
##   A Character cast keeps priority, so several plays can come before it.
## - A PAYMENT is what got selected (Backups with their element, hand cards), so the element picked while paying is
##   part of it rather than a separate message. TARGETS are the accepted picks plus confirm / cancel.
const CODEC := preload("res://scripts/agents/lockstep_codec.gd")

signal message_sent(json: String)

var inner: Agent
var sent: Array[String] = []
## Which decision the wrapped agent is waiting on right now ("" when none). A human's UI, a test driver or a debug
## overlay can read it.
var pending_kind: String = ""
## Counts priority windows, so a driver can act once per window.
var window_serial: int = 0
## Wrapping a HUMAN: their casts, payments and target picks happen through the UI, not through agent calls, so they
## are captured from the game's signals instead (see _hook_human()). An AI decides through the agent calls themselves.
var _human: bool = false
## The local player's cast in progress (a DRAFT until it commits): {"card", "nested"}. Cancelled drafts are never sent.
var _draft: Dictionary = {}
var _payment: Dictionary = {"backups": [], "hand": []}
## The current targeting session belongs to the local player, and its picks so far.
var _session_local: bool = false
var _picks: Array = []
## The open priority window (take_priority), if any.
var _window: Dictionary = {}
## An AGENT's play attempt in progress (Game.play_card_for): its decisions nest here until note_play_done() sends it.
var _current_play: Dictionary = {}
## Inside pay_cost / choose_target: nested decisions are part of that one result, not separate messages.
var _opaque_depth: int = 0

func _init(wrapped: Agent) -> void:
	inner = wrapped
	_human = wrapped is LocalAgent

func is_human() -> bool:
	return inner.is_human()

func bind(game_root: Node) -> void:
	super(game_root)
	inner.bind(game_root)
	if _human:
		_hook_human.call_deferred()

## THE HUMAN'S COMMITTED ACTIONS, from the game's own signals. A cast is a draft from charge_start until it commits
## (Game.note_action_taken ends the priority window as "acted"); a cancel anywhere drops it, and nothing is sent.
func _hook_human() -> void:
	var hand = game.hand_for(1)
	hand.charge_start.connect(_on_draft_start)
	hand.selected_cards_for_mana_has_changed.connect(func(_a, _e): _snapshot_payment())
	game.field.selected_cards_for_mana_has_changed.connect(func(_a, _e): _snapshot_payment())
	game.assistant.charge_complete.connect(_on_draft_paid)
	game.assistant.charge_cancelled.connect(_on_draft_dropped)
	game.field.targeting_started.connect(_on_targeting_started)
	game.field.target_picked.connect(_on_pick)
	game.assistant.target_complete.connect(func(): _on_targeting_done(false))
	game.assistant.target_cancel.connect(func(): _on_targeting_done(true))
	game.action_committed.connect(_on_action_committed)
	game.priority_window_ended.connect(_on_window_ended)
	game.field.skill_activation_begun.connect(_on_activation_begun)
	game.stack.s_cost_chosen.connect(_on_s_cost_chosen)
	game.stack.skill_activation_committed.connect(_on_activation_committed)

## An ability activation is a draft like a cast: nothing is sent unless it commits.
func _on_activation_begun(card: Card) -> void:
	if card == null or card.controller != Card.PLAYER:
		return
	_draft = {"kind": "activate", "card": card, "skill": -1, "nested": []}
	_payment = {"backups": [], "hand": []}

func _on_s_cost_chosen(card: Card) -> void:
	if _is_activation():
		_draft["nested"].append({"kind": "choose_discard", "result": card})

func _on_activation_committed(proxy: Card) -> void:
	if _is_activation() and proxy != null:
		_draft["skill"] = proxy.skill_activation_index

func _is_activation() -> bool:
	return str(_draft.get("kind", "")) == "activate"

func _on_draft_start(card: Card) -> void:
	if card == null or card.controller != Card.PLAYER:
		return
	_draft = {"card": card, "nested": []}
	_payment = {"backups": [], "hand": []}

func _snapshot_payment() -> void:
	if _draft.is_empty():
		return
	var field = game.field
	var backups: Array = []
	for card in field.selected_cards_for_mana_conversion:
		backups.append([card, str(field.selected_mana_elements.get(card, card.mana_element()))])
	_payment = {"backups": backups, "hand": game.hand_for(1).selected_cards_for_mana_conversion.duplicate()}

## The payment is the FIRST thing a replay asks for. A Character commits inside the very confirm that pays for it
## (charge_complete -> cast -> window ends), possibly before this handler runs, so _on_window_ended() adds it too.
func _on_draft_paid() -> void:
	_add_payment_if_missing()

func _add_payment_if_missing() -> void:
	if _draft.is_empty():
		return
	for entry in _draft["nested"]:
		if entry.get("kind", "") == "pay_cost":
			return
	var entry := {"kind": "pay_cost", "result": {"paid": true, "backups": _payment["backups"], "hand": _payment["hand"]}}
	if _is_activation():
		# An ability pays AFTER its other costs were picked, and only when it has a mana cost (charge_complete): so the
		# payment goes where it happened, and a free ability never gets one.
		if game.stack.skill_activation_proxy != null:
			_draft["nested"].append(entry)
		return
	_draft["nested"].push_front(entry)

func _on_draft_dropped() -> void:
	_draft = {}

func _on_targeting_started(source: Card) -> void:
	_session_local = _opaque_depth == 0 and source != null and is_instance_valid(source) and source.controller == Card.PLAYER
	_picks = []

func _on_pick(card: Card) -> void:
	if _session_local:
		_picks.append(card)

func _on_targeting_done(cancelled: bool) -> void:
	if not _session_local:
		return
	_session_local = false
	var entry := {"kind": "choose_target", "result": {"picks": _picks.duplicate(), "cancel": cancelled}}
	if not _draft.is_empty():
		if cancelled:
			_draft = {}   # backing out of a cast's targets abandons the cast: a draft, never sent
		else:
			_draft["nested"].append(entry)
		return
	# A target chosen while an effect resolves: the other machine asks the remote seat for exactly this.
	_send(entry)

## THE HUMAN'S DRAFT COMMITTED: sent now, so the other player sees the play the moment it happens.
func _on_action_committed() -> void:
	if not _human or _draft.is_empty():
		return
	# THE TARGETS ARE PART OF THE PLAY. Confirming the targets is what commits a Summon or an ability, and which of the
	# confirm's handlers runs first (the stack committing, or _on_targeting_done) is down to connection order. So a
	# session still open here is closed now and its picks go into the play, never after it.
	if _session_local:
		_session_local = false
		_draft["nested"].append({"kind": "choose_target", "result": {"picks": _picks.duplicate(), "cancel": false}})
	if _window.is_empty():
		push_error("[Lockstep] %s committed outside this seat's priority window - it was NOT sent" % str(_draft.get("card")))
		_draft = {}
		return
	if not _is_activation():
		_add_payment_if_missing()
	var play := {"kind": "play", "card": _draft["card"], "nested": _draft["nested"]}
	if _is_activation():
		play["ability"] = true
		play["skill"] = _draft.get("skill", -1)
	_draft = {}
	_send(play)

func _on_window_ended(_acted: bool) -> void:
	_draft = {}

## OUTGOING, IN THE ORDER THINGS WERE ASKED. A decision takes its place when the game ASKS it and is filled in when it
## is answered; messages leave only from the front, once ready. Answers can come back in a different order than the
## questions (an effect set off by one cast asks while the AI is already paying for the next), and the other machine
## asks them in the order they were asked, so that is the order they must arrive in.
var _outbox: Array = []

func _send(message: Dictionary) -> void:
	_outbox.append({"msg": message, "ready": true})
	_flush()

func _flush() -> void:
	while not _outbox.is_empty() and bool(_outbox[0]["ready"]):
		var json: String = CODEC.to_wire(_outbox.pop_front()["msg"])
		sent.append(json)
		message_sent.emit(json)

func _mark_ready(message: Dictionary) -> void:
	for item in _outbox:
		if is_same(item["msg"], message):
			item["ready"] = true
	_flush()

## A decision is being ASKED: reserve its place. Inside a play being drafted or attempted it belongs to that play;
## otherwise it is its own message. Returns the entry to fill (empty when it is not recorded at all).
func _reserve(kind: String) -> Dictionary:
	if _opaque_depth > 0:
		return {}
	var entry := {"kind": kind, "result": null}
	# The human's own decisions while drafting an activation in their priority window belong to that draft. The skill
	# picker is not recorded: the committed message names the skill.
	if _human and _is_activation() and not _window.is_empty():
		if kind == "choose_skill":
			return {}
		_draft["nested"].append(entry)
		return entry
	if not _current_play.is_empty():
		_current_play["nested"].append(entry)
		return entry
	_outbox.append({"msg": entry, "ready": false})
	return entry

## The decision was answered.
func _fill(entry: Dictionary, result: Variant) -> void:
	if entry.is_empty():
		return
	entry["result"] = result
	_mark_ready(entry)

## Ask-and-answer in one step (a decision whose question and answer arrive together).
func _record(kind: String, result: Variant) -> void:
	_fill(_reserve(kind), result)

## Game.play_card_for() tells us which card this play attempt is about, and when it is over.
func note_play(card: Card) -> void:
	if not _window.is_empty():
		_current_play = {"kind": "play", "card": card, "nested": []}
		_outbox.append({"msg": _current_play, "ready": false})

func note_play_done() -> void:
	if _current_play.is_empty():
		return
	var play: Dictionary = _current_play
	_current_play = {}
	_mark_ready(play)

func take_priority(player_id: int) -> bool:
	_window = {"kind": "take_priority"}
	window_serial += 1
	pending_kind = "take_priority"
	var acted: bool = await inner.take_priority(player_id)
	pending_kind = ""
	note_play_done()
	_window = {}
	_send({"kind": "take_priority", "result": acted})
	return acted

func pay_cost(owner_id: int, cost: Dictionary) -> bool:
	var slot: Dictionary = _reserve("pay_cost")
	_opaque_depth += 1
	var paid: bool = await inner.pay_cost(owner_id, cost)
	_opaque_depth -= 1
	var field = game.field
	var backups: Array = []
	for card in field.selected_cards_for_mana_conversion:
		backups.append([card, str(field.selected_mana_elements.get(card, card.mana_element()))])
	var hand_cards: Array = game.hand_for(owner_id).selected_cards_for_mana_conversion.duplicate()
	_fill(slot, {"paid": paid, "backups": backups, "hand": hand_cards})
	return paid

func choose_target(owner_id: int, source: Card, criteria: Dictionary) -> void:
	var picks: Array = []
	var cancelled := [false]
	var on_pick := func(card: Card) -> void: picks.append(card)
	var on_cancel := func() -> void: cancelled[0] = true
	game.field.target_picked.connect(on_pick)
	game.assistant.target_cancel.connect(on_cancel)
	var slot: Dictionary = _reserve("choose_target")
	_opaque_depth += 1
	await inner.choose_target(owner_id, source, criteria)
	_opaque_depth -= 1
	game.field.target_picked.disconnect(on_pick)
	game.assistant.target_cancel.disconnect(on_cancel)
	_fill(slot, {"picks": picks, "cancel": cancelled[0]})

func decide_attacker(player_id: int) -> Card:
	pending_kind = "decide_attacker"; var slot := _reserve("decide_attacker"); var r: Card = await inner.decide_attacker(player_id); pending_kind = ""; _fill(slot, r); return r
func decide_attackers(player_id: int) -> Array:
	pending_kind = "decide_attackers"; var slot := _reserve("decide_attackers"); var r: Array = await inner.decide_attackers(player_id); pending_kind = ""; _fill(slot, r); return r
func decide_blocker(player_id: int, attacker: Card) -> Card:
	pending_kind = "decide_blocker"; var slot := _reserve("decide_blocker"); var r: Card = await inner.decide_blocker(player_id, attacker); pending_kind = ""; _fill(slot, r); return r
func choose_party_damage_split(player_id: int, party: Array, total: int) -> Array:
	pending_kind = "choose_party_damage_split"; var slot := _reserve("choose_party_damage_split"); var r: Array = await inner.choose_party_damage_split(player_id, party, total); pending_kind = ""; _fill(slot, r); return r
func choose_damage_split(player_id: int, cards: Array, total: int) -> Array:
	pending_kind = "choose_damage_split"; var slot := _reserve("choose_damage_split"); var r: Array = await inner.choose_damage_split(player_id, cards, total); pending_kind = ""; _fill(slot, r); return r
func confirm_optional(player_id: int, prompt: String) -> bool:
	pending_kind = "confirm_optional"; var slot := _reserve("confirm_optional"); var r: bool = await inner.confirm_optional(player_id, prompt); pending_kind = ""; _fill(slot, r); return r
func choose_hand_card_to_play(owner_id: int, ids: Array, filter: Dictionary) -> int:
	pending_kind = "choose_hand_card_to_play"; var slot := _reserve("choose_hand_card_to_play"); var r: int = await inner.choose_hand_card_to_play(owner_id, ids, filter); pending_kind = ""; _fill(slot, r); return r
func choose_hand_card_to_bottom(owner_id: int, cards: Array) -> Card:
	pending_kind = "choose_hand_card_to_bottom"; var slot := _reserve("choose_hand_card_to_bottom"); var r: Card = await inner.choose_hand_card_to_bottom(owner_id, cards); pending_kind = ""; _fill(slot, r); return r
func choose_break_zone_card(owner_id: int, ids: Array, filter: Dictionary) -> int:
	pending_kind = "choose_break_zone_card"; var slot := _reserve("choose_break_zone_card"); var r: int = await inner.choose_break_zone_card(owner_id, ids, filter); pending_kind = ""; _fill(slot, r); return r
func choose_field_card(owner_id: int, candidates: Array, prompt: String = "Choose a card") -> Card:
	pending_kind = "choose_field_card"; var slot := _reserve("choose_field_card"); var r: Card = await inner.choose_field_card(owner_id, candidates, prompt); pending_kind = ""; _fill(slot, r); return r
func choose_deck_card(owner_id: int, ids: Array, filter: Dictionary) -> int:
	pending_kind = "choose_deck_card"; var slot := _reserve("choose_deck_card"); var r: int = await inner.choose_deck_card(owner_id, ids, filter); pending_kind = ""; _fill(slot, r); return r
func choose_deck_cards(owner_id: int, ids: Array, filter: Dictionary, request, prompt: String = "Choose cards") -> Array:
	pending_kind = "choose_deck_cards"; var slot := _reserve("choose_deck_cards"); var r: Array = await inner.choose_deck_cards(owner_id, ids, filter, request, prompt); pending_kind = ""; _fill(slot, r); return r
func choose_element(owner_id: int, options: Array, prompt: String = "Choose an Element") -> String:
	pending_kind = "choose_element"; var slot := _reserve("choose_element"); var r: String = await inner.choose_element(owner_id, options, prompt); pending_kind = ""; _fill(slot, r); return r
func choose_number(owner_id: int, minimum: int, maximum: int, prompt: String = "Choose a number") -> int:
	pending_kind = "choose_number"; var slot := _reserve("choose_number"); var r: int = await inner.choose_number(owner_id, minimum, maximum, prompt); pending_kind = ""; _fill(slot, r); return r
func choose_mana_color(owner_id: int, card: Card, options: Array) -> String:
	pending_kind = "choose_mana_color"; var slot := _reserve("choose_mana_color"); var r: String = await inner.choose_mana_color(owner_id, card, options); pending_kind = ""; _fill(slot, r); return r
func choose_discard(owner_id: int, cards: Array) -> Card:
	pending_kind = "choose_discard"; var slot := _reserve("choose_discard"); var r: Card = await inner.choose_discard(owner_id, cards); pending_kind = ""; _fill(slot, r); return r
func choose_skill(player_id: int, card: Card, skills: Array, usable: Array = []) -> int:
	pending_kind = "choose_skill"; var slot := _reserve("choose_skill"); var r: int = await inner.choose_skill(player_id, card, skills, usable); pending_kind = ""; _fill(slot, r); return r
func choose_sacrifice(player_id: int, candidates: Array) -> Card:
	pending_kind = "choose_sacrifice"; var slot := _reserve("choose_sacrifice"); var r: Card = await inner.choose_sacrifice(player_id, candidates); pending_kind = ""; _fill(slot, r); return r
