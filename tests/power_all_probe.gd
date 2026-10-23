extends Node
## POWER_CHANGE_TARGETS probe.
##
## Two things can be wrong here and they are separate:
##   1. the INSTRUCTION — does it raise every target, and does a one-turn buff wear off at turn_end
##   2. the DATA WIRING — card 7 reaches it at all (apply_effect fills _targets, then the instruction runs)
##
## The second one is the risky half: apply_effect is looked up at the TOP level of the card's effects for an ETB,
## not inside when_enter_field, and that is easy to get wrong in the JSON without any error appearing.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field: Node = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[PowerAll] ok   %s" % what)
	else:
		_fails += 1
		print("[PowerAll] FAIL %s" % what)


func _new_card(id: int, power: int) -> Card:
	var card: Card = _game.create_card(id, "player")
	_game.add_child(card)
	_field.play_card(card, false, false)
	card.status_effects.clear()
	card.card_effects.clear()
	card.power = power
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	var db = CardDatabase.card_database

	# --- the instruction: every target, and it wears off ------------------------------------------------
	var a: Card = _new_card(41, 5000)
	var b: Card = _new_card(41, 3000)
	_game.set("_targets", [a, b])
	_game.power_change_targets(1000, 1)
	_expect(a.power == 6000, "first target +1000 (now %d)" % a.power)
	_expect(b.power == 4000, "second target +1000 (now %d)" % b.power)
	a.turn_end()
	b.turn_end()
	_expect(a.power == 5000 and b.power == 3000, "and a one-turn buff wears off at turn_end")

	# --- a debuff goes through the same call ------------------------------------------------------------
	_game.set("_targets", [a])
	_game.power_change_targets(-2000, 1)
	_expect(a.power == 3000, "a negative amount debuffs (now %d)" % a.power)
	_field.remove_card(a)
	_field.remove_card(b)
	await get_tree().process_frame

	# --- the data wiring: card 7 ------------------------------------------------------------------------
	var entry: Dictionary = CardDatabase.card_effects.get("7", {})
	_expect(entry.has("apply_effect"), "card 7 carries apply_effect at the TOP level, where an ETB reads it")
	_expect(entry.get("when_enter_field", {}).get("instructions", []).size() > 0,
		"and its when_enter_field has instructions")
	var instr: Dictionary = entry.get("when_enter_field", {}).get("instructions", [{}])[0]
	_expect(str(instr.get("name", "")) == "power_change_targets",
		"which is power_change_targets (got '%s')" % instr.get("name", ""))
	var arg: Array = instr.get("argument", [])
	_expect(arg.size() == 2 and int(arg[0]) == 1000 and int(arg[1]) == 1,
		"with +1000 for one turn (got %s)" % str(arg))

	print("[PowerAll] card 7 is %s" % str(db[6].get("name_en", "?")))
	_finish()


func _finish() -> void:
	print("[PowerAll] %d checks | failures: %d" % [_checks, _fails])
	print("[PowerAll] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
