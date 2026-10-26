extends "res://scripts/effects/card_effect.gd"
## 1-191S Red XIII


func when_enter_field(ctx) -> void:
	var targets: Array = await ctx.choose_targets({"is_type": "Forward"})
	ctx.power_change(targets, 3000, 1)


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Cosmo Memory 《S》《Fire》《Fire》《Fire》《Fire》《Dull》: Deal 6000 damage to all Forwards opponent controls.",
			"cost": {"火": 4},
			"tap": true,
			"s_cost": true,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.damage(ctx.cards_in("field", {"is_type": "Forward", "controller": "opponent"}), 6000)