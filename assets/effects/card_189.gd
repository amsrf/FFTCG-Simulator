extends "res://scripts/effects/card_effect.gd"
## 1-189S Tifa


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Waterkick 《S》《火》: Choose 1 Forward. Dull it and deal it 6000 damage.",
			"s_cost": true,
			"cost": {"火": 1},
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.dull(ctx.targets)
	ctx.damage(ctx.targets, 6000)
