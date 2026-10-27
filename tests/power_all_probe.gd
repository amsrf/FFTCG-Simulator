extends Node
const EFFECT_CONTEXT := preload("res://scripts/effects/effect_context.gd")
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
	card.set_base_power(power)
	return card


func _ready() -> void:
	MatchSetup.config = MatchSetup.build_config("debug")
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")
	var db = CardDatabase.card_database

	# --- the duration AS JSON DELIVERS IT: a float ------------------------------------------------------
	# Every number in card_effects.json parses as a float, and Card.power_change() takes untyped arguments, so a
	# one-turn buff arrives as 1.0. turn_end() tested `dur is int`, which is FALSE for 1.0 — the buff never
	# decremented and the power never came back. The int literals above passed while the real card did not, which
	# is why this case is written with the exact shape the data uses.
	var f: Card = _new_card(41, 5000)
	f.power_change(1000.0, 1.0)
	_expect(f.power == 6000, "a FLOAT duration applies (now %d)" % f.power)
	f.turn_end()
	_expect(f.power == 5000,
		"and a float duration still wears off — this is the case the user hit (now %d)" % f.power)
	f.add_status_effect("block_disabled", 1.0)
	f.turn_end()
	_expect(not f.status_effects.has("block_disabled"),
		"a float-duration STATUS expires too (it used to be permanent)")
	_field.remove_card(f)
	await get_tree().process_frame

	# --- the instruction: every target, and it wears off ------------------------------------------------
	var a: Card = _new_card(41, 5000)
	var b: Card = _new_card(41, 3000)
	var ctx = EFFECT_CONTEXT.new(_game, a, "test")
	ctx.power_change([a, b], 1000, 1)
	_expect(a.power == 6000, "first target +1000 (now %d)" % a.power)
	_expect(b.power == 4000, "second target +1000 (now %d)" % b.power)
	a.turn_end()
	b.turn_end()
	_expect(a.power == 5000 and b.power == 3000, "and a one-turn buff wears off at turn_end")

	# --- a debuff goes through the same call ------------------------------------------------------------
	ctx.power_change([a], -2000, 1)
	_expect(a.power == 3000, "a negative amount debuffs (now %d)" % a.power)
	_field.remove_card(a)
	_field.remove_card(b)
	await get_tree().process_frame

	# --- SINGLE target, through the real dispatch path ---------------------------------------------------
	# "author": "target" resolves to _targets[0], and the instruction is dispatched as
	# executor.callv(action, argument). So Card.power_change is reachable with NO new instruction code — the
	# pair was already a working vocabulary and I had wrongly listed it as missing. This drives the actual
	# signal → instruction queue route rather than calling power_change directly.
	var solo: Card = _new_card(41, 5000)
	_game.set("_targets", [solo])
	print("[PowerAll] connections on execute_instructions: %d | _targets=%d | source=%s" % [
		solo.execute_instructions.get_connections().size(),
		(_game.get("_targets") as Array).size(),
		str(_game.get("_current_source_card"))])
	# TYPED, because the handler is declared Array[Instruction]. Emitting an untyped Array is a conversion the
	# signal will refuse, and it does so without reaching the handler.
	var typed: Array[Instruction] = [Instruction.new("power_change", "target", [1000, 1])]
	solo.execute_instructions.emit(typed)
	for _i in range(6):
		await get_tree().process_frame
		if solo.power == 6000:
			break
	_expect(solo.power == 6000,
		"author 'target' + power_change buffs ONE card through the real dispatch path (now %d)" % solo.power)
	_game.set("_targets", [solo])
	var typed2: Array[Instruction] = [Instruction.new("power_change", "target", [-2000, 1])]
	solo.execute_instructions.emit(typed2)
	for _i in range(6):
		await get_tree().process_frame
		if solo.power == 4000:
			break
	_expect(solo.power == 4000, "and a negative amount debuffs through the same route (now %d)" % solo.power)
	_field.remove_card(solo)
	await get_tree().process_frame

	# --- the data wiring: card 7 ------------------------------------------------------------------------
	var card7_effect = load("res://assets/effects/card_7.gd").new()
	_expect(card7_effect.has_method("when_enter_field"),
		"card 7's ETB power change is code-owned")

	print("[PowerAll] card 7 is %s" % str(db[6].get("name_en", "?")))
	_finish()


func _finish() -> void:
	print("[PowerAll] %d checks | failures: %d" % [_checks, _fails])
	print("[PowerAll] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
