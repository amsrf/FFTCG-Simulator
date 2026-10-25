extends Node

const GAME_SCENE := preload("res://game.tscn")
const TEST_GROUNDS := preload("res://scripts/test_grounds.gd")

var _game = null
var _field = null
var _checks: int = 0
var _fails: int = 0


## Passive target chooser: never plays cards, always accepts a may-prompt when one is inherited.
class TestAgent extends MockAgent:
	func choose_target(_owner_id: int, _source: Card, _criteria: Dictionary) -> void:
		var f = game.field
		for c in f.get_all_cards():
			if c.is_valid_target:
				f.set_target_card(c)
				game.assistant.on_target_complete()
				return


func _ready() -> void:
	await get_tree().process_frame
	MatchSetup.config = TEST_GROUNDS.config("clean")
	MatchSetup.config["shuffle"] = false
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	_game.player_agent = TestAgent.new()
	_game.player_agent.bind(_game)
	_game.opponent_agent = MockAgent.new()
	_game.opponent_agent.bind(_game)
	_field = _game.field
	await get_tree().process_frame

	await _cheque_cosmos_chaos()
	await _check_kefka()
	await _check_tidus()
	await _check_rygdea()

	print("[Reusable] %d checks | failures: %d" % [_checks, _fails])
	print("[Reusable] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Reusable] ok   ", what)
	else:
		_fails += 1
		print("[Reusable] FAIL ", what)


func _place(id: int, controller: String = "player") -> Card:
	var c: Card = _game.create_card(id, controller)
	_game.add_child(c)
	_field.play_card(c, controller == "opponent", false)
	return c


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _cheque_cosmos_chaos() -> void:
	var light: Card = _place(181, "player")
	var cosmos: Card = _place(183, "player")
	_expect(cosmos.mana_element() == "any", "Cosmos produces any-element mana while on the field")
	_expect(_game.would_break_light_dark_limit(light) == false,
		"Cosmos lifts the one-Light limit for another Light card")
	var second_light: Card = _game.create_card(181, "player")
	_expect(_game.would_break_light_dark_limit(second_light) == false,
		"a second Light card is allowed while Cosmos is on the field")
	var chaos: Card = _game.create_card(184, "player")
	_expect(_game.would_break_light_dark_limit(chaos) == true,
		"Chaos cannot enter beside a Light card")
	_game.put_card_into_graveyard(cosmos)
	_expect(_game.would_break_light_dark_limit(second_light) == true,
		"with Cosmos gone, the normal one-Light limit returns")
	second_light.queue_free()
	chaos.queue_free()
	_field.remove_card(light)

	# Any-element payment: two elemental points can be paid by two any sources.
	var assistant = _game.assistant
	assistant.mana_cost = {"火": 1, "neutral": 1}
	assistant.mana_acc = {"any": 2}
	var slots: Array = assistant.payment_breakdown()
	_expect(slots.all(func(s): return not str(s["paid_by"]).is_empty()),
		"two any-element sources pay one Fire point and one wild point")
	_expect(assistant.can_pay_cost(), "and the cost reads as fully paid")
	assistant.mana_acc = {"any": 1}
	_expect(not assistant.can_pay_cost(), "one any source cannot pay both points")
	assistant.mana_acc = {}


func _check_kefka() -> void:
	var kefka: Card = _place(104, "player")
	var target: Card = _place(41, "player")
	_expect(kefka.card_effects.has("skill"), "Kefka 104 has its Dull skill")
	target.add_status_effect("break_at_end_of_turn", 1)
	_field.end_phase_cleanup()
	_expect(not target.is_on_field(), "Kefka's delayed-break status breaks the Forward at end of turn")
	_expect(target.current_zone == Card.Zone.GRAVEYARD, "and it lands in the Break Zone")
	_field.remove_card(kefka)


func _check_tidus() -> void:
	var tidus: Card = _place(213, "player")
	var yuna: Card = _place(177, "player")
	_expect(tidus.is_brave(), "Tidus gains Brave while Yuna is on the field")
	_field.remove_card(yuna)
	_expect(not tidus.is_brave(), "and loses Brave when Yuna leaves")
	_field.remove_card(tidus)


func _check_rygdea() -> void:
	var rygdea: Card = _place(211, "player")
	rygdea.tapped = true  # keep the ETB's "active Forward" choice on the opponent's side
	var first: Card = _place(41, "opponent")
	var second: Card = _place(43, "opponent")
	_field.execute_card_effect(rygdea, "when_enter_field")
	if _game.stack.stack_length() > 0:
		await _game.stack.resolve_top_effect()
	_expect(first.accumulated_damage == 3000, "Rygdea's ETB deals 3000 to the chosen active Forward")
	_expect(first.status_effects.has("rygdea_mark"), "and leaves its break-zone rider on that Forward")
	_game.put_card_into_graveyard(first)
	await _wait(0.4)
	_expect(second.tapped, "when the marked Forward reaches the Break Zone, the rider dulls an opponent Forward")
	_field.remove_card(rygdea)
	_field.remove_card(second)
