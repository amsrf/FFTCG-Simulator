extends Node

const GAME_SCENE := preload("res://game.tscn")
const TEST_GROUNDS := preload("res://scripts/test_grounds.gd")

var _game = null
var _field = null
var _checks: int = 0
var _fails: int = 0


class TestAgent extends MockAgent:
	pass


func _ready() -> void:
	await get_tree().process_frame
	var cfg: Dictionary = TEST_GROUNDS.config("clean")
	cfg["player_deck"] = []
	cfg["opponent_deck"] = []
	MatchSetup.config = cfg
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	_game.player_agent = TestAgent.new()
	_game.player_agent.bind(_game)
	_game.opponent_agent = MockAgent.new()
	_game.opponent_agent.bind(_game)
	_field = _game.field
	# Keep the probe fast; the animation itself is asserted structurally, not by waiting 0.8 s per card.
	_game.reveal_lift_seconds = 0.0
	_game.reveal_flip_seconds = 0.0
	_game.reveal_flip_back_seconds = 0.0
	_game.reveal_back_hold_seconds = 0.0
	_game.reveal_hold_seconds = 0.0
	await get_tree().process_frame

	await _check_reveal_and_move()
	await _check_gilgamesh_branches()
	await _check_cait_sith_data()
	await _check_cait_sith_skill()

	print("[Reveal] %d checks | failures: %d" % [_checks, _fails])
	print("[Reveal] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Reveal] ok   ", what)
	else:
		_fails += 1
		print("[Reveal] FAIL ", what)


func _seed_deck(ids: Array) -> void:
	for card in _game.deck.deck_cards:
		if card != null and is_instance_valid(card):
			card.queue_free()
	_game.deck.deck_cards.clear()
	for id in ids:
		var card: Card = _game.create_card(int(id), "player")
		_game.add_child(card)
		_game.deck.deck_cards.append(card)


func _place(id: int, controller: String = "player") -> Card:
	var card: Card = _game.create_card(id, controller)
	_game.add_child(card)
	_field.play_card(card, controller == "opponent", false)
	return card


func _check_reveal_and_move() -> void:
	_seed_deck([41, 43, 47])
	await _game.reveal_top(2)
	_expect(_game.revealed_cards.size() == 2, "reveal_top(2) leaves two cards in revealed_cards")
	_expect(_game.revealed_cards[0].id == 41 and _game.revealed_cards[1].id == 43,
		"revealed_cards preserves top-to-bottom order")
	_expect(_game.deck.deck_cards.size() == 1 and _game.deck.deck_cards[0].id == 47,
		"the revealed cards are removed from the deck")
	_expect(not _game.revealed_cards[0].visible
		and _game.revealed_cards[0].process_mode == Node.PROCESS_MODE_DISABLED,
		"a revealed card is hidden and inert after its display")
	_game.check_revealed(0, {"is_type": "Forward"})
	_expect(_game._last_action_succeeded, "check_revealed sees a Forward")
	_game.check_revealed(0, {"is_type": "Backup"})
	_expect(not _game._last_action_succeeded, "and rejects the same card as a Backup")

	_game.choose_revealed({"is_type": "Forward"}, "Choose one")
	await get_tree().process_frame
	_game.put_chosen_into_hand()
	_expect(_game.hand.cards.any(func(c): return c.id == 41),
		"put_chosen_into_hand moves the chosen revealed card to the hand")
	_expect(_game.hand.cards.back().current_zone == Card.Zone.HAND and _game.hand.cards.back().visible,
		"the moved card is visible again in the hand")
	_expect(_game.revealed_cards.size() == 1, "the chosen card leaves the revealed array")

	_game.put_revealed_on_bottom()
	_expect(_game.revealed_cards.is_empty(), "put_revealed_on_bottom clears the rest")
	_expect(_game.deck.deck_cards.size() == 2
		and _game.deck.deck_cards[0].id == 47 and _game.deck.deck_cards[1].id == 43,
		"the rest go under the deck in reveal order")

	_seed_deck([31])
	await _game.reveal_top(1)
	_game.remove_revealed_from_game(0)
	_expect(_game.revealed_cards.is_empty(), "remove_revealed_from_game clears the revealed card")
	_expect(_game.player_removed.graveyard_cards.any(func(c): return c.id == 31),
		"and the card lands in the removed-from-game zone")


func _run_gilgamesh(top_id: int) -> Dictionary:
	_seed_deck([top_id])
	var gilm: Card = _place(129, "player")
	var target: Card = _place(41, "player")
	var specs: Array = gilm.effect().activated_abilities()
	var ctx = gilm.make_effect_context("activated_ability", {}, null, [target])
	await specs[0].run.call(ctx)
	var out: Dictionary = {
		"target": target,
		"target_on_field": target.is_on_field(),
		"damage": target.accumulated_damage,
		"removed": _game.player_removed.graveyard_cards.any(func(c): return c.id == top_id),
	}
	_field.remove_card(gilm)
	_field.remove_card(target)
	return out


func _check_gilgamesh_branches() -> void:
	var forward: Dictionary = await _run_gilgamesh(43)
	_expect(not forward["target_on_field"], "Gilgamesh breaks the chosen Forward when the removed card is a Forward")
	_expect(forward["removed"], "and the revealed card is removed from the game")
	var non_forward: Dictionary = await _run_gilgamesh(31)
	_expect(non_forward["damage"] == 3000, "otherwise Gilgamesh deals 3000 to the chosen Forward")
	_expect(non_forward["removed"], "and still removes the top card from the game")


func _run_cait_sith(top_id: int) -> int:
	_seed_deck([top_id])
	var cait: Card = _place(131, "player")
	var victim: Card = _place(55, "opponent")
	var specs: Array = cait.effect().activated_abilities()
	var ctx = cait.make_effect_context("activated_ability", {}, null, [])
	await specs[0].run.call(ctx)
	var dealt: int = victim.accumulated_damage
	_field.remove_card(cait)
	_field.remove_card(victim)
	return dealt


func _check_cait_sith_skill() -> void:
	var forwarded: int = await _run_cait_sith(43)
	_expect(forwarded == 7000, "Cait Sith deals 7000 to active opponent Forwards when the removed card is a Forward")
	var not_forwarded: int = await _run_cait_sith(31)
	_expect(not_forwarded == 0, "and does nothing to them when it is not a Forward")


func _check_cait_sith_data() -> void:
	var cait: Card = _place(131, "player")
	_expect(load("res://assets/effects/card_131.gd").new().has_method("when_enter_field"),
		"Cait Sith's ETB break-Backup effect is code-owned")
	var specs: Array = load("res://assets/effects/card_131.gd").new().activated_abilities()
	_expect(specs.size() == 1 and specs[0].s_cost, "and its code-owned Slots S ability")
	_field.remove_card(cait)
