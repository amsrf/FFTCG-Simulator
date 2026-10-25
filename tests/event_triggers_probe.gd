extends Node
## B4b: board-wide event triggers.

const GAME_SCENE := preload("res://game.tscn")
const AI_AGENT := preload("res://scripts/agents/ai_agent.gd")
const TEST_GROUNDS := preload("res://scripts/test_grounds.gd")


## A passive seat that still answers targeting. MockAgent never plays cards, so the probe's board cannot be changed
## by an unrelated AI play; choose_target picks the first legal target the same way a simple AI would.
class TestAgent extends MockAgent:
	func choose_target(_owner_id: int, _source: Card, _criteria: Dictionary) -> void:
		var f = game.field
		for c in f.get_all_cards():
			if c.is_valid_target:
				f.set_target_card(c)
				game.assistant.on_target_complete()
				return

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[B4b] ok   %s" % what)
	else:
		_fails += 1
		print("[B4b] FAIL %s" % what)


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


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _trigger_and_resolve(event_name: String, context: Dictionary) -> void:
	_field.trigger_event(event_name, context)
	await get_tree().process_frame
	if _game.stack.stack_length() > 0:
		var top: Card = _game.stack.cards.back()
		if not top.event_trigger.is_empty():
			await _game.stack.resolve_top_effect()
	await _wait(0.2)


func _ready() -> void:
	MatchSetup.config = TEST_GROUNDS.config("clean")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	# 108 chooses a target; the headless human cannot click, so let an AI answer this seat's prompts.
	_game.player_agent = TestAgent.new()
	_game.player_agent.bind(_game)

	# 108 Cecil: when you receive damage, may deal 5000 to an opponent Forward.
	_make(108, "player")
	var victim: Card = _make(41, "opponent")
	_game.player.take_damage(1)
	await _trigger_and_resolve("", {})
	_expect(victim.accumulated_damage == 5000, "108 damage_received deals 5000 to the chosen Forward")
	_expect(_field.targeting_arrows.is_empty() and _field.arrow == null, "108 removes every targeting arrow and arc")
	_expect(not victim.ring_selected() and not victim.ring_targeted(), "and clears the orange/red ring on the target")

	# 206 Biggs: when one of your Backups leaves the field, all opponent Forwards take 1000.
	_make(206, "player")
	var backup: Card = _make(32, "player")
	var other_victim: Card = _make(41, "opponent")
	_game.put_card_into_graveyard(backup)
	await _trigger_and_resolve("", {})
	_expect(other_victim.accumulated_damage == 1000, "206 card_left_field damages all opponent Forwards")

	# 214 Yuna: when you cast a Summon, may dull her to draw 1, once per turn.
	var yuna: Card = _make(214, "player")
	var hand_before: int = _game.player.hand.cards.size()
	var summon: Card = _off_field(4, "player")
	await _trigger_and_resolve("summon_cast", {"card": summon})
	_expect(yuna.tapped and _game.player.hand.cards.size() == hand_before + 1,
		"214 summon_cast dulls Yuna and draws 1")
	var hand_after: int = _game.player.hand.cards.size()
	await _trigger_and_resolve("summon_cast", {"card": summon})
	_expect(_game.player.hand.cards.size() == hand_after,
		"214 does not trigger a second time in the same turn")

	# 215 Lenne: when the opponent casts a Summon, activate her.
	var lenne: Card = _make(215, "player")
	lenne.tap()
	var foe_summon: Card = _off_field(4, "opponent")
	await _trigger_and_resolve("summon_cast", {"card": foe_summon})
	_expect(not lenne.tapped, "215 opponent's Summon untaps Lenne")

	# 187 Cloud: each Forward you control that attacks gains +1000.
	_make(187, "player")
	var attacker: Card = _make(41, "player")
	var attacker_power: int = attacker.power
	await _trigger_and_resolve("forward_attacks", {"card": attacker})
	_expect(attacker.power == attacker_power + 1000, "187 an attacking Forward gains +1000")

	# 213 Tidus: when a Forward named Yuna leaves your field, draw 2.
	_make(213, "player")
	var yuna_forward: Card = _make(214, "player")
	var tidus_hand: int = _game.player.hand.cards.size()
	_game.put_card_into_graveyard(yuna_forward)
	await _trigger_and_resolve("", {})
	_expect(_game.player.hand.cards.size() == tidus_hand + 2,
		"213 a Yuna Forward leaving the field draws 2")

	var effects: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/card_effects.json"))
	_expect(effects.get("108", {}).get("triggers", [{}])[0].get("on", "") == "damage_received",
		"108 uses the generic triggers array")
	_expect(effects.get("206", {}).get("triggers", [{}])[0].get("on", "") == "card_left_field",
		"206 uses card_left_field")
	_expect(effects.get("214", {}).get("triggers", [{}])[0].get("once_per_turn", false),
		"214 is marked once per turn")
	_expect(effects.get("215", {}).get("triggers", [{}])[0].get("filter", {}).get("controller", "") == "opponent",
		"215 watches only the opponent's Summons")
	_expect(effects.get("187", {}).get("triggers", [{}])[0].get("target", "") == "event",
		"187 targets the attacking Forward")

	print("[B4b] %d checks | failures: %d" % [_checks, _fails])
	print("[B4b] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
