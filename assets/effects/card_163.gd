extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Blitz Ace 《S》《Water》《Water》: Until the end of the turn Tidus gains Brave. Tidus can attack as many times as your points of damage this turn.",
			"cost": {"水": 2},
			"s_cost": true,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	ctx.add_status([ctx.source], "brave", 1)
	ctx.extra_attacks_from_damage()