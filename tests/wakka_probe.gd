extends Node
## WAKKA 216 — ability nullification and temporary power setting.

const GAME_SCENE := preload("res://game.tscn")
const TEST_GROUNDS := preload("res://scripts/test_grounds.gd")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field: Node = null
var _wakka: Card = null
var _cloud: Card = null


## Picks the Forward this probe intends, then completes the session the way Confirm would.
class PickingAgent extends Agent:
	var wanted: Card = null

	func choose_target(_owner_id: int, _source: Card, _criteria: Dictionary) -> void:
		var f = game.field
		if wanted != null and wanted.is_valid_target:
			f.set_target_card(wanted)
			game.assistant.on_target_complete()
			return
		for c in f.get_all_cards():
			if c.is_valid_target:
				f.set_target_card(c)
				game.assistant.on_target_complete()
				return


func _ready() -> void:
	await get_tree().process_frame
	MatchSetup.config = TEST_GROUNDS.config("clean")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	_game.player_agent = MockAgent.new()
	_game.player_agent.bind(_game)
	_game.opponent_agent = MockAgent.new()
	_game.opponent_agent.bind(_game)
	_field = _game.field
	await get_tree().process_frame
	_wakka = _place(216)
	_cloud = _place(182)

	await _check_nullify_and_power()
	await _check_attack_power()
	await _check_expiry()

	print("[Wakka] %d checks | failures: %d" % [_checks, _fails])
	print("[Wakka] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[Wakka] ok   ", what)
	else:
		_fails += 1
		print("[Wakka] FAIL ", what)


func _place(id: int, controller: String = "player") -> Card:
	var card: Card = _game.create_card(id, controller)
	_game.add_child(card)
	_field.play_card(card, controller == "opponent", false)
	return card


func _run_instructions(card: Card, key: String, targets: Array) -> void:
	var raw: Array = card.card_effects[key]["instructions"] if key != "skill" 		else card.card_effects["skill"][0]["instructions"]
	var instructions: Array[Instruction] = card.create_instruction_from_json(raw)
	_game._current_source_card = card
	_game._current_controller = "player"
	_game._targets = targets
	await _game._execute_instructions_and_wait(instructions)


func _check_nullify_and_power() -> void:
	var wakka: Card = _place(216)
	var cloud: Card = _place(182)
	var cloud_hand: Card = _game.create_card(182, "player")
	_game.add_child(cloud_hand)
	_game.hand.add_card(cloud_hand)
	_game.priority_holder = 1
	GlobalVariables.set_base_mode(GlobalVariables.Player_Mode.FREE)

	var base_power: int = cloud.power
	_expect(cloud.card_effects.has("skill"), "setup: Cloud has printed abilities")
	_expect(cloud.activation_skills().size() == 2, "setup: Cloud has two Special Abilities")
	_expect(_field.can_activate_now(cloud), "setup: Cloud can activate one of them")

	await _run_instructions(wakka, "skill", [cloud])

	_expect(cloud.status_effects.has("abilities_nullified"), "Status Reels applies the nullification status")
	_expect(cloud.card_effects.is_empty(), "the printed ability view is now empty")
	_expect(cloud.activation_skills().is_empty(), "Cloud cannot activate any ability")
	_expect(not _field.can_activate_now(cloud), "and the green availability gate rejects it")
	_expect(not cloud.is_brave(), "printed keywords are gone too")
	_expect(cloud.power == 1000, "and its power was set to 1000 (was %d)" % base_power)
	_expect(cloud.status_effects.has("abilities_nullified"), "the nullification is temporary")


func _check_attack_power() -> void:
	var wakka: Card = _wakka
	var zack: Card = _place(12)
	var before: int = zack.power
	var count: int = _field.get_front_cards_for("player").size()
	var previous = _game.get("player_agent")
	var picker = PickingAgent.new()
	picker.bind(_game)
	picker.wanted = zack
	_game.set("player_agent", picker)
	_field.execute_card_effect(wakka, "when_attack")
	await get_tree().process_frame
	if _game.stack.stack_length() > 0:
		await _game.stack.resolve_top_effect()
	_game.set("player_agent", previous)
	_expect(zack.power == before + count * 1000,
		"Wakka's attack trigger gives the chosen Forward +1000 per controlled Forward (%d -> %d, count %d)" % [
			before, zack.power, count])


func _check_expiry() -> void:
	var cloud: Card = _place(182)
	var power_before: int = cloud.power
	var wakka: Card = _place(216)
	await _run_instructions(wakka, "skill", [cloud])
	_expect(cloud.power == 1000, "setup: Cloud was set to 1000")
	cloud.turn_end()
	_expect(not cloud.card_effects.is_empty(), "end of turn restores the printed ability view")
	_expect(cloud.activation_skills().size() == 2, "and its abilities are usable again")
	_expect(cloud.power == power_before, "the temporary power setting expires")
