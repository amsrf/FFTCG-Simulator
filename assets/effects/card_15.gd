extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "Ultimate Jecht Shot 《S》《Fire》《2》《Dull》: Choose 1 Forward. Break it.",
			"cost": {"火": 1, "neutral": 2},
			"tap": true,
			"s_cost": true,
			"targets": {"is_type": "Forward"},
			"target_count": 1,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	if not targets.is_empty():
		ctx.break_cards(targets)