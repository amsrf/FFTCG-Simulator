extends Node
## Pending status damage payloads: one-shot shields and timed reductions.
##
## The old generic damage-modifier interpreter has been deleted; cards now own
## their damage changes in `CardEffect.modify_damage(ctx)`. What remains to test
## here is the status-payload path used by Gordon and similar cards.

const GAME_SCENE := preload("res://scenes/game/game.tscn")

const TARGET := 41       # Squall, 6000 power

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null
var _target: Card = null


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


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	_target = _make(TARGET, "player")

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

	print("[DamageMods] %d checks | failures: %d" % [_checks, _fails])
	print("[DamageMods] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
