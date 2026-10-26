extends Node
## Continuous power is a ledger: the cached power and the label follow recompute_power(), and removing one key
## leaves every other contributor intact.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PowerLedger] ok   %s" % what)
	else:
		_fails += 1
		print("[PowerLedger] FAIL %s" % what)


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	var field = _game.get("field")
	var card: Card = _game.call("create_card", 41, "player")
	_game.add_child(card)
	field.play_card(card, false, false)
	card.set_base_power(5000)
	await get_tree().process_frame

	card.add_power_modifier("aura:test:0", 1000)
	_expect(card.power == 6000, "one continuous key raises 5000 to 6000")
	card.add_power_modifier("aura:test:1", 500)
	_expect(card.power == 6500, "a second key adds independently")
	card.remove_power_modifier("aura:test:0")
	_expect(card.power == 5500, "removing one key leaves the other contributor")
	_expect(card.base_power == 5000, "base_power was never mutated")

	# The UI reads from the cached value, but the tween must settle on it.
	await get_tree().create_timer(1.0).timeout
	_expect(card.power_label != null and card.power_label.text.begins_with("5500/"),
		"the power display reflects the ledger result")

	# Temporary modifiers are still separate from the continuous ledger.
	card.power_change(500, 1)
	_expect(card.power == 6000, "a temporary buff stacks on the continuous entry")
	card.turn_end()
	_expect(card.power == 5500, "and expires without disturbing the continuous entry")
	_expect(card.power_label.text.begins_with("5500/"), "the display follows the expiry")

	field.remove_card(card)
	await get_tree().process_frame
	print("[PowerLedger] %d checks | failures: %d" % [_checks, _fails])
	print("[PowerLedger] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
