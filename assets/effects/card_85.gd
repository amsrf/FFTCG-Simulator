extends "res://scripts/effects/card_effect.gd"


func activated_abilities() -> Array:
	return [
		_ability({
			"text": "《S》《Dull》 Choose up to 3 Forwards. Divide 6000 damage among them as you like.",
			"cost": {},
			"tap": true,
			"s_cost": true,
			"targets": {"is_type": "Forward"},
			"target_count": 3,
			"divide_total": 6000,
			"run": Callable(self, "_skill_0"),
		}),
	]


func _skill_0(ctx) -> void:
	var targets: Array = ctx.targets.duplicate()
	if targets.is_empty():
		return
	ctx.apply_damage_division(6000)

func static_rules() -> Dictionary:
	return {"cannot_be_blocked_by": {"min_cost": 4}}
