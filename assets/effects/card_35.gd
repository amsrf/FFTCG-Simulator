extends "res://scripts/effects/card_effect.gd"
## 1-035C Shiva


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《氷》《氷》《Dull》: Choose 1 Forward. Dull it.",
			"cost": {"氷": 2},
			"tap": true,
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_dull_target"),
		}),
	]

func _dull_target(ctx) -> void:
	ctx.dull(ctx.targets)

