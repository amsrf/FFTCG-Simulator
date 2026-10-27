extends Node
const EVENTS := preload("res://scripts/effects/events.gd")
## CARDS 1-100, batch 1 — the entries that needed no new instruction (plus power_change_matching for Sylph).
##
## Covers one representative card per mechanism actually exercised; the pure data-shape entries are asserted by key.

const GAME_SCENE := preload("res://game.tscn")

const MAGUS := 24
const DARK_KNIGHT := 55
const SYLPH := 74
const RIKKU := 90
const VINCENT := 94
const KNIGHT := 165
const SQUALL := 41
const SNOW := 43

class RikkuAgent extends Agent:
	## Rikku's ETB may choose up to five Backups and allows confirming early. This agent makes the two picks this
	## probe cares about in the resolution-time targeting session, then confirms.
	var wanted: Array = []

	func choose_target(_owner_id: int, _source: Card, _criteria: Dictionary) -> void:
		for card in wanted:
			if card != null and is_instance_valid(card) and card.is_valid_target:
				game.field.set_target_card(card)
		game.assistant.on_target_complete()


var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Batch1] ok   %s" % what)
	else:
		_fails += 1
		print("[Batch1] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


func _off_field(id: int, side: String) -> Card:
	## A card that is NOT on the field (Summons), so it can still be the source of an effect.
	var card: Card = _game.call("create_card", id, side)
	add_child(card)
	return card


func _drain() -> void:
	var stack = _game.get("stack")
	var guard: int = 0
	while stack.stack_length() > 0 and guard < 20:
		await stack.resolve_top_effect()
		guard += 1
	await get_tree().process_frame


func _complete_target(card: Card) -> void:
	var stack = _game.get("stack")
	if stack.stack_length() > 0 and GlobalVariables.get_player_mode() != GlobalVariables.Player_Mode.TARGET:
		stack.resolve_top_effect()
	for _i in range(60):
		if GlobalVariables.get_player_mode() == GlobalVariables.Player_Mode.TARGET:
			break
		await get_tree().process_frame
	_field.set_target_card(card)
	_game.get("assistant").call("on_target_complete")


func _ready() -> void:
	# The data-shape checks do not need a game, so they run first and cannot be disturbed by board state.
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/card_effects.json"))
	_expect(load("res://assets/effects/card_23.gd").new().ex_burst_event() == EVENTS.Event.CAST,
		"Brynhildr (23) is EX BURST -> when_cast")
	_expect(load("res://assets/effects/card_39.gd").new().cast_target_criteria(null).to_legacy().get("is_tapped") == true,
		"Shiva (39) targets a DULL Forward")
	_expect("first_strike" in load("res://assets/effects/card_44.gd").new().keywords(), "Sephiroth (44) has First Strike")
	var chick_specs: Array = load("res://assets/effects/card_19.gd").new().activated_abilities()
	_expect(chick_specs.size() == 1 and chick_specs[0].tap, "Chocobo Chick (19) is a dull ability")

	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "ai", "player_hand": [10, 11], "opponent_hand": [1, 2]})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	# --- 24 Magus: ETB 3000 to ALL opponent Forwards --------------------------------------------------------
	var opp_a: Card = _make(SQUALL, "opponent")
	var opp_b: Card = _make(SNOW, "opponent")
	var magus: Card = _make(MAGUS, "player")
	# play_card(animate = false) is the SETUP path and deliberately does not fire ETB (pre-placed cards were never
	# played). The probe is simulating a real play, so it triggers the ETB itself.
	_field.execute_card_effect(magus, "when_enter_field")
	await _drain()
	print("[Batch1] Magus: %s took %d, %s took %d" % [opp_a.card_name, opp_a.accumulated_damage,
		opp_b.card_name, opp_b.accumulated_damage])
	_expect(opp_a.accumulated_damage == 3000 and opp_b.accumulated_damage == 3000,
		"Magus: its ETB deals 3000 to every opponent Forward")

	# --- 55 Dark Knight: put from the field into the Break Zone -> its controller takes 1 -------------------
	var dk: Card = _make(DARK_KNIGHT, "player")
	await _drain()
	var damage_before: int = _game.get("player").damage_count()
	# break_card() is the real break path: it removes from the field and the Break Zone pile fires the trigger.
	_game.call("break_card", dk)
	await _drain()
	print("[Batch1] Dark Knight: player damage %d -> %d" % [damage_before, _game.get("player").damage_count()])
	_expect(_game.get("player").damage_count() > damage_before,
		"Dark Knight: leaving the field deals its controller 1 damage")

	# --- 74 Sylph: activate a Forward, all your Forwards +1000 ----------------------------------------------
	var tap_me: Card = _make(KNIGHT, "player")
	var buff_me: Card = _make(SQUALL, "player")
	await _drain()
	tap_me.tap()
	var buff_before: int = buff_me.power
	var sylph: Card = _off_field(SYLPH, "player")
	_field.execute_card_effect(sylph, "when_cast")
	await _complete_target(tap_me)
	await _drain()
	print("[Batch1] Sylph: %s tapped=%s, %s %d -> %d" % [
		tap_me.card_name, tap_me.tapped, buff_me.card_name, buff_before, buff_me.power])
	_expect(not tap_me.tapped, "Sylph: the chosen Forward is activated")
	_expect(buff_me.power == buff_before + 1000, "Sylph: all your Forwards gain +1000")

	# --- 90 Rikku: choose up to 5 Backups you control, return them to hand ----------------------------------
	var b1: Card = _make(31, "player")    # Chemist, a Backup
	var b2: Card = _make(32, "player")    # Chemist, a Backup
	await _drain()
	var hand_before: int = _game.get("hand").cards.size()
	var rikku: Card = _make(RIKKU, "player")
	# Same as Magus: the setup path does not fire ETB, so the probe triggers it explicitly. The ETB is an
	# auto-ability, so it chooses its targets when it resolves.
	var rikku_agent := RikkuAgent.new()
	rikku_agent.bind(_game)
	rikku_agent.wanted = [b1, b2]
	_game.set("player_agent", rikku_agent)
	_field.execute_card_effect(rikku, "when_enter_field")
	await _game.get("stack").resolve_top_effect()
	# The return animation is a tween the instruction awaits; the landing callback fires near its end, so give it time
	# (same reason as the Tonogiri check in party_cards_probe).
	await get_tree().create_timer(1.0).timeout
	print("[Batch1] Rikku: hand %d -> %d, b1 on field=%s, b2 on field=%s" % [
		hand_before, _game.get("hand").cards.size(), b1.is_on_field(), b2.is_on_field()])
	_expect(not b1.is_on_field() and not b2.is_on_field(), "Rikku: the chosen Backups leave the field")
	_expect(_game.get("hand").cards.size() >= hand_before + 2,
		"Rikku: and they go to their owner's hand (up to 5, confirmed early)")

	# --- 94 Vincent: when it attacks it gains First Strike ---------------------------------------------------
	var vincent: Card = _make(VINCENT, "player")
	await _drain()
	_field.reset_attacker()
	_field.set_attacker(vincent)
	_field.execute_card_attack()
	await _drain()
	print("[Batch1] Vincent: first_strike=%s" % vincent.is_first_strike())
	_expect(vincent.is_first_strike(), "Vincent: attacking grants it First Strike")

	print("[Batch1] %d checks | failures: %d" % [_checks, _fails])
	print("[Batch1] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
