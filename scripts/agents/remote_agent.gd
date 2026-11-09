extends "res://scripts/agents/agent.gd"
## ONLINE LOCKSTEP, RECEIVING SIDE. Answers every decision of the OTHER machine's seat from the messages its
## RecordingAgent sent, in order. Each message must be the kind of decision this game is asking for; anything else
## means the two games have diverged, and it is reported as such (desync_detected on the Game) instead of guessed at.
##
## A priority window replays each PLAY as it arrives (Game.play_card_for(), or the ability activation), answering the
## payment and the targets asked during it from that play's own recorded decisions, until the message that ends the
## window ("take_priority": passed, or acted on the stack).
const CODEC := preload("res://scripts/agents/lockstep_codec.gd")

signal message_arrived

var _inbox: Array[String] = []
## The decisions recorded during the play attempt being replayed (answered before the inbox).
var _replay: Array = []
var diverged: bool = false

## Feed a message from the other machine (the transport calls this).
func receive(json: String) -> void:
	_inbox.append(json)
	message_arrived.emit()

func _next(kind: String) -> Dictionary:
	# DIVERGED IS FINAL. The match has been stopped (Game._halt_out_of_sync); every later question gets the empty
	# answer at once instead of consuming messages that belong to a different game.
	if diverged:
		return {}
	var message: Dictionary
	if not _replay.is_empty():
		message = _replay.pop_front()
	else:
		while _inbox.is_empty():
			await message_arrived
		message = CODEC.from_wire(_inbox.pop_front())
	if str(message.get("kind", "")) != kind:
		diverged = true
		push_error("[Lockstep] expected a '%s' decision, the other machine sent '%s'" % [kind, message.get("kind", "?")])
		if game != null:
			game.desync_detected.emit(game.turn_number, "expected " + kind, str(message.get("kind", "?")))
		return {}
	return message

func _as_array(value: Variant) -> Array:
	return value if value is Array else []

func _as_int(value: Variant) -> int:
	return int(value) if (value is int or value is float) else -1

func _result(kind: String) -> Variant:
	var message: Dictionary = await _next(kind)
	return CODEC.decode(message.get("result"), game)

func take_priority(player_id: int) -> bool:
	await _settle()
	while true:
		var message: Dictionary = await _next_window_message()
		if message.is_empty():
			return false
		if str(message.get("kind", "")) == "take_priority":
			return bool(message.get("result", false))
		_replay = message.get("nested", []).duplicate()
		var card = CODEC.decode(message.get("card"), game)
		if card is Card and bool(message.get("ability", false)):
			await _replay_activation(card, int(message.get("skill", -1)))
		elif card is Card:
			await game.play_card_for(player_id, card)
		# A question the play started can be asked a little AFTER the play call returns: a Summon's target is chosen once
		# the presentation has caught up. Give those questions their recorded answers before checking for leftovers.
		var waited: float = 0.0
		while not _replay.is_empty() and not diverged and waited < UNCLAIMED_LIMIT:
			await game.get_tree().process_frame
			waited += game.get_process_delta_time()
		if not _replay.is_empty():
			push_error("[Lockstep] %d recorded decision(s) were not asked for during a replayed play of %s: %s" % [
				_replay.size(), str(card.card_name if card is Card else card), str(_replay.map(func(e): return e.get("kind")))])
			diverged = true
		_replay = []
		# Let what the play set off (an enter-the-field trigger...) ask its own questions before the next play.
		await _settle()
	return false

## Seconds a message may wait at the front of the inbox for the game to ask the question it answers.
const UNCLAIMED_LIMIT := 30.0

## The next PLAY or end of the window. Any other message at the front answers a question the game is about to ask
## (an effect set off by the last play), so it is left for that question to take. If nothing claims it, the games
## have diverged.
func _next_window_message() -> Dictionary:
	var waited: float = 0.0
	while true:
		if diverged or game == null:
			return {}
		if not _inbox.is_empty():
			var front: Dictionary = CODEC.from_wire(_inbox[0])
			var kind: String = str(front.get("kind", ""))
			if kind == "play" or kind == "take_priority":
				_inbox.pop_front()
				return front
			waited += game.get_process_delta_time()
			if waited > UNCLAIMED_LIMIT:
				diverged = true
				push_error("[Lockstep] a '%s' decision arrived that this game never asked for" % kind)
				game.desync_detected.emit(game.turn_number, "expected a play or a pass", kind)
				return {}
		else:
			waited = 0.0
		await game.get_tree().process_frame
	return {}

## An ability activated from the field: the same activation, decided by this agent from the recorded answers. It
## returns once the activation has committed (or was abandoned), i.e. when the costs are no longer pending.
func _replay_activation(card: Card, skill_index: int) -> void:
	var stack = game.stack
	await game.field.begin_skill_activation(card, skill_index, true)
	while stack.skill_mana_deferred_until_target_confirm and not diverged:
		await game.get_tree().process_frame

func pay_cost(owner_id: int, _cost: Dictionary) -> bool:
	await _settle()
	var payment = await _result("pay_cost")
	if not (payment is Dictionary):
		return false
	for entry in payment.get("backups", []):
		if entry is Array and entry.size() == 2 and entry[0] is Card:
			game.field.add_card_to_mana_conversion(entry[0], str(entry[1]))
	var owner_hand = game.hand_for(owner_id)
	for card in payment.get("hand", []):
		if card is Card:
			owner_hand.add_card_to_mana_conversion(card)
	return bool(payment.get("paid", false))

func choose_target(_owner_id: int, _source: Card, _criteria: Dictionary) -> void:
	await _settle()
	var answer = await _result("choose_target")
	if not (answer is Dictionary):
		return
	for card in answer.get("picks", []):
		if card is Card:
			game.field.set_target_card(card)
	if bool(answer.get("cancel", false)):
		game.assistant.on_target_cancel()
	else:
		game.assistant.on_target_complete()

func decide_attacker(_p: int) -> Card:
	await _settle(); var card = await _result("decide_attacker"); return card if card is Card else null
func decide_attackers(_p: int) -> Array:
	await _settle(); return _as_array(await _result("decide_attackers"))
func decide_blocker(_p: int, _attacker: Card) -> Card:
	await _settle(); var card = await _result("decide_blocker"); return card if card is Card else null
func choose_party_damage_split(_p: int, _party: Array, _total: int) -> Array:
	await _settle(); return _as_array(await _result("choose_party_damage_split"))
func choose_damage_split(_p: int, _cards: Array, _total: int) -> Array:
	await _settle(); return _as_array(await _result("choose_damage_split"))
func confirm_optional(_p: int, _prompt: String) -> bool:
	await _settle(); return bool(await _result("confirm_optional"))
func choose_hand_card_to_play(_o: int, _ids: Array, _filter: Dictionary) -> int:
	await _settle(); return _as_int(await _result("choose_hand_card_to_play"))
func choose_hand_card_to_bottom(_o: int, _cards: Array) -> Card:
	await _settle(); var card = await _result("choose_hand_card_to_bottom"); return card if card is Card else null
func choose_break_zone_card(_o: int, _ids: Array, _filter: Dictionary) -> int:
	await _settle(); return _as_int(await _result("choose_break_zone_card"))
func choose_field_card(_o: int, _candidates: Array, _prompt: String = "Choose a card") -> Card:
	await _settle(); var card = await _result("choose_field_card"); return card if card is Card else null
func choose_deck_card(_o: int, _ids: Array, _filter: Dictionary) -> int:
	await _settle(); return _as_int(await _result("choose_deck_card"))
func choose_deck_cards(_o: int, _ids: Array, _filter: Dictionary, _request, _prompt: String = "Choose cards") -> Array:
	await _settle(); return _as_array(await _result("choose_deck_cards"))
func choose_element(_o: int, _options: Array, _prompt: String = "Choose an Element") -> String:
	await _settle(); return str(await _result("choose_element"))
func choose_number(_o: int, _minimum: int, _maximum: int, _prompt: String = "Choose a number") -> int:
	await _settle(); return _as_int(await _result("choose_number"))
func choose_mana_color(_o: int, _card: Card, _options: Array) -> String:
	await _settle(); return str(await _result("choose_mana_color"))
func choose_discard(_o: int, _cards: Array) -> Card:
	await _settle(); var card = await _result("choose_discard"); return card if card is Card else null
func choose_skill(_p: int, _card: Card, _skills: Array, _usable: Array = []) -> int:
	await _settle(); return _as_int(await _result("choose_skill"))
func choose_sacrifice(_p: int, _candidates: Array) -> Card:
	await _settle(); var card = await _result("choose_sacrifice"); return card if card is Card else null
