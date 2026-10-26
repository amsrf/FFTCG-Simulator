extends "res://scripts/effects/card_effect.gd"
## 1-216S Wakka


func when_attack(ctx) -> void:
	var targets: Array = await ctx.choose_targets({
		"is_type": "Forward", "controller": "your",
	})
	if targets.is_empty():
		return
	var forwards: int = ctx.cards_in("field", {
		"is_type": "Forward", "controller": "your",
	}).size()
	ctx.power_change(targets, forwards * 1000, 1)


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Status Reels 《S》《水》: Choose 1 Forward. Until the end of the turn, it loses all its abilities and its power becomes 1000.",
			"cost": {"水": 1},
			"s_cost": true,
			"targets": {"is_type": "Forward"},
			"target_count": 1,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	ctx.add_status(targets, "abilities_nullified", 1)
	ctx.set_power(targets, 1000, 1)