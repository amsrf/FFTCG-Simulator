extends "res://scripts/effects/card_effect.gd"
## 1-003C Red Mage
## 《Fire》《1》《Dull》: Choose 1 Forward. It cannot block this turn.


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《火》《1》《Dull》: Choose 1 Forward. It cannot block this turn.",
			"cost": {"火": 1, "neutral": 1},
			"tap": true,
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_bind_forward"),
		}),
	]


func _bind_forward(ctx) -> void:
	ctx.add_status(ctx.targets, "block_disabled", 1)
