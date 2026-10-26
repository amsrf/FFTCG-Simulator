extends "res://scripts/effects/card_effect.gd"
## 1-121C Red Mage


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《雷》《Dull》: Choose 1 Forward. It gains Haste until the end of the turn.",
			"cost": {"雷": 1},
			"tap": true,
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.add_status(ctx.targets, "haste", 1)
