extends "res://scripts/effects/card_effect.gd"
## 1-049C Time Mage
## 《Ice》《1》《Dull》: Choose 1 Forward. It cannot attack this turn.


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《氷》《1》《Dull》: Choose 1 Forward. It cannot attack this turn.",
			"cost": {"氷": 1, "neutral": 1},
			"tap": true,
			"targets": {"is_type": "Forward"},
			"run": Callable(self, "_stop_forward"),
		}),
	]


func _stop_forward(ctx) -> void:
	ctx.add_status(ctx.targets, "cannot_attack", 1)
