extends "res://scripts/effects/card_effect.gd"
## 1-209C Red Mage


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《雷》《Dull》: Choose 1 attacking Lightning Forward. It gains First Strike.",
			"cost": {"雷": 1},
			"tap": true,
			"targets": {"is_type": "Forward", "is_attacking": true, "is_element": "雷"},
			"run": Callable(self, "_first_strike_target"),
		}),
	]

func _first_strike_target(ctx) -> void:
	ctx.add_status(ctx.targets, "first_strike", 1)

