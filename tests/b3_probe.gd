extends Node
## B3: targeting priority, conditional protection, two-player choices, Break-Zone search, and return protection.

const GAME_SCENE := preload("res://game.tscn")
const MOCK := preload("res://scripts/agents/mock_agent.gd")

const CECIL := 162
const YAAG := 174
const SERAFIE := 109
const CLOUD := 158
const EMPEROR := 185
const RIKKU := 201
const GILGAMESH := 207

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[B3] ok   %s" % what)
	else:
		_fails += 1
		print("[B3] FAIL %s" % what)


func _boot() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	# Both seats answer through the base Agent methods (first candidate); no UI can open in a probe.
	var a = MOCK.new()
	a.bind(_game)
	var b = MOCK.new()
	b.bind(_game)
	_game.set("player_agent", a)
	_game.set("opponent_agent", b)


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
	_game.add_child(card)
	return card


func _ready() -> void:
	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/card_effects.json"))

	# --- 162 / 174: must be chosen if possible ---------------------------------------------------------
	await _boot()
	var cecil: Card = _make(CECIL, "player")
	var yaag: Card = _make(YAAG, "player")
	var other: Card = _make(41, "player")
	var foe_summon_1: Card = _off_field(4, "opponent")
	_field.set_viable_targets({"is_type": "Forward"}, foe_summon_1, "Summon")
	_expect(cecil.is_valid_target and not other.is_valid_target,
		"against a Forward choice Cecil is the only legal target")
	_field.set_viable_targets({"is_type": "Backup"}, foe_summon_1, "Ability")
	_expect(yaag.is_valid_target, "against a Backup choice Yaag is the only legal target")
	var own_summon: Card = _off_field(4, "player")
	_field.set_viable_targets({"is_type": "Forward"}, own_summon, "Summon")
	_expect(cecil.is_valid_target and other.is_valid_target, "your own Summon may choose any Forward")
	var cecil_rules: Dictionary = load("res://assets/effects/card_162.gd").new().static_rules()
	_expect(bool(cecil_rules.get("must_be_chosen", {}).get("sources", []).has("Summon")),
		"Cecil's must-be-chosen rule is code-owned")
	_game.queue_free()
	await get_tree().process_frame

	# --- 201: Rikku's conditional power and protection -------------------------------------------------
	await _boot()
	var rikku: Card = _make(RIKKU, "player")
	var yuna: Card = _make(176, "player")
	_expect(rikku.power == 8000, "Rikku gains +2000 while you control Yuna")
	var foe_summon_2: Card = _off_field(4, "opponent")
	var ability_source: Card = _off_field(41, "opponent")
	_expect(not rikku.can_be_chosen_by(foe_summon_2, "Summon"), "Yuna makes Rikku untargetable by Summons")
	_expect(rikku.can_be_chosen_by(ability_source, "Ability"), "but not by abilities yet")
	var paine: Card = _make(199, "player")
	_expect(rikku.power == 10000, "Paine adds another +2000")
	_expect(not rikku.can_be_chosen_by(ability_source, "Ability"), "Paine makes Rikku untargetable by abilities")
	_expect(not rikku.can_be_chosen_by(foe_summon_2, "Summon"), "and the Summon protection remains")
	var rikku_rules: Dictionary = load("res://assets/effects/card_201.gd").new().static_rules()
	_expect(rikku_rules.get("conditional_cannot_be_chosen", []).size() == 2,
		"Rikku's two conditional shields are code-owned")
	_game.queue_free()
	await get_tree().process_frame

	# --- 109: each player recovers a Forward from their Break Zone -------------------------------------
	await _boot()
	var player_bz_forward: Card = _off_field(41, "player")
	var player_bz_backup: Card = _off_field(31, "player")
	var opponent_bz_forward: Card = _off_field(43, "opponent")
	_game.player.graveyard.add_card(player_bz_forward)
	_game.player.graveyard.add_card(player_bz_backup)
	_game.opponent.graveyard.add_card(opponent_bz_forward)
	var serafie: Card = _make(SERAFIE, "player")
	_field.execute_card_effect(serafie, "when_enter_field")
	await get_tree().process_frame
	if _game.stack.stack_length() > 0:
		await _game.stack.resolve_top_effect()
	_expect(_game.player.hand.cards.has(player_bz_forward), "P1 gets its chosen Forward back")
	_expect(not _game.player.graveyard.graveyard_cards.has(player_bz_forward), "and it leaves the Break Zone")
	_expect(_game.player.graveyard.graveyard_cards.has(player_bz_backup), "a Backup is not a legal pick")
	_expect(_game.opponent.hand.cards.has(opponent_bz_forward), "P2 gets its chosen Forward back")
	_expect(load("res://assets/effects/card_109.gd").new().has_method("when_enter_field"),
		"Serafie's Break Zone choice is code-owned")
	_game.queue_free()
	await get_tree().process_frame

	# --- 158: each player keeps one Forward, every other Forward is put into the Break Zone ------------
	await _boot()
	var cloud: Card = _make(CLOUD, "player")
	var p_keep: Card = _make(41, "player")
	var p_other: Card = _make(29, "player")
	var o_keep: Card = _make(43, "opponent")
	var o_other: Card = _make(47, "opponent")
	_field.execute_card_effect(cloud, "when_enter_field")
	await get_tree().process_frame
	if _game.stack.stack_length() > 0:
		await _game.stack.resolve_top_effect()
	_expect(_field.get_front_cards_for("player").size() == 1, "P1 keeps exactly one Forward")
	_expect(_field.get_front_cards_for("opponent").size() == 1, "P2 keeps exactly one Forward")
	_expect(not p_other.is_on_field() and not o_other.is_on_field(),
		"the unselected Forwards leave the field")
	_expect(load("res://assets/effects/card_158.gd").new().has_method("when_enter_field"),
		"Cloud of Darkness's keep-one choice is code-owned")
	_game.queue_free()
	await get_tree().process_frame

	# --- 185: The Emperor searches and plays itself dull ----------------------------------------------
	await _boot()
	var emperor: Card = _make(EMPEROR, "player")
	var deck_copy: Card = _off_field(EMPEROR, "player")
	_game.player.deck.deck_cards.push_front(deck_copy)
	_game.put_card_into_graveyard(emperor)
	await get_tree().process_frame
	if _game.stack.stack_length() > 0:
		await _game.stack.resolve_top_effect()
	await get_tree().process_frame
	var new_emperor: Card = null
	for card in _field.get_front_cards_for("player"):
		if card.id == EMPEROR and card != emperor:
			new_emperor = card
			break
	_expect(new_emperor != null, "the searched The Emperor is played")
	_expect(new_emperor != null and new_emperor.tapped, "and it enters the field dull")
	_expect(not _game.player.deck.deck_cards.has(deck_copy), "the searched copy leaves the deck")
	_game.queue_free()
	await get_tree().process_frame

	# --- 207: return protection and the 4-damage ability gate -----------------------------------------
	await _boot()
	var gilgamesh: Card = _make(GILGAMESH, "player")
	var foe_summon_3: Card = _off_field(4, "opponent")
	var hand_copy: Card = _off_field(GILGAMESH, "player")
	_game.player.hand.add_card(hand_copy)
	var hand_before: int = _game.player.hand.cards.size()
	_game.set("_current_source_card", foe_summon_3)
	_game.set("_targets", [gilgamesh])
	await _game.return_targets_to_hand()
	_expect(gilgamesh.is_on_field(), "an opponent's Summon cannot return Gilgamesh")
	_expect(_game.player.hand.cards.size() == hand_before, "and no card is added to hand")
	var gil_rules: Dictionary = load("res://assets/effects/card_207.gd").new().static_rules()
	_expect(bool(gil_rules.get("cannot_be_returned_to_hand", {}).get("sources", []).has("Ability")),
		"Gilgamesh's return protection is code-owned")
	# Divider is the second code ability. The pump beside it keeps Gilgamesh offered, so the gate is asserted on
	# the AbilitySpec itself rather than on the card-level availability.
	var gil_specs: Array = load("res://assets/effects/card_207.gd").new().activated_abilities()
	_expect(gil_specs.size() == 2 and gil_specs[1].only_if_damage_received == 4,
		"Divider is gated on having received 4 damage")
	_expect(gil_specs.size() == 2 and gil_specs[1].s_cost and not gil_specs[1].tap,
		"and it is a non-tap S ability")
	_game.queue_free()

	print("[B3] %d checks | failures: %d" % [_checks, _fails])
	print("[B3] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
