extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Shout 《S》《Lightning》: Until the end of the turn, Ramza gains +2000 power, Haste and First Strike.",
			"cost": {"雷": 1},
			"s_cost": true,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.power_change([ctx.source], 2000, 1)
	ctx.add_status([ctx.source], "haste", 1)
	ctx.add_status([ctx.source], "first_strike", 1)