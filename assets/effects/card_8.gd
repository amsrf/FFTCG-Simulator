extends "res://scripts/effects/card_effect.gd"

func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《火》《1》《Dull》: Choose 1 Forward of cost 3 or less. Deal it 2000 damage.",
			"cost": {"火": 1, "neutral": 1},
			"tap": true,
			"targets": {"is_type": "Forward", "is_cost_lower_than": 3},
			"target_count": 1,
			"run": Callable(self, "_shot"),
		}),
	]


func _shot(ctx) -> void:
	ctx.damage(ctx.targets, 2000)
