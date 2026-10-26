extends Node
## Cost modifiers are continuous queries. These checks cover the two hooks, the floor, counted self costs and a source
## entering/leaving without mutating the printed cost.

const GAME_SCENE := preload("res://game.tscn")

var _checks: int = 0
var _fails: int = 0
var _game: Node = null
var _field = null


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[CostModifier] ok   %s" % what)
	else:
		_fails += 1
		print("[CostModifier] FAIL %s" % what)


func _place(id: int, side: String = "player") -> Card:
	var card: Card = _game.call("create_card", id, side)
	_game.add_child(card)
	_field.play_card(card, side == "opponent", false, false)
	return card


func _hand(id: int, side: String = "player") -> Card:
	return _game.call("create_card", id, side)


func _total(cost: Dictionary) -> int:
	var total: int = 0
	for value in cost.values():
		total += int(value)
	return total


func _ready() -> void:
	for id in [20, 46, 153, 177, 187, 210, 213]:
		var script = load("res://assets/effects/card_%d.gd" % id)
		_expect(script != null, "%d has a code cost modifier" % id)
		var effect = script.new()
		_expect(effect.has_method("modify_cost") or effect.has_method("modify_cost_for"),
			"%d exposes a cost hook" % id)

	MatchSetup.config = MatchSetup.build_config("clean", {"opponent_type": "mock"})
	_game = GAME_SCENE.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_field = _game.get("field")

	# Fang 20: your Bahamut costs 2 less, only while Fang is on the field.
	var bahamut: Card = _hand(18)
	var base: Dictionary = _field.effective_cost(bahamut)
	var fang: Card = _place(20)
	var reduced: Dictionary = _field.effective_cost(bahamut)
	_expect(_total(reduced) == _total(base) - 2, "Fang reduces Bahamut by 2")
	_field.remove_card(fang)
	await get_tree().process_frame
	_expect(_field.effective_cost(bahamut) == base, "and the reduction disappears with Fang")

	# Alma 153: self cost drops while Ovelia is controlled.
	var alma: Card = _hand(153)
	var alma_base: Dictionary = _field.effective_cost(alma)
	var ovelia: Card = _place(156)
	_expect(_total(_field.effective_cost(alma)) == _total(alma_base) - 1,
		"Alma costs 1 less while Ovelia is on the field")
	_field.remove_card(ovelia)
	await get_tree().process_frame
	_expect(_field.effective_cost(alma) == alma_base, "and the reduction disappears with Ovelia")

	# Yuna's floor is applied after all modifiers, not per source.
	var water_summon: Card = _hand(172)  # Water Summon, cost 1
	_place(177)
	_place(177)
	var floored: Dictionary = _field.effective_cost(water_summon)
	_expect(_total(floored) == 1, "two -1 auras cannot take a 1-cost Water Summon below 1")

	print("[CostModifier] %d checks | failures: %d" % [_checks, _fails])
	print("[CostModifier] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
