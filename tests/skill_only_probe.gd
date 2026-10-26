extends Node
## Every skill-only card now exposes its activated abilities through AbilitySpec.

const EXPECTED := {
	13: 1, 19: 1, 34: 1, 35: 1, 89: 2, 96: 1, 53: 1, 48: 1,
	149: 2, 157: 1, 205: 1, 209: 1, 146: 1, 200: 1, 128: 1,
	130: 1, 139: 1, 169: 1, 160: 1, 104: 1, 102: 1,
}

var _checks: int = 0
var _fails: int = 0


func _expect(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("[SkillOnly] ok   %s" % what)
	else:
		_fails += 1
		print("[SkillOnly] FAIL %s" % what)


func _ready() -> void:
	for id in EXPECTED:
		var path: String = "res://assets/effects/card_%d.gd" % id
		var script = load(path)
		_expect(script != null, "%d has a code effect script" % id)
		if script == null:
			continue
		var effect = script.new()
		var abilities: Array = effect.activated_abilities()
		_expect(abilities.size() == int(EXPECTED[id]), "%d exposes %d activated ability/abilities" % [id, EXPECTED[id]])
		for i in range(abilities.size()):
			var spec = abilities[i]
			_expect(spec != null and spec.run.is_valid(), "%d ability %d has a callable handler" % [id, i])
			_expect(spec != null and not spec.text.is_empty(), "%d ability %d has display text" % [id, i])

	# A few structural facts that the generator could silently get wrong.
	var g128 = load("res://assets/effects/card_128.gd").new().activated_abilities()[0]
	_expect(g128.s_cost and bool(g128.only_your_turn), "Gilgamesh 128 keeps its S cost and turn restriction")
	var b102 = load("res://assets/effects/card_102.gd").new().activated_abilities()[0]
	_expect(b102.s_cost and b102.targets.get("has_special_ability", false),
		"Kimahri 102 still targets only Special Ability Forwards")
	var b200 = load("res://assets/effects/card_200.gd").new().activated_abilities()[0]
	_expect(b200.as_skill_dict().get("choose_target", {}).get("count", 1) == 2,
		"Baralai 200 asks for up to two targets")

	print("[SkillOnly] %d checks | failures: %d" % [_checks, _fails])
	print("[SkillOnly] RESULT: %s" % ("all checks passed" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit()
