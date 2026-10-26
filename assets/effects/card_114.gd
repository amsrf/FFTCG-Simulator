extends "res://scripts/effects/card_effect.gd"
## 1-114R Barret


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Hammer Blow 《S》《土》《土》: Choose 1 Forward. Deal it 4000 damage. Barret gains +4000 power.",
			"s_cost": true,
			"cost": {"土": 2},
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.damage(ctx.targets, 4000)
	ctx.source.power_change(4000, 1)
