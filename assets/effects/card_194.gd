extends "res://scripts/effects/card_effect.gd"
## 1-194S Snow


func when_blocks(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"})
	ctx.dull(targets)


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Vendetta 《S》《Ice》: Until the end of the turn, Snow gains +2000 power and First Strike. Use only while Snow is blocking.",
			"cost": {"氷": 1},
			"s_cost": true,
			"only_if_blocking": true,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.power_change([ctx.source], 2000, 1)
	ctx.add_status([ctx.source], "first_strike", 1)