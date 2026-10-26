extends "res://scripts/effects/card_effect.gd"
## 1-078C Ninja


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《風》, discard 1 card: Choose 1 Forward. Deal it 2000 damage.",
			"cost": {"風": 1},
			"discard": 1,
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_activate"),
		}),
	]


func _activate(ctx) -> void:
	ctx.damage(ctx.targets, 2000)
