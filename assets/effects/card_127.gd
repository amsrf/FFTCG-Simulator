extends "res://scripts/effects/card_effect.gd"
## 1-127H Kain


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"})
	if targets.is_empty():
		return
	ctx.power_change(targets, -5000, 1)


func ex_burst_event() -> String:
	return "when_enter_field"


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Dragoon's Pride 《S》《Lightning》《Lightning》《Dull》: Choose 1 Forward. Break it. Kain will not activate during your next Active Phase.",
			"cost": {"雷": 2},
			"tap": true,
			"s_cost": true,
			"targets": {"is_type": "Forward"},
			"target_count": 1,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.break_cards(targets)
	ctx.add_status([ctx.source], "skip_next_active", 1)