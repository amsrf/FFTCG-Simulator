extends "res://scripts/effects/card_effect.gd"
## 1-100C Black Belt


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《土》《Dull》: Choose 1 Forward blocking. It gains +1000 power.",
			"cost": {"土": 1},
			"tap": true,
			"targets": {"is_type": "Forward", "is_blocking": true},
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.power_change(ctx.targets, 1000, 1)
