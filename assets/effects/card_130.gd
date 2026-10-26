extends "res://scripts/effects/card_effect.gd"
## 1-130C Black Mage


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《雷》《雷》《Dull》, put Black Mage into the Break Zone: Choose 1 damaged Forward. Break it.",
			"cost": {"雷": 2},
			"tap": true,
			"sacrifice": {"is_source": true},
			"targets": {"is_type": "Forward", "is_damaged": true},
			"run": Callable(self, "_break_target"),
		}),
	]

func _break_target(ctx) -> void:
	ctx.break_cards(ctx.targets)

