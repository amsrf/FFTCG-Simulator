extends Node
## B1: the small vocabulary batch. One check per primitive, plus data-shape checks for the cards whose shape is the
## whole mechanism.

const GAME_SCENE := preload("res://game.tscn")

const SQUALL := 41
const SNOW := 43
const DRAGOON := 148          # Standard Unit Forward WITHOUT printed First Strike, for Warrior of Light's aura
const TIFA := 189             # cost 4, for Zangan's Haste aura
const ALMA := 153
const OVELIA := 156


class PickAgent extends Agent:
	func choose_discard(_player_id: int, cards: Array) -> Card:
		return cards[0] if not cards.is_empty() else null

	func confirm_optional(_player_id: int, _prompt: String) -> bool:
		return true

	func choose_hand_card_to_play(_player_id: int, ids: Array, filter: Dictionary) -> int:
		var wanted: String = str(filter.get("type", filter.get("is_type", "")))
		for id in ids:
			var data: Dictionary = CardDatabase.card_database[int(id) - 1]
			if wanted == "" or str(data.get("type_en", "")) == wanted:
				return int(id)
		return int(ids[0]) if not ids.is_empty() else -1

	func choose_hand_card_to_bottom(_player_id: int, cards: Array) -> Card:
		return cards[0] if not cards.is_empty() else null


var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _stack = null
var _assistant = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[B1] ok   %s" % what)
	else:
		_fails += 1
		print("[B1] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


func _off_field(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	add_child(card)
	return card


func _drain() -> void:
	var guard: int = 0
	while _stack.stack_length() > 0 and guard < 20:
		await _stack.resolve_top_effect()
		guard += 1
	await get_tree().process_frame


func _pick(card: Card) -> void:
	_field.set_target_card(card)
	_assistant.call("on_target_complete")


func _ready() -> void:
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/card_effects.json"))
	_expect(effects.get("106", {}).get("when_cast", {}).get("instructions", [{}])[0].get("name")
		== "power_change_targets_if_blocking", "Golem 106 has the blocking-conditional power instruction")
	_expect(bool(effects.get("194", {}).get("skill", [{}])[0].get("only_if_blocking", false)),
		"Snow 194's Vendetta is gated on blocking")
	_expect(effects.get("155", {}).get("aura", [{}, {}])[1].get("method") == "grant_status",
		"Warrior of Light 155 grants First Strike as a status aura")
	_expect(effects.get("188", {}).get("aura", [{}])[0].get("status") == "haste",
		"Zangan 188 grants Haste")
	_expect(effects.get("139", {}).get("skill", [{}])[0].get("instructions", [{}])[0].get("name")
		== "cast_summon_for_free", "Summoner 139 casts a Summon for free")
	_expect(effects.get("163", {}).get("power_per", {}).get("count", {}).has("exclude"),
		"Tidus 163 counts Forwards other than himself")

	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_stack = _game.get("stack")
	_assistant = _game.get("assistant")

	# Deterministic answers for the instructions that normally ask a human.
	var picker := PickAgent.new()
	picker.bind(_game)
	_game.set("player_agent", picker)

	# --- 125 Onion Knight: only a DAMAGED Forward is a legal target ------------------------------------
	var healthy: Card = _make(SQUALL, "opponent")
	var hurt: Card = _make(152, "opponent")
	hurt.suffer_damage(1000)
	var onion: Card = _make(125, "player")
	_field.execute_card_effect(onion, "when_enter_field")
	print("[B1] 125 viable: healthy=%s damaged=%s" % [healthy.is_valid_target, hurt.is_valid_target])
	_expect(not healthy.is_valid_target and hurt.is_valid_target,
		"Onion Knight 125 can only choose a damaged Forward")
	_pick(hurt)
	await _drain()
	_expect(hurt.accumulated_damage == 6000, "and deals it 5000")

	# --- 127 Kain: skip the next Active Phase ---------------------------------------------------------
	var kain: Card = _make(127, "player")
	kain.add_status_effect("skip_next_active", 1)
	kain.tap()
	_field.untap_cards_for("player")
	_expect(kain.tapped and not kain.status_effects.has("skip_next_active"),
		"Kain 127's skip_next_active is consumed by the Active Phase it denies")

	# --- 106 Golem: +2000 normally, +4000 while blocking ----------------------------------------------
	var normal: Card = _make(SQUALL, "player")
	var blocking: Card = _make(SQUALL, "player")
	blocking.status_effects["blocking"] = 1
	var pn: int = normal.power
	var pb: int = blocking.power
	var golem: Card = _off_field(106, "player")
	_field.execute_card_effect(golem, "when_cast")
	_pick(normal)
	await _drain()
	var golem2: Card = _off_field(106, "player")
	_field.execute_card_effect(golem2, "when_cast")
	_pick(blocking)
	await _drain()
	print("[B1] Golem: normal %d->%d, blocking %d->%d" % [pn, normal.power, pb, blocking.power])
	_expect(normal.power == pn + 2000, "Golem 106 gives +2000 to a non-blocking Forward")
	_expect(blocking.power == pb + 4000, "and +4000 to a blocking one")

	# --- 194 Snow: the ability is only offered while blocking -----------------------------------------
	var snow: Card = _make(194, "player")
	var snow_card: Card = _game.call("create_card", SNOW, "player")
	_game.add_child(snow_card)
	_game.get("hand").add_card(snow_card)          # S cost material
	_game.set("priority_holder", 1)
	GlobalVariables.set_base_mode(GlobalVariables.Player_Mode.FREE)
	snow.status_effects["blocking"] = 1
	var offered_blocking: bool = _field.can_activate_now(snow)
	snow.status_effects.erase("blocking")
	var offered_idle: bool = _field.can_activate_now(snow)
	_expect(offered_blocking and not offered_idle,
		"Snow 194's Vendetta is offered only while blocking")

	# --- 155 Warrior of Light: Standard Unit Forwards get +2000 and First Strike -----------------------
	var dragoon: Card = _make(DRAGOON, "player")
	var d0: int = dragoon.power
	var wol: Card = _make(155, "player")
	_expect(dragoon.power == d0 + 2000 and dragoon.is_first_strike(),
		"Warrior of Light 155 gives +2000 and First Strike to a Standard Unit")
	_game.call("break_card", wol)
	await _drain()
	_expect(dragoon.power == d0 and not dragoon.is_first_strike(),
		"and both come off when it leaves")

	# --- 188 Zangan: a cost-4 Tifa gains Haste --------------------------------------------------------
	var tifa: Card = _make(TIFA, "player")
	var zangan: Card = _make(188, "player")
	_expect(tifa.has_haste(), "Zangan 188 gives Haste to a cost-4 Tifa")
	_game.call("break_card", zangan)
	await _drain()
	_expect(not tifa.has_haste(), "and it comes off with Zangan")

	# --- 153 Alma: self cost reduction with Ovelia ----------------------------------------------------
	var alma: Card = _off_field(ALMA, "player")
	var base_total: int = 0
	for n in alma.get_cost().values():
		base_total += int(n)
	var ovelia: Card = _make(OVELIA, "player")
	var reduced: Dictionary = _field.effective_cost(alma)
	var reduced_total: int = 0
	for n in reduced.values():
		reduced_total += int(n)
	print("[B1] Alma cost %d -> %d with Ovelia" % [base_total, reduced_total])
	_expect(reduced_total == base_total - 1, "Alma 153 costs 1 less while you control Ovelia")

	# --- 169 Geomancer: look at the top card, put it on the bottom -------------------------------------
	var deck = _game.get("deck")
	var top_before: int = deck.deck_cards[0].id
	_game.set("_current_controller", "player")
	await _game.call("look_top_may_bottom")
	var top_after: int = deck.deck_cards[0].id
	_expect(top_after != top_before and deck.deck_cards.back().id == top_before,
		"Geomancer 169 can move the top card to the bottom")

	# --- 175 Yuj: draw, then put a hand card on the bottom --------------------------------------------
	var hand = _game.get("hand")
	var h0: int = hand.cards.size()
	var chosen_card: Card = hand.cards[0]
	await _game.call("put_hand_card_on_bottom")
	_expect(hand.cards.size() == h0 - 1 and deck.deck_cards.back() == chosen_card,
		"Yuj 175 puts a chosen hand card at the bottom of the deck")

	# --- 133 Sage: Break Zone -> hand -----------------------------------------------------------------
	var pile = _game.get("player_graveyard")
	var buried: Card = _game.call("create_card", SQUALL, "player")
	_game.add_child(buried)
	pile.add_card(buried)
	var hand_before: int = hand.cards.size()
	# The picker waits for a choice; drive it the way the window's own button would.
	var pending = _game.call("break_zone_to_hand", {})
	await get_tree().process_frame
	var window = null
	for child in _game.get_children():
		if child is CanvasLayer and child.has_method("_finish"):
			window = child
			break
	if window != null:
		window.call("_finish", buried.id)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[B1] Sage: hand %d -> %d" % [hand_before, hand.cards.size()])
	_expect(hand.cards.size() == hand_before + 1, "Sage 133 returns a Break Zone Character to hand")

	# --- 172 Moogle: draw 2, discard 1 ----------------------------------------------------------------
	var h1: int = hand.cards.size()
	var moogle: Card = _off_field(172, "player")
	_field.execute_card_effect(moogle, "when_cast")
	await _drain()
	_expect(hand.cards.size() == h1 + 1, "Moogle 172 draws 2 and discards 1")

	# --- 190 Bahamut Fury: the discard changes 5000 into 7000 ----------------------------------------
	var burn: Card = _make(152, "opponent")
	var hand_before_190: int = hand.cards.size()
	var fury: Card = _off_field(190, "player")
	_field.execute_card_effect(fury, "when_cast")
	_pick(burn)
	await _drain()
	print("[B1] Bahamut Fury: damage %d, hand %d -> %d" % [burn.accumulated_damage,
		hand_before_190, hand.cards.size()])
	_expect(burn.accumulated_damage == 7000 and hand.cards.size() == hand_before_190 - 1,
		"Bahamut Fury 190 discards for 7000 instead of 5000")

	# --- 116 Prishe / 128 Gilgamesh: double power and extra attacks ------------------------------------
	var prishe: Card = _make(116, "player")
	var pr: int = prishe.power
	prishe.double_power(1)
	_expect(prishe.power == pr * 2, "Prishe 116 doubles its power")
	var greg: Card = _make(128, "player")
	greg.set_extra_attacks(1)
	_field.reset_attacker()
	_field.set_attacker(greg)
	_field.execute_card_attack()
	var after_first: bool = greg.tapped
	_field.reset_attacker()
	_field.set_attacker(greg)
	_field.execute_card_attack()
	_expect(not after_first and greg.tapped,
		"Gilgamesh 128 stays untapped for the second attack and taps on the last")

	# --- 163 Tidus: extra attacks from damage ---------------------------------------------------------
	var tidus: Card = _make(163, "player")
	var dz = _game.get("player").damage_zone
	for _i in range(2):
		var dmg: Card = _game.call("create_card", 1, "player")
		_game.add_child(dmg)
		dz.add_card(dmg)
	_game.set("_current_controller", "player")
	_game.set("_current_source_card", tidus)
	_game.call("extra_attacks_from_damage")
	print("[B1] Tidus extra attacks: %d for 2 damage" % tidus.extra_attacks)
	_expect(tidus.extra_attacks == 1, "Tidus 163 gets one extra attack at 2 points of damage")

	# --- 139 Summoner: cast a Summon from hand for free ------------------------------------------------
	var ifrit: Card = _game.call("create_card", 4, "player")
	_game.add_child(ifrit)
	hand.add_card(ifrit)
	var stack_before: int = _stack.stack_length()
	await _game.call("cast_summon_for_free", {"is_type": "Summon", "is_cost_at_most": 6})
	var parked = _stack.get("summon_casting_card")
	print("[B1] Summoner: hand still has Ifrit=%s, stack %d -> %d, parked=%s" % [hand.cards.has(ifrit),
		stack_before, _stack.stack_length(), parked.card_name if parked != null else "none"])
	_expect(not hand.cards.has(ifrit) and (parked == ifrit or _stack.stack_length() > stack_before),
		"Summoner 139 casts a hand Summon onto the stack for free")

	print("[B1] %d checks | failures: %d" % [_checks, _fails])
	print("[B1] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
