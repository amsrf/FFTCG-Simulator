extends "res://scripts/effects/card_effect.gd"
## 1-120C Monk


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《土》《Dull》, put Monk into the Break Zone: Choose 1 Forward. It gains +2000 power.",
			"cost": {"土": 1},
			"tap": true,
			"sacrifice": {"is_source": true},
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.power_change(ctx.targets, 2000, 1)
