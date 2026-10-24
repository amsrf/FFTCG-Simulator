extends Node
## The generic damage-modifier interpreter: operations, context refs and the semantic conditions.

const GAME_SCENE := preload("res://game.tscn")

const OWNER := 12       # Zack, no printed damage modifiers
const TARGET := 41      # Squall, 6000 power
const OTHER := 29       # Red XIII

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _owner: Card = null
var _target: Card = null
var _other: Card = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[DamageMods] ok   %s" % what)
	else:
		_fails += 1
		print("[DamageMods] FAIL %s" % what)


func _make(id: int, side: String) -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	card.status_effects.clear()
	card.accumulated_damage = 0
	card.untap()
	return card


func _rule(operation: String, value: Variant, conditions: Array = [], targets: Dictionary = {}) -> void:
	_owner.card_effects["damage_modifiers"] = [{
		"targets": targets,
		"conditions": conditions,
		"operation": operation,
		"value": value,
	}]


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_owner = _make(OWNER, "player")
	_target = _make(TARGET, "player")
	_other = _make(OTHER, "player")

	# --- operations -----------------------------------------------------------------------------------
	_rule("add", 1000)
	_expect(_field.modify_damage(null, _target, 1000) == 2000, "add 1000 to 1000")
	_rule("subtract", 300)
	_expect(_field.modify_damage(null, _target, 1000) == 700, "subtract 300 from 1000")
	_rule("multiply", 2)
	_expect(_field.modify_damage(null, _target, 1000) == 2000, "multiply 1000 by 2")
	_rule("set", 0)
	_expect(_field.modify_damage(null, _target, 1000) == 0, "set 1000 to 0")

	# --- compare_values: context vs a literal ---------------------------------------------------------
	_rule("add", 1000, [{
		"compare_values": {
			"left": {"context": "amount"},
			"op": "lt",
			"right": 5000,
		},
	}])
	_expect(_field.modify_damage(null, _target, 4000) == 5000, "compare context.amount < 5000")
	_expect(_field.modify_damage(null, _target, 6000) == 6000, "and does not apply at 6000")

	# --- compare_values: context vs a Card property ---------------------------------------------------
	_rule("add", 1000, [{
		"compare_values": {
			"left": {"context": "amount"},
			"op": "lt",
			"right": {"context": "target", "property": "power"},
		},
	}])
	_expect(_field.modify_damage(null, _target, 4000) == 5000, "compare amount < target.power (6000)")
	_expect(_field.modify_damage(null, _target, 6000) == 6000, "and equal-to-power does not apply")

	# --- source_is_self -------------------------------------------------------------------------------
	_rule("multiply", 2, [{"source_is_self": true}])
	_expect(_field.modify_damage(_owner, _target, 1000) == 2000, "source_is_self applies to the owner's damage")
	_expect(_field.modify_damage(_other, _target, 1000) == 1000, "and not to another card's damage")

	# --- pending status payloads: the generic one-shot shield ----------------------------------------
	_owner.card_effects["damage_modifiers"] = []
	_target.add_status_effect("next_receiving_damage", 1, {"operation": "subtract", "value": 2000})
	_expect(_field.modify_damage(null, _target, 5000) == 3000, "a status payload can subtract 2000")
	_expect(not _target.status_effects.has("next_receiving_damage"), "and is consumed")
	_target.add_status_effect("next_receiving_damage", 1, {"operation": "set", "value": 0})
	_expect(_field.modify_damage(null, _target, 5000) == 0, "a status payload can set the damage to 0")
	_expect(not _target.status_effects.has("next_receiving_damage"), "and is consumed")
	_target.add_status_effect("next_receiving_damage", 1,
		{"operation": "subtract", "value": 1000, "once": false})
	_expect(_field.modify_damage(null, _target, 5000) == 4000, "once:false applies")
	_expect(_field.modify_damage(null, _target, 5000) == 4000, "and keeps applying")
	_expect(_target.status_effects.has("next_receiving_damage"), "while the status remains")
	_target.turn_end()
	_expect(not _target.status_effects.has("next_receiving_damage"), "and turn_end expires it")

	# --- static status condition + consume_status -----------------------------------------------------
	_rule("set", 0, [{"status": "test_marker"}])
	_owner.card_effects["damage_modifiers"][0]["consume_status"] = "test_marker"
	_target.add_status_effect("test_marker", 1)
	_expect(_field.modify_damage(null, _target, 1000) == 0, "a static status condition still applies")
	_expect(not _target.status_effects.has("test_marker"), "and consume_status erases the marker")

	print("[DamageMods] %d checks | failures: %d" % [_checks, _fails])
	print("[DamageMods] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
